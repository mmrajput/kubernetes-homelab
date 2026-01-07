# Phase 3 Troubleshooting Guide

This document covers common issues you'll encounter during Kubernetes installation and how to fix them. These scenarios frequently appear on the CKA exam.

---

## Pre-Installation Issues

### Issue 1: Swap Not Disabled

**Symptom:**
```
kubelet fails to start with error: "failed to run Kubelet: running with swap on is not supported"
```

**Root Cause:**
Kubelet requires swap to be disabled for deterministic memory allocation.

**Solution:**
```bash
# Immediate disable
sudo swapoff -a

# Permanent disable
sudo sed -i '/ swap / s/^/#/' /etc/fstab

# Verify
swapon --show  # Should return empty
```

**CKA Exam Tip:** Always check swap status first when kubelet fails.

---

### Issue 2: Kernel Modules Not Loaded

**Symptom:**
```
kubeadm init fails with: "br_netfilter module is not loaded"
```

**Root Cause:**
Container networking requires specific kernel modules.

**Solution:**
```bash
# Load modules immediately
sudo modprobe overlay
sudo modprobe br_netfilter

# Verify
lsmod | grep -E 'overlay|br_netfilter'

# Persist across reboots
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
```

**CKA Exam Tip:** Know the two critical modules: `overlay` and `br_netfilter`.

---

### Issue 3: IP Forwarding Disabled

**Symptom:**
Pods cannot reach each other across nodes.

**Root Cause:**
IP forwarding not enabled in sysctl.

**Solution:**
```bash
# Check current setting
sysctl net.ipv4.ip_forward
# Should return: net.ipv4.ip_forward = 1

# Enable if disabled
sudo sysctl -w net.ipv4.ip_forward=1

# Persist
echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.d/k8s.conf
sudo sysctl -p /etc/sysctl.d/k8s.conf
```

---

## Control Plane Issues

### Issue 4: kubeadm init Hangs at "Waiting for kubelet"

**Symptom:**
```
[wait-control-plane] Waiting for the kubelet to boot up the control plane...
[timeout after 4m0s]
```

**Root Cause:**
Usually containerd misconfiguration (cgroup driver mismatch).

**Diagnosis:**
```bash
# Check kubelet logs
sudo journalctl -xeu kubelet | tail -50

# Look for: "failed to run Kubelet: validate service connection: CRI v1 runtime API is not implemented"
```

**Solution:**
```bash
# Fix containerd config
sudo containerd config default | sudo tee /etc/containerd/config.toml

# Edit config.toml, find this line:
#   SystemdCgroup = false
# Change to:
#   SystemdCgroup = true

# Restart containerd
sudo systemctl restart containerd

# Reset kubeadm and retry
sudo kubeadm reset -f
sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=192.168.178.34
```

**CKA Exam Tip:** Know how to check and fix containerd cgroup driver.

---

### Issue 5: Control Plane Pods in CrashLoopBackOff

**Symptom:**
```bash
kubectl get pods -n kube-system
# Shows: kube-apiserver-k8s-cp-01   0/1   CrashLoopBackOff
```

**Diagnosis:**
```bash
# Check static pod manifest
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml

# Check pod logs (if API server is up)
kubectl logs -n kube-system kube-apiserver-k8s-cp-01

# Check kubelet logs
sudo journalctl -xeu kubelet | grep apiserver

# Check for certificate issues
sudo ls -la /etc/kubernetes/pki/
```

**Common Causes:**
1. **Invalid manifest YAML** → Fix syntax in `/etc/kubernetes/manifests/`
2. **Certificate expiry** → Regenerate with `kubeadm certs renew all`
3. **Port conflict** → Check if 6443 is already in use

**Solution Example (Port Conflict):**
```bash
# Check what's using port 6443
sudo netstat -tulpn | grep 6443

# If something else is using it, stop that service or change API server port
```

**CKA Exam Tip:** Remember, control plane pods are **static pods** managed by kubelet, not the API server.

---

### Issue 6: Cannot Access API Server

**Symptom:**
```bash
kubectl get nodes
# Error: The connection to the server localhost:8080 was refused
```

**Root Cause:**
Kubeconfig not set up correctly.

**Solution:**
```bash
# Check if kubeconfig exists
ls -la ~/.kube/config

# If missing, copy from control plane
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Or set KUBECONFIG environment variable
export KUBECONFIG=/etc/kubernetes/admin.conf

# Verify
kubectl cluster-info
```

**CKA Exam Tip:** Know the default kubeconfig locations:
- `/etc/kubernetes/admin.conf` (root)
- `~/.kube/config` (non-root user)

---

## CNI / Networking Issues

### Issue 7: CoreDNS Pods Stuck in Pending

**Symptom:**
```bash
kubectl get pods -n kube-system
# Shows: coredns-xxx   0/1   Pending
```

**Root Cause:**
CNI not installed yet - pods can't get IP addresses.

**Solution:**
```bash
# Install Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Wait for Calico pods to be ready
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s

# Check CoreDNS again
kubectl get pods -n kube-system
```

**CKA Exam Tip:** Without CNI, only pods using `hostNetwork: true` can run.

---

### Issue 8: Calico Pods CrashLoopBackOff

**Symptom:**
```bash
kubectl get pods -n kube-system | grep calico
# Shows: calico-node-xxx   0/1   CrashLoopBackOff
```

**Diagnosis:**
```bash
# Check Calico pod logs
kubectl logs -n kube-system -l k8s-app=calico-node

# Common errors to look for:
# - "failed to create veth pair"
# - "CIDR mismatch"
# - "IP pool already exists"
```

**Solution (CIDR Mismatch):**
```bash
# Delete Calico
kubectl delete -f calico.yaml

# Download manifest
curl -O https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Edit CIDR to match your kubeadm init value
sed -i 's|192.168.0.0/16|10.244.0.0/16|g' calico.yaml

# Reapply
kubectl apply -f calico.yaml
```

---

### Issue 9: Pods Cannot Reach Each Other

**Symptom:**
Pod A cannot ping Pod B on different nodes.

**Diagnosis:**
```bash
# Check CNI is running
kubectl get pods -n kube-system -l k8s-app=calico-node

# Check IP routes
ip route show

# Check iptables rules
sudo iptables -L -n -v | grep KUBE

# Check if pods have IPs
kubectl get pods -o wide
```

**Solution:**
```bash
# Verify sysctl settings
sudo sysctl net.bridge.bridge-nf-call-iptables
sudo sysctl net.ipv4.ip_forward
# Both should be 1

# Restart Calico
kubectl delete pods -n kube-system -l k8s-app=calico-node

# Wait for pods to restart
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s
```

---

## Worker Node Issues

### Issue 10: Worker Node Join Fails - Token Expired

**Symptom:**
```bash
kubeadm join ...
# Error: "token has expired"
```

**Root Cause:**
Bootstrap tokens expire after 24 hours.

**Solution:**
```bash
# On control plane, generate new token
kubeadm token create --print-join-command

# Copy output and run on worker node
sudo kubeadm join 192.168.178.34:6443 --token <new-token> ...
```

**CKA Exam Tip:** Memorize this command - it's very common on exam.

---

### Issue 11: Worker Node Join Fails - CA Hash Mismatch

**Symptom:**
```bash
kubeadm join ...
# Error: "discovery token CA hash does not match"
```

**Solution:**
```bash
# On control plane, get correct hash
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //'

# Use this hash in join command
sudo kubeadm join 192.168.178.34:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<correct-hash>
```

---

### Issue 12: Node Shows NotReady

**Symptom:**
```bash
kubectl get nodes
# Shows: k8s-worker-01   NotReady
```

**Diagnosis:**
```bash
# Check node conditions
kubectl describe node k8s-worker-01

# Look for:
# - "KubeletNotReady runtime network not ready: NetworkReady=false"
# - "container runtime is down"

# SSH to worker and check kubelet
sudo journalctl -xeu kubelet | tail -50

# Check containerd
sudo systemctl status containerd
```

**Solution (CNI Issue):**
```bash
# Verify CNI plugin installed
kubectl get pods -n kube-system -o wide | grep calico

# Check if Calico pod is running on this node
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide

# Restart kubelet on worker
sudo systemctl restart kubelet
```

**Solution (Containerd Issue):**
```bash
# Restart containerd
sudo systemctl restart containerd
sudo systemctl restart kubelet

# Wait 1-2 minutes, then check
kubectl get nodes
```

---

## Certificate Issues

### Issue 13: Certificates Expired

**Symptom:**
```bash
kubectl get nodes
# Error: "x509: certificate has expired"
```

**Solution:**
```bash
# Check certificate expiry
sudo kubeadm certs check-expiration

# Renew all certificates
sudo kubeadm certs renew all

# Restart control plane components
sudo systemctl restart kubelet

# Update kubeconfig
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
```

**CKA Exam Tip:** Know certificate locations in `/etc/kubernetes/pki/`.

---

## General Debugging Commands

### Essential Troubleshooting Commands

```bash
# Node-level debugging
kubectl get nodes
kubectl describe node <node-name>
kubectl top nodes  # Requires metrics-server

# Pod-level debugging
kubectl get pods -A -o wide
kubectl describe pod <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous  # Previous container

# Control plane component logs (via systemd)
sudo journalctl -xeu kubelet | tail -100
sudo journalctl -xeu containerd | tail -100

# Control plane component logs (via kubectl)
kubectl logs -n kube-system kube-apiserver-k8s-cp-01
kubectl logs -n kube-system kube-controller-manager-k8s-cp-01
kubectl logs -n kube-system kube-scheduler-k8s-cp-01
kubectl logs -n kube-system etcd-k8s-cp-01

# Network debugging
kubectl get svc -A
kubectl get endpoints -A
kubectl exec -it <pod-name> -- ping <other-pod-ip>
kubectl exec -it <pod-name> -- nslookup kubernetes.default

# Resource debugging
kubectl get events --sort-by='.lastTimestamp' -A
kubectl get componentstatuses  # Deprecated but useful
kubectl cluster-info dump
```

---

## Reset and Start Over

If everything is broken and you want to start fresh:

```bash
# On all nodes (control plane and workers)
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/etcd
sudo rm -rf /var/lib/kubelet
sudo rm -rf ~/.kube

# Reboot (recommended)
sudo reboot

# After reboot, re-run Ansible playbook
ansible-playbook -i inventory.ini install-kubernetes.yml
```

---

## CKA Exam Quick Reference

### Critical File Locations
```
/etc/kubernetes/manifests/       # Static pod manifests
/etc/kubernetes/pki/             # Cluster certificates
/etc/kubernetes/admin.conf       # Admin kubeconfig
/etc/kubernetes/kubelet.conf     # Kubelet kubeconfig
/var/lib/kubelet/                # Kubelet data
/var/lib/etcd/                   # etcd data
/etc/containerd/config.toml      # Containerd config
/etc/systemd/system/kubelet.service.d/  # Kubelet systemd config
```

### Critical Commands
```bash
# Cluster management
kubeadm init
kubeadm join
kubeadm reset
kubeadm token create --print-join-command
kubeadm certs check-expiration
kubeadm certs renew all

# Service management
sudo systemctl status kubelet
sudo systemctl restart kubelet
sudo systemctl status containerd
sudo systemctl restart containerd

# Logs
sudo journalctl -xeu kubelet
sudo journalctl -xeu containerd
kubectl logs -n kube-system <pod-name>
```

---

**Remember:** The CKA exam tests your ability to troubleshoot these exact scenarios under time pressure. Practice these until they're muscle memory!
