# Git Conventional Commit Types Reference

## Core Types

| Type | When to Use | Example |
|------|-------------|---------|
| `feat` | New feature or capability | `feat(argocd): add prometheus application` |
| `fix` | Bug fix or error correction | `fix(ingress): resolve TLS certificate validation` |
| `docs` | Documentation only changes | `docs(adr): add ADR-009 storage strategy` |
| `style` | Formatting, whitespace, semicolons (no code change) | `style(ansible): fix yaml indentation` |
| `refactor` | Code restructuring without behavior change | `refactor(scripts): simplify backup logic` |
| `perf` | Performance improvement | `perf(prometheus): optimize scrape intervals` |
| `test` | Adding or updating tests | `test(cluster): add node health verification` |
| `chore` | Maintenance, dependencies, tooling | `chore(deps): update helm to v3.16.4` |
| `ci` | CI/CD pipeline changes | `ci(github): add workflow for manifest validation` |
| `build` | Build system or external dependencies | `build(docker): update base image to ubuntu:24.04` |
| `revert` | Reverting a previous commit | `revert: feat(argocd): add prometheus application` |

## Platform Engineering Specific

| Type | Scope Examples | Use Case |
|------|----------------|----------|
| `feat` | `argocd`, `prometheus`, `ingress` | New platform service or capability |
| `fix` | `calico`, `storage`, `dns` | Infrastructure bug fixes |
| `config` | `k8s`, `helm`, `ansible` | Configuration changes |
| `security` | `rbac`, `network-policy`, `tls` | Security-related changes |
| `infra` | `proxmox`, `vm`, `cluster` | Infrastructure provisioning |

## Scope Examples for Homelab

| Scope | Description |
|-------|-------------|
| `adr` | Architecture Decision Records |
| `ansible` | Ansible playbooks and inventory |
| `argocd` | ArgoCD configuration |
| `calico` | CNI and network policies |
| `cluster` | Cluster-wide changes |
| `devcontainer` | Development environment |
| `docs` | General documentation |
| `grafana` | Grafana dashboards and config |
| `helm` | Helm charts and values |
| `ingress` | Ingress controller configuration |
| `k8s` | Kubernetes manifests |
| `loki` | Log aggregation |
| `prometheus` | Metrics and alerting |
| `proxmox` | VM and hypervisor scripts |
| `repo` | Repository-level changes |
| `storage` | Storage provisioner configuration |

## Decision Guide

```
Is it a new capability?
  └─ Yes → feat

Is it fixing broken behavior?
  └─ Yes → fix

Is it only documentation?
  └─ Yes → docs

Is it only formatting (no content change)?
  └─ Yes → style

Is it restructuring without behavior change?
  └─ Yes → refactor

Is it updating dependencies or tooling?
  └─ Yes → chore

Is it CI/CD pipeline related?
  └─ Yes → ci

Is it improving performance?
  └─ Yes → perf
```

## Examples by Scenario

### Adding New Components
```
feat(prometheus): deploy kube-prometheus-stack
feat(argocd): add grafana application
feat(ingress): configure TLS termination
```

### Fixing Issues
```
fix(calico): resolve pod network connectivity
fix(storage): correct PVC access mode
fix(ansible): fix inventory host grouping
```

### Documentation Updates
```
docs(adr): add ADR-007 ingress strategy
docs(readme): update architecture diagram
docs(runbook): add disaster recovery procedure
```

### Configuration Changes
```
config(prometheus): increase retention to 30d
config(argocd): enable auto-sync for platform apps
config(ingress): add rate limiting annotations
```

### Maintenance Tasks
```
chore(deps): update kubectl to v1.31.5
chore(cleanup): remove unused helm charts
chore(repo): update .gitignore patterns
```

### Refactoring
```
refactor(ansible): split playbook into roles
refactor(repo): rename kubernetes-homelab-01 to kubernetes-homelab
refactor(platform): reorganize directory structure
```

## Breaking Changes

Add `!` after type/scope for breaking changes:

```
feat(storage)!: migrate from local-path to longhorn
refactor(argocd)!: restructure app-of-apps hierarchy
```

## Multi-line Commit Format

```
<type>(<scope>): <subject>
                                        ← blank line
<body - explain why, not what>
                                        ← blank line
<footer - references, breaking changes>
```

**Example:**
```
feat(observability): deploy kube-prometheus-stack

Implement full observability stack for cluster monitoring.
Includes Prometheus, Grafana, and Alertmanager.

- 15-day metric retention
- Pre-configured dashboards for node and pod metrics
- ServiceMonitors for platform components

Refs: Phase-6
```
