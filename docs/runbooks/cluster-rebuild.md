# Cluster Rebuild Runbook

**Last Updated:** March 2026  
**Cluster:** mmrajputhomelab.org  
**Hardware:** Beelink SER5 Pro (32GB RAM, 500GB SSD) — Proxmox VE  
**Kubernetes:** v1.31.4 (kubeadm), Calico CNI  

---

## Overview

This runbook documents the complete procedure to rebuild the homelab Kubernetes cluster from scratch. It covers three distinct layers:

```
infra/       → Proxmox VM provisioning + Ansible Kubernetes install
bootstrap/   → One-time kubectl applies to prepare cluster for ArgoCD
platform/    → Everything managed by ArgoCD (GitOps)
```

**Estimated time:** 2–3 hours for a full rebuild.

---

## Prerequisites

- Proxmox VE access on Beelink SER5 Pro
- SSH access to all nodes
- GitHub repository access: `https://github.com/mmrajput/kubernetes-homelab`
- Cloudflare API token (stored securely, never committed to Git)
- Devcontainer running (`homelab-devcontainer`)

---

## Phase 1 — VM Provisioning (infra/)

### 1.1 Create VM Template

```bash
cd infra/proxmox/vm-templates
./create-template.sh
```

### 1.2 Provision Control Plane and Worker Nodes

```bash
./create-k8s-controlplane.sh
./create-k8s-workers.sh
```

Expected result: 3 VMs running in Proxmox
- `k8s-control-plane` — 192.168.178.34
- `k8s-worker-01` — 192.168.178.35
- `k8s-worker-02` — 192.168.178.36

### 1.3 Install Kubernetes with Ansible

```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml
```

Verify cluster is up:

```bash
kubectl get nodes
```

Expected output:
```
NAME                STATUS   ROLES           AGE
k8s-control-plane   Ready    control-plane   Xm
k8s-worker-01       Ready    <none>          Xm
k8s-worker-02       Ready    <none>          Xm
```

---

## Phase 2 — Bootstrap (bootstrap/)

This phase runs once per cluster lifetime. These steps are deliberately outside GitOps — they create the foundation that ArgoCD will build on.

### 2.1 Apply Namespace Manifests with PSS Labels

> **Why manual:** ArgoCD v3.2.3 has a nil pointer dereference bug when syncing Namespace resources. Namespaces are managed via bootstrap, not ArgoCD. See ADR-006.

```bash
kubectl apply -f bootstrap/namespaces/
```

Verify PSS labels are applied:

```bash
kubectl get namespaces -o custom-columns=\
"NAME:.metadata.name,\
ENFORCE:.metadata.labels.pod-security\.kubernetes\.io/enforce,\
AUDIT:.metadata.labels.pod-security\.kubernetes\.io/audit,\
WARN:.metadata.labels.pod-security\.kubernetes\.io/warn"
```

Expected output:
```
NAME           ENFORCE      AUDIT        WARN
cert-manager   restricted   restricted   restricted
cloudflare     restricted   restricted   restricted
ingress-nginx  restricted   restricted   restricted
monitoring     baseline     restricted   restricted
platform       restricted   restricted   restricted
```

### 2.2 Install ArgoCD

```bash
kubectl apply -n platform -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.3/manifests/install.yaml
```

Wait for ArgoCD to be ready:

```bash
kubectl wait --for=condition=available deployment/argocd-server -n platform --timeout=120s
```

### 2.3 Bootstrap GitOps with Root App

```bash
kubectl apply -f platform/argocd/root-app.yaml
```

This single command bootstraps the entire platform via the App-of-Apps pattern. ArgoCD will pick up all child Application manifests from `platform/argocd/apps/` and deploy everything.

---

## Phase 3 — Secrets (Manual, Never in Git)

These secrets must be applied manually after the namespaces exist but before ArgoCD syncs the dependent apps.

### 3.1 Cloudflare API Token (cert-manager)

```bash
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=<TOKEN> \
  -n cert-manager
```

### 3.2 Cloudflare Tunnel Token (cloudflared)

```bash
kubectl create secret generic cloudflare-tunnel-token \
  --from-literal=token=<TUNNEL_TOKEN> \
  -n cloudflare
```

> **Note:** Without these secrets, cert-manager will fail to issue certificates and cloudflared will fail to start. Apply them before or immediately after ArgoCD starts syncing.

---

## Phase 4 — ArgoCD Sync Verification

After root-app is applied, ArgoCD will begin syncing all applications. Monitor progress:

```bash
kubectl get applications -n platform -w
```

Expected final state (allow 5–10 minutes):
```
NAME                    SYNC STATUS   HEALTH STATUS
argocd                  Synced        Healthy
cert-manager            Synced        Healthy
grafana                 Synced        Healthy
ingress-nginx           Synced        Healthy
kube-prometheus-stack   Synced        Healthy
loki                    Synced        Healthy
network-policies        Synced        Healthy
promtail                Synced        Healthy
root-app                Synced        Healthy
```

---

## Phase 5 — Post-Rebuild Verification

### 5.1 Verify All Pods Running

```bash
kubectl get pods -A | grep -v "Running\|Completed"
```

Expected: no output (all pods Running or Completed).

### 5.2 Verify TLS Certificate

```bash
kubectl get certificate -n ingress-nginx
```

Expected:
```
NAME                  READY   SECRET               AGE
wildcard-homelab-tls  True    wildcard-homelab-tls  Xm
```

> **Note:** Certificate issuance via DNS-01 challenge can take 2–5 minutes. If READY is False, check cert-manager logs:
> ```bash
> kubectl logs -n cert-manager -l app=cert-manager --tail=50
> ```

### 5.3 Verify External Access

```bash
curl -I https://grafana.mmrajputhomelab.org
curl -I https://argocd.mmrajputhomelab.org
curl -I https://prometheus.mmrajputhomelab.org
```

Expected: HTTP 200 or 302 responses (no 5xx errors).

### 5.4 Verify Prometheus Targets

```bash
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool | grep -c "health"
```

Expected: 30+ targets discovered.

---

## Known Issues and Workarounds

### ArgoCD v3.2.3 Nil Pointer Dereference

**Symptom:** `runtime error: invalid memory address or nil pointer dereference` on sync

**Root cause:** ArgoCD v3.2.3 bug triggered when syncing Namespace resources or when the Kubernetes API is unreachable due to NetworkPolicy blocking egress to `10.96.0.1:443`.

**Resolution:**
1. Check if Kubernetes API is reachable from the platform namespace (see NetworkPolicy section below)
2. Namespace management is handled via `bootstrap/` — not ArgoCD

### NetworkPolicy Deadlock

**Symptom:** ArgoCD sync fails with API timeout. Manual `kubectl apply` reverts because selfHeal is active.

**Resolution:**
```bash
# Step 1 - Disable selfHeal temporarily
kubectl patch application network-policies -n platform \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":false}}}}'

# Step 2 - Apply the correct NetworkPolicy
kubectl apply -f platform/network-policies/platform-netpol.yaml

# Step 3 - Re-enable selfHeal
kubectl patch application network-policies -n platform \
  --type merge \
  -p '{"spec":{"syncPolicy":{"automated":{"prune":true,"selfHeal":true}}}}'
```

### Calico DNAT — Kubernetes API Egress

**Symptom:** Pods in `platform` or `cert-manager` namespace cannot reach `10.96.0.1:443`.

**Root cause:** Calico evaluates NetworkPolicy rules before kube-proxy DNAT. Traffic to the `kubernetes` ClusterIP (`10.96.0.1`) is NATted to the control plane node IP (`192.168.178.34:6443`). Both IPs must be allowed in egress rules.

**Required egress rules in platform-netpol.yaml and cert-manager-netpol.yaml:**
```yaml
- to:
    - ipBlock:
        cidr: 10.96.0.1/32       # kubernetes service ClusterIP
    - ipBlock:
        cidr: 192.168.178.34/32  # control plane node IP (post-DNAT)
  ports:
    - port: 443
      protocol: TCP
    - port: 6443
      protocol: TCP
```

**Verify connectivity:**
```bash
kubectl run test --image=curlimages/curl --rm -it --restart=Never -n platform \
  --overrides='{"spec":{"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"test","image":"curlimages/curl","args":["-I","https://10.96.0.1:443","--max-time","5","--insecure"],"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}}]}}'
```

Expected: `HTTP/2 403` (connected, rejected due to no credentials — correct behavior).

### ArgoCD Application Finalizer Blocking Deletion

**Symptom:** `DeletionError: failed to get api resource ... dial tcp 10.96.0.1:443: i/o timeout`

**Resolution:** Remove the finalizer before deleting:
```bash
kubectl patch application <app-name> -n platform \
  --type json \
  -p '[{"op":"remove","path":"/metadata/finalizers"}]'

kubectl delete application <app-name> -n platform
```

---

## Teardown

To destroy the cluster and all VMs:

```bash
cd infra/proxmox/vm-templates
./destroy-cluster.sh
```

> **Warning:** This is irreversible. Ensure all persistent data is backed up before running.

---

## Reference

| Component | Version | Namespace |
|-----------|---------|-----------|
| Kubernetes | v1.31.4 | — |
| ArgoCD | v3.2.3 | platform |
| cert-manager | v1.16.2 | cert-manager |
| nginx-ingress | latest | ingress-nginx |
| cloudflared | 2025.2.1 | cloudflare |
| kube-prometheus-stack | latest | monitoring |
| Loki | latest | monitoring |
| Grafana | latest | monitoring |

| Hostname | Service |
|----------|---------|
| argocd.mmrajputhomelab.org | ArgoCD UI |
| grafana.mmrajputhomelab.org | Grafana |
| prometheus.mmrajputhomelab.org | Prometheus |
| alertmanager.mmrajputhomelab.org | Alertmanager |
