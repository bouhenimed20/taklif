# SRE Practical Test - Kind Cluster Setup (PowerShell) - FIXED for Windows/kind

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "SRE Practical Test - Kind Cluster Setup" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$REGISTRY_NAME = "kind-registry"
$REGISTRY_PORT = "5001"
$CLUSTER_NAME  = "sre-kind"

Write-Host "[1/7] Checking prerequisites..." -ForegroundColor Yellow
$commands = @("kind", "docker", "kubectl")
foreach ($cmd in $commands) {
    if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Host "$cmd not found. Install it first." -ForegroundColor Red
        exit 1
    }
}

Write-Host "[2/7] Creating local registry..." -ForegroundColor Yellow
$registryExists = docker ps -a --format '{{.Names}}' | Select-String -Pattern "^${REGISTRY_NAME}$"
if (!$registryExists) {
    docker run -d -p ${REGISTRY_PORT}:5000 --restart=always --name ${REGISTRY_NAME} registry:2
    Write-Host "Registry started: localhost:${REGISTRY_PORT}" -ForegroundColor Green
} else {
    Write-Host "Registry already exists" -ForegroundColor Green
}

Write-Host "[3/7] Creating Kind cluster (Calico-only CNI)..." -ForegroundColor Yellow
$clusterExists = kind get clusters | Select-String -Pattern "^${CLUSTER_NAME}$"
if (!$clusterExists) {

    # IMPORTANT:
    # - disableDefaultCNI: true so kindnet is NOT installed
    # - Calico will be installed next as the ONLY CNI
    # - no extraPortMappings (we'll access ingress via port-forward)
    $kindConfig = @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
networking:
  disableDefaultCNI: true
  podSubnet: "192.168.0.0/16"
nodes:
- role: control-plane
- role: worker
- role: worker
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${REGISTRY_PORT}"]
    endpoint = ["http://${REGISTRY_NAME}:5000"]
"@

    $kindConfig | Out-File -FilePath "$env:TEMP\kind-config.yaml" -Encoding UTF8

    kind create cluster --config="$env:TEMP\kind-config.yaml"
    Write-Host "Cluster ${CLUSTER_NAME} created" -ForegroundColor Green
} else {
    Write-Host "Cluster ${CLUSTER_NAME} already exists. Skipping creation." -ForegroundColor Green
}

# Ensure kubectl context is correct
kubectl config use-context "kind-${CLUSTER_NAME}" | Out-Null

Write-Host "[4/7] Connecting registry to kind network..." -ForegroundColor Yellow
# Simple correct connect: registry container joins the kind network
docker network connect kind ${REGISTRY_NAME} 2>$null | Out-Null
Write-Host "Registry connected to kind network" -ForegroundColor Green

Write-Host "[5/7] Installing Calico CNI (wait until ready)..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

Write-Host "Waiting for Calico nodes to be ready..." -ForegroundColor Yellow
kubectl wait -n kube-system --for=condition=Ready pod -l k8s-app=calico-node --timeout=300s

Write-Host "[6/7] Installing NGINX Ingress Controller..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

Write-Host "Waiting for NGINX to be ready..." -ForegroundColor Yellow
kubectl wait -n ingress-nginx --for=condition=Ready pod -l app.kubernetes.io/component=controller --timeout=240s

Write-Host "[7/7] Installing Metrics Server (with kind patch)..." -ForegroundColor Yellow
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Patch for kind TLS + address types
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"},
  {"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP"}
]'

Write-Host "Waiting for Metrics Server to be ready..." -ForegroundColor Yellow
kubectl rollout status deploy/metrics-server -n kube-system --timeout=180s

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Cluster: ${CLUSTER_NAME}" -ForegroundColor White
Write-Host "Registry: localhost:${REGISTRY_PORT}" -ForegroundColor White
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Build images: .\scripts\build-images.ps1" -ForegroundColor White
Write-Host "2. Deploy services: .\scripts\deploy.ps1" -ForegroundColor White
Write-Host "3. Ingress access: kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 8081:80" -ForegroundColor White
Write-Host ""
