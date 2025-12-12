# Cleanup Kind Cluster and Registry (PowerShell)

$ErrorActionPreference = "Stop"

$CLUSTER_NAME = "sre-kind"
$REGISTRY_NAME = "kind-registry"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Cleaning up Kind Cluster and Registry" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan

$confirmation = Read-Host "This will delete the cluster and registry. Continue? (yes/no)"
if ($confirmation -ne "yes") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit 0
}

Write-Host "Deleting Kind cluster..." -ForegroundColor Yellow
kind delete cluster --name ${CLUSTER_NAME}

Write-Host "Stopping and removing registry..." -ForegroundColor Yellow
docker stop ${REGISTRY_NAME} 2>$null
docker rm ${REGISTRY_NAME} 2>$null

Write-Host ""
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Cleanup Complete!" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Cyan
