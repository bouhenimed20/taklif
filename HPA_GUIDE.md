# Horizontal Pod Autoscaler (HPA) Guide

## Overview

This project implements advanced HPA configurations for all microservices with CPU, memory, and custom Prometheus metrics-based autoscaling.

## Enhancements Applied

### 1. Advanced Scaling Behavior

All HPAs now include fine-tuned scaling behavior policies:

**Scale Up (Fast Response):**
- Zero stabilization window for immediate response to load spikes
- Can scale up by 100% or add 4 pods per 15 seconds (whichever is greater)
- Prevents slow response to traffic surges

**Scale Down (Gradual and Safe):**
- 5-minute stabilization window to avoid flapping
- Maximum 50% reduction per 15 seconds
- Ensures stable performance during load decrease

### 2. Multi-Metric Autoscaling

#### main-api HPA
Location: `k8s/07-autoscaling.yaml:1-45`

```yaml
metrics:
- CPU: 70% target
- Memory: 80% target
- Custom: http_request_duration_ms (500ms average target)
```

Scales from 3 to 10 replicas based on:
- Resource utilization
- HTTP request latency from Prometheus metrics

#### auth-service HPA
Location: `k8s/07-autoscaling.yaml:47-80`

```yaml
metrics:
- CPU: 75% target
- Memory: 85% target
```

Scales from 2 to 8 replicas for authentication workloads.

#### image-service HPA
Location: `k8s/07-autoscaling.yaml:82-115`

```yaml
metrics:
- CPU: 70% target
- Memory: 80% target
```

Scales from 2 to 8 replicas for image processing tasks.

## Custom Prometheus Metrics

### main-api Metrics

The main-api service exposes Prometheus metrics at `/metrics`:

**Available Metrics:**
- `http_request_duration_ms` - HTTP request latency histogram
- `process_cpu_seconds_total` - CPU usage
- `nodejs_heap_size_used_bytes` - Memory usage

**HPA Integration:**
The HPA uses `http_request_duration_ms` to scale based on application performance:
- Target: 500ms average
- Scales up when request latency exceeds target
- Scales down when latency is consistently below target

### Enabling Prometheus Adapter (Required for Custom Metrics)

To use custom Prometheus metrics with HPA, you need the Prometheus Adapter:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus-adapter prometheus-community/prometheus-adapter \
  --namespace prod-monitoring \
  --set prometheus.url=http://prometheus.prod-monitoring.svc \
  --set prometheus.port=9090
```

### Custom Metrics Configuration

For production, configure the Prometheus Adapter with custom rules:

```yaml
rules:
- seriesQuery: 'http_request_duration_ms'
  resources:
    overrides:
      namespace: {resource: "namespace"}
      pod: {resource: "pod"}
  name:
    matches: "^(.*)$"
    as: "http_request_duration_ms"
  metricsQuery: 'avg(<<.Series>>{<<.LabelMatchers>>})'
```

## Testing Autoscaling

### 1. Monitor HPA Status

```bash
kubectl get hpa -A -w
```

### 2. Generate Load (main-api)

```bash
kubectl run load-generator --rm -i --tty --image=busybox --restart=Never -n prod-api -- \
  /bin/sh -c "while sleep 0.01; do wget -q -O- http://main-api:3000/health; done"
```

### 3. Watch Pods Scale

```bash
kubectl get pods -n prod-api -w
```

### 4. Check Metrics

```bash
kubectl top pods -n prod-api
kubectl describe hpa main-api-hpa -n prod-api
```

## Scaling Characteristics

### Scale Up Behavior

**main-api:**
- Triggers at 70% CPU OR 80% memory OR 500ms latency
- Can add up to 4 pods at once
- Maximum: 10 pods

**auth-service:**
- Triggers at 75% CPU OR 85% memory
- Can add up to 2 pods at once
- Maximum: 8 pods

**image-service:**
- Triggers at 70% CPU OR 80% memory
- Can add up to 2 pods at once
- Maximum: 8 pods

### Scale Down Behavior

All services:
- Wait 5 minutes after last scale event
- Remove maximum 50% of pods per cycle
- Prevents premature scale-down during temporary dips

## Viewing Metrics in Grafana

Access Grafana dashboard:
```bash
kubectl port-forward -n prod-monitoring svc/grafana 3000:3000
```

Visit: http://localhost:3000
- Username: admin
- Password: admin123

**Useful Queries:**
- `rate(http_request_duration_ms_count[5m])` - Request rate
- `http_request_duration_ms_sum / http_request_duration_ms_count` - Average latency
- `container_cpu_usage_seconds_total` - CPU usage
- `container_memory_working_set_bytes` - Memory usage

## Production Recommendations

### 1. Adjust Metrics Targets

Based on your SLAs:
```yaml
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 60  # More headroom for traffic spikes
```

### 2. Add More Custom Metrics

Examples:
- Request queue depth
- Error rate percentage
- Database connection pool usage
- External API response time

### 3. Set Resource Requests/Limits

Ensure all deployments have proper resource definitions:
```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 512Mi
```

### 4. Configure PodDisruptionBudgets

Prevent too many pods from being evicted during maintenance:
```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: main-api-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: main-api
```

## Troubleshooting

### HPA Not Scaling

**Check Metrics Server:**
```bash
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
```

**Check HPA Status:**
```bash
kubectl describe hpa <hpa-name> -n <namespace>
```

**Common Issues:**
- Metrics Server not installed or not ready
- Resource requests not defined in deployment
- Prometheus metrics not being scraped
- Prometheus Adapter not configured

### Metrics Not Available

**Verify Prometheus:**
```bash
kubectl port-forward -n prod-monitoring svc/prometheus 9090:9090
```

Visit: http://localhost:9090

Query: `http_request_duration_ms`

**Check Service Annotations:**
```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "3000"
  prometheus.io/path: "/metrics"
```

### Pods Not Scaling Down

**Causes:**
- Active connections preventing graceful shutdown
- Stabilization window still active
- Metrics still above threshold

**Solution:**
- Wait for stabilization window (5 minutes)
- Check current metrics: `kubectl top pods -n <namespace>`
- Review HPA events: `kubectl describe hpa <hpa-name> -n <namespace>`

## Advanced Configuration

### Multiple Custom Metrics

```yaml
metrics:
- type: Pods
  pods:
    metric:
      name: http_requests_per_second
    target:
      type: AverageValue
      averageValue: "1000"
- type: Pods
  pods:
    metric:
      name: http_errors_per_second
    target:
      type: AverageValue
      averageValue: "10"
```

### External Metrics (e.g., SQS queue depth)

```yaml
metrics:
- type: External
  external:
    metric:
      name: sqs_queue_depth
      selector:
        matchLabels:
          queue: "image-processing"
    target:
      type: AverageValue
      averageValue: "100"
```

## References

- [Kubernetes HPA Documentation](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)
- [Prometheus Operator](https://github.com/prometheus-operator/prometheus-operator)
- [Prometheus Adapter](https://github.com/kubernetes-sigs/prometheus-adapter)
- [HPA Walkthrough](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale-walkthrough/)
