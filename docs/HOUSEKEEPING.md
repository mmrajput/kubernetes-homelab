# Homelab Housekeeping Guide

**Purpose:** Maintenance tasks to keep the homelab healthy and organized  
**Last Updated:** 2026-01-12  

---

## Quick Reference

| Task | Frequency | Time | Script |
|------|-----------|------|--------|
| DevContainer cleanup | Weekly | 2 min | `scripts/helpers/cleanup-devcontainer.sh` |
| Verify tools | After rebuild | 1 min | `scripts/verify-tools.sh` |
| Check cluster health | Daily | 30 sec | `kubectl get nodes` |
| Update documentation | After changes | 5 min | Manual |
| Git commit progress | End of session | 2 min | Manual |

---

## Weekly Tasks (Every Sunday)

### 1. DevContainer Cleanup (2 minutes)

**Why:** Remove old Docker images, free disk space  
**When:** Every Sunday evening  

```bash
# Run cleanup script
./scripts/helpers/cleanup-devcontainer.sh

# Expected: 2-6GB freed
```

**What it does:**
- Keeps last 2 DevContainer images
- Removes stopped containers
- Cleans build cache
- Verifies Ubuntu base image

**Success criteria:**
- ✅ Script completes without errors
- ✅ 2+ DevContainer images remain
- ✅ Ubuntu 24.04 base present

---

### 2. Cluster Health Check (30 seconds)

**Why:** Ensure all nodes and critical pods are healthy  

```bash
# Enter DevContainer
./scripts/dev-shell.sh

# Check nodes
kubectl get nodes

# Check system pods
kubectl get pods -A | grep -v Running

# Check resource usage
kubectl top nodes
```

**Success criteria:**
- ✅ All nodes STATUS=Ready
- ✅ No pods in CrashLoopBackOff
- ✅ No nodes with high resource usage (>80%)

**If issues found:** Document in `docs/TROUBLESHOOTING.md` (create if needed)

---

### 3. Git Commit Weekly Progress (5 minutes)

**Why:** Track progress, enable rollback if needed  

```bash
# Check what changed
git status

# Add changes
git add .

# Commit with meaningful message
git commit -m "Phase X: [Brief description]

- Completed: [task 1]
- Completed: [task 2]
- Next: [upcoming task]
"

# Push to remote
git push
```

**Commit message format:**
```
Phase X: [One-line summary]

[Detailed changes]
- Key accomplishment 1
- Key accomplishment 2

Next steps:
- Upcoming task

Related: [Link to ADR if applicable]
```

---

## Monthly Tasks (First Sunday of Month)

### 1. Update Tool Versions (15 minutes)

**Why:** Keep tools current, apply security patches  
**When:** First Sunday of each month  

```bash
# Check for updates (inside DevContainer)
kubectl version --client  # Compare to latest
helm version              # Compare to latest
k9s version              # Compare to latest

# If updates available:
# 1. Update .devcontainer/Dockerfile versions
# 2. Rebuild: devcontainer build --workspace-folder . --no-cache
# 3. Test: ./scripts/verify-tools.sh
# 4. Document in CHANGELOG.md
```

**Version sources:**
- kubectl: https://kubernetes.io/releases/
- helm: https://github.com/helm/helm/releases
- k9s: https://github.com/derailed/k9s/releases

---

### 2. Review and Update Documentation (30 minutes)

**Why:** Keep docs accurate, add learnings  

**Check these files:**
- [ ] `README.md` - Still accurate?
- [ ] `docs/devcontainer.md` - Any new tips?
- [ ] `docs/adr/ADR-*.md` - Need updates?
- [ ] `HOUSEKEEPING.md` - New tasks to add?

**Add to docs:**
- New troubleshooting tips discovered
- Workflow improvements
- Common mistakes to avoid

---

### 3. Backup Critical Configurations (10 minutes)

**Why:** Disaster recovery, easy cluster rebuild  

```bash
# Backup kubeconfig
cp ~/.kube/config ~/backups/kubeconfig-$(date +%Y%m%d).yaml

# Backup important cluster resources (when deployed)
kubectl get all -A -o yaml > ~/backups/cluster-state-$(date +%Y%m%d).yaml

# Store in external location (Google Drive, GitHub private repo, etc.)
```

**Important:** Never commit kubeconfig to public repos!

---

## After Each Phase Completion

### 1. Update Phase Documentation (15 minutes)

**Create/update:**
- `docs/PHASE-X-[NAME].md` - What was accomplished
- `docs/ADR-XXX-[DECISION].md` - Key architectural decisions
- `README.md` - Update "Current Phase" section

**Template for PHASE-X.md:**
```markdown
# Phase X: [Phase Name]

**Status:** Complete  
**Duration:** [Start date] - [End date]  
**Effort:** [Estimated hours]

## Objectives
- [ ] Objective 1
- [ ] Objective 2

## What Was Built
- Component 1: [Description]
- Component 2: [Description]

## Key Decisions
- Decision 1 (See ADR-XXX)
- Decision 2 (See ADR-XXX)

## Challenges & Solutions
- Challenge: [Description]
  Solution: [How it was solved]

## Testing & Verification
- [ ] Test 1
- [ ] Test 2

## Next Phase
Phase X+1: [Name and objectives]
```

---

### 2. Git Tag Phase Completion (2 minutes)

**Why:** Mark milestones, easy rollback points  

```bash
# Tag the phase completion
git tag -a phase-3-devcontainer -m "Phase 3: DevContainer Setup Complete

- DevContainer with 18 tools
- Environment variables for portability
- Custom colorful prompt
- Comprehensive documentation
"

# Push tag
git push origin phase-3-devcontainer
```

---

### 3. Update Housekeeping Tasks (5 minutes)

**Review this file and add:**
- New maintenance tasks discovered
- New helper scripts created
- Updated frequencies based on experience

**Example additions:**
```markdown
### 4. ArgoCD Sync Check (New in Phase 4)
kubectl get applications -n argocd
```

---

## Quarterly Tasks (Every 3 Months)

### 1. Major Dependency Updates (1-2 hours)

**Why:** Stay current with major versions  

- Review Kubernetes version (cluster + kubectl)
- Review DevContainer base image (Ubuntu LTS)
- Consider migration paths for breaking changes

### 2. Documentation Audit (1 hour)

- Read through ALL docs as if you're a new team member
- Fix outdated information
- Add missing details
- Improve clarity

### 3. Backup Testing (30 minutes)

- Test cluster restore from backup
- Verify backup procedures still work
- Update backup documentation

---

## Emergency Tasks (As Needed)

### DevContainer Rebuild Failed

```bash
# 1. Check error message
# 2. Clear all Docker cache
docker system prune -a -f

# 3. Rebuild from scratch
devcontainer build --workspace-folder . --no-cache

# 4. If still fails, check:
# - Dockerfile syntax
# - Network connectivity
# - .devcontainer/config/ files exist
```

### Cluster Node Down

```bash
# 1. SSH to node
ssh mahmood@node-ip

# 2. Check system health
systemctl status kubelet
systemctl status containerd

# 3. Check logs
journalctl -u kubelet -f

# 4. Document issue in TROUBLESHOOTING.md
```

### Out of Disk Space

```bash
# 1. Check usage
df -h

# 2. Run aggressive cleanup
docker system prune -a -f --volumes
sudo apt autoremove

# 3. Identify large files
du -h --max-depth=1 / | sort -hr | head -20
```

---

## Scripts Reference

### Helper Scripts

Located in `scripts/helpers/`:

| Script | Purpose | Frequency |
|--------|---------|-----------|
| `cleanup-devcontainer.sh` | Clean Docker images/containers | Weekly |
| `backup-cluster.sh` | Backup cluster state | Monthly |
| `update-tools.sh` | Update DevContainer tools | Monthly |

### Workflow Scripts

Located in `scripts/`:

| Script | Purpose | Frequency |
|--------|---------|-----------|
| `dev-shell.sh` | Enter DevContainer | Daily |
| `verify-tools.sh` | Verify tool installations | After rebuild |

---

## Maintenance Log

Keep a simple log of maintenance performed:

### 2025-01-12 (Phase 3 Complete)
- ✅ DevContainer setup complete
- ✅ All 18 tools verified
- ✅ Documentation updated
- ✅ Git committed and pushed

### [Date] (Phase 4 In Progress)
- ⏳ ArgoCD installation started
- 

---

## Tips & Best Practices

### Git Workflow
- Commit after each significant milestone
- Use meaningful commit messages
- Tag phase completions
- Push regularly (don't lose work!)

### Documentation
- Update docs as you go (not at the end)
- Include "why" not just "what"
- Add troubleshooting tips when you solve issues
- Keep examples concrete and working

### DevContainer
- Rebuild weekly to catch issues early
- Test verification script after rebuilds
- Keep .env file backed up separately
- Document any manual tweaks in ADRs

### Cluster Management
- Check cluster health before starting work
- Monitor resource usage trends
- Keep notes on performance issues
- Regular backups before major changes

---

## Checklist Templates

### Weekly Checklist

```
Date: ________

DevContainer:
[ ] Run cleanup script
[ ] Verify 2+ images remain
[ ] Ubuntu base present

Cluster:
[ ] All nodes Ready
[ ] No failing pods
[ ] Resource usage normal

Git:
[ ] Changes committed
[ ] Meaningful commit message
[ ] Pushed to remote

Notes:
_______________________________
_______________________________
```

### Monthly Checklist

```
Date: ________

Updates:
[ ] Check tool versions
[ ] Review security advisories
[ ] Update if needed

Documentation:
[ ] README accurate
[ ] ADRs up to date
[ ] New learnings documented

Backups:
[ ] Kubeconfig backed up
[ ] Cluster state exported
[ ] Stored externally

Review:
[ ] Last month's progress
[ ] Next month's goals
[ ] Adjust housekeeping tasks
```

---

## Future Additions

As the project grows, add tasks for:

- [ ] ArgoCD sync health checks (Phase 4)
- [ ] Prometheus alert review (Phase 5)
- [ ] Grafana dashboard updates (Phase 5)
- [ ] Longhorn volume health (Phase 6)
- [ ] Velero backup verification (Phase 7)
- [ ] Certificate expiration checks (Phase 8)

---

**Remember:** Consistency beats intensity. 10 minutes weekly is better than 2 hours quarterly!

**Questions or improvements?** Update this file and commit!
