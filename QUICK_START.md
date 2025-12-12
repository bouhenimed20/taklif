# Quick Start Guide - Windows PowerShell

This project is **ready to run** and answers all SRE practical test requirements!

## What You Have

A complete Kubernetes microservices setup with:
- 3 services (Node.js, Go, Python)
- Private registry
- Network security
- TLS/SSL
- Autoscaling
- Monitoring (Prometheus + Grafana)
- All in Arabic guide: `ARABIC_GUIDE.md`

## Prerequisites Check

Open PowerShell and verify:
```powershell
docker --version
kind --version
kubectl version --client
```

All should return version numbers. If not, install the missing tool.

## Step-by-Step Setup (5 minutes)

### 1. Create the Cluster
```powershell
# Navigate to project directory
cd path\to\project

# Run setup script
.\scripts\setup-kind.ps1
```
**Time:** ~2-3 minutes
**What it does:** Creates Kind cluster, local registry, installs ingress & metrics server

### 2. Build & Push Images
```powershell
.\scripts\build-images.ps1
```
**Time:** ~3-5 minutes
**What it does:** Builds Docker images for all 3 services and pushes to local registry

### 3. Deploy Services
```powershell
.\scripts\deploy.ps1
```
**Time:** ~1-2 minutes
**What it does:** Deploys all services, network policies, ingress, autoscaling, monitoring

### 4. Add Domain to Hosts File
**Run PowerShell as Administrator:**
```powershell
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n127.0.0.1 api.local"
```

## Verify Everything Works

### Check Pods Status
```powershell
kubectl get pods -A
```
All pods should show "Running" status.

### Test the API
```powershell
# Using curl (if installed)
curl https://api.local/health -k

# Or using PowerShell
Invoke-WebRequest -Uri https://api.local/health -SkipCertificateCheck
```
Response should be: `{"status":"ok"}`

### Access Grafana Dashboard
```powershell
kubectl port-forward -n prod-monitoring svc/grafana 3000:3000
```
Open browser: http://localhost:3000
- Username: `admin`
- Password: `admin123`

### Access Prometheus
```powershell
kubectl port-forward -n prod-monitoring svc/prometheus 9090:9090
```
Open browser: http://localhost:9090

## Architecture Overview

```
Internet → Ingress (TLS) → main-api → auth-service (Go)
                                    → image-service (Python)
```

- **Namespaces:** Isolated (prod-api, prod-auth, prod-image, prod-monitoring)
- **Network Policies:** Only authorized communication allowed
- **Secrets:** All sensitive data encrypted
- **Autoscaling:** CPU/Memory based HPA
- **Monitoring:** Full Prometheus + Grafana stack

## Test Network Security

```powershell
# This should SUCCEED (main-api can access auth-service)
kubectl exec -it deployment/main-api -n prod-api -- curl http://auth-service.prod-auth:8080/health

# This should FAIL (image-service cannot access auth-service)
kubectl exec -it deployment/image-service -n prod-image -- curl http://auth-service.prod-auth:8080/health --connect-timeout 5
```

## Test Autoscaling

```powershell
# Watch HPA status
kubectl get hpa -A -w

# In another window, check current pods
kubectl get pods -n prod-api

# Generate load to trigger scaling
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -n prod-api -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://main-api:3000/health; done"
```
You'll see pods scale from 3 to higher numbers.

## Cleanup

When done, remove everything:
```powershell
.\scripts\cleanup.ps1
```
Type `yes` to confirm deletion.

## Troubleshooting

### Pods stuck in "Pending"
```powershell
kubectl describe pod <pod-name> -n <namespace>
```

### Registry connection issues
```powershell
docker ps | Select-String "registry"
```
Should show registry running on port 5001.

### Metrics not showing
```powershell
kubectl get deployment metrics-server -n kube-system
kubectl logs -f deployment/metrics-server -n kube-system
```

## Project Structure

```
project/
├── main-api/           # Node.js service
├── auth-service/       # Go service
├── image-service/      # Python service
├── k8s/                # All Kubernetes manifests
├── scripts/            # Setup scripts (PowerShell + Bash)
├── ARABIC_GUIDE.md     # Complete Arabic documentation
├── SETUP_GUIDE.md      # Detailed setup guide
└── README.md           # Project overview
```

## Key Files

- `ARABIC_GUIDE.md` - **Complete test requirements coverage in Arabic**
- `README.md` - Technical documentation
- `SETUP_GUIDE.md` - Detailed setup instructions
- `k8s/*.yaml` - All Kubernetes configurations
- `scripts/*.ps1` - PowerShell scripts for Windows

## What Makes This SRE-Ready?

✅ **Multi-language microservices** (Node.js, Go, Python)
✅ **Kubernetes deployment** with proper resource management
✅ **Private registry** for images
✅ **Network isolation** with Network Policies
✅ **Secrets management** for sensitive data
✅ **TLS/SSL** on Ingress
✅ **Autoscaling** (HPA) based on CPU/Memory
✅ **Monitoring** with Prometheus + Grafana
✅ **Health checks** (Liveness + Readiness probes)
✅ **Zero-downtime deployments** (Rolling updates)
✅ **High availability** (Multiple replicas)
✅ **Failure recovery** (Auto-restart, Auto-scale)

## Next Steps

1. Review `ARABIC_GUIDE.md` for complete test coverage explanation
2. Test failure scenarios (delete pods, generate load)
3. Create custom Grafana dashboards
4. Document any additional features you add

## Support

For detailed explanations:
- **Arabic Guide:** `ARABIC_GUIDE.md` (complete test requirements)
- **Technical Details:** `README.md`
- **Setup Help:** `SETUP_GUIDE.md`

---

**Your SRE test project is ready! 🚀**
