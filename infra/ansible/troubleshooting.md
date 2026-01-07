## Troubleshooting

**Quick diagnostic commands:**

```bash
# Check playbook syntax
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml --syntax-check

# Run in verbose mode
ansible-playbook -i inventory.ini playbooks/install-kubernetes.yml -v
# Use -vv or -vvv for more detail

# Check specific host facts
ansible -i inventory.ini k8s-cp-01 -m setup

# Test sudo access
ansible -i inventory.ini all -m shell -a "sudo whoami"
```

**Common issues:**

| Issue | Cause | Fix |
|-------|-------|-----|
| `unreachable` error | SSH connectivity | Check SSH keys, test manual SSH |
| `timeout` on tasks | Slow network/mirrors | Use `-vv` to see which task hangs |
| `kubelet not starting` | Swap still enabled | Check `/etc/fstab`, reboot nodes |
| `Calico pods pending` | Wrong pod CIDR | Verify CIDR matches in playbook + manifest |
| `Workers not joining` | Token expired | Generate new token on control plane |

### Playbook fails on containerd configuration
**Issue:** containerd service won't start after config modification

**Solution:**
```bash
# Check containerd logs
sudo journalctl -u containerd -xe

# Regenerate config
sudo rm /etc/containerd/config.toml
sudo containerd config default > /etc/containerd/config.toml
sudo systemctl restart containerd
```

### Worker nodes fail to join
**Issue:** Token expired (24-hour default)

**Solution:**
```bash
# On control plane, generate new join command
sudo kubeadm token create --print-join-command

# Copy output and run on worker nodes
sudo <paste-join-command-here>
```

### Calico pods stuck in Pending
**Issue:** Pod network CIDR mismatch

**Solution:**
```bash
# Verify CIDR in Calico manifest matches group_vars
kubectl get cm -n kube-system calico-config -o yaml | grep IPV4POOL

# If mismatch, reapply with correct CIDR
kubectl delete -f /tmp/calico.yaml
# Edit calico.yaml CIDR, then:
kubectl apply -f /tmp/calico.yaml
```