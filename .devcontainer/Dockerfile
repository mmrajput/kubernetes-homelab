# Homelab Infrastructure DevContainer
# Base: Ubuntu 24.04 LTS (matching cluster VMs)
# Purpose: Isolated CLI environment for Kubernetes cluster management
# User: rajput (UID 1000)

FROM ubuntu:24.04

# Build arguments
ARG USERNAME=rajput
ARG USER_UID=1000
ARG USER_GID=1000

# Tool versions - Pinned for reproducibility
# CKA exam targets Kubernetes 1.31, kubectl must match
ARG KUBECTL_VERSION=1.31.4
ARG K9S_VERSION=0.32.7
ARG HELM_VERSION=3.16.3
ARG ARGOCD_VERSION=2.13.2
ARG ETCD_VERSION=3.5.17
ARG CRICTL_VERSION=1.31.1
ARG YQ_VERSION=4.44.6

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin

# Install system dependencies
RUN apt-get update && apt-get install -y \
    # Essential tools
    curl \
    wget \
    git \
    vim \
    nano \
    unzip \
    tar \
    gzip \
    tree \ 
    ca-certificates \
    gnupg \
    lsb-release \
    apt-transport-https \
    # Network tools
    iputils-ping \
    dnsutils \
    netcat-openbsd \
    traceroute \
    # Build tools (for some CLI compilations)
    build-essential \
    # Python for Ansible
    python3 \
    python3-pip \
    python3-venv \
    # JSON/YAML processing
    jq \
    # SSH client
    openssh-client \
    # Additional utilities
    bash-completion \
    sudo \
    && rm -rf /var/lib/apt/lists/*

# Create user with sudo privileges
# Ubuntu 24.04 pre-creates ubuntu:ubuntu (1000:1000), so we handle conflicts
RUN set -e; \
    # Remove existing ubuntu user if it exists with UID 1000
    if id ubuntu >/dev/null 2>&1; then \
        userdel -r ubuntu 2>/dev/null || true; \
    fi; \
    # Remove existing group with GID 1000 if it exists
    if getent group 1000 >/dev/null 2>&1; then \
        GROUP_TO_DELETE=$(getent group 1000 | cut -d: -f1); \
        groupdel $GROUP_TO_DELETE 2>/dev/null || true; \
    fi; \
    # Now create our user and group
    groupadd --gid ${USER_GID} ${USERNAME}; \
    useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} -s /bin/bash; \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    
# Install kubectl v1.31.4 (CKA exam version)
RUN curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" \
    && curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" \
    && echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check \
    && install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl \
    && rm kubectl kubectl.sha256

# Install kubeadm v1.31.4 (cluster operations)
RUN curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubeadm" \
    && curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubeadm.sha256" \
    && echo "$(cat kubeadm.sha256)  kubeadm" | sha256sum --check \
    && install -o root -g root -m 0755 kubeadm /usr/local/bin/kubeadm \
    && rm kubeadm kubeadm.sha256

# Install k9s (TUI for Kubernetes)
RUN curl -LO "https://github.com/derailed/k9s/releases/download/v${K9S_VERSION}/k9s_linux_amd64.tar.gz" \
    && tar -xzf k9s_linux_amd64.tar.gz \
    && install -o root -g root -m 0755 k9s /usr/local/bin/k9s \
    && rm k9s k9s_linux_amd64.tar.gz LICENSE README.md

# Install Helm
RUN curl -LO "https://get.helm.sh/helm-v${HELM_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf helm-v${HELM_VERSION}-linux-amd64.tar.gz \
    && install -o root -g root -m 0755 linux-amd64/helm /usr/local/bin/helm \
    && rm -rf helm-v${HELM_VERSION}-linux-amd64.tar.gz linux-amd64

# Install ArgoCD CLI
RUN curl -sSL -o /usr/local/bin/argocd "https://github.com/argoproj/argo-cd/releases/download/v${ARGOCD_VERSION}/argocd-linux-amd64" \
    && chmod +x /usr/local/bin/argocd

# Install etcdctl (CKA exam requirement)
RUN curl -LO "https://github.com/etcd-io/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz \
    && install -o root -g root -m 0755 etcd-v${ETCD_VERSION}-linux-amd64/etcdctl /usr/local/bin/etcdctl \
    && rm -rf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz etcd-v${ETCD_VERSION}-linux-amd64

# Install crictl (container runtime CLI - CKA exam requirement)
RUN curl -LO "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRICTL_VERSION}/crictl-v${CRICTL_VERSION}-linux-amd64.tar.gz" \
    && tar -xzf crictl-v${CRICTL_VERSION}-linux-amd64.tar.gz \
    && install -o root -g root -m 0755 crictl /usr/local/bin/crictl \
    && rm crictl crictl-v${CRICTL_VERSION}-linux-amd64.tar.gz

# Install yq (YAML processor)
RUN curl -LO "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
    && install -o root -g root -m 0755 yq_linux_amd64 /usr/local/bin/yq \
    && rm yq_linux_amd64

# Install Ansible via pip (latest 2.x stable)
RUN pip3 install --no-cache-dir --break-system-packages \
    ansible==10.7.0 \
    ansible-core==2.17.7 \
    kubernetes \
    jmespath

# Enable bash completion for kubectl
RUN kubectl completion bash > /etc/bash_completion.d/kubectl

# Switch to user
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Create .devcontainer directory for post-create script
RUN mkdir -p /home/${USERNAME}/.devcontainer

# Copy post-create script
COPY --chown=${USERNAME}:${USERNAME} post-create.sh /home/${USERNAME}/.devcontainer/post-create.sh
RUN chmod +x /home/${USERNAME}/.devcontainer/post-create.sh

# Set up shell environment - Basic configuration
RUN echo 'source <(kubectl completion bash)' >> ~/.bashrc \
    && echo 'alias k=kubectl' >> ~/.bashrc \
    && echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc \
    && echo 'export EDITOR=vim' >> ~/.bashrc

# Set up custom colorful prompt
RUN cat >> ~/.bashrc << 'PROMPT_EOF'

# Custom Prompt Configuration
parse_git_branch() {
    git branch 2>/dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
}

parse_k8s_context() {
    if [ -f ~/.kube/config ]; then
        ctx=$(kubectl config current-context 2>/dev/null)
        echo "⎈ ${ctx##*@}"
    fi
}

# Colors
PURPLE='\[\033[0;35m\]'
CYAN='\[\033[0;36m\]'
YELLOW='\[\033[1;33m\]'
BLUE='\[\033[0;34m\]'
GREEN='\[\033[0;32m\]'
RED='\[\033[0;31m\]'
WHITE='\[\033[0;37m\]'
RESET='\[\033[0m\]'

# Two-line prompt
PS1="${PURPLE}┌─[${CYAN}\u${WHITE}@${CYAN}\h${PURPLE}]─[${YELLOW}\w${PURPLE}]"
PS1="${PS1}${BLUE}\$(parse_k8s_context)${PURPLE}\$(parse_git_branch)${RESET}\n"
PS1="${PS1}${PURPLE}└─"
if [ $? -eq 0 ]; then
    PS1="${PS1}${GREEN}\$${RESET} "
else
    PS1="${PS1}${RED}\$${RESET} "
fi

export PS1
PROMPT_EOF

# Default command
CMD ["/bin/bash"]