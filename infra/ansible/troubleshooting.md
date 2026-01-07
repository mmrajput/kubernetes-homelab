## Troubleshooting

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