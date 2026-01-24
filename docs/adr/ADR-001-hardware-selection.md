# ADR-001: Hardware Platform Selection

## Status

Accepted

## Date

2025-12-10

## Context

Need a platform to run a multi-node Kubernetes cluster for hands-on learning. Requirements: sufficient resources for 3+ VMs, persistent availability, and reasonable cost.

## Decision

Use a **Mini PC** (Beelink SER5 Pro: AMD Ryzen 5 5500U, 32GB RAM, 500GB NVMe).

## Rationale

| Criteria | Mini PC | Raspberry Pi Cluster | Cloud (AWS/Azure) |
|----------|---------|---------------------|-------------------|
| Upfront cost | €350 one-time | ~€400 for 3-node | €0 |
| Monthly cost | ~€15 electricity | ~€5 electricity | €100-200+ |
| Resources | 32GB RAM, 6 cores | 8GB RAM per node | Unlimited (pay more) |
| Availability | 24/7 local | 24/7 local | 24/7 |
| Network latency | <1ms | <1ms | 20-100ms |
| Learning value | Bare-metal + virtualization | ARM architecture | Cloud-native only |
| Portability | Physical access needed | Physical access needed | Anywhere |

**Key factors:**

1. **Cost over 12 months**: Mini PC wins (€350 + €180 electricity = €530) vs Cloud (~€1,800/year)
2. **Resource density**: Single Mini PC with Proxmox provides more flexibility than dedicated Pi nodes
3. **x86 architecture**: Matches production environments (no ARM compatibility issues)

## Consequences

### Positive
- Predictable fixed cost after initial investment
- Full control over hardware and network
- Learn virtualization layer (Proxmox) in addition to Kubernetes

### Negative
- Physical hardware dependency (power outages, hardware failure)
- No multi-region or HA capabilities
- Initial capital expenditure required

## Alternatives Considered

**Raspberry Pi Cluster**: Rejected due to ARM architecture limitations and lower per-node resources.

**Cloud VMs**: Rejected due to ongoing costs and wanting to learn the full infrastructure stack including virtualization.

## References

- [Beelink SER5 Pro Specifications](https://www.bee-link.com/products/beelink-ser5-pro)
