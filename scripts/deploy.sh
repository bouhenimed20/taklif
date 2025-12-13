#!/bin/bash

set -e

CLUSTER_NAME="sre-kind"

echo "========================================="
echo "Deploying Services to Kind Cluster"
echo "========================================="

# Ensure cluster is running
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster ${CLUSTER_NAME} not found. Run setup-kind.sh first."
  exit 1
fi

# Set context
kubectl config use-context kind-${CLUSTER_NAME}

echo "[1/4] Applying namespace configurations..."
kubectl apply -f k8s/00-namespaces.yaml

echo "[2/4] Applying secrets and configurations..."
kubectl apply -f k8s/01-secrets.yaml

echo "[3/4] Deploying services..."
kubectl apply -f k8s/02-main-api.yaml
kubectl apply -f k8s/03-auth-service.yaml
kubectl apply -f k8s/04-image-service.yaml

echo "[4/4] Applying network policies and ingress..."
kubectl apply -f k8s/05-network-policies.yaml
kubectl apply -f k8s/06-ingress.yaml
kubectl apply -f k8s/07-autoscaling.yaml

echo ""
echo "Deploying monitoring stack..."
kubectl apply -f k8s/08-prometheus.yaml
kubectl apply -f k8s/09-grafana.yaml

echo ""
echo "========================================="
echo "Deployment Complete!"
echo "========================================="
echo ""
echo "Waiting for pods to be ready..."
echo ""

echo "Checking prod-api..."
kubectl wait --for=condition=ready pod -l app=main-api -n prod-api --timeout=120s || true

echo "Checking prod-auth..."
kubectl wait --for=condition=ready pod -l app=auth-service -n prod-auth --timeout=120s || true

echo "Checking prod-image..."
kubectl wait --for=condition=ready pod -l app=image-service -n prod-image --timeout=120s || true

echo ""
echo "Service Status:"
echo "=============="
kubectl get svc -A | grep -E "prod-|monitoring"

echo ""
echo "Pod Status:"
echo "==========="
kubectl get pods -A | grep -E "prod-|monitoring"

echo ""
echo "Access Points:"
echo "=============="
echo "Main API: http://api.local (add to /etc/hosts: 127.0.0.1 api.local)"
echo "Grafana: kubectl port-forward -n prod-monitoring svc/grafana 3000:3000"
echo "Prometheus: kubectl port-forward -n prod-monitoring svc/prometheus 9090:9090"
echo ""
