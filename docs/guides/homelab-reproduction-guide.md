# Homelab Reproduction Guide

A step-by-step guide to reproduce this Kubernetes homelab from scratch on equivalent hardware.

**Estimated time:** 4–6 hours (mostly waiting for downloads and ArgoCD sync)
**Target platform:** Single mini PC (AMD Ryzen, 32GB RAM, 500GB NVMe) running Proxmox VE

---

## Prerequisites

### Hardware

Any x86-64 machine with:
- 32GB+ RAM (minimum for running 3 VMs with the full stack)
- 500GB+ NVMe SSD
- Gigabit Ethernet
- BIOS with VT-x/VT-d enabled

This repo was built on a **Beelink SER5 Pro** (AMD Ryzen 5 5500U, 32GB DDR4, 500GB NVMe). See [ADR-001](../adr/ADR-001-hardware-selection.md).

### Accounts and Services Required

| Service | Purpose | Notes |
|---------|---------|-------|
| [Cloudflare](https://cloudflare.com) | DNS + Tunnel | Free tier sufficient |
| [GitHub](https://github.com) | Git repository | Fork this repo |
| [OneDrive](https://onedrive.live.com) | Offsite backup destination | Free 5GB sufficient for homelab |
| [Let's Encrypt](https://letsencrypt.org) | TLS certificates | Automatic via cert-manager |

### Domain Name

You need a domain managed by Cloudflare. This repo uses `mmrajputhomelab.org`. Replace it with your own domain throughout.

### Your Workstation

- Git
- VS Code with Dev Containers extension (recommended) or Docker + devcontainer CLI
- SSH access to the Proxmox host

---

## Phase 0 — Prepare Accounts

### 0.1 — Fork the repository

Fork `https://github.com/mmrajput/kubernetes-homelab-01` to your GitHub account. Update all references from `mmrajput/kubernetes-homelab-01` to your fork.

### 0.2 — Add domain to Cloudflare

Add your domain to Cloudflare and point nameservers. Wait for DNS propagation (up to 24 hours).

### 0.3 — Create a Cloudflare API token

In Cloudflare Dashboard → My Profile → API Tokens → Create Token:
- **Template:** Edit zone DNS
- **Zone Resources:** Your domain
- Save the token — you'll use it in Phase 3.

### 0.4 — Create a Cloudflare Tunnel

In Cloudflare Dashboard → Zero Trust → Access → Tunnels → Create a tunnel:
- Name: `homelab`
- Install connector: choose Docker (you'll deploy it in Kubernetes later)
- Save the tunnel token — you'll use it in Phase 3.

### 0.5 — Create a GitHub App for ARC runners

In GitHub → Settings → Developer settings → GitHub Apps → New GitHub App:
- Name: `homelab-arc`
- Homepage URL: your GitHub profile
- Permissions: Repository (read), Actions (read/write), Metadata (read)
- Install on your repositories
- Save App ID, private key, and installation ID — you'll use them when configuring Vault.

### 0.6 — Create a GitHub Personal Access Token (for ArgoCD)

In GitHub → Settings → Developer settings → Personal access tokens → Fine-grained:
- Permissions: Read access to your forked repository
- Save the token for ArgoCD repository configuration.

---

## Phase 1 — Install Proxmox VE

Install Proxmox VE on your hardware:

1. Download [Proxmox VE ISO](https://www.proxmox.com/en/downloads)
2. Flash to USB with Rufus or Balena Etcher
3. Boot from USB and complete the installer
   - Static IP: `192.168.178.33` (or your preferred IP)
   - FQDN: `proxmox.homelab.local`
4. After install, remove subscription nag (optional):
   ```bash
   sed -i.bak "s/NotFound/Active/g" /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js
   systemctl restart pveproxy
   ```

Full guide: [`docs/guides/proxmox-installation.md`](proxmox-installation.md)

---

## Phase 2 — Provision Kubernetes VMs

Start the devcontainer — all subsequent commands run inside it:

```bash
# On your workstation
git clone https://github.com/<your-fork>/kubernetes-homelab-01
cd kubernetes-homelab-01
# Open in VS Code and "Reopen in Container"
# Or: ./scripts/dev-shell.sh
```

### 2.1 — Create the Ubuntu VM template

```bash
cd infra/proxmox/vm-templates
./create-template.sh
```

This downloads Ubuntu 24.04 cloud image, configures cloud-init, and creates a Proxmox VM template.

### 2.2 — Provision the 3 VMs

```bash
./create-k8s-controlplane.sh   # k8s-cp-01 at 192.168.178.34
./create-k8s-workers.sh        # k8s-worker-01, k8s-worker-02
```

Verify the VMs are running and SSH-accessible:

```bash
ssh ubuntu@192.168.178.34 "hostname"
ssh ubuntu@192.168.178.35 "hostname"
ssh ubuntu@192.168.178.36 "hostname"
```

### 2.3 — Install Kubernetes with Ansible

```bash
cd infra/ansible
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml
```

This installs containerd, kubeadm, Calico CNI, and joins all worker nodes. Takes ~10 minutes.

Verify:

```bash
kubectl get nodes
# NAME              STATUS   ROLES           AGE
# k8s-cp-01         Ready    control-plane   Xm
# k8s-worker-01     Ready    <none>          Xm
# k8s-worker-02     Ready    <none>          Xm
```

Full Ansible reference: [`infra/ansible/README.md`](../../infra/ansible/README.md)

---

## Phase 3 — Bootstrap the Cluster

These steps run once per cluster lifetime. They create the foundation that ArgoCD will build on.

### 3.1 — Apply namespace manifests

```bash
kubectl apply -f bootstrap/namespaces/
```

> **Why manual:** ArgoCD v3.2.3 has a bug when syncing Namespace resources. Namespaces are always managed via bootstrap, never via ArgoCD.

### 3.2 — Install ArgoCD

```bash
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/v3.2.3/manifests/install.yaml

kubectl wait --for=condition=available deployment/argocd-server \
  -n argocd --timeout=120s
```

### 3.3 — Apply bootstrap secrets (not in Git)

These secrets cannot come from ESO — they bootstrap the chain.

```bash
# cert-manager: Cloudflare API token for DNS-01 TLS challenges
kubectl create secret generic cloudflare-api-token \
  --from-literal=api-token=<YOUR_CLOUDFLARE_API_TOKEN> \
  -n cert-manager

# cloudflared: Cloudflare Tunnel token
kubectl create secret generic cloudflare-tunnel-token \
  --from-literal=token=<YOUR_TUNNEL_TOKEN> \
  -n cloudflare
```

### 3.4 — Bootstrap Vault

Vault starts sealed and uninitialised. After ArgoCD syncs the Vault application (Step 3.5 will trigger this), initialise it:

```bash
# Wait for Vault pod to be running (ArgoCD will deploy it)
kubectl wait --for=condition=ready pod/vault-0 -n vault --timeout=300s

# Initialise (saves keys to vault-init.json — KEEP THIS FILE SAFE, NEVER COMMIT)
kubectl exec -n vault vault-0 -- vault operator init \
  -key-shares=3 -key-threshold=2 \
  -format=json > vault-init.json

# Unseal (run twice with different keys from vault-init.json)
kubectl exec -it -n vault vault-0 -- vault operator unseal <key-1>
kubectl exec -it -n vault vault-0 -- vault operator unseal <key-2>

# Login with root token from vault-init.json
kubectl exec -it -n vault vault-0 -- vault login <root-token>
```

### 3.5 — Configure Vault

Enable the KV v2 secrets engine and Kubernetes auth:

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh

# Inside Vault shell:
vault secrets enable -path=secret kv-v2

vault auth enable kubernetes
vault write auth/kubernetes/config \
  kubernetes_host="https://10.96.0.1:443"

# Create ESO policy
vault policy write external-secrets - <<EOF
path "secret/data/*" { capabilities = ["read"] }
path "secret/metadata/*" { capabilities = ["read", "list"] }
EOF

# Bind the ESO ServiceAccount to the policy
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=external-secrets \
  ttl=1h

exit
```

### 3.6 — Populate Vault secrets

Create all required secrets in Vault before ArgoCD syncs dependent applications. Follow the secret path conventions documented in [`docs/reference/data-layer.md`](../reference/data-layer.md).

```bash
kubectl exec -it -n vault vault-0 -- /bin/sh

vault login <root-token>

# ArgoCD OIDC (Keycloak client secret)
vault kv put secret/argocd/oidc clientSecret="<value>"

# Grafana OIDC
vault kv put secret/grafana/oidc clientSecret="<value>"

# Keycloak
vault kv put secret/keycloak/admin adminPassword="<value>"
vault kv put secret/databases/keycloak username="keycloak" password="<value>"

# Nextcloud
vault kv put secret/databases/nextcloud username="nextcloud" password="<value>"
vault kv put secret/nextcloud/admin username="admin" password="<value>"

# MinIO credentials (use values matching your MinIO deployment)
vault kv put secret/minio/cnpg access-key="<value>" secret-key="<value>"
vault kv put secret/minio/loki accessKey="<value>" secretKey="<value>"
vault kv put secret/minio/velero access_key="<value>" secret_key="<value>"
vault kv put secret/minio/rclone access_key_id="<value>" secret_access_key="<value>"

# rclone OneDrive (see: https://rclone.org/onedrive/ for token generation)
vault kv put secret/operators/rclone-onedrive token="<rclone_oauth_token_json>"

exit
```

> **Key format matters:** CNPG initdb secrets require exactly `username` and `password`. ESO key names must match what the consuming application expects. Refer to [`docs/reference/data-layer.md`](../reference/data-layer.md) for the exact key names per secret.

### 3.7 — Update repository references

Before applying the root-app, update the repository URL in ArgoCD application manifests to point to your fork:

```bash
# Replace all occurrences of the original repo URL with your fork
grep -r "mmrajput/kubernetes-homelab-01" platform/ --include="*.yaml" -l
# Edit each file to use your fork's URL
```

### 3.8 — Bootstrap GitOps with root-app

```bash
kubectl apply -f platform/argocd/root-app.yaml
```

This single command bootstraps the entire platform. ArgoCD discovers all child apps from `platform/argocd/apps/` and begins syncing.

Monitor progress:

```bash
kubectl get applications -n argocd -w
# Allow 10–20 minutes for all apps to sync
# Some apps will wait for others (e.g., ESO waits for Vault, CNPG clusters wait for ESO)
```

---

## Phase 4 — Verify the Platform

### 4.1 — All applications healthy

```bash
kubectl get applications -n argocd
# All apps must show: SYNC STATUS = Synced, HEALTH STATUS = Healthy
```

### 4.2 — TLS certificate issued

```bash
kubectl get certificate -n ingress-nginx
# wildcard-homelab-tls must show READY = True
# Takes 2–5 minutes for DNS-01 challenge
```

### 4.3 — External access working

```bash
curl -I https://argocd.<your-domain>
curl -I https://grafana.<your-domain>
curl -I https://prometheus.<your-domain>
# Expected: HTTP 200 or 302 (no 5xx)
```

### 4.4 — Secrets synced

```bash
kubectl get externalsecret -A
# All must show STATUS = SecretSynced
```

### 4.5 — CNPG clusters healthy

```bash
kubectl get cluster -n databases
# All clusters must show STATUS = Cluster in healthy state
```

### 4.6 — Backups active

```bash
velero schedule get
# nightly-full and nextcloud-files must be present

kubectl get backupstoragelocation -n velero
# Phase must be: Available
```

### 4.7 — Observability working

```bash
# Check Prometheus targets (30+ should be UP)
kubectl port-forward -n monitoring svc/prometheus-operated 9090:9090 &
curl -s 'http://localhost:9090/api/v1/targets' | jq '[.data.activeTargets[] | select(.health=="up")] | length'
pkill -f "port-forward.*9090"
```

---

## Phase 5 — Onboard a Workload

The platform is now fully operational. To deploy a workload (e.g., a new application):

1. Follow [`docs/reference/workload-onboarding.md`](../reference/workload-onboarding.md)
2. Create Vault secrets for the application
3. Commit the onboarding files atomically to a feature branch and open a PR
4. After merge, ArgoCD auto-deploys within 120 seconds

---

## Adapting to Your Environment

| This repo | Your setup | Where to change |
|-----------|-----------|-----------------|
| `mmrajputhomelab.org` | your domain | All Ingress hostnames, cert-manager ClusterIssuer |
| `192.168.178.34–36` | your node IPs | Ansible inventory, NetworkPolicies, kubeadm config |
| `192.168.178.33` | your Proxmox IP | Proxmox scripts |
| `mmrajput/kubernetes-homelab-01` | your fork | ArgoCD app repoURL fields |
| `github.com/mmrajput` | your GitHub | ARC GitHub App, workflow files |

---

## Related Documentation

- [Cluster Rebuild Runbook](../runbooks/cluster-rebuild.md) — abbreviated rebuild steps for an existing setup
- [Workload Onboarding](../reference/workload-onboarding.md) — adding new applications
- [Platform Inventory](../reference/platform-inventory.md) — all service endpoints
- [Disaster Recovery](../runbooks/disaster-recovery.md) — restore from backups
- [Vault Operations](../runbooks/vault-operations.md) — Vault day-2 operations
