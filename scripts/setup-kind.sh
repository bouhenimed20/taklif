#!/bin/bash

set -e

echo "========================================="
echo "SRE Practical Test - Kind Cluster Setup"
echo "========================================="

REGISTRY_NAME="kind-registry"
REGISTRY_PORT="5001"
CLUSTER_NAME="sre-kind"

echo "[1/7] Checking prerequisites..."
command -v kind &> /dev/null || { echo "kind not found. Install it first."; exit 1; }
command -v docker &> /dev/null || { echo "docker not found. Install it first."; exit 1; }
command -v kubectl &> /dev/null || { echo "kubectl not found. Install it first."; exit 1; }

echo "[2/7] Creating local registry..."
if ! docker ps -a --format '{{.Names}}' | grep -q "^${REGISTRY_NAME}$"; then
  docker run -d -p ${REGISTRY_PORT}:5000 --restart=always --name ${REGISTRY_NAME} registry:2
  echo "Registry started: localhost:${REGISTRY_PORT}"
else
  echo "Registry already exists"
fi

echo "[3/7] Creating Kind cluster..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Cluster ${CLUSTER_NAME} already exists. Skipping creation."
else
  cat > /tmp/kind-config.yaml <<EOF
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
EOF

  kind create cluster --config=/tmp/kind-config.yaml
  echo "Cluster ${CLUSTER_NAME} created"
fi

echo "[4/7] Connecting registry to cluster..."
REGISTRY_CONTAINER_ID=$(docker ps -q -f name="^${REGISTRY_NAME}$")
if [ ! -z "$REGISTRY_CONTAINER_ID" ]; then
  NETWORK=$(docker inspect ${REGISTRY_CONTAINER_ID} --format='{{json .HostConfig.NetworkMode}}' | tr -d '"')

  CLUSTER_NODES=$(kind get nodes --name ${CLUSTER_NAME})
  for node in $CLUSTER_NODES; do
    docker network connect ${NETWORK} ${node} 2>/dev/null || true
  done
  echo "Registry connected to cluster nodes"
fi

echo "[5/7] Installing NGINX Ingress Controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/kind/deploy.yaml
echo "Waiting for NGINX to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s || echo "NGINX may still be starting"

echo "[6/8] Installing Metrics Server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
echo "Waiting for Metrics Server to be ready..."
kubectl wait --namespace kube-system \
  --for=condition=ready pod \
  --selector=k8s-app=metrics-server \
  --timeout=60s || echo "Metrics Server may still be starting"

kubectl patch deployment metrics-server -n kube-system --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'

echo "[7/8] Installing cert-manager..."
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
echo "Waiting for cert-manager to be ready..."
kubectl wait --namespace cert-manager \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/instance=cert-manager \
  --timeout=120s || echo "cert-manager may still be starting"

echo "[8/8] Setting up namespaces with labels..."
kubectl get namespaces -o name | while read ns; do
  ns_name="${ns##*/}"
  if [[ "$ns_name" == prod-* ]]; then
    kubectl label namespace "$ns_name" name="$ns_name" --overwrite
  fi
done
kubectl label namespace ingress-nginx name=ingress-nginx --overwrite

kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml


echo ""
echo "========================================="
echo "Setup Complete!"
echo "========================================="
echo ""
echo "Cluster: ${CLUSTER_NAME}"
echo "Registry: localhost:${REGISTRY_PORT}"
echo ""
echo "Next steps:"
echo "1. Build images: ./scripts/build-images.sh"
echo "2. Deploy services: ./scripts/deploy.sh"
echo "3. Monitor with: kubectl port-forward -n prod-monitoring svc/grafana 3000:3000"
echo ""
