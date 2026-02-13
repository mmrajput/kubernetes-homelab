# Prometheus Architecture & ServiceMonitor Guide

A comprehensive guide to understanding Prometheus components and Kubernetes ServiceMonitor pattern for production-grade monitoring.

---

## Table of Contents

1. [Prometheus Architecture Overview](#prometheus-architecture-overview)
2. [Core Components Deep Dive](#core-components-deep-dive)
3. [The ServiceMonitor Pattern](#the-servicemonitor-pattern)
4. [Practical Implementation Guide](#practical-implementation-guide)
5. [Troubleshooting & Debugging](#troubleshooting--debugging)
6. [Key Takeaways](#key-takeaways)

---

## Prometheus Architecture Overview

### Basic Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Prometheus Server                        │
│                                                             │
│  ┌──────────────┐      ┌──────────────┐    ┌──────────────┐ │
│  │   Retrieval  │───▶  │    TSDB     │───▶│   PromQL     │ │
│  │   (Scraper)  │      │  (Storage)   │    │   Engine     │ │
│  └──────────────┘      └──────────────┘    └──────────────┘ │
│         │                                        │          │
└─────────┼────────────────────────────────────────┼──────────┘
          │                                        │
          │ HTTP GET /metrics                      │ HTTP API
          ▼                                        ▼
    ┌──────────┐                           ┌─────────────┐
    │  Targets │                           │   Grafana   │
    │ (Apps,   │                           │  (Queries)  │
    │  Nodes)  │                           └─────────────┘
    └──────────┘
```

**Flow**: Retrieval scrapes metrics → TSDB stores time-series → PromQL queries data

### Key Architectural Principles

1. **Pull Model**: Prometheus actively pulls metrics from targets (not pushed)
2. **Time-Series Database**: Optimized for storing metrics with timestamps
3. **Service Discovery**: Automatically finds targets to scrape
4. **PromQL**: Powerful query language for data analysis

---

## Core Components Deep Dive

### 1. Service Discovery & Scraping

```
┌──────────────────────────────────────────────────────┐
│              Prometheus Server                       │
│                                                      │
│  ┌─────────────────┐        ┌──────────────────┐     │
│  │Service Discovery│──────▶ │  Target Manager  │    │
│  │  (Kubernetes,   │        │  (Active Targets)│     │
│  │   Static, DNS)  │        └────────┬─────────┘     │
│  └─────────────────┘                 │               │
│                                      │               │
│                          ┌───────────┼────────┐      │
│                          ▼           ▼        ▼      │
│                      ┌────────┐  ┌────────┐  ...     │
│                      │Scraper │  │Scraper │          │
│                      │Job 1   │  │Job 2   │          │
│                      └────┬───┘  └───┬────┘          │
└───────────────────────────┼──────────┼───────────────┘
                            │          │
                   /metrics │          │ /metrics
                            ▼          ▼
                      ┌─────────┐  ┌─────────┐
                      │Pod 1    │  │Pod 2    │
                      │:8080    │  │:9090    │
                      └─────────┘  └─────────┘
```

**Flow**: Service Discovery finds targets → Target Manager assigns scrapers → Scrapers pull metrics via HTTP

### 2. Metric Collection Flow

```
Application Side                  Prometheus Side
───────────────                  ────────────────

┌──────────────┐                 ┌─────────────────┐
│ Application  │                 │  Prometheus     │
│              │                 │  Server         │
│  ┌────────┐  │                 │                 │
│  │Counter │  │                 │  Every 15s      │
│  │Gauge   │◀┼─────────────────┼─ GET /metrics  │
│  │Histogram│ │  HTTP Scrape    │                 │
│  │Summary │  │                 │                 │
│  └───┬────┘  │                 │                 │
│      │       │                 │                 │
│      ▼       │  Response:      │                 │
│  ┌────────┐  │  text/plain     │                 │
│  │/metrics│──┼────────────────▶│  ┌───────────┐  │
│  │endpoint│  │                 │  │Parse &    │  │
│  └────────┘  │  # TYPE ...     │  │Store TSDB │  │
│              │  metric_name x  │  └───────────┘  │
└──────────────┘                 └─────────────────┘
```

**Key Point**: Applications expose metrics passively; Prometheus actively pulls them

### 3. Time-Series Database (TSDB)

```
┌────────────────────────────────────────────────────┐
│                  Time Series Database              │
│                                                    │
│  Incoming Metrics:                                 │
│  http_requests_total{method="GET", status="200"}   │
│                                                    │
│         │                                          │
│         ▼                                          │
│  ┌──────────────┐                                  │
│  │  Write-Ahead │  (Crash recovery)                │
│  │  Log (WAL)   │                                  │
│  └──────┬───────┘                                  │
│         │                                          │
│         ▼                                          │
│  ┌──────────────┐     After 2h blocks              │
│  │ Memory Block │────────────┐                     │
│  │ (Head Block) │            │                     │
│  └──────────────┘            ▼                     │
│                      ┌────────────────┐            │
│                      │ Persistent     │            │
│  Query ◀───────────▶│ Blocks on Disk │            │
│                      │ (2h chunks,    │            │
│                      │  compressed)   │            │
│                      └────────┬───────┘            │
│                               │                    │
│                               ▼                    │
│                      ┌────────────────┐            │
│                      │ Retention      │            │
│                      │ (Delete after  │            │
│                      │  15 days)      │            │
│                      └────────────────┘            │
└────────────────────────────────────────────────────┘
```

**Flow**: Metrics → WAL → Memory → 2h disk blocks → Retention cleanup

### 4. Alerting Pipeline

```
┌────────────────────────────────────────────────────┐
│              Prometheus Server                     │
│                                                    │
│  ┌──────────────┐      ┌──────────────┐            │
│  │ Alert Rules  │─────▶│ Alert State  │           │
│  │ (YAML)       │      │ Engine       │            │
│  │              │      └──────┬───────┘            │
│  │cpu_high >80% │             │                    │
│  └──────────────┘             │ Firing             │
│                               │ Alerts             │
└───────────────────────────────┼────────────────────┘
                                │
                                ▼
                    ┌──────────────────────┐
                    │   Alertmanager       │
                    │                      │
                    │  ┌────────────────┐  │
                    │  │  Grouping      │  │
                    │  │  Deduplication │  │
                    │  │  Silencing     │  │
                    │  └───────┬────────┘  │
                    │          │           │
                    │          ▼           │
                    │  ┌────────────────┐  │
                    │  │   Routing      │  │
                    │  └───┬────────────┘  │
                    └──────┼───────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         ┌────────┐  ┌─────────┐  ┌────────┐
         │ Email  │  │ Slack   │  │PagerDuty│
         └────────┘  └─────────┘  └────────┘
```

**Flow**: Rules evaluate → Fire alerts → Alertmanager routes → Notifications sent

### 5. Complete Monitoring Stack

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              kube-prometheus-stack                   │   │
│  │                                                      │   │
│  │  ┌────────────┐   ┌──────────────┐  ┌────────────┐   │   │
│  │  │Prometheus  │──▶│Alertmanager  │─▶│Notifications│ │   │
│  │  │  Server    │   └──────────────┘  └────────────┘   │   │
│  │  └─────┬──────┘                                      │   │
│  │        │                                             │   │
│  │        │ Scrapes via ServiceMonitors                 │   │
│  │        │                                             │   │
│  │  ┌─────▼──────────────────────────────────────────┐  │   │
│  │  │ ServiceMonitor CRDs (Kubernetes Operator)      │  │   │
│  │  └─────┬──────────────────────────────────────────┘  │   │
│  └────────┼─────────────────────────────────────────────┘   │
│           │                                                 │
│     ┌─────┼─────────┬──────────────┬───────────┐            │  
│     ▼     ▼         ▼              ▼           ▼            │
│  ┌────┐ ┌────┐  ┌──────┐      ┌────────┐  ┌──────┐          │
│  │Node│ │kube│  │nginx │      │Your    │  │Loki  │          │
│  │Exp.│ │-st. │  │Ingress      │Apps    │  │(logs)│         │
│  └──┬─┘ │mgr │  └──────┘      └────────┘  └───┬──┘          │
│     │   └────┘                                 │            │
│     │ /metrics endpoints                       │            │
│     └──────────────────────────────────────────┘            │
│                                                             │
│  ┌──────────────────────────────────────────────────┐       │
│  │              Grafana                             │       │
│  │  Queries Prometheus + Loki ───▶ Dashboards      │        │  
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

## The ServiceMonitor Pattern

### The Problem: Manual Configuration Doesn't Scale

**Without ServiceMonitors (Manual Prometheus Configuration):**

```
┌──────────────────────────────────────────────────┐
│  prometheus.yml (Static Configuration File)      │
│                                                  │
│  scrape_configs:                                 │
│    - job_name: 'my-app'                          │
│      static_configs:                             │
│        - targets:                                │
│          - '10.0.1.5:8080'  ← Pod IP (changes!)  │
│          - '10.0.1.8:8080'  ← Pod IP (changes!)  │
│          - '10.0.1.9:8080'  ← Pod IP (changes!)  │
└──────────────────────────────────────────────────┘
                    
❌ PROBLEMS:
• Pod IPs change constantly
• Need to restart Prometheus
• Manual updates required
• Doesn't scale in Kubernetes
```

**With ServiceMonitors (Kubernetes-Native):**

```
┌──────────────────────────────────────────────────┐
│  ServiceMonitor (Kubernetes Resource)            │
│                                                  │
│  apiVersion: monitoring.coreos.com/v1            │
│  kind: ServiceMonitor                            │
│  spec:                                           │
│    selector:                                     │
│      matchLabels:                                │
│        app: my-app  ← Dynamic discovery!         │
└──────────────────────────────────────────────────┘
                    
✅ BENEFITS:
• Auto-discovers pods
• No restarts needed
• GitOps friendly
• Kubernetes-native
```

### ServiceMonitor Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Kubernetes Cluster                         │
│                                                             │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         Prometheus Operator (Controller)              │  │
│  │                                                       │  │
│  │  Watches for:                                         │  │
│  │  • ServiceMonitor CRDs                                │  │
│  │  • Service objects                                    │  │
│  │  • Pod endpoints                                      │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │  1. Detects ServiceMonitor created              │  │  │
│  │  │  2. Finds matching Service (by labels)          │  │  │
│  │  │  3. Discovers Pod IPs behind Service            │  │  │
│  │  │  4. Auto-generates Prometheus scrape config     │  │  │
│  │  │  5. Reloads Prometheus (hot reload, no restart) │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
│                           │                                 │
│                           │ Generates config                │
│                           ▼                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         Prometheus Server                             │  │
│  │                                                       │  │
│  │  Scrape Config (auto-generated):                      │  │
│  │  - job_name: serviceMonitor/my-namespace/my-app/0     │  │
│  │    kubernetes_sd_configs:  ← Service Discovery!       │  │
│  │      - role: endpoints                                │  │
│  │    relabel_configs: [...]                             │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Complete Flow: From ServiceMonitor to Scraping

#### Step 1: Create ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: default
  labels:
    release: kube-prometheus-stack  # CRITICAL - Operator watches this!
spec:
  selector:
    matchLabels:
      app: my-app  # Key selector - finds matching Service
  endpoints:
    - port: metrics
      path: /metrics
      interval: 30s
```

#### Step 2: Operator Detects ServiceMonitor

```
┌──────────────────────────────────────┐
│   Prometheus Operator                │
│   (Running in Kubernetes)            │
│                                      │
│   Watch Event:                       │
│   "ServiceMonitor created!"          │
│                                      │
│   Action: Find matching Service...   │
└──────────────────────────────────────┘
         │
         │ Looks for Service with
         │ labels: app=my-app
         ▼
```

#### Step 3: Operator Finds Matching Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app-service
  labels:
    app: my-app  # Matches ServiceMonitor selector!
spec:
  selector:
    app: my-app  # Points to pods
  ports:
    - name: metrics
      port: 8080
      targetPort: 8080
```

#### Step 4: Operator Discovers Pod Endpoints

```
Endpoints Object (auto-created by Kubernetes):
  Pod IPs behind Service:
  • 10.244.1.5:8080
  • 10.244.2.3:8080
  • 10.244.1.9:8080
```

#### Step 5: Auto-Generated Prometheus Config

```yaml
# Prometheus Server (Config auto-updated by Operator)
scrape_configs:
  - job_name: 'serviceMonitor/default/my-app-monitor/0'
    kubernetes_sd_configs:
      - role: endpoints
        namespaces:
          names: [default]
    relabel_configs:
      - source_labels: [__meta_kubernetes_service_label_app]
        regex: my-app
        action: keep
    metrics_path: /metrics
    scrape_interval: 30s
```

Config is hot-reloaded without restarting Prometheus!

#### Step 6: Prometheus Scrapes Pods

```
Prometheus Scraper runs every 30s:

GET http://10.244.1.5:8080/metrics
GET http://10.244.2.3:8080/metrics
GET http://10.244.1.9:8080/metrics

         ┌─────────┐  ┌─────────┐  ┌─────────┐
         │ Pod 1   │  │ Pod 2   │  │ Pod 3   │
         │ :8080   │  │ :8080   │  │ :8080   │
         │/metrics │  │/metrics │  │/metrics │
         └─────────┘  └─────────┘  └─────────┘
```

### Label Matching: The Critical Connection

```
ServiceMonitor uses labels to find Service to scrape:

ServiceMonitor                Service                 Pods
──────────────                ───────                ─────

selector:                     metadata:              metadata:
  matchLabels:                  labels:                labels:
    app: nginx  ══════════════▶   app: nginx            app: nginx
    env: prod                     env: prod  ─────────▶ env: prod
                                              selects
```

**Three Critical Label Matchings:**

1. **ServiceMonitor → Prometheus Operator**
   - Label: `release: kube-prometheus-stack`
   - Purpose: Tells Operator to watch this ServiceMonitor

2. **ServiceMonitor → Service**
   - Field: `spec.selector.matchLabels`
   - Purpose: Finds which Service to scrape

3. **Service → Pods**
   - Field: `spec.selector`
   - Purpose: Finds which Pods expose metrics

**All three must align for scraping to work!**

### Real Example: nginx-ingress ServiceMonitor

```
┌────────────────────────────────────────────────────────────┐
│ nginx-ingress-controller Helm chart deploys 3 resources:   │
└────────────────────────────────────────────────────────────┘

1. Deployment (creates pods)
───────────────────────────
labels:
  app.kubernetes.io/name: ingress-nginx
  app.kubernetes.io/component: controller

         │
         ▼

2. Service (exposes pods on port 10254)
────────────────────────────────────────
metadata:
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/component: controller
spec:
  selector:
    app.kubernetes.io/name: ingress-nginx
  ports:
    - name: metrics
      port: 10254

         │
         ▼

3. ServiceMonitor (tells Prometheus to scrape)
───────────────────────────────────────────────
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: ingress-nginx
      app.kubernetes.io/component: controller
  endpoints:
    - port: metrics  # Matches Service port name
      path: /metrics
      interval: 30s
```

**Prometheus Operator Logic:**

1. "ServiceMonitor created for ingress-nginx"
2. "Looking for Service with matching labels..."
3. "Found Service: ingress-nginx-controller"
4. "Service has port named 'metrics' on 10254"
5. "Service selects pods with matching labels"
6. "Generating Prometheus scrape config..."
7. "Prometheus now scraping nginx pods!"

---

## Practical Implementation Guide

### Deploying Your Own Application with ServiceMonitor

#### Step 1: Deploy Application

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-cool-app
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-cool-app  # Important label!
  template:
    metadata:
      labels:
        app: my-cool-app  # Important label!
    spec:
      containers:
      - name: app
        image: my-app:v1
        ports:
        - name: metrics    # Name your metrics port!
          containerPort: 8080
```

#### Step 2: Create Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-cool-app-service
  namespace: default
  labels:
    app: my-cool-app  # Matches deployment!
spec:
  selector:
    app: my-cool-app  # Points to pods!
  ports:
  - name: metrics     # Same name as in pod!
    port: 8080
    targetPort: metrics
```

#### Step 3: Create ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-cool-app-monitor
  namespace: default
  labels:
    release: kube-prometheus-stack  # CRITICAL!
spec:
  selector:
    matchLabels:
      app: my-cool-app  # Finds the Service!
  endpoints:
  - port: metrics       # Matches Service port name!
    path: /metrics
    interval: 30s
```

**Why `release: kube-prometheus-stack` label is critical:**

The Prometheus Operator ONLY watches ServiceMonitors with specific labels (configured during Helm install).

Check which labels your Prometheus watches:

```bash
kubectl get prometheus -n monitoring -o yaml
# Look for: serviceMonitorSelector.matchLabels
```

#### Step 4: Verify Setup

```bash
# Check ServiceMonitor created
kubectl get servicemonitor -n default

# Check Prometheus targets
# Open Prometheus UI → Status → Targets
# Look for: serviceMonitor/default/my-cool-app-monitor/0

# Test metrics endpoint directly
kubectl run curl --image=curlimages/curl -it --rm -- \
  curl http://my-cool-app-service.default.svc.cluster.local:8080/metrics
```

---

## Troubleshooting & Debugging

### Debugging Flow

```
Problem: Metrics not showing in Prometheus
──────────────────────────────────────────

Step 1: Check ServiceMonitor exists
────────────────────────────────────
$ kubectl get servicemonitor -A

If missing → Create it!


Step 2: Check ServiceMonitor has correct label
───────────────────────────────────────────────
$ kubectl get servicemonitor my-app -o yaml | grep release

Should show: release: kube-prometheus-stack

If missing → Add label to ServiceMonitor!


Step 3: Check ServiceMonitor selector matches Service
──────────────────────────────────────────────────────
$ kubectl get servicemonitor my-app -o yaml
# Look at: spec.selector.matchLabels

$ kubectl get service my-app -o yaml
# Look at: metadata.labels

Labels must match!


Step 4: Check Service selector matches Pods
────────────────────────────────────────────
$ kubectl get service my-app -o yaml
# Look at: spec.selector

$ kubectl get pods -l app=my-app
# Should return your pods!

If no pods → Service selector is wrong!


Step 5: Check Prometheus targets
─────────────────────────────────
Prometheus UI → Status → Targets

Look for your ServiceMonitor job

If status is "DOWN":
  • Check pod is actually exposing /metrics
  • curl pod-ip:port/metrics
  
If you don't see the target at all:
  • ServiceMonitor label issue
  • Selector mismatch
  • Operator not watching this namespace


Step 6: Check Operator logs
────────────────────────────
$ kubectl logs -n monitoring \
  -l app.kubernetes.io/name=prometheus-operator

Look for errors about your ServiceMonitor
```

### Common Issues & Solutions

#### Issue 1: ServiceMonitor not picked up by Operator

**Symptoms:**
- ServiceMonitor exists but no targets appear in Prometheus
- No scrape jobs generated

**Solution:**
```bash
# Check if ServiceMonitor has the correct label
kubectl get servicemonitor my-app -o yaml | grep -A 5 labels

# Should have:
# labels:
#   release: kube-prometheus-stack

# If missing, patch it:
kubectl label servicemonitor my-app release=kube-prometheus-stack
```

#### Issue 2: Service not matching ServiceMonitor selector

**Symptoms:**
- ServiceMonitor exists with correct labels
- Service exists but not being scraped

**Solution:**
```bash
# Compare labels
kubectl get servicemonitor my-app -o jsonpath='{.spec.selector.matchLabels}'
kubectl get service my-app -o jsonpath='{.metadata.labels}'

# Labels must match exactly!
```

#### Issue 3: Pods not exposing metrics

**Symptoms:**
- Target shows "DOWN" in Prometheus UI
- Connection refused or 404 errors

**Solution:**
```bash
# Test metrics endpoint directly
kubectl get pods -l app=my-app
kubectl exec -it <pod-name> -- wget -O- localhost:8080/metrics

# Check if port is correct
kubectl get service my-app -o yaml | grep -A 5 ports
kubectl get pods my-app-xxx -o yaml | grep -A 5 ports
```

### Verification Commands

```bash
# List all ServiceMonitors
kubectl get servicemonitor -A

# Check specific ServiceMonitor details
kubectl describe servicemonitor my-app -n default

# View Prometheus Operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator --tail=100

# Check Prometheus configuration
kubectl get secret prometheus-kube-prometheus-prometheus -n monitoring -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip

# Port-forward to Prometheus UI
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Open: http://localhost:9090/targets

# Check endpoints discovered by Service
kubectl get endpoints my-app-service -n default
```

---

## Key Takeaways

### Prometheus Core Concepts

1. **Pull Model**: Prometheus actively scrapes targets, not passive receiving
2. **Time-Series Storage**: Optimized TSDB with 2-hour blocks and retention
3. **Service Discovery**: Dynamic target discovery via Kubernetes API
4. **PromQL**: Powerful query language for metric analysis
5. **Alerting Pipeline**: Rules → Alertmanager → Notifications

### ServiceMonitor Pattern

1. **Kubernetes-Native**: Declared as Custom Resource Definitions (CRDs)
2. **Dynamic Discovery**: Automatically finds pods via Service labels
3. **GitOps Friendly**: Managed through version control like any K8s resource
4. **No Manual Config**: Prometheus Operator generates scrape configs automatically
5. **Hot Reload**: Configuration updates without restarting Prometheus

### Label Matching is Everything

```
Three critical label connections must align:

1. ServiceMonitor → Prometheus Operator
   release: kube-prometheus-stack

2. ServiceMonitor selector → Service labels
   spec.selector.matchLabels

3. Service selector → Pod labels
   spec.selector

Break any link → No metrics!
```

### Production Best Practices

1. **Always name your ports**: Use `name: metrics` consistently
2. **Use meaningful labels**: `app`, `component`, `tier` for organization
3. **Set appropriate intervals**: Balance between data freshness and load
4. **Configure retention**: Match your compliance and disk space requirements
5. **Monitor the monitors**: Set up alerts for Prometheus itself
6. **Document ServiceMonitors**: Add annotations explaining what's being monitored
7. **Test endpoints first**: Verify `/metrics` works before creating ServiceMonitor
8. **Use namespaced ServiceMonitors**: Keep monitoring config with applications

### Homelab Implementation Notes

- **kube-prometheus-stack**: Bundles Prometheus + Operator + Grafana + Alertmanager
- **ServiceMonitor CRDs**: Created automatically for core components (kube-state-metrics, node-exporter, etc.)
- **App-of-Apps Pattern**: Manage platform services with ArgoCD
- **Resource Constraints**: Optimize Helm values for homelab resources
- **Persistent Storage**: Use Longhorn for Prometheus TSDB with proper retention

---

## Additional Resources

### Official Documentation
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Prometheus Operator](https://prometheus-operator.dev/)
- [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)

### Enterprise Patterns
- ServiceMonitor pattern aligns with enterprise GitOps workflows
- CRD-based configuration enables declarative infrastructure
- Operator pattern reduces operational overhead
- Kubernetes-native monitoring integrates with RBAC and network policies

### Next Steps for Learning

1. Create custom ServiceMonitors for your applications
2. Explore PodMonitors (similar to ServiceMonitor but targets pods directly)
3. Implement custom alert rules
4. Build Grafana dashboards using Prometheus data
5. Configure Alertmanager routing and notifications
6. Experiment with recording rules for query optimization
7. Study PromQL for advanced queries

---

**Document Version**: 1.0  
**Last Updated**: Based on Prometheus 2.x and Prometheus Operator 0.70+  
**Target Audience**: Platform Engineers, DevOps practitioners, SRE teams  
**Homelab Context**: Kubernetes v1.31.4, kube-prometheus-stack, ArgoCD GitOps
