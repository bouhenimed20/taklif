# Network Policy Guide - Egress Controls

## Overview

This guide explains the enhanced network policies with egress (outbound) traffic restrictions. All services now operate under a "default-deny-all" policy, with explicit allow rules for necessary communication.

## Security Model

**Zero Trust Architecture:**
- Default deny all ingress and egress traffic
- Explicitly allow only required communication paths
- DNS resolution allowed for all services
- Service-to-service communication strictly controlled

## Network Policy Structure

### prod-api Namespace

Location: `k8s/05-network-policies.yaml:71-145`

#### 1. Default Deny All
```yaml
policyTypes:
- Ingress
- Egress
```
Blocks all inbound and outbound traffic by default.

#### 2. Allow Ingress from NGINX
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: ingress-nginx
  ports:
  - protocol: TCP
    port: 3000
```
Only NGINX Ingress Controller can reach main-api on port 3000.

#### 3. Allow DNS Egress
```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
    podSelector:
      matchLabels:
        k8s-app: kube-dns
  ports:
  - protocol: UDP
    port: 53
  - protocol: TCP
    port: 53
```
Required for service discovery and DNS resolution.

#### 4. Allow Egress to auth-service
```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        name: prod-auth
    podSelector:
      matchLabels:
        app: auth-service
  ports:
  - protocol: TCP
    port: 8080
```
main-api can call auth-service on port 8080.

#### 5. Allow Egress to image-service
```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        name: prod-image
    podSelector:
      matchLabels:
        app: image-service
  ports:
  - protocol: TCP
    port: 5000
```
main-api can call image-service on port 5000.

### prod-auth Namespace

Location: `k8s/05-network-policies.yaml:1-45`

#### 1. Default Deny All
Blocks all traffic by default.

#### 2. Allow Ingress from main-api
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: prod-api
    podSelector:
      matchLabels:
        app: main-api
  ports:
  - protocol: TCP
    port: 8080
```
Only main-api pods can reach auth-service.

#### 3. Allow DNS Egress
Required for internal Kubernetes service discovery.

**No other egress allowed** - auth-service cannot initiate connections to external services or other internal services.

### prod-image Namespace

Location: `k8s/05-network-policies.yaml:47-69`

#### 1. Default Deny All
Blocks all traffic by default.

#### 2. Allow Ingress from main-api
```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        name: prod-api
    podSelector:
      matchLabels:
        app: main-api
  ports:
  - protocol: TCP
    port: 5000
```
Only main-api pods can reach image-service.

#### 3. Allow DNS Egress
Required for service discovery.

#### 4. Allow Egress to S3/MinIO
```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        name: prod-storage
  ports:
  - protocol: TCP
    port: 9000
```
image-service can access S3-compatible storage (MinIO) on port 9000.

## Traffic Flow Diagram

```
Internet
   ↓ (HTTPS)
NGINX Ingress
   ↓ (HTTP:3000, allowed)
main-api (prod-api)
   ├─→ (HTTP:8080, allowed) → auth-service (prod-auth)
   │                              ↓ (DNS:53, allowed)
   │                              kube-dns
   │
   └─→ (HTTP:5000, allowed) → image-service (prod-image)
                                  ├─→ (DNS:53, allowed) → kube-dns
                                  └─→ (TCP:9000, allowed) → MinIO (prod-storage)
```

## Testing Network Policies

### 1. Verify Allowed Communication

**main-api to auth-service (should work):**
```bash
kubectl exec -n prod-api deployment/main-api -- \
  curl -s http://auth-service.prod-auth:8080/health
```

**main-api to image-service (should work):**
```bash
kubectl exec -n prod-api deployment/main-api -- \
  curl -s http://image-service.prod-image:5000/health
```

### 2. Verify Blocked Communication

**auth-service to image-service (should timeout):**
```bash
kubectl exec -n prod-auth deployment/auth-service -- \
  curl -s --connect-timeout 5 http://image-service.prod-image:5000/health
```

**image-service to auth-service (should timeout):**
```bash
kubectl exec -n prod-image deployment/image-service -- \
  curl -s --connect-timeout 5 http://auth-service.prod-auth:8080/health
```

**Direct pod access without going through main-api (should fail):**
```bash
kubectl run test-pod --rm -i --tty --image=busybox --restart=Never -- \
  wget -qO- http://auth-service.prod-auth:8080/health
```

### 3. Test DNS Resolution

**All services should be able to resolve DNS:**
```bash
kubectl exec -n prod-api deployment/main-api -- nslookup kubernetes.default
kubectl exec -n prod-auth deployment/auth-service -- nslookup kubernetes.default
kubectl exec -n prod-image deployment/image-service -- nslookup kubernetes.default
```

## Network Policy Events

### View Applied Policies
```bash
kubectl get networkpolicies -A
```

### Describe Specific Policy
```bash
kubectl describe networkpolicy allow-from-api -n prod-auth
```

### Check Pod Labels
```bash
kubectl get pods -n prod-api --show-labels
kubectl get pods -n prod-auth --show-labels
kubectl get pods -n prod-image --show-labels
```

## Common Issues and Troubleshooting

### Service Cannot Connect

**Symptoms:**
- Timeouts when calling other services
- "Connection refused" errors
- DNS resolution works but connection fails

**Diagnosis:**
```bash
# Check if network policies exist
kubectl get networkpolicies -n <namespace>

# Verify pod labels match policy selectors
kubectl get pods -n <namespace> --show-labels

# Check policy details
kubectl describe networkpolicy <policy-name> -n <namespace>
```

**Common Causes:**
1. Missing egress rule for the source service
2. Missing ingress rule for the destination service
3. Incorrect pod label selectors
4. Wrong namespace labels
5. Incorrect port numbers

### DNS Resolution Fails

**Symptoms:**
- "Could not resolve host" errors
- Service discovery failures

**Solution:**
Ensure DNS egress policy exists:
```bash
kubectl get networkpolicy allow-dns-egress -n <namespace>
```

If missing, the DNS egress rule should be:
```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
    podSelector:
      matchLabels:
        k8s-app: kube-dns
  ports:
  - protocol: UDP
    port: 53
  - protocol: TCP
    port: 53
```

### External API Calls Blocked

**Symptoms:**
- Cannot reach external services (e.g., third-party APIs)
- Timeouts when accessing internet resources

**Solution:**
Add explicit egress rule for external traffic:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-external-apis
  namespace: prod-api
spec:
  podSelector:
    matchLabels:
      app: main-api
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8    # Block internal IPs
        - 172.16.0.0/12
        - 192.168.0.0/16
    ports:
    - protocol: TCP
      port: 443
    - protocol: TCP
      port: 80
```

## Production Considerations

### 1. Namespace Labels

Ensure all namespaces have proper labels:
```bash
kubectl label namespace prod-api name=prod-api
kubectl label namespace prod-auth name=prod-auth
kubectl label namespace prod-image name=prod-image
kubectl label namespace ingress-nginx name=ingress-nginx
```

### 2. Pod Disruption

Network policies do not cause pod restarts, but ensure they are applied before deploying services.

### 3. Monitoring

**Track blocked connections:**
- Use CNI plugin logs (Calico, Cilium)
- Enable network policy logging
- Monitor connection timeouts in application logs

**Calico logging example:**
```bash
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100 | grep -i "denied"
```

### 4. Audit Network Policies

Regularly review and audit network policies:
```bash
# List all network policies
kubectl get networkpolicies -A -o wide

# Export for review
kubectl get networkpolicies -A -o yaml > network-policies-audit.yaml
```

### 5. Testing Before Production

Always test network policies in staging:
1. Deploy policies
2. Run integration tests
3. Verify all service-to-service communication
4. Check application logs for connection errors
5. Load test to ensure no performance impact

## Advanced Configurations

### Allow Specific External IPs

```yaml
egress:
- to:
  - ipBlock:
      cidr: 203.0.113.0/24  # Specific external service
  ports:
  - protocol: TCP
    port: 443
```

### Allow Multiple Ports

```yaml
egress:
- to:
  - namespaceSelector:
      matchLabels:
        name: prod-database
  ports:
  - protocol: TCP
    port: 5432
  - protocol: TCP
    port: 6379
```

### Combined Ingress and Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: combined-policy
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: allowed-source
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: allowed-destination
```

## Security Best Practices

1. **Default Deny:** Always start with default-deny-all policies
2. **Least Privilege:** Only allow necessary connections
3. **Document Policies:** Comment why each rule exists
4. **Regular Audits:** Review policies quarterly
5. **Test Changes:** Always test in non-production first
6. **Monitor Traffic:** Log and monitor denied connections
7. **Version Control:** Keep policies in Git with review process

## References

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [Network Policy Recipes](https://github.com/ahmetb/kubernetes-network-policy-recipes)
- [Calico Network Policy](https://docs.projectcalico.org/security/kubernetes-network-policy)
- [Cilium Network Policy](https://docs.cilium.io/en/stable/policy/)
