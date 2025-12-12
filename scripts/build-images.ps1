# Build and Push Images (PowerShell)

$ErrorActionPreference = "Stop"

$REGISTRY = "localhost:5001"
$CLUSTER_NAME = "sre-kind"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Building and Pushing Images" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

# Ensure cluster is running
$clusterExists = kind get clusters | Select-String -Pattern "^${CLUSTER_NAME}$"
if (!$clusterExists) {
    Write-Host "Cluster ${CLUSTER_NAME} not found. Run setup-kind.ps1 first." -ForegroundColor Red
    exit 1
}

Write-Host "[1/3] Building main-api image..." -ForegroundColor Yellow
docker build -t ${REGISTRY}/main-api:latest ./main-api
Write-Host "Pushing main-api to registry..." -ForegroundColor Yellow
docker push ${REGISTRY}/main-api:latest

Write-Host ""
Write-Host "[2/3] Building auth-service image..." -ForegroundColor Yellow
docker build -t ${REGISTRY}/auth-service:latest ./auth-service
Write-Host "Pushing auth-service to registry..." -ForegroundColor Yellow
docker push ${REGISTRY}/auth-service:latest

Write-Host ""
Write-Host "[3/3] Building image-service image..." -ForegroundColor Yellow
docker build -t ${REGISTRY}/image-service:latest ./image-service
Write-Host "Pushing image-service to registry..." -ForegroundColor Yellow
docker push ${REGISTRY}/image-service:latest

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "All images built and pushed successfully!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
