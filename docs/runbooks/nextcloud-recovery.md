# Nextcloud Recovery Runbook

**Last updated:** April 2026
**Applies to:** `nextcloud-production` namespace, chart `nextcloud/nextcloud` v9.0.4, app 33.0.0

---

## Overview

This runbook covers recovery of the Nextcloud production instance. Choose the scenario that matches your situation:

| Scenario | PVC | Database | Action |
|---|---|---|---|
| [A](#scenario-a--configphp-lost-pvc-and-db-intact) | Intact | Intact | Reconstruct config.php only |
| [B](#scenario-b--database-lost-pvc-intact) | Intact | Lost/empty | CNPG WAL recovery + patch config.php |
| [C](#scenario-c--fresh-install-no-usable-db-backup) | Intact | Lost, no WAL | Fresh install via `occ` |
| [D](#scenario-d--pvc-lost-database-intact) | Lost | Intact | Velero PVC restore |
| Full DR | Both lost | Both lost | See [disaster-recovery.md](disaster-recovery.md) |

### Backup topology

| Data | Tool | Destination | Schedule |
|---|---|---|---|
| Nextcloud PVC (`/var/www/html`) | Velero — `nextcloud-files` | MinIO `velero` | Every 6 hours |
| Nextcloud PVC + namespace objects | Velero — `nightly-full` | MinIO `velero` | Daily 2:00 AM |
| PostgreSQL WAL stream | Barman → MinIO | MinIO `cnpg-backups/nextcloud-production` | Continuous |
| PostgreSQL base backups | CNPG ScheduledBackup | MinIO `cnpg-backups/nextcloud-production` | Daily 3:30 AM |

> CNPG PVCs are excluded from Velero (`backup.velero.io/backup-volumes-excludes: pgdata`).
> Barman is the sole authoritative backup path for all PostgreSQL data.

---

## Scenario A — config.php lost, PVC and DB intact

Symptoms: Nextcloud returns 503/500, pod logs show no errors connecting to DB,
`/var/www/html/config/config.php` is missing or zero bytes.

### Step 1 — Read the instanceid from the data directory

The `instanceid` **must** match the appdata directory already present on the PVC.
A mismatch causes all cached app data (previews, app configs) to become orphaned.

```bash
kubectl exec -n nextcloud-production <pod> -- ls /var/www/html/data/
# Look for the appdata_<instanceid> directory, e.g.:
#   appdata_oc5mcu5994f2  ← instanceid is oc5mcu5994f2
```

### Step 2 — Read DB credentials from the secret

```bash
kubectl get secret nextcloud-production-secret -n nextcloud-production \
  -o jsonpath='{.data.db-username}' | base64 -d && echo
kubectl get secret nextcloud-production-secret -n nextcloud-production \
  -o jsonpath='{.data.db-password}' | base64 -d && echo
```

### Step 3 — Write config.php

```bash
cat << 'EOF' | kubectl exec -i -n nextcloud-production <pod> -- sh -c 'cat > /var/www/html/config/config.php'
<?php
$CONFIG = array (
  'instanceid' => '<instanceid-from-step-1>',
  'passwordsalt' => '<generate: python3 -c "import secrets; print(secrets.token_urlsafe(32)[:22])">',
  'secret' => '<generate: python3 -c "import secrets; print(secrets.token_urlsafe(64)[:48])">',
  'trusted_domains' =>
  array (
    0 => 'nextcloud.mmrajputhomelab.org',
  ),
  'datadirectory' => '/var/www/html/data',
  'dbtype' => 'pgsql',
  'version' => '33.0.0.16',
  'dbhost' => 'nextcloud-prod-db-rw.databases.svc.cluster.local',
  'dbport' => '',
  'dbtableprefix' => 'oc_',
  'dbname' => 'nextcloud',
  'dbuser' => '<db-username>',
  'dbpassword' => '<db-password>',
  'installed' => true,
);
EOF
```

Set ownership and mode:
```bash
kubectl exec -n nextcloud-production <pod> -- chmod 0640 /var/www/html/config/config.php
```

> The ConfigMap-mounted split config files (redis, apcu, reverse-proxy, etc.) handle
> memcache, Redis, and trusted proxy settings — do not duplicate those keys here.

### Step 4 — Verify

```bash
kubectl exec -n nextcloud-production <pod> -- curl -sf http://localhost/status.php
# Expect: {"installed":true,"maintenance":false,"needsDbUpgrade":false,...}
```

---

## Scenario B — Database lost, PVC intact

Use this when the CNPG cluster is empty or has been recreated, but WAL archives in MinIO
are available. CNPG replays the WAL stream and restores the database to the point of the
last archived segment — no `occ install`, no file scan, no user recreation required.

### Step 1 — Confirm WAL archives exist in MinIO

```bash
kubectl exec -n minio <minio-pod> -- mc ls minio/cnpg-backups/nextcloud-production/
# Should show wals/ and base/ directories with recent timestamps
```

### Step 2 — Patch the CNPG cluster bootstrap to `recovery`

`platform/data/cnpg/clusters/nextcloud-prod-cluster.yaml` — replace the `bootstrap` block:

```yaml
bootstrap:
  recovery:
    source: nextcloud-prod-db

externalClusters:
  - name: nextcloud-prod-db
    barmanObjectStore:
      destinationPath: s3://cnpg-backups/nextcloud-production
      endpointURL: http://minio.minio.svc.cluster.local:9000
      s3Credentials:
        accessKeyId:
          name: cnpg-minio-secret
          key: access-key
        secretAccessKey:
          name: cnpg-minio-secret
          key: secret-key
      wal:
        compression: gzip
```

> For PITR to a specific timestamp, add `recoveryTarget.targetTime` inside `recovery:`.
> Full procedure: [disaster-recovery.md — Scenario 2](disaster-recovery.md#scenario-2--cnpg-point-in-time-recovery-pitr).

### Step 3 — Delete the empty cluster and let ArgoCD recreate it

```bash
# Disable selfHeal first (see ArgoCD note below), then:
kubectl delete cluster nextcloud-prod-db -n databases
# ArgoCD will apply the patched manifest and CNPG will begin WAL replay
kubectl get cluster nextcloud-prod-db -n databases -w
# Wait for: Cluster in healthy state
```

### Step 4 — Reconstruct config.php if also lost

Follow [Scenario A](#scenario-a--configphp-lost-pvc-and-db-intact).
The database already has all user data — only config.php needs to be written.

### Step 5 — Revert bootstrap block in Git

Once the cluster is healthy, change `bootstrap` back to `initdb` (or a neutral recovery
block) and commit on the feature branch, so a future ArgoCD sync does not re-trigger
the recovery bootstrap on a running cluster.

---

## Scenario C — Fresh install (no usable DB backup)

Use this when the database is empty and no WAL archives are available.
All database-stored data (user accounts, shares, app settings, activity log) will be lost.
Files on the PVC survive and can be re-indexed.

> **Known gotchas from the April 2026 incident:**
> - `installed=true` in config.php causes `occ maintenance:install` to abort — set it to `false` first.
> - The `admin` home directory on the PVC blocks `occ user:add admin` — move it aside temporarily.
> - ArgoCD selfHeal continuously reverts `kubectl scale --replicas=0` (the Application CRD is
>   managed by the root app in Git). Work inside the running pod between liveness probe cycles
>   rather than trying to scale down.

### Step 1 — Write config.php with `installed=false`

Identify the `instanceid` from the appdata directory name (see [Scenario A, Step 1](#step-1--read-the-instanceid-from-the-data-directory)).

```bash
cat << 'EOF' | kubectl exec -i -n nextcloud-production <pod> -- sh -c 'cat > /var/www/html/config/config.php'
<?php
$CONFIG = array (
  'instanceid' => '<instanceid-from-appdata-dir>',
  'passwordsalt' => '<generated>',
  'secret' => '<generated>',
  'trusted_domains' =>
  array (
    0 => 'nextcloud.mmrajputhomelab.org',
  ),
  'datadirectory' => '/var/www/html/data',
  'dbtype' => 'pgsql',
  'version' => '33.0.0.16',
  'dbhost' => 'nextcloud-prod-db-rw.databases.svc.cluster.local',
  'dbport' => '',
  'dbtableprefix' => 'oc_',
  'dbname' => 'nextcloud',
  'dbuser' => '<db-username>',
  'dbpassword' => '<db-password>',
  'installed' => false,
);
EOF
```

### Step 2 — Run `occ maintenance:install` with a temporary admin account

Use `ncadmin` (not `admin`) to avoid the existing `admin/` directory conflict:

```bash
kubectl exec -n nextcloud-production <pod> -- \
  php /var/www/html/occ maintenance:install \
    --database pgsql \
    --database-host nextcloud-prod-db-rw.databases.svc.cluster.local \
    --database-name nextcloud \
    --database-user nextcloud \
    --database-pass '<db-password>' \
    --admin-user ncadmin \
    --admin-pass '<any-temporary-password>' \
    --data-dir /var/www/html/data
# Expect: Nextcloud was successfully installed
```

`occ` rewrites config.php with `installed=true` and regenerates `passwordsalt`/`secret`.

### Step 3 — Fix trusted_domains

`occ` sets `trusted_domains[0] = localhost`. Override it:

```bash
kubectl exec -n nextcloud-production <pod> -- \
  php /var/www/html/occ config:system:set trusted_domains 0 \
    --value='nextcloud.mmrajputhomelab.org'

kubectl exec -n nextcloud-production <pod> -- \
  php /var/www/html/occ config:system:delete trusted_domains 1 2>/dev/null || true
```

### Step 4 — Recreate the admin account

Move aside the existing admin data directory, create the account, restore it:

```bash
kubectl exec -n nextcloud-production <pod> -- sh -c '
  mv /var/www/html/data/admin /var/www/html/data/admin.bak &&
  OC_PASS=<admin-password> php /var/www/html/occ user:add \
    --password-from-env --display-name="Admin" admin &&
  rm -rf /var/www/html/data/admin &&
  mv /var/www/html/data/admin.bak /var/www/html/data/admin
'
```

Add to the admin group:
```bash
kubectl exec -n nextcloud-production <pod> -- \
  php /var/www/html/occ group:adduser admin admin
```

### Step 5 — Delete the temporary bootstrap account

```bash
kubectl exec -n nextcloud-production <pod> -- \
  php /var/www/html/occ user:delete ncadmin
```

### Step 6 — Re-index files

```bash
kubectl exec -n nextcloud-production <pod> -- \
  php /var/www/html/occ files:scan --all
```

### Step 7 — Set config.php permissions

```bash
kubectl exec -n nextcloud-production <pod> -- \
  chmod 0640 /var/www/html/config/config.php
```

### Step 8 — Verify

```bash
kubectl exec -n nextcloud-production <pod> -- curl -sf http://localhost/status.php
# Expect: {"installed":true,"maintenance":false,"needsDbUpgrade":false,...}
kubectl get pods -n nextcloud-production
# Expect: 1/1 Running
```

---

## Scenario D — PVC lost, database intact

Velero restores the full `/var/www/html` tree including config.php. The database is
untouched — no `occ` commands needed after restore.

### Step 1 — Identify the right backup

```bash
velero backup get | grep nextcloud
```

Choose the most recent `velero-nextcloud-files-*` backup that predates the incident.

### Step 2 — Restore the namespace

```bash
velero restore create nextcloud-restore-$(date +%s) \
  --from-backup <backup-name> \
  --include-namespaces nextcloud-production
```

Monitor:
```bash
velero restore describe nextcloud-restore-<timestamp> --details
```

### Step 3 — Verify config.php and pod health

```bash
kubectl exec -n nextcloud-production <pod> -- cat /var/www/html/config/config.php
kubectl exec -n nextcloud-production <pod> -- curl -sf http://localhost/status.php
```

---

## ArgoCD note — scaling down is blocked

The `nextcloud-production` Application has `selfHeal: true` managed from Git via the root app.
Patching `selfHeal: false` on the Application object is immediately reverted by ArgoCD.
`kubectl scale --replicas=0` is also reverted within seconds.

**Workaround:** All `occ` commands above are designed to run inside the already-running pod
(`kubectl exec`) rather than requiring the deployment to be scaled down.
If you genuinely need the pod stopped (e.g. a PVC migration), the only reliable method is
to temporarily change `replicas: 0` in `workloads/nextcloud/production-values.yaml`,
commit and push to Git, and let ArgoCD apply it.

---

## Credentials reference

| Value | Source |
|---|---|
| DB host | `nextcloud-prod-db-rw.databases.svc.cluster.local` |
| DB name / user | `nextcloud` |
| DB password | `nextcloud-production-secret` → key `db-password` |
| Admin username | `nextcloud-production-secret` → key `nextcloud-username` |
| Admin password | `nextcloud-production-secret` → key `nextcloud-password` |
| instanceid | `ls /var/www/html/data/` → `appdata_<instanceid>` |

---

## Related runbooks

- [disaster-recovery.md](disaster-recovery.md) — full cluster DR, Velero restore procedure, CNPG PITR detail
- [backup-procedures.md](backup-procedures.md) — Velero schedule and CNPG backup verification
