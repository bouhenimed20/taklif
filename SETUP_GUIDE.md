# SRE Practical Test Setup Guide

## What's Been Set Up

Your SRE practical test project is now complete with a production-like microservices architecture running on Kubernetes (Kind).

### Project Components

#### 1. Three Microservices
- **main-api** (Node.js): Public API gateway (3 replicas, port 3000)
- **auth-service** (Go): Authentication service (2 replicas, port 8080)
- **image-service** (Python): Image management (2 replicas, port 5000)

#### 2. Kubernetes Infrastructure
- **Kind cluster**: 3 nodes (1 control plane, 2 workers)
- **Private registry**: Docker registry on localhost:5001
- **NGINX Ingress**: For routing external traffic
- **Metrics Server**: For container resource metrics
- **Network Policies**: Security isolation between services
- **Secrets Management**: Encrypted credential storage
- **Autoscaling**: Horizontal Pod Autoscaler (HPA) configured

#### 3. Monitoring Stack
- **Prometheus**: Metrics collection and time-series database
- **Grafana**: Visualization and dashboard interface
- **Pre-configured scrape configs**: Kubernetes API, nodes, pods

#### 4. Automation Scripts
- `setup-kind.sh`: Creates Kind cluster and installs prerequisites
- `build-images.sh`: Builds and pushes Docker images
- `deploy.sh`: Deploys all services to the cluster
- `cleanup.sh`: Removes cluster and registry

## Quick Start Commands

### Step 1: Create the cluster
```bash
chmod +x scripts/setup-kind.sh
./scripts/setup-kind.sh
```
Takes ~2-3 minutes

### Step 2: Build and push images
```bash
chmod +x scripts/build-images.sh
./scripts/build-images.sh
```
Takes ~3-5 minutes

### Step 3: Deploy services
```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```
Takes ~1 minute

## Verifying the Setup

### Check Services
```bash
kubectl get pods -A | grep prod-
```
All pods should show "Running" status.

### Test API Health
```bash
curl https://api.local/health -k
```
Response: `{"status":"ok","service":"main-api"}`

### Monitor Resources
```bash
kubectl top nodes
kubectl top pods -n prod-api
```

## Access Points

### Main API
```bash
# Add to /etc/hosts
127.0.0.1 api.local

# Test
curl https://api.local/health -k
```

### Prometheus Metrics
```bash
kubectl port-forward -n prod-monitoring svc/prometheus 9090:9090
# Open: http://localhost:9090
```

### Grafana Dashboards
```bash
kubectl port-forward -n prod-monitoring svc/grafana 3000:3000
# Open: http://localhost:3000
# Login: admin / admin123
```

## Architecture Details

### Network Isolation
Each service is in its own namespace with network policies:
- `prod-api`: Accessible from ingress controller only
- `prod-auth`: Only accessible from main-api
- `prod-image`: Only accessible from main-api

### Service Discovery
Internal DNS for service-to-service communication:
- auth-service: `http://auth-service.prod-auth:8080`
- image-service: `http://image-service.prod-image:5000`

### Autoscaling Configuration
Services scale based on CPU/memory utilization:
- **main-api**: 3-10 replicas, 70% CPU / 80% memory target
- **auth-service**: 2-8 replicas, 75% CPU / 85% memory target
- **image-service**: 2-8 replicas, 70% CPU / 80% memory target

### Health Checks
All services have:
- Liveness probes: Restart if unhealthy
- Readiness probes: Mark unavailable if not ready
- Initial delays: 5-10 seconds before first check

## Testing Scenarios

### 1. Test Service-to-Service Communication
```bash
kubectl exec -it deployment/main-api -n prod-api -- \
  curl http://auth-service.prod-auth:8080/health
```

### 2. Test Network Policy Enforcement
```bash
# This should fail (auth-service only accepts from main-api)
kubectl exec -it deployment/image-service -n prod-image -- \
  curl http://auth-service.prod-auth:8080/health
```

### 3. Test Autoscaling
```bash
# Monitor HPA status
kubectl get hpa -A

# Watch pods scale up under load
kubectl get pods -n prod-api -w
```

### 4. Simulate Pod Failure
```bash
# Kill a pod (it will auto-restart)
kubectl delete pod <pod-name> -n prod-api

# Watch the replica immediately restart
kubectl get pods -n prod-api -w
```

## Monitoring Queries

### Prometheus Queries
- `node_memory_MemAvailable_bytes`: Available memory
- `container_cpu_usage_seconds_total`: CPU usage
- `kube_pod_status_ready`: Pod readiness status
- `kube_deployment_status_replicas`: Deployment replicas

### Kubernetes Status
```bash
# All pods
kubectl get pods -A

# Services
kubectl get svc -A | grep prod-

# Network policies
kubectl get networkpolicies -A

# Ingress
kubectl get ingress -A

# HPA status
kubectl get hpa -A
```

## File Structure

```
project/
├── main-api/              # Node.js service
│   ├── Dockerfile
│   ├── package.json
│   └── server.js
├── auth-service/          # Go service
│   ├── Dockerfile
│   ├── go.mod
│   ├── go.sum
│   └── main.go
├── image-service/         # Python service
│   ├── Dockerfile
│   ├── requirements.txt
│   └── app.py
├── k8s/                   # Kubernetes manifests
│   ├── 00-namespaces.yaml
│   ├── 01-secrets.yaml
│   ├── 02-main-api.yaml
│   ├── 03-auth-service.yaml
│   ├── 04-image-service.yaml
│   ├── 05-network-policies.yaml
│   ├── 06-ingress.yaml
│   ├── 07-autoscaling.yaml
│   ├── 08-prometheus.yaml
│   └── 09-grafana.yaml
├── scripts/               # Setup scripts
│   ├── setup-kind.sh
│   ├── build-images.sh
│   ├── deploy.sh
│   └── cleanup.sh
├── README.md              # Complete documentation
└── SETUP_GUIDE.md         # This file
```

## Troubleshooting

### Cluster not starting
```bash
# Check if ports are available
sudo lsof -i :5001  # Registry port
sudo lsof -i :80    # HTTP port
sudo lsof -i :443   # HTTPS port

# Remove kind-registry network if stuck
docker network rm kind  2>/dev/null || true
```

### Images not pushing
```bash
# Verify registry is running
docker ps | grep registry

# Check registry logs
docker logs kind-registry
```

### Pods stuck in pending
```bash
# Check pod description
kubectl describe pod <pod-name> -n <namespace>

# Check node resources
kubectl describe nodes
kubectl top nodes
```

### Services not communicating
```bash
# Check network policies
kubectl get networkpolicies -n prod-auth
kubectl describe networkpolicy allow-from-api -n prod-auth

# Test DNS resolution
kubectl exec -it deployment/main-api -n prod-api -- \
  nslookup auth-service.prod-auth
```

## Cleanup

To remove everything and free up resources:
```bash
chmod +x scripts/cleanup.sh
./scripts/cleanup.sh
```

This removes:
- Kind cluster
- Docker registry
- All deployed services
- All namespaces

## Next Steps

1. **Add custom dashboards** to Grafana
2. **Test failure scenarios**:
   - Kill pods and observe recovery
   - Simulate high load and watch autoscaling
   - Test network policy enforcement
3. **Implement alerting** in Prometheus
4. **Add persistent storage** for databases
5. **Configure CI/CD pipeline** for deployments
6. **Implement service mesh** (Istio) for advanced networking
7. **Set up logging** (ELK Stack or Loki)

## Key Learning Points

This setup demonstrates:
- Kubernetes workload management (Deployments, Replicas)
- Networking (Ingress, Services, NetworkPolicies)
- Security (Secrets, RBAC, Namespace isolation)
- Observability (Prometheus, Grafana)
- Autoscaling (HPA)
- Health management (Liveness/Readiness probes)
- Local development with production-like architecture

## Support Resources

- Kubernetes Docs: https://kubernetes.io/docs/
- Kind Docs: https://kind.sigs.k8s.io/
- Prometheus Docs: https://prometheus.io/docs/
- Grafana Docs: https://grafana.com/docs/
