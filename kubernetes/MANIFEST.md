# Mautic on Kubernetes – Deployment Manifest

This document describes the Mautic deployment defined in `kubernetes/` and the expected configuration to operate it in the `mautic` namespace.

## Overview
- **Namespace**: `mautic` (`kubernetes/namepsace.yaml`)
- **App**: Mautic (PHP/Apache image) with MySQL
- **Ingress**: `mautic-ingress` routes `campaign.expona.ai` to the Mautic Service over TLS
- **Persistent storage**: PVCs for Mautic data and MySQL data
- **Secrets**: `mautic-db-secret` contains MySQL root/user passwords
- **Cert-Manager**: Issuers for Let’s Encrypt (staging and prod) and a Certificate resource

## Components

### 1) Mautic (Deployment + Service)
- File: `kubernetes/mautic-deployment.yaml`
  - `Deployment/mautic` (apps/v1)
  - Replicas: `1`
  - Image: `mautic/mautic:v4` (commented alternative: `mautic/mautic:5.2.1-apache`)
  - Container port: `80`
  - Volume mounts:
    - `mautic-data` → `/var/www/html` (PVC: `mautic-pvc`)
    - `mautic-config` → `/config` (PVC: `mautic-config-pvc`) – see Known Gaps
  - Environment:
    - `MAUTIC_DB_HOST=mautic-db`
    - `MAUTIC_DB_PORT=3306`
    - `MAUTIC_DB_NAME=mautic`
    - `MAUTIC_DB_USER=mautic`
    - `MAUTIC_DB_PASSWORD` from Secret `mautic-db-secret` key `mysql-user-password`
    - `PHP_MEMORY_LIMIT=4G`
    - `PHP_MAX_EXECUTION_TIME=3600`
    - `PHP_MAX_UPLOAD=200M`
    - `MAUTIC_URL=https://campaign.expona.ai`
    - `MAUTIC_RUN_INSTALLER=false`

- File: `kubernetes/mautic-service.yaml`
  - `Service/mautic` (v1)
  - Port: `8090` → targetPort `80`
  - Selector: `app: mautic`

### 2) Ingress (TLS)
- File: `kubernetes/mautic-ingress.yaml`
  - `Ingress/mautic-ingress` (networking.k8s.io/v1)
  - Ingress class: `nginx`
  - Host: `campaign.expona.ai`
  - Routes: `campaign.expona.ai` → `Service/mautic:8090`
  - TLS: `secretName: expona-api-tls`
  - Annotations (Linode LB + cert-manager):
    - `service.beta.kubernetes.io/linode-loadbalancer-preserve: "true"`
    - `service.beta.kubernetes.io/linode-loadbalancer-default-protocol: http`
    - `service.beta.kubernetes.io/linode-loadbalancer-port-443: '{ "tls-secret-name": "expona-api-tls", "protocol": "https" }'`
    - `cert-manager.io/issuer: letsencrypt-prod`
    - `nginx.ingress.kubernetes.io/ssl-redirect: "true"`

### 3) MySQL (Deployment + Service)
- File: `kubernetes/mysql.yaml`
  - `Deployment/mautic-db`
    - Image: `mysql:8.4`
    - Env:
      - `MYSQL_ROOT_PASSWORD` from Secret `mautic-db-secret/mysql-root-password`
      - `MYSQL_DATABASE=mautic`
      - `MYSQL_USER=mautic`
      - `MYSQL_PASSWORD` from Secret `mautic-db-secret/mysql-user-password`
    - Port: `3306`
    - Volume mount: `mysql-data` → `/var/lib/mysql` (PVC: `mysql-pvc`)
  - `Service/mautic-db`
    - Port: `3306` → targetPort `3306`
    - Selector: `app: mautic-db`

### 4) Secrets
- File: `kubernetes/db-secret.yaml`
  - `Secret/mautic-db-secret` (Opaque)
  - Keys:
    - `mysql-root-password` = base64 `cm9vdF9wYXNzd29yZA==` (root_password)
    - `mysql-user-password` = base64 `bWF1dGljX3Bhc3N3b3Jk` (mautic_password)

### 5) PersistentVolumeClaims
- File: `kubernetes/mautic-pvc.yaml`
  - `PVC/mautic-pvc` – 10Gi, ReadWriteOnce
- File: `kubernetes/mysql-pvc.yaml`
  - `PVC/mysql-pvc` – 10Gi, ReadWriteOnce

### 6) Cert-Manager Issuers and Certificate
- File: `kubernetes/cert-manager-issuer.yaml`
  - `Issuer/letsencrypt-staging`, `Issuer/letsencrypt-prod`
- File: `kubernetes/create-certificate-expona.yml`
  - `Certificate/expona-api-tls` with `dnsNames: [ next.expona.ai ]`
  - `secretName: expona-api-tls`
  - `issuerRef: letsencrypt-prod`

## Expected Configuration (Environment)
Use these environment settings for Mautic (as set in `mautic-deployment.yaml`):

```env
MAUTIC_DB_HOST=mautic-db
MAUTIC_DB_PORT=3306
MAUTIC_DB_NAME=mautic
MAUTIC_DB_USER=mautic
MAUTIC_DB_PASSWORD=<from secret mautic-db-secret/mysql-user-password>
MAUTIC_URL=https://campaign.expona.ai
MAUTIC_RUN_INSTALLER=false
PHP_MEMORY_LIMIT=4G
PHP_MAX_EXECUTION_TIME=3600
PHP_MAX_UPLOAD=200M
```

- Full FQDNs if needed: `MAUTIC_DB_HOST=mautic-db.mautic.svc.cluster.local`
- If you want the container to self-install on first boot (`MAUTIC_RUN_INSTALLER=true`), ensure write access and that the `/config` or `/var/www/html/app/config` path persists. This repo mounts `/var/www/html` and a separate `/config` path.

## Networking
- **Internal**:
  - `Service/mautic`: ClusterIP on port `8090` → pod port `80`
  - `Service/mautic-db`: ClusterIP on port `3306`
- **External**:
  - `Ingress/mautic-ingress` exposes `campaign.expona.ai` over HTTPS using TLS secret `expona-api-tls`

## Storage
- **Mautic Data**: `PVC/mautic-pvc` mounted at `/var/www/html`
- **Mautic Config**: `PVC/mautic-config-pvc` expected (mounted at `/config`) – see Known Gaps
- **MySQL Data**: `PVC/mysql-pvc` mounted at `/var/lib/mysql`

## Apply Order
Recommended application sequence:

```bash
kubectl apply -f kubernetes/namepsace.yaml
kubectl apply -f kubernetes/db-secret.yaml
kubectl apply -f kubernetes/mysql-pvc.yaml
kubectl apply -f kubernetes/mautic-pvc.yaml
# (Create missing: kubernetes/mautic-config-pvc.yaml)  # see Known Gaps
kubectl apply -f kubernetes/mysql.yaml
kubectl apply -f kubernetes/mautic-service.yaml
kubectl apply -f kubernetes/mautic-deployment.yaml
kubectl apply -f kubernetes/cert-manager-issuer.yaml
kubectl apply -f kubernetes/create-certificate-expona.yml
kubectl apply -f kubernetes/mautic-ingress.yaml
```

Wait for pods to become Ready:
```bash
kubectl -n mautic get pods
kubectl -n mautic get svc,ingress
```

## Known Gaps and Mismatches
- **Missing PVC**: The deployment mounts `mautic-config-pvc` at `/config`, but no `mautic-config-pvc` is defined in this repo. Add a PVC, e.g. `kubernetes/mautic-config-pvc.yaml`:
  ```yaml
  apiVersion: v1
  kind: PersistentVolumeClaim
  metadata:
    name: mautic-config-pvc
    namespace: mautic
  spec:
    accessModes: ["ReadWriteOnce"]
    resources:
      requests:
        storage: 1Gi
  ```
- **Certificate host mismatch**:
  - Ingress host: `campaign.expona.ai`
  - Certificate `expona-api-tls` dnsNames: `next.expona.ai`
  - Fix by aligning the certificate’s `dnsNames` with the ingress host (or create a second certificate for `campaign.expona.ai`). Example:
    ```yaml
    apiVersion: cert-manager.io/v1
    kind: Certificate
    metadata:
      name: expona-api-tls
      namespace: mautic
    spec:
      secretName: expona-api-tls
      dnsNames:
        - campaign.expona.ai
      issuerRef:
        name: letsencrypt-prod
        kind: Issuer
    ```
- **Image registry differences**:
  - The cluster output you shared includes pods with `ImagePullBackOff` and a running `mautic-web` pod. Those workloads (e.g., campaigns trigger/update, messenger-consumer) are not defined in this repo; they are likely separate manifests (CronJobs/Deployments) with different images (possibly private GHCR images). If you intend to use GHCR images for web/worker components, update `mautic-deployment.yaml` to reference your `ghcr.io/expona-ai/mautic-web-service:latest` and add `imagePullSecrets`.
- **Service names**:
  - This repo uses `mautic-db` for MySQL. Your cluster services also show `mautic-mariadb`; those are different and not defined here. Ensure the `MAUTIC_DB_HOST` matches the service deployed from this repo (`mautic-db`) unless you intentionally point to a separate DB service.

## Operational Notes
- Initial installation can be run via the container’s entrypoint (if supported by the image) or manually via CLI (`bin/console mautic:install`). When running manually, ensure network policies and DNS allow the pod to reach `Service/mautic-db`.
- Backups: Snapshot or backup the PVCs (`mysql-pvc`, `mautic-pvc`, and `mautic-config-pvc` once created) as part of your data retention strategy.
- Resources: No CPU/Memory limits/requests are defined in the provided YAML; consider adding them for production stability.
- Health checks: No `livenessProbe`/`readinessProbe` are configured; adding them will improve rollout reliability.

## Quick Reference
- Namespace: `mautic`
- Deployments: `mautic`, `mautic-db`
- Services: `mautic` (8090→80), `mautic-db` (3306)
- Ingress: `mautic-ingress` (`campaign.expona.ai` → `Service/mautic:8090`)
- PVCs: `mautic-pvc` (10Gi), `mysql-pvc` (10Gi), EXPECTED `mautic-config-pvc`
- Secret: `mautic-db-secret` (MySQL credentials)
- Cert-Manager: `letsencrypt-staging`, `letsencrypt-prod`, `expona-api-tls` (update dnsNames)
