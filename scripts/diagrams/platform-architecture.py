"""
Homelab Kubernetes Platform — Architecture Diagram
===================================================
Generates: docs/architecture/platform-architecture.png

Design principles:
  - Left-to-right flow: external traffic enters left, data persists right
  - Top-to-bottom within cluster: control plane (CI/CD) → workloads → data
  - Cross-cutting concerns (Security, Observability) span vertically on left side
  - All components connected with purposeful edges — no orphans

Edge colour legend:
  Grey   #4a5568 — data plane  (solid=live traffic, dashed=scheduled/backup)
  Blue   #3182ce — GitOps control plane  (ArgoCD syncs)
  Purple #805ad5 — PKI / TLS / Identity (cert-manager, Keycloak SSO)
  Red    #e53e3e — Secrets distribution  (Vault → ESO → workloads)
  Green  #38a169 — Observability plane   (metrics, logs)

Run from repo root:
    python3 scripts/diagrams/platform-architecture.py
"""

from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.gitops import ArgoCD
from diagrams.onprem.monitoring import Grafana, Prometheus
from diagrams.onprem.logging import Loki, FluentBit
from diagrams.onprem.security import Vault
from diagrams.onprem.network import Nginx
from diagrams.onprem.database import PostgreSQL
from diagrams.onprem.inmemory import Redis
from diagrams.onprem.storage import Ceph
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.vcs import Github
from diagrams.onprem.certificates import CertManager
from diagrams.saas.cdn import Cloudflare
from diagrams.saas.filesharing import Nextcloud
from diagrams.saas.identity import Auth0
from diagrams.k8s.others import CRD
from diagrams.generic.storage import Storage
from diagrams.k8s.compute import Cronjob
from diagrams.onprem.client import User

# ── Graph-level styling ───────────────────────────────────────────────────────
graph_attr = {
    "fontsize":   "24",
    "fontname":   "Helvetica Bold",
    "bgcolor":    "#f0f2f5",
    "pad":        "1.8",
    "splines":    "ortho",   # right-angle edges — clean engineering look
    "nodesep":    "0.7",
    "ranksep":    "1.2",
    "dpi":        "160",
    "rankdir":    "LR",      # left → right master direction
    "labeljust":  "c",
    "labelfloat": "true",
}

cluster_attr = {
    "fontsize":  "12",
    "fontname":  "Helvetica Bold",
    "style":     "rounded",
    "bgcolor":   "white",
    "pencolor":  "#b0b8c8",
    "margin":    "20",
}

inner_cluster = {
    **cluster_attr,
    "bgcolor":  "#f7f9fc",
    "pencolor": "#c8d0dc",
    "margin":   "12",
}

# ── Reusable edge factories ───────────────────────────────────────────────────

def e_invis():
    """Invisible layout-nudge edge."""
    return Edge(style="invis")

def e_traffic(label="", headlabel="", taillabel="", labeldistance="1.0"):
    return Edge(color="#4a5568", style="solid", penwidth="1.5",
                label=label, headlabel=headlabel, taillabel=taillabel, labeldistance=labeldistance)

def e_backup(label="", headlabel="", taillabel="", labeldistance="1.0"):
    return Edge(color="#4a5568", style="dashed", penwidth="1.2",
                label=label, headlabel=headlabel, taillabel=taillabel, labeldistance=labeldistance)

def e_gitops(label="", headlabel="", taillabel="", labeldistance="1.0"):
    """Dashed blue — ArgoCD GitOps control plane."""
    return Edge(color="#3182ce", style="dashed", penwidth="1.2", 
                label=label, headlabel=headlabel, taillabel=taillabel, labeldistance=labeldistance)

def e_pki(label="", headlabel="", taillabel="", labeldistance="1.0"):
    return Edge(color="#805ad5", style="dashed", penwidth="1.2",
                label=label, headlabel=headlabel, taillabel=taillabel, labeldistance=labeldistance)

def e_secret(label="", headlabel="", taillabel="", labeldistance="1.0"):
    return Edge(color="#e53e3e", style="dashed", penwidth="1.2",
                label=label, headlabel=headlabel, taillabel=taillabel, labeldistance=labeldistance)

def e_telemetry(label="", headlabel="", taillabel="", solid=False, labeldistance="1.0"):
    return Edge(color="#38a169", style="solid" if solid else "dashed", penwidth="1.2",
                label=label, headlabel=headlabel, taillabel=taillabel, labeldistance=labeldistance)

# =============================================================================

with Diagram(
    "Kubernetes Homelab Platform",
    filename="docs/architecture/platform-architecture",
    outformat="png",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
) as diag:

    # ── External ──────────────────────────────────────────────────────────────
    with Cluster("External", graph_attr=cluster_attr):
        platform_engineer = User("Platform\nEngineer")
        cloudflare = Cloudflare("Cloudflare\nTunnel / DNS")
        github     = Github("GitHub\ngithub.com/mmrajput")

    # ── Kubernetes Cluster ────────────────────────────────────────────────────
    with Cluster(
        "Kubernetes Cluster   ·   v1.31   ·   kubeadm   ·   Calico CNI",
        graph_attr={**cluster_attr, "bgcolor": "#eef1f7"},
    ):
        # ── CI / CD · GitOps ─────────────────────────────────────────────────
        with Cluster("CI / CD  ·  GitOps managed", graph_attr=cluster_attr):
            argocd = ArgoCD("ArgoCD\n(poll-based)")
            arc    = GithubActions("ARC Runners\n(webhook-based)")

        # ── Networking ────────────────────────────────────────────────────────
        with Cluster("Networking  ·  GitOps managed", graph_attr=cluster_attr):
            ingress     = Nginx("ingress-nginx")
            certmanager = CertManager("cert-manager\n(webhook certs)")

        # ── Security · Identity ───────────────────────────────────────────────
        with Cluster("Security  ·  Identity  ·  GitOps managed", graph_attr=cluster_attr):
            keycloak   = Auth0("Keycloak 26\nSSO / OIDC")
            eso        = CRD("External Secrets\nOperator")
            vault      = Vault("HashiCorp\nVault")

        # ── Workloads ─────────────────────────────────────────────────────────
        with Cluster("Workloads  ·  GitOps managed", graph_attr=cluster_attr):
            nextcloud = Nextcloud("Nextcloud\n(File Sharing)")

        # ── Data · Storage · Backup ───────────────────────────────────────────
        with Cluster("Data  ·  Storage  ·  Backup  ·  GitOps managed", graph_attr=cluster_attr):
            cnpg        = PostgreSQL("CNPG\nPostgreSQL clusters")
            redis       = Redis("Redis")
            longhorn    = Ceph("Longhorn\nv1.7.2  RF=2")
            minio       = Storage("MinIO\nS3-compatible")
            velero      = Storage("Velero")
            rclone      = Cronjob("rclone")

        # ── Observability ─────────────────────────────────────────────────────
        with Cluster("Observability  ·  GitOps managed", graph_attr=cluster_attr):
            promtail   = FluentBit("Promtail\n(DaemonSet)")
            prometheus = Prometheus("Prometheus\n+ Alertmanager")
            loki       = Loki("Loki")
            grafana    = Grafana("Grafana")

    # ── Offsite DR ────────────────────────────────────────────────────────────
    onedrive = Storage("OneDrive\n(Offsite DR)")

    # =========================================================================
    # EDGES
    # =========================================================================

    # ── External traffic — data plane ────────────────────────────────────────

    cloudflare        >> e_invis()    >> platform_engineer  # Force icons positioning
    
    platform_engineer >> e_gitops(headlabel="git push", labeldistance="10.0") >> github
    platform_engineer >> e_traffic()  >> cloudflare   # end user / admin traffic
    cloudflare        >> e_traffic()  >> ingress
    ingress           >> e_traffic()  >> nextcloud
    ingress           >> e_traffic()  >> grafana       # Grafana Dashboard via ingress
    ingress           >> e_traffic()  >> argocd        # Argocd UI via ingress

    # ── PKI / TLS ─────────────────────────────────────────────────────────────
    ingress     >> e_pki()     >> certmanager    # webhook cert provisioning

    # ── GitOps — ArgoCD syncs all clusters ───────────────────────────────────
    github >> e_gitops(headlabel="polls", labeldistance="10.0")    >> argocd     # GitOps source
    github >> e_gitops(headlabel="triggers", labeldistance="10.0") >> arc        # GitHub webhooks ARC runners 

    # ── SSO / Identity ────────────────────────────────────────────────────────
    keycloak >> e_pki()           >> argocd        # ArgoCD login via Keycloak
    keycloak >> e_pki()           >> grafana       # Grafana login via Keycloak

    # ── Secrets — Vault → ESO → consumers ────────────────────────────────────
    vault >> e_secret()                 >> eso
    eso   >> e_secret()                 >> keycloak      # Keycloak DB credentials
    eso   >> e_secret()                 >> cnpg          # CNPG superuser credentials
    eso   >> e_secret()                 >> nextcloud     # Nextcloud app secrets

    # ── Workload → Data — live data plane ────────────────────────────────────
    # Force Row 1 left → right
    longhorn >> e_invis() >> cnpg
    cnpg     >> e_invis() >> redis

    # Force Row 2 left → right  
    velero   >> e_invis() >> minio
    minio    >> e_invis() >> rclone

    # Force Row 1 above Row 2
    longhorn >> e_invis() >> velero

    keycloak >> e_traffic()             >> cnpg          # Keycloak uses CNPG as its database
    nextcloud >> e_traffic()            >> cnpg          # primary database
    nextcloud >> e_traffic()            >> redis         # file locking / cache
    nextcloud >> e_traffic()            >> longhorn      # persistent file storage
    
    # ── Backup / DR ───────────────────────────────────────────────────────────
    longhorn >> e_backup(taillabel="fs backup\n(kopia)")        >> velero
    velero   >> e_backup("")            >> minio
    cnpg     >> e_backup("WAL archiving\n(Barman)")    >> minio
    minio  >> e_backup("sync source")   >> rclone
    rclone >> e_backup("offsite copy")  >> onedrive

    # ── Observability — telemetry plane ──────────────────────────────────────
    nextcloud  >> e_telemetry(headlabel="metrics", labeldistance="10.0") >> prometheus                   # Prometheus pulls metrics
    promtail   >> e_telemetry("ship logs")      >> loki          # Promtail ships node logs
    loki       >> e_backup(taillabel="log chunks", labeldistance="10.0")        >> minio         # Loki writes chunks to MinIO
    loki       >> e_telemetry(solid=True)       >> grafana    # Grafana queries Loki
    prometheus >> e_telemetry(solid=True)       >> grafana    # Grafana queries Prometheus