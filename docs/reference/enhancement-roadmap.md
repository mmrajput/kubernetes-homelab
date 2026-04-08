# Enhancement Roadmap

Ideas ordered roughly by value vs. effort.

## Security hardening
- **Falco** — runtime threat detection (syscall-level); integrates with Grafana/Loki
- **Trivy Operator** — continuous in-cluster vulnerability scanning; Grafana dashboard exists
- **OPA Gatekeeper or Kyverno** — admission policies: enforce labels, deny latest tags, require resource limits
- **SOPS / age-encrypted secrets in Git** — replace plain ExternalSecret YAML with encrypted versions
- **CIS Benchmark scan** — run `kube-bench` periodically via CronJob; surface results in Grafana
- **Pod Security Standards audit** — tighten remaining namespaces from baseline → restricted

## Observability
- **Alertmanager rules** — PrometheusRule objects: PVC > 80%, pod crash loops, node memory pressure
- **Grafana SLO dashboard** — uptime, latency p95, error rate for Nextcloud
- **Loki alerts** — LogQL-based alerts forwarded to Alertmanager
- **Distributed tracing** — Tempo + OpenTelemetry
- **Uptime Kuma** — lightweight external uptime monitor for all ingress endpoints

## GitOps & CI/CD
- **ArgoCD Image Updater** — watch ghcr.io; removes manual workflow trigger
- **Renovate Bot** — automated Helm chart version PRs
- **Staging gate in CI** — smoke tests against staging before promoting to production
- **Multi-environment promotion workflow** — required manual approval in GitHub Actions

## Platform resilience
- **CNPG read replicas in staging** — promote nextcloud-db to 2 instances
- **Longhorn recurring snapshots** — scheduled snapshot policy per PVC
- **Velero restore drills** — CronJob that restores staging from latest backup weekly
- **MinIO multi-drive / erasure coding** — distributed mode for redundancy

## New workloads
- **WikiJS or Outline** — internal knowledge base
- **Vaultwarden** — self-hosted Bitwarden-compatible password manager
- **Forgejo** — self-hosted Git mirror
- **Matrix / Element** — self-hosted team chat; OIDC via Keycloak already available
- **Immich** — self-hosted photo management

## Infrastructure
- **Second physical node / Proxmox cluster** — HA Proxmox + production/staging physical isolation
- **Cluster API (CAPI)** — declarative cluster lifecycle; replace manual Ansible provisioning
- **External DNS** — automate Cloudflare DNS from Ingress annotations
- **Cert-manager internal CA** — TLS for service-to-service communication
- **Network topology upgrade** — dedicated VLAN for cluster nodes
