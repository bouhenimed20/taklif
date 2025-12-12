#!/bin/bash

set -e

CLUSTER_NAME="sre-kind"
REGISTRY_NAME="kind-registry"

echo "========================================="
echo "Cleaning up Kind Cluster and Registry"
echo "========================================="

read -p "This will delete the cluster and registry. Continue? (yes/no): " -r
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo "Deleting Kind cluster..."
kind delete cluster --name ${CLUSTER_NAME} || true

echo "Stopping and removing registry..."
docker stop ${REGISTRY_NAME} 2>/dev/null || true
docker rm ${REGISTRY_NAME} 2>/dev/null || true

echo ""
echo "========================================="
echo "Cleanup Complete!"
echo "========================================="
