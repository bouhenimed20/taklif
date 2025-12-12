# Deploy Services to Kind Cluster (PowerShell)

$ErrorActionPreference = "Stop"

$CLUSTER_NAME = "sre-kind"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Deploying Services to Kind Cluster" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Ensure cluster is running
$clusterExists = kind get clusters | Select-String -Pattern "^${CLUSTER_NAME}$"
if (!$clusterExists) {
    Write-Host "Cluster ${CLUSTER_NAME} not found. Run setup-kind.ps1 first." -ForegroundColor Red
    exit 1
}

# Set context
kubectl config use-context kind-${CLUSTER_NAME}

Write-Host "[1/4] Applying namespace configurations..." -ForegroundColor Yellow
kubectl apply -f k8s/00-namespaces.yaml

Write-Host "[2/4] Applying secrets and configurations..." -ForegroundColor Yellow
kubectl apply -f k8s/01-secrets.yaml

Write-Host "[3/4] Deploying services..." -ForegroundColor Yellow
kubectl apply -f k8s/02-main-api.yaml
kubectl apply -f k8s/03-auth-service.yaml
kubectl apply -f k8s/04-image-service.yaml

Write-Host "[4/4] Applying network policies and ingress..." -ForegroundColor Yellow
kubectl apply -f k8s/05-network-policies.yaml
kubectl apply -f k8s/06-ingress.yaml
kubectl apply -f k8s/07-autoscaling.yaml

Write-Host ""
Write-Host "Deploying monitoring stack..." -ForegroundColor Yellow
kubectl apply -f k8s/08-prometheus.yaml
kubectl apply -f k8s/09-grafana.yaml

Write-Host ""
Write-Host "Deploying cert-manager resources..." -ForegroundColor Yellow
kubectl apply -f k8s/10-cert-manager.yaml

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Deployment Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Waiting for pods to be ready..." -ForegroundColor Yellow
Write-Host ""

Write-Host "Checking prod-api..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=main-api -n prod-api --timeout=120s

Write-Host "Checking prod-auth..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=auth-service -n prod-auth --timeout=120s

Write-Host "Checking prod-image..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=image-service -n prod-image --timeout=120s

Write-Host ""
Write-Host "Service Status:" -ForegroundColor Cyan
Write-Host "==============" -ForegroundColor Cyan
kubectl get svc -A | Select-String -Pattern "prod-|monitoring"

Write-Host ""
Write-Host "Pod Status:" -ForegroundColor Cyan
Write-Host "===========" -ForegroundColor Cyan
kubectl get pods -A | Select-String -Pattern "prod-|monitoring"

Write-Host ""
Write-Host "Access Points:" -ForegroundColor Cyan
Write-Host "==============" -ForegroundColor Cyan
Write-Host "Main API: http://api.local (add to C:\Windows\System32\drivers\etc\hosts: 127.0.0.1 api.local)" -ForegroundColor White
Write-Host "Grafana: kubectl port-forward -n prod-monitoring svc/grafana 3000:3000" -ForegroundColor White
Write-Host "Prometheus: kubectl port-forward -n prod-monitoring svc/prometheus 9090:9090" -ForegroundColor White
Write-Host ""
