# SRE Kubernetes Enhancements

## Summary of Enhancements

This document outlines three major security and scalability enhancements added to the SRE practical test project.

## 1. Advanced Horizontal Pod Autoscaling (HPA)

### What Changed

Enhanced HPA configurations for all three services with:
- Advanced scaling behavior policies
- Custom Prometheus metrics integration
- Fine-tuned scale-up and scale-down controls

### Files Modified
- `k8s/07-autoscaling.yaml`

### Key Features

#### Scale-Up Behavior
- Zero stabilization window for immediate response
- Can scale by 100% or add 2-4 pods per 15 seconds
- Fast response to traffic spikes

#### Scale-Down Behavior
- 5-minute stabilization window to prevent flapping
- Maximum 50% reduction per cycle
- Gradual and safe scale-down

#### Multi-Metric Scaling
- CPU utilization (70-75%)
- Memory utilization (80-85%)
- Custom Prometheus metrics (main-api: http_request_duration_ms)

### Documentation
See `HPA_GUIDE.md` for complete details on:
- Testing autoscaling
- Custom metrics setup
- Prometheus adapter configuration
- Production recommendations

### Benefits
- Faster response to load increases
- Stable performance during traffic fluctuations
- Cost optimization through intelligent scale-down
- Application-aware scaling using custom metrics

---

## 2. Network Policy Egress Controls

### What Changed

Added comprehensive egress (outbound) traffic restrictions to all namespaces. All services now operate under a "default-deny-all" policy with explicit allow rules.

### Files Modified
- `k8s/05-network-policies.yaml`

### Security Model

#### Default Policy
All namespaces now have:
```yaml
policyTypes:
- Ingress
- Egress
```
This blocks ALL incoming and outgoing traffic by default.

#### Allowed Communication

**prod-api namespace:**
- Ingress: From NGINX Ingress Controller only
- Egress:
  - DNS resolution (kube-dns)
  - auth-service (port 8080)
  - image-service (port 5000)

**prod-auth namespace:**
- Ingress: From main-api only
- Egress: DNS resolution only

**prod-image namespace:**
- Ingress: From main-api only
- Egress:
  - DNS resolution (kube-dns)
  - S3 storage (MinIO, port 9000)

### Documentation
See `NETWORK_POLICY_GUIDE.md` for:
- Traffic flow diagrams
- Testing procedures
- Troubleshooting guide
- Production considerations

### Benefits
- Zero-trust security architecture
- Prevents lateral movement in case of compromise
- Explicit control over service-to-service communication
- Blocks unauthorized external connections
- Compliance with security best practices

---

## 3. cert-manager and Let's Encrypt Integration

### What Changed

Replaced self-signed certificates with automated certificate management using cert-manager and Let's Encrypt.

### Files Added
- `k8s/10-cert-manager.yaml` - ClusterIssuers and Certificate resources

### Files Modified
- `k8s/06-ingress.yaml` - Added cert-manager annotations
- `scripts/setup-kind.sh` - Added cert-manager installation
- `scripts/setup-kind.ps1` - Added cert-manager installation
- `scripts/deploy.sh` - Deploy cert-manager resources
- `scripts/deploy.ps1` - Deploy cert-manager resources

### Components

#### ClusterIssuers
Two issuers configured:
1. **letsencrypt-staging** - For testing (rate limit-free)
2. **letsencrypt-prod** - For production (trusted certificates)

#### Certificate Resource
Automatically requests and manages TLS certificates:
- Automatic issuance via ACME protocol
- HTTP-01 challenge validation
- Automatic renewal (30 days before expiry)
- Stored in Kubernetes Secrets

#### Ingress Integration
Ingress annotations trigger automatic certificate management:
```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-staging"
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
  nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

### Documentation
See `CERT_MANAGER_GUIDE.md` for:
- Setup instructions
- Switching to production
- Domain configuration
- Troubleshooting
- Advanced configurations (DNS-01, wildcards)

### Benefits
- Trusted SSL/TLS certificates (no browser warnings)
- Automatic certificate renewal
- No manual certificate management
- Industry-standard ACME protocol
- Free certificates from Let's Encrypt
- Automatic HTTP to HTTPS redirect

---

## Quick Start

### 1. Setup Cluster (includes cert-manager)
```bash
./scripts/setup-kind.sh
```

### 2. Build Images
```bash
./scripts/build-images.sh
```

### 3. Deploy Services (includes all enhancements)
```bash
./scripts/deploy.sh
```

### 4. Verify Enhancements

**Check HPA:**
```bash
kubectl get hpa -A
kubectl describe hpa main-api-hpa -n prod-api
```

**Check Network Policies:**
```bash
kubectl get networkpolicies -A
kubectl describe networkpolicy default-deny-all -n prod-auth
```

**Check Certificates:**
```bash
kubectl get certificate -n prod-api
kubectl describe certificate api-tls-cert -n prod-api
```

---

## Testing Procedures

### Test Autoscaling

Generate load:
```bash
kubectl run load-generator --rm -i --tty --image=busybox --restart=Never -n prod-api -- \
  /bin/sh -c "while sleep 0.01; do wget -q -O- http://main-api:3000/health; done"
```

Watch scaling:
```bash
kubectl get hpa -A -w
kubectl get pods -n prod-api -w
```

### Test Network Policies

**Should succeed (allowed):**
```bash
kubectl exec -n prod-api deployment/main-api -- \
  curl http://auth-service.prod-auth:8080/health
```

**Should timeout (blocked):**
```bash
kubectl exec -n prod-auth deployment/auth-service -- \
  curl --connect-timeout 5 http://image-service.prod-image:5000/health
```

### Test Certificate Management

Check certificate status:
```bash
kubectl get certificate -n prod-api
kubectl describe certificate api-tls-cert -n prod-api
```

View cert-manager logs:
```bash
kubectl logs -n cert-manager deployment/cert-manager
```

---

## Architecture Diagram (Updated)

```
                    Internet/Client
                          │
                          │ HTTPS (TLS via cert-manager)
                          ▼
                  ┌──────────────────┐
                  │ NGINX Ingress    │
                  │ (Let's Encrypt)  │
                  └────────┬─────────┘
                           │
            ┌──────────────┴──────────────┐
            │      prod-api namespace     │
            │  ┌────────────────────────┐ │
            │  │  main-api (HPA 3-10)   │ │
            │  │  - Egress: auth, image │ │
            │  │  - Ingress: ingress-nx │ │
            │  └──────┬────────┬────────┘ │
            └─────────┼────────┼──────────┘
                      │        │
        ┌─────────────┘        └─────────────┐
        │                                     │
        │ Allowed egress                     │ Allowed egress
        ▼                                     ▼
┌───────────────────┐              ┌───────────────────┐
│ prod-auth         │              │ prod-image        │
│ ┌───────────────┐ │              │ ┌───────────────┐ │
│ │ auth-service  │ │              │ │ image-service │ │
│ │ (HPA 2-8)     │ │              │ │ (HPA 2-8)     │ │
│ │ Egress: DNS   │ │              │ │ Egress: DNS   │ │
│ │ Ingress: API  │ │              │ │ Egress: S3    │ │
│ └───────────────┘ │              │ │ Ingress: API  │ │
└───────────────────┘              │ └───────┬───────┘ │
                                   └─────────┼─────────┘
                                             │
                                             │ Allowed egress
                                             ▼
                                    ┌─────────────────┐
                                    │  S3 (MinIO)     │
                                    │  prod-storage   │
                                    └─────────────────┘

        ┌────────────────────────────────────┐
        │   prod-monitoring namespace        │
        │  ┌──────────┐     ┌──────────┐    │
        │  │Prometheus│◄────┤ Grafana  │    │
        │  └────┬─────┘     └──────────┘    │
        │       │ Scrapes all pods           │
        └───────┼────────────────────────────┘
                │
                └──► All services (metrics)
```

**Legend:**
- HPA: Horizontal Pod Autoscaler with min-max replicas
- Egress: Allowed outbound traffic
- Ingress: Allowed inbound traffic
- All unlisted traffic is DENIED by default

---

## Production Readiness

### Checklist

**HPA:**
- [ ] Install Prometheus Adapter for custom metrics
- [ ] Configure application metrics endpoints
- [ ] Test autoscaling under realistic load
- [ ] Set appropriate min/max replica counts
- [ ] Configure PodDisruptionBudgets

**Network Policies:**
- [ ] Verify all namespace labels are correct
- [ ] Test all service-to-service communication paths
- [ ] Document any additional egress requirements
- [ ] Enable network policy logging (CNI-specific)
- [ ] Regular security audits

**cert-manager:**
- [ ] Update email address in ClusterIssuer
- [ ] Point domain DNS to cluster
- [ ] Test with staging issuer first
- [ ] Switch to production issuer
- [ ] Configure certificate expiry alerts
- [ ] Document renewal procedures

### Performance Considerations

**HPA:**
- Prometheus scrape interval: 15s
- HPA evaluation interval: 15s
- Metrics availability delay: ~30s
- Scale-up response time: <1 minute
- Scale-down response time: 5+ minutes (stabilization)

**Network Policies:**
- Minimal performance overhead (<1%)
- Applied at pod creation time
- Does not affect existing connections
- CNI plugin dependent (Calico recommended)

**cert-manager:**
- Certificate issuance: 1-5 minutes (first time)
- Renewal: Automatic, 30 days before expiry
- HTTP-01 challenge: Requires port 80 accessible
- Rate limits: 50 certs/domain/week (Let's Encrypt)

---

## Troubleshooting

### Common Issues

**HPA not scaling:**
- Check Metrics Server: `kubectl top nodes`
- Verify resource requests in deployments
- Check HPA status: `kubectl describe hpa <name> -n <namespace>`

**Network policies blocking traffic:**
- Verify namespace labels: `kubectl get ns --show-labels`
- Check pod labels: `kubectl get pods -n <namespace> --show-labels`
- Test DNS: `kubectl exec <pod> -- nslookup kubernetes.default`

**Certificate not issuing:**
- Check cert-manager logs: `kubectl logs -n cert-manager deployment/cert-manager`
- Verify DNS points to cluster
- Check challenge status: `kubectl get challenges -A`
- Test with staging issuer first

### Getting Help

Refer to detailed guides:
- `HPA_GUIDE.md` - Complete HPA documentation
- `NETWORK_POLICY_GUIDE.md` - Network security guide
- `CERT_MANAGER_GUIDE.md` - Certificate management guide

---

## Maintenance

### Regular Tasks

**Weekly:**
- Monitor HPA scaling events
- Review network policy deny logs
- Check certificate validity

**Monthly:**
- Audit autoscaling thresholds
- Review network policy rules
- Test certificate renewal

**Quarterly:**
- Performance tuning of HPA metrics
- Security audit of network policies
- Update cert-manager and dependencies

---

## Summary

These three enhancements transform the SRE test project into a production-ready Kubernetes deployment:

1. **HPA** ensures optimal resource utilization and cost efficiency
2. **Network Policies** provide defense-in-depth security
3. **cert-manager** eliminates manual certificate management

All enhancements follow Kubernetes best practices and are fully automated through the provided scripts.
