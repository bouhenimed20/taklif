# cert-manager and Let's Encrypt Integration Guide

## Overview

This guide explains the cert-manager integration for automatic TLS certificate management using Let's Encrypt instead of self-signed certificates.

## What is cert-manager?

cert-manager is a Kubernetes add-on that automates the management and issuance of TLS certificates. It integrates with Let's Encrypt to provide free, automatically renewed SSL/TLS certificates.

## Components

### 1. cert-manager Installation

Location: `scripts/setup-kind.sh` (step 7/8)

Installs cert-manager v1.13.3 with all CRDs (Custom Resource Definitions):
- Certificate
- CertificateRequest
- Issuer
- ClusterIssuer

### 2. ClusterIssuers

Location: `k8s/10-cert-manager.yaml`

Two ClusterIssuers are configured:

#### Staging Issuer (For Testing)
```yaml
name: letsencrypt-staging
server: https://acme-staging-v02.api.letsencrypt.org/directory
```

**Use for:**
- Development and testing
- Avoiding Let's Encrypt rate limits
- Certificates are not trusted by browsers

#### Production Issuer
```yaml
name: letsencrypt-prod
server: https://acme-v02.api.letsencrypt.org/directory
```

**Use for:**
- Production deployments
- Trusted certificates
- Subject to rate limits (50 certs/week per domain)

### 3. Certificate Resource

Location: `k8s/10-cert-manager.yaml`

Automatically requests and manages certificates:
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: api-tls-cert
  namespace: prod-api
spec:
  secretName: api-tls
  issuerRef:
    name: letsencrypt-staging
    kind: ClusterIssuer
  dnsNames:
  - api.local
  - www.api.local
```

### 4. Ingress Integration

Location: `k8s/06-ingress.yaml`

Ingress annotations trigger automatic certificate issuance:
```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-staging"
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
  nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
```

## How It Works

### Certificate Lifecycle

1. **Request:** Certificate resource is created
2. **Challenge:** Let's Encrypt sends HTTP-01 or DNS-01 challenge
3. **Solve:** cert-manager solves the challenge automatically
4. **Issue:** Let's Encrypt issues the certificate
5. **Store:** Certificate stored in Kubernetes Secret
6. **Renew:** Automatically renewed before expiry (30 days before)

### HTTP-01 Challenge Flow

```
Let's Encrypt → HTTP Request
                    ↓
              Ingress Controller
                    ↓
              cert-manager solver pod
                    ↓
              Challenge response (token)
                    ↓
              Let's Encrypt verifies
                    ↓
              Certificate issued
```

## Setup Instructions

### 1. Install cert-manager

Already included in setup script:
```bash
./scripts/setup-kind.sh
```

Or manually:
```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.3/cert-manager.yaml
```

### 2. Verify Installation

```bash
kubectl get pods -n cert-manager
```

Expected output:
```
NAME                                      READY   STATUS    RESTARTS   AGE
cert-manager-<hash>                       1/1     Running   0          2m
cert-manager-cainjector-<hash>            1/1     Running   0          2m
cert-manager-webhook-<hash>               1/1     Running   0          2m
```

### 3. Deploy ClusterIssuers and Certificate

```bash
kubectl apply -f k8s/10-cert-manager.yaml
```

### 4. Update Ingress

Already updated in `k8s/06-ingress.yaml`:
```bash
kubectl apply -f k8s/06-ingress.yaml
```

### 5. Verify Certificate

```bash
kubectl get certificate -n prod-api
```

Expected output:
```
NAME           READY   SECRET     AGE
api-tls-cert   True    api-tls    5m
```

### 6. Check Certificate Details

```bash
kubectl describe certificate api-tls-cert -n prod-api
```

## Switching to Production

### Update Email Address

Edit `k8s/10-cert-manager.yaml`:
```yaml
email: your-email@example.com  # Replace with actual email
```

### Use Production Issuer

#### Option 1: Update Certificate Resource
```yaml
spec:
  issuerRef:
    name: letsencrypt-prod  # Changed from letsencrypt-staging
```

#### Option 2: Update Ingress Annotation
```yaml
annotations:
  cert-manager.io/cluster-issuer: "letsencrypt-prod"
```

### Apply Changes

```bash
kubectl delete certificate api-tls-cert -n prod-api
kubectl apply -f k8s/10-cert-manager.yaml
kubectl apply -f k8s/06-ingress.yaml
```

## Domain Configuration

### For Public Domains

1. **Point DNS to your cluster:**
   ```
   api.example.com  A  <your-cluster-ip>
   ```

2. **Update Certificate:**
   ```yaml
   dnsNames:
   - api.example.com
   - www.api.example.com
   ```

3. **Update Ingress:**
   ```yaml
   rules:
   - host: api.example.com
   ```

### For Local Testing

For `api.local` or other local domains, Let's Encrypt cannot verify the domain. Options:

1. **Use staging issuer** (already configured)
2. **Use self-signed issuer:**
   ```yaml
   apiVersion: cert-manager.io/v1
   kind: ClusterIssuer
   metadata:
     name: selfsigned
   spec:
     selfSigned: {}
   ```

## Monitoring and Troubleshooting

### Check Certificate Status

```bash
kubectl get certificate -n prod-api
kubectl describe certificate api-tls-cert -n prod-api
```

### Check CertificateRequest

```bash
kubectl get certificaterequest -n prod-api
kubectl describe certificaterequest <name> -n prod-api
```

### Check cert-manager Logs

```bash
kubectl logs -n cert-manager deployment/cert-manager
```

### Check Ingress Events

```bash
kubectl describe ingress main-api-ingress -n prod-api
```

### Common Issues

#### Certificate Stuck in "Pending"

**Causes:**
- Domain not publicly accessible
- DNS not pointing to cluster
- HTTP-01 challenge cannot be completed

**Solution for local testing:**
Use self-signed issuer instead of Let's Encrypt.

#### "Waiting for HTTP-01 challenge propagation"

**Causes:**
- Ingress controller not ready
- Wrong ingress class
- Firewall blocking port 80

**Check:**
```bash
kubectl get ingress -A
kubectl get pods -n ingress-nginx
```

#### Rate Limit Errors

Let's Encrypt has rate limits:
- 50 certificates per registered domain per week
- 5 duplicate certificates per week

**Solution:**
- Use staging issuer for testing
- Wait for rate limit reset
- Use different subdomains

### View Certificate Secret

```bash
kubectl get secret api-tls -n prod-api -o yaml
```

Certificate is stored in `tls.crt` and `tls.key` fields (base64 encoded).

### Decode Certificate

```bash
kubectl get secret api-tls -n prod-api -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text
```

## Advanced Configuration

### DNS-01 Challenge (For Wildcard Certificates)

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-dns
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-dns
    solvers:
    - dns01:
        cloudflare:
          email: admin@example.com
          apiTokenSecretRef:
            name: cloudflare-api-token
            key: api-token
```

### Wildcard Certificate

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-cert
spec:
  secretName: wildcard-tls
  issuerRef:
    name: letsencrypt-dns
    kind: ClusterIssuer
  dnsNames:
  - "*.example.com"
  - example.com
```

### Multiple Domains in One Certificate

```yaml
dnsNames:
- api.example.com
- api.example.net
- api.example.org
```

### Custom Certificate Validity

```yaml
spec:
  duration: 2160h  # 90 days
  renewBefore: 720h  # 30 days before expiry
```

## Automatic Renewal

cert-manager automatically renews certificates:
- Default: 30 days before expiry
- Configurable via `renewBefore` field
- No manual intervention required

### Monitor Renewal

```bash
kubectl get certificate -n prod-api -w
```

Watch for:
- Status changes from "True" to "False" (renewal started)
- Back to "True" (renewal completed)

### Force Renewal

```bash
kubectl delete certificaterequest -n prod-api --all
kubectl delete secret api-tls -n prod-api
```

cert-manager will automatically create new requests.

## Best Practices

1. **Use Staging First:** Always test with staging issuer
2. **Monitor Expiry:** Set up alerts for certificate expiry
3. **Email Notifications:** Use valid email for Let's Encrypt notifications
4. **Rate Limits:** Be aware of Let's Encrypt limits
5. **Backup Secrets:** Regular backups of certificate secrets
6. **DNS-01 for Internal:** Use DNS-01 for internal services
7. **Separate Issuers:** Different issuers for different environments

## Production Checklist

- [ ] Update email address in ClusterIssuer
- [ ] Switch to production issuer
- [ ] Verify DNS points to cluster
- [ ] Test certificate issuance in staging first
- [ ] Configure monitoring for certificate expiry
- [ ] Document certificate renewal process
- [ ] Set up alerts for failed renewals
- [ ] Test automatic renewal (30 days before expiry)
- [ ] Backup certificate secrets
- [ ] Plan for rate limit management

## Migration from Self-Signed

If you're migrating from self-signed certificates:

1. **Delete old secret:**
   ```bash
   kubectl delete secret api-tls -n prod-api
   ```

2. **Apply cert-manager resources:**
   ```bash
   kubectl apply -f k8s/10-cert-manager.yaml
   ```

3. **Update ingress:**
   ```bash
   kubectl apply -f k8s/06-ingress.yaml
   ```

4. **Verify new certificate:**
   ```bash
   kubectl get certificate -n prod-api
   ```

## Security Considerations

1. **Private Key Storage:** Keys stored in Kubernetes Secrets (encrypted at rest)
2. **RBAC:** Limit access to cert-manager and certificate secrets
3. **Email Privacy:** Use role account, not personal email
4. **Challenge Tokens:** Automatically cleaned up after validation
5. **Certificate Transparency:** All certs logged in CT logs (public)

## References

- [cert-manager Documentation](https://cert-manager.io/docs/)
- [Let's Encrypt Documentation](https://letsencrypt.org/docs/)
- [Let's Encrypt Rate Limits](https://letsencrypt.org/docs/rate-limits/)
- [cert-manager Troubleshooting](https://cert-manager.io/docs/troubleshooting/)
- [ACME Challenge Types](https://letsencrypt.org/docs/challenge-types/)
