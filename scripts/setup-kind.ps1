# SRE Practical Test - Kind Cluster Setup (PowerShell)

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "SRE Practical Test - Kind Cluster Setup" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$REGISTRY_NAME = "kind-registry"
$REGISTRY_PORT = "5001"
$CLUSTER_NAME = "sre-kind"

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

Write-Host "[3/7] Creating Kind cluster..." -ForegroundColor Yellow
$clusterExists = kind get clusters | Select-String -Pattern "^${CLUSTER_NAME}$"
if (!$clusterExists) {
    $kindConfig = @"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${CLUSTER_NAME}
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
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

Write-Host "[4/7] Connecting registry to cluster..." -ForegroundColor Yellow
$REGISTRY_CONTAINER_ID = docker ps -q -f name="^${REGISTRY_NAME}$"
if ($REGISTRY_CONTAINER_ID) {
    $NETWORK = docker inspect $REGISTRY_CONTAINER_ID --format='{{json .HostConfig.NetworkMode}}' | ConvertFrom-Json
    $CLUSTER_NODES = kind get nodes --name ${CLUSTER_NAME}
    foreach ($node in $CLUSTER_NODES) {
        docker network connect $NETWORK $node 2>$null
    }
    Write-Host "Registry connected to cluster nodes" -ForegroundColor Green
}

Write-Host "[5/7] Installing NGINX Ingress Controller..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
Write-Host "Waiting for NGINX to be ready..." -ForegroundColor Yellow
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

Write-Host "[6/8] Installing Metrics Server..." -ForegroundColor Yellow
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
Write-Host "Waiting for Metrics Server to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 10
kubectl patch deployment metrics-server -n kube-system --type='json' -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

Write-Host "[7/8] Installing cert-manager..." -ForegroundColor Yellow
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
Write-Host "Waiting for cert-manager to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 30
kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=120s

Write-Host "[8/8] Setting up namespaces with labels..." -ForegroundColor Yellow
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

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
Write-Host "3. Monitor with: kubectl port-forward -n prod-monitoring svc/grafana 3000:3000" -ForegroundColor White
Write-Host ""
