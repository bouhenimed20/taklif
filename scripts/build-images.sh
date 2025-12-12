#!/bin/bash

set -e

REGISTRY="localhost:5001"
CLUSTER_NAME="sre-kind"

echo "========================================="
echo "Building and Pushing Images"
echo "========================================="

# Ensure cluster is running
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster ${CLUSTER_NAME} not found. Run setup-kind.sh first."
  exit 1
fi

echo "[1/3] Building main-api image..."
docker build -t ${REGISTRY}/main-api:latest ./main-api
echo "Pushing main-api to registry..."
docker push ${REGISTRY}/main-api:latest

echo ""
echo "[2/3] Building auth-service image..."
docker build -t ${REGISTRY}/auth-service:latest ./auth-service
echo "Pushing auth-service to registry..."
docker push ${REGISTRY}/auth-service:latest

echo ""
echo "[3/3] Building image-service image..."
docker build -t ${REGISTRY}/image-service:latest ./image-service
echo "Pushing image-service to registry..."
docker push ${REGISTRY}/image-service:latest

echo ""
echo "========================================="
echo "All images built and pushed successfully!"
echo "========================================="
