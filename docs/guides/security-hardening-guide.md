# Kubernetes Security Hardening Guide

**Homelab:** `mmrajputhomelab.org`  
**Cluster:** kubeadm v1.31.4, Calico CNI, ArgoCD GitOps  
**Phase:** 7 — Security Hardening  

---

## Overview: Defence in Depth

Security hardening is not a single control — it is a set of independent layers where each layer assumes the previous one has already failed. The four primary layers in this cluster are:

| Layer | What it controls | Failure mode it mitigates |
|-------|-----------------|--------------------------|
| NetworkPolicy | Traffic between pods and to external endpoints | Compromised pod laterally moving through the cluster |
| Pod Security Standards (PSS) | What a container can do on the node | Container escape to the underlying host |
| RBAC | What identities can do via the Kubernetes API | Compromised pod using its ServiceAccount token to exfiltrate or modify cluster resources |
| TLS / Certificate Management | Encryption in transit | Traffic interception between services and at the edge |
| Runtime Security (Falco) | Syscall-level behaviour on every node | Detects attacks that have already bypassed the layers above — shell spawned inside a container, unexpected file writes, privilege escalation attempts |

A concrete attack scenario to illustrate why all layers matter:

> Grafana has a vulnerability. An attacker gets code execution inside the container.
>
> - **No NetworkPolicy** → attacker pivots to Prometheus, Loki, ArgoCD, and the database directly.
> - **NetworkPolicy in place, no PSS** → attacker is isolated but container runs as root — container escape to the node is possible.
> - **PSS in place, no RBAC hardening** → attacker reads the mounted ServiceAccount token, calls the Kubernetes API, lists all Secrets across all namespaces.
> - **All three layers in place** → attacker is isolated, cannot escape the container, and the pod has no token to use against the API.

---

## Layer 1: NetworkPolicy

### Mental Model

NetworkPolicy controls packet flow. It operates at the network level before any Kubernetes authentication or authorisation occurs. A connection timeout means NetworkPolicy (or a firewall) is blocking — not RBAC.

**Error signal mapping:**
- `i/o timeout` → NetworkPolicy or firewall blocking the connection
- `connection refused` → Service reachable but nothing listening
- `403 Forbidden` → RBAC denying the authenticated request
- `401 Unauthorized` → Authentication failed

### Pattern: Default-Deny + Explicit Allow

Every namespace in this cluster follows the same pattern:

```yaml
# Step 1: Default-deny all ingress and egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
```

```yaml
# Step 2: Explicit allow policy per namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: <namespace>-allow
  namespace: <namespace>
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: ingress-nginx
    - from:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: <namespace>
  egress:
    - ports:
        - port: 53
          protocol: UDP
        - port: 53
          protocol: TCP
      to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: <namespace>
```

### Key Findings from This Cluster

**nginx-ingress connects to pod IPs directly, not service IPs.**  
Calico DNAT resolves service ClusterIPs to pod IPs before NetworkPolicy evaluation. Egress rules for workloads that receive traffic from nginx-ingress must use the actual pod port, not the service port.

Example: Grafana service exposes port 80, but Grafana pod listens on port 3000. The NetworkPolicy egress rule from nginx-ingress must allow port 3000.

**Kubernetes API server requires two egress destinations.**  
For namespaces that need API server access (ArgoCD, cert-manager):

```yaml
egress:
  - ports:
      - port: 443
        protocol: TCP
      - port: 6443
        protocol: TCP
    to:
      - ipBlock:
          cidr: 10.96.0.1/32   # kubernetes service ClusterIP
      - ipBlock:
          cidr: <control-plane-node-ip>/32  # Calico DNAT resolves to this
```

Calico's DNAT means some packets are evaluated against the control plane node IP rather than the ClusterIP. Both must be explicitly allowed.

**ArgoCD v3+ nil pointer bug.**  
If NetworkPolicy blocks API server access for ArgoCD, it triggers a nil pointer dereference rather than a clean error. Always verify API server egress is working after NetworkPolicy changes by checking ArgoCD pod logs.

---

## Layer 2: Pod Security Standards (PSS)

### Mental Model

PSS controls the pod's relationship to the underlying Linux host — not what it can do inside Kubernetes. Three enforcement levels:

| Level | What it allows |
|-------|---------------|
| `privileged` | Unrestricted — anything goes |
| `baseline` | Prevents known privilege escalation vectors (no hostPID, no privileged containers) |
| `restricted` | Hardened — requires non-root, read-only filesystem, seccomp profile, dropped capabilities |

### Namespace Labels

```yaml
# Enforce baseline, audit and warn at restricted
# Use this for namespaces with workloads that cannot meet restricted (e.g. node-exporter, Promtail)
labels:
  pod-security.kubernetes.io/enforce: baseline
  pod-security.kubernetes.io/audit: restricted
  pod-security.kubernetes.io/warn: restricted

# Use this for namespaces where all workloads can meet restricted
labels:
  pod-security.kubernetes.io/enforce: restricted
  pod-security.kubernetes.io/audit: restricted
  pod-security.kubernetes.io/warn: restricted
```

### Namespace Assignments in This Cluster

| Namespace | Enforcement | Reason |
|-----------|------------|--------|
| `monitoring` | `privileged` | node-exporter requires hostPID and hostNetwork; Promtail requires hostPath mounts and runs as root |
| `falco` | `privileged` | Falco loads the `modern_ebpf` driver and inspects host syscalls — incompatible with baseline or restricted |
| `platform` | `restricted` | ArgoCD components all meet restricted requirements |
| `ingress-nginx` | `restricted` | nginx-ingress meets restricted requirements |
| `cloudflare` | `restricted` | cloudflared meets restricted requirements |
| `cert-manager` | `restricted` | cert-manager meets restricted requirements |

### Restricted PSS Security Context

For workloads that can meet `restricted`:

```yaml
# Pod-level
podSecurityContext:
  runAsNonRoot: true
  runAsUser: <non-zero UID>
  runAsGroup: <non-zero GID>
  fsGroup: <non-zero GID>
  fsGroupChangePolicy: OnRootMismatch
  seccompProfile:
    type: RuntimeDefault   # Required at pod level for restricted PSS

# Container-level
containerSecurityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]
  seccompProfile:
    type: RuntimeDefault   # Also set at container level for defence in depth
```

### Loki-Specific Note

In the `grafana/loki` Helm chart, `podSecurityContext` and `containerSecurityContext` must be nested under the `loki:` key, not under `singleBinary:`. The `singleBinary:` key controls StatefulSet-level overrides; the `loki:` key sets defaults applied across all components.

```yaml
# Correct
loki:
  podSecurityContext: ...
  containerSecurityContext: ...

# Incorrect — security contexts not applied to pods
singleBinary:
  podSecurityContext: ...
  containerSecurityContext: ...
```

### Promtail PSS Position

Promtail is intentionally left at `baseline` enforcement. It requires:
- `hostPath` volume mounts to read node log files (`/var/log`)
- Running as root (UID 0) to access protected log paths

This is a known, accepted constraint. Promtail's node log access is its core function — restricting it would break log collection. Document this explicitly so it is not treated as an oversight.

---

## Layer 5: Runtime Security (Falco)

### Mental Model

The four layers above are **preventive** — they reduce the attack surface. Falco is **detective** — it watches what actually happens on the node and raises an alert when behaviour deviates from what is expected. A process that bypasses all four preventive layers (zero-day, misconfigured PSS, over-permissioned RBAC) will still generate a Falco event the moment it does something anomalous.

Falco instruments the Linux kernel via the `modern_ebpf` driver, inspecting every syscall on every node without requiring a kernel module. Events are forwarded to Falcosidekick, which fans them out to Loki (queryable in Grafana) and Prometheus (metrics for dashboards and alerting).

### Architecture

```
Falco DaemonSet (one pod per node)
  └── modern_ebpf driver → syscall stream
        └── HTTP → Falcosidekick (Deployment)
                      ├── Loki :3100  → Grafana log panel
                      └── Prometheus :2802 → ServiceMonitor → Grafana metrics
```

### Driver: modern_ebpf

`modern_ebpf` runs entirely in kernel space via BPF programs — no kernel module compilation, no DKMS, compatible with Ubuntu 24.04 LTS and kernel 6.x out of the box.

```yaml
driver:
  kind: modern_ebpf
```

Do not use `ebpf` (legacy) or `kmod` on this cluster — both require kernel headers or module compilation that is not present on the kubeadm node images.

### Custom Suppress Rules

Default Falco rules generate significant noise from known platform workloads (ArgoCD, Prometheus, Longhorn, Promtail all trigger `Write below etc`, `Read sensitive file`, and `Launch Privileged Container` by design). Suppress with a macro rather than disabling rules entirely:

```yaml
customRules:
  suppress-homelab.yaml: |-
    - macro: trusted_homelab_containers
      condition: >
        (container.image.repository startswith "quay.io/argoproj/argocd" or
         container.image.repository startswith "grafana/grafana" or
         container.image.repository startswith "longhornio" or
         container.image.repository startswith "quay.io/prometheus" or
         container.image.repository startswith "grafana/promtail" or
         container.image.repository startswith "rancher/")

    - rule: Write below etc
      append: true
      condition: and not trusted_homelab_containers
```

Appending `and not trusted_homelab_containers` to a rule narrows it rather than disabling it — unexpected containers still trigger the rule.

### NetworkPolicy for Falco

Falco requires `privileged` PSS and a split NetworkPolicy (falco pods and falcosidekick pods have different traffic profiles):

| Traffic | Direction | Port |
|---------|-----------|------|
| Falco → Falcosidekick | egress (intra-namespace) | 2801 |
| Falcosidekick → Loki | egress to `monitoring` | 3100 |
| Prometheus → Falcosidekick | ingress from `monitoring` | 2802 |
| Falcosidekick → external | egress (Slack webhooks) | 443 |

Falco itself does **not** need Kubernetes API egress unless k8s audit log enrichment is enabled (it is not enabled in this cluster).

### Verifying Falco is Working

```bash
# All Falco pods running (one per node)
kubectl get pods -n falco -o wide

# Falcosidekick is forwarding to Loki
kubectl logs -n falco -l app.kubernetes.io/name=falcosidekick | grep -i loki

# Trigger a test event (generates a Falco alert)
kubectl run falco-test --image=alpine --rm -it --restart=Never -- \
  sh -c 'cat /etc/shadow'
# Then query Grafana: {namespace="falco", container="falcosidekick"}
```

---

## Layer 3: RBAC

### Mental Model

RBAC controls what authenticated identities can do via the Kubernetes API. It operates after the network connection is established and after authentication. RBAC cannot substitute for NetworkPolicy — if a pod's token is compromised, NetworkPolicy is the only thing preventing the attacker from reaching the API server to use it.

**The three controls:**

1. **Token mounting** — `automountServiceAccountToken: false` prevents the credential from existing in the pod at all. Nothing to steal.
2. **ServiceAccount scoping** — dedicated ServiceAccount per workload, never share, never use `default`.
3. **Permission scoping** — RoleBindings and ClusterRoleBindings grant only the minimum permissions required.

### Decision Tree Per Workload

```
Does this pod need to talk to the Kubernetes API?
├── No  → automountServiceAccountToken: false (at both SA and pod spec level)
└── Yes → dedicated ServiceAccount + minimum necessary permissions only
```

### Workload Classification in This Cluster

| Workload | Needs API Access | Reason |
|----------|-----------------|--------|
| Grafana | No | UI only — reads from Prometheus and Loki via HTTP |
| Loki | No | Log storage — no cluster state required |
| Alertmanager | No | Receives alerts and routes them — no API interaction |
| node-exporter | No | Reads host metrics via hostPath — no API interaction |
| cloudflared | No | Tunnel only — no cluster state required |
| Promtail | Yes | Reads pod metadata for log enrichment (labels, namespace, pod name) |
| Prometheus | Yes | Scrapes API metrics endpoints |
| kube-state-metrics | Yes | Reads cluster state (pods, deployments, etc.) |
| prometheus-operator | Yes | Manages CRDs (PrometheusRule, ServiceMonitor, etc.) |
| ArgoCD components | Yes | Create, update, delete resources across namespaces |
| cert-manager | Yes | Manages Certificate and CertificateRequest CRDs |

### Disabling Token Mounting in Helm Values

Set at both ServiceAccount and pod spec level. Pod spec takes precedence over ServiceAccount — setting both makes the intent explicit at two layers.

```yaml
# ServiceAccount level: default for any pod using this SA
serviceAccount:
  create: true
  automountServiceAccountToken: false

# Pod spec level: explicit override, takes precedence over SA setting
automountServiceAccountToken: false
```

For sub-components in kube-prometheus-stack (Alertmanager):

```yaml
alertmanager:
  serviceAccount:
    create: true
    automountServiceAccountToken: false
  alertmanagerSpec:
    automountServiceAccountToken: false
```

### Verifying Token Mount Status

Check all pods in a namespace:

```bash
kubectl get pod -n <namespace> -o json | jq -r '
  .items[] |
  [.metadata.name, (.spec.automountServiceAccountToken // "not-set")] |
  @tsv' | sort
```

`not-set` at the pod spec level is acceptable only if the ServiceAccount itself has `automountServiceAccountToken: false`. Verify:

```bash
kubectl get serviceaccount -n <namespace> <sa-name> \
  -o jsonpath='{.automountServiceAccountToken}'
```

Confirm no token is mounted inside the pod:

```bash
kubectl exec -n <namespace> <pod-name> -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Expected: No such file or directory
```

### Checking for Broad ClusterRoleBindings

```bash
kubectl get clusterrolebindings -o json | jq -r '
  .items[] |
  select(.roleRef.name | test("cluster-admin|admin|edit")) |
  [.metadata.name, .roleRef.name, (.subjects // [] | map(.name) | join(","))] |
  @tsv'
```

Only kubeadm bootstrap bindings (`system:masters`, `kubeadm:cluster-admins`) should appear. Any application ServiceAccount bound to `cluster-admin` is a critical finding.

---

## Layer 4: TLS and Certificate Management

### Architecture

```
Browser → HTTPS → Cloudflare Edge → Cloudflare Tunnel (QUIC) → HTTP → nginx-ingress → Pod
```

TLS is terminated at the Cloudflare edge. Traffic between Cloudflare Tunnel and nginx-ingress travels over HTTP within the cluster. This is intentional — the tunnel provides encrypted transport, and terminating TLS twice inside the cluster adds complexity without meaningful security benefit in this topology.

### Cloudflare Free Tier Wildcard Constraint

Cloudflare's free tier wildcard certificate covers `*.mmrajputhomelab.org` — one subdomain level only. It does not cover `*.homelab.mmrajputhomelab.org` or any two-level subdomain pattern.

All service hostnames are therefore single-level subdomains:
- `argocd.mmrajputhomelab.org` ✅
- `grafana.mmrajputhomelab.org` ✅
- `argocd.homelab.mmrajputhomelab.org` ❌ — not covered by wildcard

Plan subdomain architecture before deploying services. Migrating hostnames after services are deployed requires updating Ingress objects, Cloudflare Tunnel config, and any hardcoded references.

### SSL Redirect Configuration

nginx-ingress must have SSL redirects disabled to prevent 308 redirect loops. Cloudflare sends HTTPS to the tunnel; the tunnel forwards HTTP to nginx-ingress. If nginx-ingress then issues a 308 redirect back to HTTPS, the browser enters an infinite loop.

```yaml
annotations:
  nginx.ingress.kubernetes.io/ssl-redirect: "false"
  nginx.ingress.kubernetes.io/force-ssl-redirect: "false"
```

### cert-manager DNS01 Challenge

Wildcard certificates require DNS01 challenge (HTTP01 cannot validate wildcard domains). The Cloudflare API token used by cert-manager requires `Zone:DNS:Edit` permission scoped to the specific zone.

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-production
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: letsencrypt-production-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-api-token
              key: api-token
```

---

## ArgoCD + Helm Hooks: Known Friction

Helm hook resources with `hook-delete-policy: before-hook-creation,hook-succeeded` are deleted by Helm after a successful run. ArgoCD with `prune: true` then treats them as orphaned resources on subsequent syncs and removes them, breaking future Helm upgrades that depend on those resources.

**Affected resources in this cluster:** `kube-prometheus-stack` admission webhook Jobs, Roles, and RoleBindings.

**Resolution:** Disable the admission webhook for homelab use. It validates PrometheusRules before apply — useful in production, unnecessary overhead here.

```yaml
prometheusOperator:
  admissionWebhooks:
    enabled: false
```

In a production environment the correct fix is to manage these RBAC resources explicitly in Git via a separate ArgoCD Application, rather than relying on Helm hooks to create them.

---

## Security Checklist

Use this checklist when adding a new namespace or workload.

### New Namespace

- [ ] Default-deny NetworkPolicy applied
- [ ] Explicit allow NetworkPolicy created with minimum required ingress/egress rules
- [ ] PSS labels set (`enforce`, `audit`, `warn`)
- [ ] PSS level justified and documented (why baseline vs restricted)

### New Workload

- [ ] Does it need Kubernetes API access? Decision documented.
- [ ] If no API access: `automountServiceAccountToken: false` set at SA and pod spec level
- [ ] If API access needed: dedicated ServiceAccount created, permissions scoped to minimum required
- [ ] Pod runs as non-root (`runAsNonRoot: true`, non-zero UID)
- [ ] `readOnlyRootFilesystem: true` where possible
- [ ] `allowPrivilegeEscalation: false`
- [ ] `capabilities.drop: [ALL]`
- [ ] `seccompProfile.type: RuntimeDefault` at pod and container level
- [ ] NetworkPolicy egress rules use pod ports, not service ports (verify with `kubectl get pod -o wide`)
- [ ] Ingress annotations disable SSL redirect if behind Cloudflare Tunnel

### After Changes

- [ ] Verify pods running: `kubectl get pods -n <namespace>`
- [ ] Verify no PSS violations: `kubectl get events -n <namespace> | grep -i policy`
- [ ] Verify token mount status: check SA and pod spec `automountServiceAccountToken`
- [ ] Confirm no token in pod: `ls /var/run/secrets/kubernetes.io/serviceaccount/`
- [ ] Commit and push — ArgoCD syncs from Git, manual applies are temporary

---

## Troubleshooting Reference

| Symptom | Layer | Likely Cause |
|---------|-------|-------------|
| `i/o timeout` connecting to API server | NetworkPolicy | Egress rule missing for `10.96.0.1:443` or control plane node IP |
| `403 Forbidden` from API server | RBAC | ServiceAccount lacks permission for the requested resource/verb |
| `401 Unauthorized` from API server | Authentication | Token missing, expired, or invalid |
| Pod stuck in `Pending` with PSS violation event | PSS | Container spec violates namespace enforcement level |
| `CrashLoopBackOff` on admission Job | RBAC + Helm hooks | Admission RBAC resources pruned by ArgoCD; disable webhook or manage in Git |
| 308 redirect loop in browser | TLS config | SSL redirect enabled on nginx-ingress behind Cloudflare Tunnel |
| ArgoCD nil pointer dereference | NetworkPolicy | API server egress blocked for ArgoCD namespace |
| Loki security context not applied | Helm values structure | `podSecurityContext` nested under `singleBinary:` instead of `loki:` |
