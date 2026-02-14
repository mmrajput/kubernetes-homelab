# Grafana Visualization Platform

Unified observability UI for metrics and logs visualization in Kubernetes homelab.

## Overview

Grafana is an open-source analytics and interactive visualization platform. It provides charts, graphs, and alerts when connected to supported data sources.

**Purpose in Observability Stack:**
- Visualize Prometheus metrics
- Query and filter Loki logs
- Pre-built Kubernetes monitoring dashboards
- Custom dashboard creation
- Alerting based on metrics and logs

## Architecture

```
┌─────────────────────────────────────────────────┐
│              Grafana Platform                   │
├─────────────────────────────────────────────────┤
│                                                 │
│  ┌──────────────────────────────────┐           │
│  │         Grafana Server           │           │
│  │        (Deployment)              │           │
│  │                                  │           │
│  │  ┌────────────────────────────┐  │           │
│  │  │   Dashboard Engine         │  │           │
│  │  │   - Panel rendering        │  │           │
│  │  │   - Query execution        │  │           │
│  │  │   - Alert evaluation       │  │           │
│  │  └────────────────────────────┘  │           │
│  │                                  │           │
│  │  Data Sources (configured):      │           │ 
│  │  ├─ Prometheus (default)         │           │
│  │  └─ Loki                         │           │
│  │                                  │           │
│  └─────────┬────────────────────────┘           │
│            │                                    │
│            │ Queries via HTTP                   │
│            ├──────────────┬──────────────┐      │
│            ▼              ▼              │      │
│  ┌──────────────┐  ┌──────────────┐      │      │
│  │  Prometheus  │  │     Loki     │      │      │
│  │   :9090      │  │    :3100     │      │      │
│  └──────────────┘  └──────────────┘      │      │
│                                          │      │
│  Storage:                                │      │ 
│  └─ 1Gi PVC (dashboards, users, prefs)   │      │
│                                          │      │
│  Access:                                 │      │
│  └─ nginx-ingress (grafana.homelab.local)│      │
│                                          │      │
└──────────────────────────────────────────┘      │
                                                  │
         User Access (Browser)                    │
         grafana.homelab.local:30080  ◄───────────┘
```

### Data Flow

1. **User Access**: Browser → nginx-ingress → Grafana pod
2. **Dashboard Loading**: Grafana renders panels from config
3. **Query Execution**: Grafana → Prometheus/Loki (PromQL/LogQL)
4. **Data Retrieval**: Metrics/logs returned to Grafana
5. **Visualization**: Panels render charts, graphs, tables
6. **Storage**: Dashboard configs saved to PVC

## Resource Allocation

| Component | Replicas | CPU | Memory | Storage |
|-----------|----------|-----|--------|---------|
| Grafana | 1 | 100m / - | 256Mi / 512Mi | 1Gi PVC |

**Total Phase 6 Stack:**
- Prometheus: ~1.8Gi
- Loki: ~640Mi
- Grafana: ~256Mi
- **Total**: ~2.7Gi request, ~5.8Gi limit

## Configuration

### Admin Credentials

**Default (change on first login):**
- Username: `admin`
- Password: `admin`

**On first login:** Grafana prompts for password change. Set a secure password or skip for homelab.

### Data Sources

**Auto-configured via Helm values:**

#### Prometheus (Default)
```yaml
- name: Prometheus
  type: prometheus
  url: http://prometheus-prometheus:9090
  access: proxy
  isDefault: true
```

**Connection Details:**
- Service: `prometheus-prometheus.monitoring.svc`
- Port: 9090
- Access mode: Proxy (Grafana backend queries)
- Default: Yes (used when no data source specified)

#### Loki
```yaml
- name: Loki
  type: loki
  url: http://loki:3100
  access: proxy
```

**Connection Details:**
- Service: `loki.monitoring.svc`
- Port: 3100
- Access mode: Proxy
- Max lines per query: 1000

**Why proxy mode?**
- Browser can't reach internal ClusterIP services
- Grafana backend proxies requests
- Better security (no direct cluster access from browser)

### Pre-installed Dashboards

| Dashboard | Grafana ID | Purpose | Metrics Source |
|-----------|------------|---------|----------------|
| Kubernetes Cluster Monitoring | 7249 | Cluster-wide resource usage | Prometheus |
| Kubernetes Pods Monitoring | 6417 | Per-pod metrics and health | Prometheus |
| Node Exporter Full | 1860 | Detailed node metrics (CPU, mem, disk, network) | Prometheus |
| Loki Logs | 13639 | Log aggregation and search | Loki |

**Auto-import on deployment:**
- Dashboards fetched from grafana.com on first start
- Saved to PVC for persistence
- Editable in Grafana UI

### Installed Plugins

- `grafana-piechart-panel`: Pie chart visualizations
- `grafana-clock-panel`: Clock widget for dashboards

**Installing more plugins:**
```yaml
# In values.yaml
plugins:
  - grafana-piechart-panel
  - grafana-clock-panel
  - grafana-polystat-panel  # Add new plugin
```

### Security Settings

**Authentication:**
- Anonymous access: Disabled
- User sign-up: Disabled
- Default role for new users: Viewer

**Session Security:**
- Cookie secure: false (dev/homelab)
- Cookie SameSite: lax
- Allow embedding: true

**Production differences:**
- Enable HTTPS (cookie_secure: true)
- OAuth2/OIDC integration
- LDAP/Active Directory
- Multi-org support

## Deployment

### Prerequisites
- ArgoCD operational
- nginx-ingress controller
- Prometheus deployed and accessible
- Loki deployed and accessible
- StorageClass available

### GitOps Deployment

**Managed by:**
- ArgoCD App: `platform/argocd/apps/grafana-app.yaml`
- Helm Values: `platform/grafana/values.yaml`
- Chart: `grafana/grafana v10.5.15`
- Grafana Version: 12.3.1

### Update Configuration

```bash
# Edit Grafana configuration
vim platform/grafana/values.yaml

# Commit and push
git add platform/grafana/values.yaml
git commit -m "feat(observability): update Grafana configuration"
git push origin main

# ArgoCD auto-syncs within 3 minutes
# Or force immediate sync:
kubectl patch application grafana -n platform \
  -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}' \
  --type=merge
```

## Access

### Web UI

**URL:** http://grafana.homelab.local:30080

**DNS Configuration:**
Add to `/etc/hosts` (Windows: `C:\Windows\System32\drivers\etc\hosts`):
```
192.168.178.34   grafana.homelab.local
```

**Login:**
- Username: `admin`
- Password: `admin` (change on first login)

### API Access

**For automation/scripts:**
```bash
# Get API key (in Grafana UI: Configuration → API Keys)
API_KEY="your-api-key"

# Example: List dashboards
curl -H "Authorization: Bearer $API_KEY" \
  http://grafana.homelab.local:30080/api/search

# Example: Create dashboard
curl -X POST -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d @dashboard.json \
  http://grafana.homelab.local:30080/api/dashboards/db
```

## Verification

### Check Deployment Status

```bash
# Pod status
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana

# Expected: 1/1 Running

# PVC status
kubectl get pvc -n monitoring | grep grafana

# Ingress status
kubectl get ingress -n monitoring | grep grafana

# Resource usage
kubectl top pod -n monitoring -l app.kubernetes.io/name=grafana
```

### Verify Data Sources

**In Grafana UI:**

1. **⚙️ Configuration** → **Data sources**
2. Click **Prometheus**
3. Scroll down, click **Save & test**
4. Should show: ✅ **"Data source is working"**

5. Go back, click **Loki**
6. Click **Save & test**
7. Should show: ✅ **"Data source successfully connected"**

**CLI verification:**
```bash
# Test from Grafana pod
kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  curl -s http://prometheus-prometheus:9090/api/v1/status/config | head -20

kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  curl -s http://loki:3100/ready
```

### Verify Dashboards

**In Grafana UI:**

1. **🏠 Dashboards** (four squares icon)
2. Should see 4 imported dashboards
3. Click **"Node Exporter Full"**
4. Should display metrics from all 3 nodes

**Expected panels:**
- CPU usage graphs
- Memory usage
- Disk I/O
- Network traffic
- System load

### Test Log Viewer

**In Grafana UI:**

1. **🧭 Explore** (compass icon)
2. **Data source:** Select **Loki** (top dropdown)
3. **Log browser:** Click button
4. Select `namespace` → `monitoring`
5. Click **"Show logs"**

**Should see:** Live logs from monitoring namespace

**Try queries:**
```logql
{pod=~"prometheus.*"}
{namespace="monitoring"} |~ "error"
{app="loki"}
```

## Troubleshooting

### Grafana Pod in CrashLoopBackOff

**Symptom:** Pod repeatedly restarting, init container failing

**Common cause:** `init-chown-data` container can't change ownership of data directory

**Solution:**
```yaml
# In values.yaml
initChownData:
  enabled: false

securityContext:
  runAsUser: 472
  runAsGroup: 472
  fsGroup: 472
```

**Why this works:**
- Grafana runs as user 472 by default
- `fsGroup: 472` sets PVC ownership via Kubernetes
- No need for privileged init container

### Data Source Connection Failed

**Symptom:** "Data source is not working" or "no such host" error

**Debug:**
```bash
# Check service names
kubectl get svc -n monitoring | grep -E "prometheus|loki"

# Test connectivity from Grafana pod
kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  nslookup prometheus-prometheus

kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  curl -s http://prometheus-prometheus:9090/api/v1/status/config
```

**Common fixes:**
- Verify service name matches (e.g., `prometheus-prometheus` not `prometheus-kube-prometheus-prometheus`)
- Use short names when in same namespace
- Check Prometheus/Loki pods are running

### Dashboards Not Loading

**Symptom:** Dashboard shows "Panel plugin not found" or empty panels

**Solutions:**

**Missing plugin:**
```yaml
# Add to values.yaml
plugins:
  - grafana-missing-plugin-name
```

**Data source not selected:**
- Edit panel → Query → Select correct data source

**No data in time range:**
- Adjust time range (top right) to "Last 24 hours"
- Check if Prometheus has retention data

### No Logs in Explore View

**Symptom:** Loki data source works but queries return empty

**Debug:**
```bash
# Check Promtail is sending logs
kubectl logs -n monitoring -l app.kubernetes.io/name=promtail --tail=20
# Look for: "Successfully sent batch"

# Check Loki has data
kubectl port-forward -n monitoring svc/loki 3100:3100 &
curl -s "http://localhost:3100/loki/api/v1/labels" | jq
pkill -f "port-forward.*loki"
```

**Common issues:**
- Promtail not running on all nodes
- Loki retention expired (7 days)
- Wrong label selectors in query

### High Memory Usage

**Symptom:** Grafana pod using >500Mi, hitting limits

**Solutions:**

**Increase limits:**
```yaml
resources:
  limits:
    memory: 1Gi  # Up from 512Mi
```

**Reduce dashboard complexity:**
- Fewer panels per dashboard
- Longer refresh intervals
- Limit query time ranges

### Login Loop / Session Issues

**Symptom:** Can't login, redirects back to login page

**Debug:**
```bash
# Check Grafana logs
kubectl logs -n monitoring -l app.kubernetes.io/name=grafana --tail=50
```

**Common causes:**
- Incorrect `root_url` in grafana.ini
- Cookie domain mismatch
- Browser cache issues

**Fix:**
```yaml
grafana.ini:
  server:
    root_url: http://grafana.homelab.local:30080  # Must match access URL
```

## Dashboard Creation

### Creating a Simple Dashboard

1. **+ Create** → **Dashboard**
2. **Add visualization**
3. **Select data source:** Prometheus
4. **Query:** `sum(rate(container_cpu_usage_seconds_total[5m])) by (namespace)`
5. **Panel title:** "CPU Usage by Namespace"
6. **Apply**
7. **💾 Save dashboard**

### Common PromQL Queries

**Node CPU usage:**
```promql
100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Node memory usage:**
```promql
100 - ((node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100)
```

**Pod CPU usage:**
```promql
sum(rate(container_cpu_usage_seconds_total{namespace="monitoring"}[5m])) by (pod)
```

**Pod memory usage:**
```promql
sum(container_memory_working_set_bytes{namespace="monitoring"}) by (pod)
```

### Common LogQL Queries

**Error logs:**
```logql
{namespace="monitoring"} |~ "error|Error|ERROR"
```

**Logs from specific pod:**
```logql
{pod="prometheus-prometheus-prometheus-0"}
```

**Log rate (errors per minute):**
```logql
sum(rate({namespace="monitoring"} |~ "error" [1m]))
```

**Parse JSON logs:**
```logql
{namespace="monitoring"} | json | level="error"
```

### Dashboard Best Practices

**Performance:**
- Use time range variables (`$__interval`)
- Limit query results (e.g., `topk(10, ...)`)
- Set appropriate refresh intervals (30s-5m)
- Avoid `*` selectors (e.g., `{namespace=~".*"}`)

**Usability:**
- Meaningful panel titles
- Units configured (bytes, percent, seconds)
- Thresholds for warnings/errors
- Descriptions for complex queries

**Organization:**
- Group related panels in rows
- Use variables for filtering (namespace, pod)
- Consistent color schemes
- Annotations for deployments/incidents

## Alerting

### Creating an Alert

1. Open dashboard → Edit panel
2. **Alert** tab
3. **Create alert rule**
4. **Condition:** `WHEN max() OF query(A) IS ABOVE 80`
5. **Evaluate every:** 1m
6. **For:** 5m (wait before firing)
7. **Notifications:** Select channel

### Alert Channels

**Supported:**
- Email (requires SMTP config)
- Slack (webhook URL)
- PagerDuty (integration key)
- Webhook (custom HTTP endpoint)

**Example Slack config:**
```yaml
# In values.yaml
grafana.ini:
  alerting:
    enabled: true
  
  "unified_alerting":
    enabled: false
```

## Production Comparison

| Aspect | Homelab | Enterprise |
|--------|---------|------------|
| Deployment | Single pod | HA with 3+ replicas |
| Storage | 1Gi PVC | 10-50Gi with backups |
| Auth | Admin user | OAuth2/OIDC/LDAP |
| Dashboards | 4 pre-installed | 50-100+ custom |
| Users | 1 admin | Multi-org, role-based |
| Alerting | Basic | PagerDuty/Opsgenie integration |
| Data sources | 2 (Prometheus, Loki) | 10+ (Prometheus, Loki, Tempo, Cloud providers) |
| High Availability | No | Load balanced across AZs |
| Backup | Manual export | Automated to S3/Git |
| SSL/TLS | HTTP only | HTTPS with valid certs |

**Cloud Cost Equivalent:**
- Grafana Cloud Free Tier: 10k metrics, 50GB logs/month (free)
- Grafana Cloud Pro: $8/user/month + usage
- Self-hosted equivalent: ~$20-50/month (hosting + maintenance)
- Homelab cost: ~$0

## Integration Points

### Current Integrations
- **Prometheus**: Default data source for metrics
- **Loki**: Log aggregation and querying
- **nginx-ingress**: External access to UI
- **local-path-provisioner**: Persistent storage

### Future Integrations
- **Tempo**: Distributed tracing (Phase 7+)
- **Alertmanager**: Alert routing (currently basic)
- **Git**: Dashboard version control
- **Slack/Discord**: Alert notifications

## Backup & Export

### Export Dashboards

**Via UI:**
1. Open dashboard
2. **⚙️ Dashboard settings** (gear icon)
3. **JSON Model**
4. Copy JSON
5. Save to `platform/grafana/dashboards/my-dashboard.json`

**Via API:**
```bash
# Export all dashboards
curl -H "Authorization: Bearer $API_KEY" \
  http://grafana.homelab.local:30080/api/search?type=dash-db | \
  jq -r '.[] | .uid' | \
  while read uid; do
    curl -H "Authorization: Bearer $API_KEY" \
      http://grafana.homelab.local:30080/api/dashboards/uid/$uid > "$uid.json"
  done
```

### Backup PVC

```bash
# Snapshot Grafana data
kubectl exec -n monitoring -l app.kubernetes.io/name=grafana -- \
  tar czf /tmp/grafana-backup.tar.gz /var/lib/grafana

# Copy out
kubectl cp monitoring/$(kubectl get pod -n monitoring -l app.kubernetes.io/name=grafana -o name | cut -d/ -f2):/tmp/grafana-backup.tar.gz \
  ./grafana-backup-$(date +%Y%m%d).tar.gz
```

### Restore from Backup

```bash
# Copy backup into pod
kubectl cp grafana-backup.tar.gz monitoring/<grafana-pod>:/tmp/

# Extract
kubectl exec -n monitoring <grafana-pod> -- \
  tar xzf /tmp/grafana-backup.tar.gz -C /

# Restart pod
kubectl rollout restart deployment grafana -n monitoring
```

## Maintenance

### Upgrade Grafana

```bash
# Check current version
kubectl get application grafana -n platform -o yaml | grep targetRevision

# Update to new version
vim platform/argocd/apps/grafana-app.yaml
# Change: targetRevision: 10.5.15 → 10.6.0

# Review changelog
# https://github.com/grafana/grafana/releases

git add platform/argocd/apps/grafana-app.yaml
git commit -m "chore(observability): upgrade Grafana to v10.6.0"
git push
```

### Add New Data Source

```yaml
# In values.yaml, under datasources.datasources.yaml.datasources
- name: Tempo
  type: tempo
  url: http://tempo:3100
  access: proxy
```

### Add New Dashboard

**Option 1: Auto-import from grafana.com**
```yaml
dashboards:
  default:
    my-new-dashboard:
      gnetId: 12345
      revision: 1
      datasource: Prometheus
```

**Option 2: From JSON file**
```yaml
dashboards:
  default:
    custom-dashboard:
      json: |
        {
          "dashboard": { ... },
          "overwrite": true
        }
```

### Reset Admin Password

```bash
# Connect to Grafana pod
kubectl exec -it -n monitoring <grafana-pod> -- /bin/sh

# Reset password
grafana-cli admin reset-admin-password newpassword

# Exit and test login
```

## Related Documentation

- **ADR**: `docs/adr/010-observability-stack-architecture.md`
- **ArgoCD App**: `platform/argocd/apps/grafana-app.yaml`
- **Prometheus Integration**: `platform/prometheus/README.md`
- **Loki Integration**: `platform/loki/README.md`
- **Grafana Docs**: https://grafana.com/docs/grafana/latest/
- **Dashboard Gallery**: https://grafana.com/grafana/dashboards/

## Tips & Tricks

### Keyboard Shortcuts

- `d` + `h` - Go to home dashboard
- `d` + `s` - Star dashboard
- `Ctrl/Cmd + S` - Save dashboard
- `Esc` - Exit panel edit
- `f` - Toggle fullscreen

### Template Variables

Create dynamic dashboards with variables:

**Example:** Namespace selector
1. Dashboard settings → Variables → Add variable
2. Name: `namespace`
3. Type: Query
4. Data source: Prometheus
5. Query: `label_values(kube_pod_info, namespace)`
6. Use in queries: `{namespace="$namespace"}`

### Annotations

Mark deployments/incidents on graphs:

1. Dashboard settings → Annotations
2. Add annotation query
3. Data source: Prometheus
4. Query: `changes(kube_deployment_status_observed_generation{namespace="monitoring"}[5m])`

### Share Dashboard

**Snapshot (no login required):**
1. Dashboard → Share
2. Snapshot
3. Publish to snapshots.raintank.io
4. Copy link

**Direct link (login required):**
```
http://grafana.homelab.local:30080/d/<dashboard-uid>
```

---

**Last Updated**: 2026-02-07  
**Grafana Version**: 12.3.1  
**Chart Version**: 10.5.15  
**Kubernetes**: v1.31.4
