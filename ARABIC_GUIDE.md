# دليل الاختبار العملي للـ SRE

## نظرة عامة

هذا المشروع يجيب على جميع متطلبات الاختبار العملي للـ SRE. تم بناء نظام مكون من ثلاث خدمات ويب بلغات مختلفة تعمل على Kubernetes (Kind) مع تحقيق الأمان والمراقبة والتوسع التلقائي.

---

## ✅ المتطلبات المنفذة

### 1️⃣ تحليل النظام وتصميم المعمارية

#### المعمارية:
```
المستخدم (Client)
    ↓
Ingress + TLS (HTTPS)
    ↓
main-api (Node.js - Port 3000)
    ├─→ auth-service (Go - Port 8080)
    └─→ image-service (Python - Port 5000)
         └─→ S3 Storage (MinIO)
```

#### عزل الخدمات:
- **Namespaces منفصلة:**
  - `prod-api` - للخدمة الرئيسية
  - `prod-auth` - لخدمة المصادقة
  - `prod-image` - لخدمة الصور
  - `prod-monitoring` - للمراقبة (Prometheus & Grafana)

- **Network Policies:**
  - `auth-service`: يسمح فقط بالوصول من `main-api`
  - `image-service`: يسمح فقط بالوصول من `main-api`
  - `main-api`: يسمح فقط بالوصول من Ingress Controller
  - الملفات: `k8s/05-network-policies.yaml`

#### إدارة بيانات الاعتماد:
- **Kubernetes Secrets** لجميع البيانات الحساسة:
  - `auth-secrets`: JWT_SECRET
  - `image-secrets`: مفاتيح S3 والإعدادات
  - `api-secrets`: عناوين الخدمات الداخلية
  - الملف: `k8s/01-secrets.yaml`

---

### 2️⃣ بناء ونشر الخدمات

#### الخدمات الثلاث:

1. **main-api (Node.js)**
   - الملفات:
     - `main-api/Dockerfile`
     - `main-api/server.js`
     - `main-api/package.json`
   - الميزات: API Gateway, Prometheus metrics, Health checks

2. **auth-service (Go)**
   - الملفات:
     - `auth-service/Dockerfile`
     - `auth-service/main.go`
     - `auth-service/go.mod`
   - الميزات: JWT authentication, Login/Register endpoints

3. **image-service (Python)**
   - الملفات:
     - `image-service/Dockerfile`
     - `image-service/app.py`
     - `image-service/requirements.txt`
   - الميزات: Image upload/download, S3 integration, Prometheus metrics

#### Private Registry:
- **Registry محلي** على `localhost:5001`
- يتم إنشاؤه وربطه مع Kind cluster تلقائياً
- جميع الصور يتم رفعها إلى هذا Registry
- الكلستر يستطيع الوصول إليه عبر `localhost:5001`

#### ملفات Kubernetes YAML:
- `k8s/00-namespaces.yaml` - إنشاء جميع الـ Namespaces
- `k8s/01-secrets.yaml` - جميع البيانات الحساسة
- `k8s/02-main-api.yaml` - Deployment + Service للـ API الرئيسي
- `k8s/03-auth-service.yaml` - Deployment + Service للمصادقة
- `k8s/04-image-service.yaml` - Deployment + Service للصور

#### أنواع الـ Services:
- **ClusterIP**: لجميع الخدمات الداخلية (auth, image)
- **Ingress**: للوصول الخارجي إلى main-api مع TLS

---

### 3️⃣ الشبكات والأمان

#### Network Policies:
الملف: `k8s/05-network-policies.yaml`

**للـ prod-auth namespace:**
```yaml
- Default Deny: منع جميع الاتصالات الواردة
- Allow من main-api فقط على Port 8080
```

**للـ prod-image namespace:**
```yaml
- Default Deny: منع جميع الاتصالات الواردة
- Allow من main-api فقط على Port 5000
```

**للـ prod-api namespace:**
```yaml
- Allow من Ingress Controller فقط
```

#### Secrets Management:
جميع البيانات الحساسة في Kubernetes Secrets:
- تشفير تلقائي في etcd
- لا توجد معلومات حساسة في الكود
- يتم تحميلها كمتغيرات بيئة في الـ Pods

#### TLS/SSL:
الملف: `k8s/06-ingress.yaml`
- Ingress مع TLS للـ domain: `api.local`
- يستخدم Self-signed certificate (للبيئة المحلية)
- يمكن استبدالها بـ Let's Encrypt في الإنتاج

---

### 4️⃣ المراقبة والرصد

#### Prometheus:
الملف: `k8s/08-prometheus.yaml`
- جمع Metrics من جميع الخدمات
- مراقبة Kubernetes API, Nodes, Pods
- ServiceAccount مع RBAC permissions

#### Grafana:
الملف: `k8s/09-grafana.yaml`
- واجهة رسومية للـ Metrics
- متصل تلقائياً بـ Prometheus
- Username: `admin`, Password: `admin123`

---

### 5️⃣ التوسع التلقائي (Autoscaling)

الملف: `k8s/07-autoscaling.yaml`

**Horizontal Pod Autoscaler (HPA) لكل خدمة:**

1. **main-api:**
   - Min: 3 replicas, Max: 10 replicas
   - CPU target: 70%
   - Memory target: 80%

2. **auth-service:**
   - Min: 2 replicas, Max: 8 replicas
   - CPU target: 75%
   - Memory target: 85%

3. **image-service:**
   - Min: 2 replicas, Max: 8 replicas
   - CPU target: 70%
   - Memory target: 80%

---

### 6️⃣ الاعتمادية والفشل

#### Health Checks:
جميع الخدمات تحتوي على:
- **Liveness Probe**: إعادة تشغيل Pod إذا فشل
- **Readiness Probe**: منع إرسال Traffic للـ Pod غير الجاهز

#### Rolling Updates:
- `maxSurge: 1` - إنشاء Pod جديد قبل حذف القديم
- `maxUnavailable: 0` - لا يتم حذف أي Pod قبل جاهزية البديل
- Zero-downtime deployments

#### Resource Limits:
- CPU و Memory limits لكل Pod
- منع استهلاك موارد الـ Node بالكامل

---

## 🚀 خطوات التشغيل

### المتطلبات:
- Docker Desktop (مفعل WSL2 على Windows)
- Kind
- kubectl
- PowerShell

### 1️⃣ إنشاء الكلستر:
```powershell
.\scripts\setup-kind.ps1
```

هذا السكريبت سيقوم بـ:
- إنشاء Registry محلي على port 5001
- إنشاء Kind cluster مع 3 nodes
- تثبيت NGINX Ingress Controller
- تثبيت Metrics Server للـ autoscaling
- تثبيت Calico للـ Network Policies

### 2️⃣ بناء ورفع الصور:
```powershell
.\scripts\build-images.ps1
```

هذا السكريبت سيقوم بـ:
- بناء Docker images للخدمات الثلاث
- رفعها إلى Registry المحلي

### 3️⃣ نشر الخدمات:
```powershell
.\scripts\deploy.ps1
```

هذا السكريبت سيقوم بـ:
- إنشاء Namespaces
- إنشاء Secrets
- نشر جميع الخدمات
- تطبيق Network Policies
- تطبيق Ingress + TLS
- تطبيق HPA
- نشر Prometheus و Grafana

### 4️⃣ إضافة Domain إلى hosts file:
افتح PowerShell كـ Administrator:
```powershell
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`n127.0.0.1 api.local"
```

---

## 🧪 اختبار النظام

### 1. فحص حالة الخدمات:
```powershell
kubectl get pods -A
kubectl get svc -A
kubectl get hpa -A
```

### 2. اختبار الـ API:
```powershell
# Health check
curl https://api.local/health -k

# أو استخدم Invoke-WebRequest
Invoke-WebRequest -Uri https://api.local/health -SkipCertificateCheck
```

### 3. الوصول إلى Grafana:
```powershell
kubectl port-forward -n prod-monitoring svc/grafana 3000:3000
# ثم افتح: http://localhost:3000
# Username: admin
# Password: admin123
```

### 4. الوصول إلى Prometheus:
```powershell
kubectl port-forward -n prod-monitoring svc/prometheus 9090:9090
# ثم افتح: http://localhost:9090
```

### 5. اختبار Network Policies:
```powershell
# هذا يجب أن ينجح (main-api يستطيع الوصول لـ auth-service)
kubectl exec -it deployment/main-api -n prod-api -- curl http://auth-service.prod-auth:8080/health

# هذا يجب أن يفشل (image-service لا يستطيع الوصول لـ auth-service)
kubectl exec -it deployment/image-service -n prod-image -- curl http://auth-service.prod-auth:8080/health --connect-timeout 5
```

### 6. اختبار Autoscaling:
```powershell
# مراقبة HPA
kubectl get hpa -A -w

# توليد حمل على الخدمة
kubectl run -i --tty load-generator --rm --image=busybox --restart=Never -n prod-api -- /bin/sh -c "while sleep 0.01; do wget -q -O- http://main-api:3000/health; done"

# في نافذة أخرى، راقب Pods
kubectl get pods -n prod-api -w
```

---

## 🛠️ سيناريوهات الفشل

### 1. فشل Pod:
```powershell
# احذف Pod
kubectl delete pod <pod-name> -n prod-api

# شاهد إعادة إنشائه تلقائياً
kubectl get pods -n prod-api -w
```

### 2. زيادة الحمل:
```powershell
# شاهد HPA يقوم بزيادة عدد Pods
kubectl get hpa -A -w
```

### 3. فشل Node:
```powershell
# في Kind، احذف worker node
docker stop <node-container>

# Pods ستنتقل تلقائياً إلى nodes أخرى
```

---

## 📊 المخطط المعماري

```
┌─────────────────────────────────────────────────────┐
│                    Internet/User                     │
└────────────────────┬────────────────────────────────┘
                     │
                     │ HTTPS (TLS)
                     │
┌────────────────────▼────────────────────────────────┐
│              Ingress Controller                      │
│           (NGINX - api.local:443)                    │
└────────────────────┬────────────────────────────────┘
                     │
                     │ HTTP
                     │
┌────────────────────▼────────────────────────────────┐
│             prod-api namespace                       │
│  ┌───────────────────────────────────────────────┐  │
│  │  main-api (Node.js)                           │  │
│  │  - 3 replicas (HPA: 3-10)                     │  │
│  │  - Port 3000                                   │  │
│  │  - Prometheus metrics                          │  │
│  └───┬───────────────────────┬───────────────────┘  │
└──────┼───────────────────────┼──────────────────────┘
       │                       │
       │ HTTP                  │ HTTP
       │                       │
       │                       │
┌──────▼──────────┐    ┌───────▼──────────┐
│  prod-auth      │    │  prod-image       │
│  namespace      │    │  namespace        │
│  ┌───────────┐  │    │  ┌────────────┐   │
│  │auth-service│ │    │  │image-service│  │
│  │   (Go)     │ │    │  │  (Python)   │  │
│  │2 replicas  │ │    │  │  2 replicas │  │
│  │Port 8080   │ │    │  │  Port 5000  │  │
│  └───────────┘  │    │  └──────┬─────┘   │
│                 │    │         │         │
└─────────────────┘    └─────────┼─────────┘
                                 │
                                 │ S3 API
                                 │
                        ┌────────▼─────────┐
                        │   S3 Storage     │
                        │    (MinIO)       │
                        └──────────────────┘

┌─────────────────────────────────────────────────────┐
│           prod-monitoring namespace                  │
│  ┌──────────────┐         ┌──────────────┐          │
│  │  Prometheus  │◄────────│   Grafana    │          │
│  │  Port 9090   │         │   Port 3000  │          │
│  └──────┬───────┘         └──────────────┘          │
│         │                                            │
│         │ Scrape Metrics                             │
│         └────────────────────────────────────────────┤
│                  All Pods & Nodes                    │
└─────────────────────────────────────────────────────┘
```

---

## 🔒 ميزات الأمان

1. **Namespace Isolation**: كل خدمة في namespace منفصل
2. **Network Policies**: منع الوصول غير المصرح به
3. **Secrets Management**: جميع البيانات الحساسة مشفرة
4. **RBAC**: أذونات محدودة للـ ServiceAccounts
5. **TLS**: تشفير الاتصال عبر Ingress
6. **Resource Limits**: منع استنزاف الموارد

---

## 📈 ميزات الاعتمادية

1. **Health Checks**: Liveness و Readiness probes
2. **Autoscaling**: HPA للتوسع التلقائي
3. **Rolling Updates**: تحديثات بدون توقف
4. **Multiple Replicas**: تكرار Pods للمرونة
5. **Resource Management**: CPU و Memory limits

---

## 🔍 المراقبة

1. **Prometheus**: جمع Metrics من جميع المكونات
2. **Grafana**: لوحات تحكم مرئية
3. **Kubernetes Metrics**: CPU, Memory, Network
4. **Application Metrics**: Custom metrics من الخدمات

---

## 🧹 التنظيف

لحذف الكلستر والـ Registry بالكامل:
```powershell
.\scripts\cleanup.ps1
```

---

## 📝 ملاحظات مهمة

### للاستخدام في الإنتاج:
1. استبدل Self-signed certificates بـ Let's Encrypt
2. استخدم External Secret Store (مثل HashiCorp Vault)
3. أضف Persistent Storage للـ Prometheus و Grafana
4. استخدم Registry خارجي (Docker Hub, ECR, etc.)
5. أضف Backup و Disaster Recovery
6. أضف Logging Stack (ELK أو Loki)
7. أضف Service Mesh (Istio أو Linkerd)

---

## ✅ ملخص الإنجاز

هذا المشروع يغطي **جميع متطلبات الاختبار**:

✅ معمارية واضحة مع مخطط توضيحي
✅ ثلاث خدمات بلغات مختلفة (Node.js, Go, Python)
✅ Dockerfiles لكل خدمة
✅ Private Registry محلي
✅ ملفات YAML كاملة (Deployment + Service + Ingress)
✅ Network Policies للعزل الأمني
✅ Secrets Management
✅ Ingress مع TLS
✅ Autoscaling (HPA)
✅ Monitoring (Prometheus + Grafana)
✅ Health Checks
✅ سيناريوهات الفشل والمعالجة

**المشروع جاهز للتقديم!** 🎉
