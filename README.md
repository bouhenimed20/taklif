# SRE Practical Test - Local Kind Kubernetes Setup

A complete production-like microservices architecture running on local Kubernetes with security isolation, monitoring, autoscaling, and failure recovery.

## Architecture Overview

```
Client
  ↓
Ingress (TLS)
  ↓
main-api (Node.js, port 3000)
  ├── → auth-service (Go, port 8080)
  └── → image-service (Python, port 5000)
```

### Services

1. **main-api** (Node.js)
   - Public API entrypoint
   - Routes authentication and image requests
   - Deployed to `prod-api` namespace
   - 3 replicas with autoscaling

2. **auth-service** (Go)
   - Internal authentication service
   - JWT token generation
   - Deployed to `prod-auth` namespace
   - 2 replicas with autoscaling
   - Network policy: only accessible from main-api

3. **image-service** (Python)
   - Image upload and management
   - S3 storage integration (MinIO compatible)
   - Deployed to `prod-image` namespace
   - 2 replicas with autoscaling
   - Network policy: only accessible from main-api

### Security Features

- **Namespace Isolation**: Services separated into dedicated namespaces
- **Network Policies**: Default-deny ingress with explicit allow rules
- **Secrets Management**: All sensitive data in Kubernetes Secrets
- **RBAC**: Limited service accounts and permissions
- **TLS**: Ingress with self-signed certificates (cert-manager)

### Monitoring & Observability

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Metrics Server**: For HPA (Horizontal Pod Autoscaler)

### Autoscaling

- CPU and memory-based HPA for all services
- Min/max replica ranges configured per service
- Target metrics: CPU 70-75%, Memory 80-85%

## Prerequisites

- Docker (latest)
- Kind (v0.20+)
- kubectl (v1.28+)
- docker (for building and pushing images)

## Quick Start

### 1. Setup Kind Cluster

```bash
chmod +x scripts/setup-kind.sh
./scripts/setup-kind.sh
```

This will:
- Create a local Docker registry on port 5001
- Create a Kind cluster with 3 nodes (1 control plane, 2 workers)
- Install NGINX Ingress Controller
- Install Metrics Server for autoscaling

### 2. Build and Push Images

```bash
chmod +x scripts/build-images.sh
./scripts/build-images.sh
```

Builds all service images and pushes to local registry.

### 3. Deploy Services

```bash
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

Deploys all microservices, network policies, monitoring stack.

### 4. Access Services

#### Add to /etc/hosts
```bash
127.0.0.1 api.local
```

#### Main API
```bash
curl https://api.local/health
```

#### Prometheus
```bash
kubectl port-forward -n prod-monitoring svc/prometheus 9090:9090
# Access: http://localhost:9090
```

#### Grafana
```bash
kubectl port-forward -n prod-monitoring svc/grafana 3000:3000
# Access: http://localhost:3000
# Default credentials: admin / admin123
```

## Project Structure

```
.
├── main-api/                 # Node.js API service
│   ├── package.json
│   ├── server.js
│   └── Dockerfile
├── auth-service/             # Go authentication service
│   ├── go.mod
│   ├── main.go
│   └── Dockerfile
├── image-service/            # Python image service
│   ├── requirements.txt
│   ├── app.py
│   └── Dockerfile
├── k8s/                       # Kubernetes manifests
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
└── scripts/
    ├── setup-kind.sh         # Create Kind cluster
    ├── build-images.sh       # Build and push images
    ├── deploy.sh             # Deploy services
    └── cleanup.sh            # Cleanup cluster
```

## API Endpoints

### Main API
- `GET /health` - Health check
- `POST /api/auth/login` - Login (proxies to auth-service)
- `POST /api/auth/register` - Register (proxies to auth-service)
- `POST /api/images/upload` - Upload image (proxies to image-service)
- `GET /api/images/{id}` - Get image (proxies to image-service)

### Auth Service
- `GET /health` - Health check
- `POST /auth/login` - Login endpoint
- `POST /auth/register` - Register endpoint

### Image Service
- `GET /health` - Health check
- `POST /images/upload` - Upload image
- `GET /images/{id}` - Get image metadata

## Testing

### Verify Services are Running
```bash
kubectl get pods -A | grep prod-
```

### Check Service Connectivity
```bash
kubectl exec -it deployment/main-api -n prod-api -- curl http://auth-service.prod-auth:8080/health
```

### Monitor Logs
```bash
kubectl logs -f deployment/main-api -n prod-api
kubectl logs -f deployment/auth-service -n prod-auth
kubectl logs -f deployment/image-service -n prod-image
```

### Test API
```bash
# Health check
curl https://api.local/health -k

# Login
curl -X POST https://api.local/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com","password":"pass"}' -k
```

## Network Policies

Network policies enforce security boundaries:

1. **prod-auth**: Default deny + allow only from main-api
2. **prod-image**: Default deny + allow only from main-api
3. **prod-api**: Allow from NGINX ingress controller

## Secrets Management

All sensitive data is stored in Kubernetes Secrets:

- `auth-secrets` (prod-auth): JWT_SECRET
- `image-secrets` (prod-image): AWS credentials, S3 config
- `api-secrets` (prod-api): Service URLs

To update a secret:
```bash
kubectl edit secret auth-secrets -n prod-auth
```

## Troubleshooting

### Pods not starting
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
```

### Services not communicating
```bash
# Check network policies
kubectl get networkpolicies -A

# Verify DNS
kubectl exec -it deployment/main-api -n prod-api -- nslookup auth-service.prod-auth
```

### Metrics not appearing in Prometheus
```bash
# Check Metrics Server
kubectl get deployment metrics-server -n kube-system
kubectl logs -f deployment/metrics-server -n kube-system
```

### High resource usage
```bash
# Check metrics
kubectl top nodes
kubectl top pods -n prod-api
kubectl top pods -n prod-auth
kubectl top pods -n prod-image
```

## Cleanup

```bash
chmod +x scripts/cleanup.sh
./scripts/cleanup.sh
```

This will:
- Delete the Kind cluster
- Stop and remove the local registry
- Remove all deployed services

## Performance Considerations

- **Autoscaling**: Configured for CPU 70% and Memory 80% utilization
- **Resource Limits**: Set to prevent node overload
- **Liveness/Readiness Probes**: Configured for fast failure detection
- **Rolling Updates**: Zero-downtime deployments enabled

## Production Differences

This setup mirrors production patterns but differs in:

1. **TLS**: Uses self-signed certificates (use Let's Encrypt in prod)
2. **Registry**: Local Docker registry (use Docker Hub/ECR in prod)
3. **Storage**: EmptyDir for monitoring (use PersistentVolumes in prod)
4. **Scaling**: Limited to local machine resources
5. **Secrets**: Base K8s secrets (use external secret store in prod)

## Next Steps

1. Add health check dashboards to Grafana
2. Configure persistent storage for monitoring
3. Add ingress-nginx annotations for rate limiting
4. Implement service-to-service mTLS with Istio
5. Add failure injection for chaos engineering tests
6. Configure backup and disaster recovery

## Support

For issues or questions, check the logs:
```bash
kubectl logs -f deployment/<service> -n <namespace>
```

## License

SRE Practical Test - Educational project for Kubernetes and microservices
