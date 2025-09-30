# Production Mautic Web Image – MANIFEST

This document describes the production-grade, web-only Docker image and how to use it with the Kubernetes manifests in this repo. It is based on the patterns in `KISSMauticDKR/Dockerfile` but removes the embedded database and focuses on a standalone Mautic web container connecting to an external MySQL/MariaDB.

## Overview
- Image: `ghcr.io/expona-ai/mautic-web-service`
  - Tags: `6.0.2`, `latest`
- Dockerfile: `Dockerfile` (repo root)
- Entrypoint: `scripts/entrypoint-web.sh`
- Local.php template: `scripts/local.php.template`
- Kubernetes manifests: files in `kubernetes/`

## What this image does
- Installs Apache 2.4, PHP-FPM 8.3, and all PHP extensions required by Mautic 6.
- Downloads and unpacks Mautic `6.0.2` into `/var/www/html`.
- Does not install or run a database.
- Includes MariaDB client tooling (`mariadb-admin`, `mariadb-check`) to validate DB connectivity.
- Default `MAUTIC_RUN_INSTALLER=false` so the image does not attempt to run the Mautic installer by default.
- If no `config/local.php` exists at runtime, the entrypoint renders it from `scripts/local.php.template` using environment variables.

## Build-time parameters
The Docker image accepts these build args (see `Dockerfile`):
- `PHP_VER` (default `8.3`)
- `MAUTIC_VER` (default `6.0.2`)

Example:
```bash
docker build -t ghcr.io/expona-ai/mautic-web-service:6.0.2 \
  --build-arg PHP_VER=8.3 --build-arg MAUTIC_VER=6.0.2 .
```

## Runtime environment variables
The container reads environment variables to render `config/local.php` when it’s missing. Defined and used in `scripts/entrypoint-web.sh`:
- Database
  - `MAUTIC_DB_DRIVER` (default `pdo_mysql`)
  - `MAUTIC_DB_HOST`
  - `MAUTIC_DB_PORT` (default `3306`)
  - `MAUTIC_DB_NAME`
  - `MAUTIC_DB_USER`
  - `MAUTIC_DB_PASSWORD` (provide via Secret)
- Application
  - `MAUTIC_SITE_URL` (public base URL)
  - `MAUTIC_SECRET_KEY` (auto-generated if not provided)
  - `MAUTIC_REMEMBERME_KEY` (auto-generated if not provided)
- Installer toggle
  - `MAUTIC_RUN_INSTALLER` (default `false`)
    - When `true` and no `local.php` exists, the entrypoint runs `bin/console mautic:install` with DB and (optionally) admin values.

Admin credentials (only used if running CLI installer):
- `MAUTIC_ADMIN_FIRSTNAME`
- `MAUTIC_ADMIN_LASTNAME`
- `MAUTIC_ADMIN_USERNAME`
- `MAUTIC_ADMIN_EMAIL`
- `MAUTIC_ADMIN_PASSWORD`

## Entrypoint behavior (`scripts/entrypoint-web.sh`)
- Starts PHP-FPM, then Apache (foreground).
- DB checks (non-fatal):
  - `mariadb-admin ping` against `${MAUTIC_DB_HOST}:${MAUTIC_DB_PORT}`.
  - If reachable, optionally runs `mariadb-check` against `${MAUTIC_DB_NAME}` to log issues.
- Renders `config/local.php` from `/usr/local/share/mautic/local.php.template` if no `local.php` exists:
  - Replaces placeholders with corresponding `MAUTIC_*` variables.
  - Generates `MAUTIC_SECRET_KEY` and `MAUTIC_REMEMBERME_KEY` if not provided.
- Installer is disabled by default (`MAUTIC_RUN_INSTALLER=false`). If enabled and `local.php` is absent, runs `bin/console mautic:install`.

## Database testing tools
Available via `mariadb-client` package:
- Connectivity: `mariadb-admin ping -h $MAUTIC_DB_HOST -P $MAUTIC_DB_PORT -u $MAUTIC_DB_USER -p$MAUTIC_DB_PASSWORD --silent`
- Sanity check: `mariadb-check -h $MAUTIC_DB_HOST -P $MAUTIC_DB_PORT -u $MAUTIC_DB_USER -p$MAUTIC_DB_PASSWORD $MAUTIC_DB_NAME`

These are used internally by the entrypoint for diagnostics and do not block startup.

## Healthcheck
The image defines a simple healthcheck in `Dockerfile`:
- Verifies Apache and PHP-FPM services are running.
- Performs `curl -f http://localhost`.

## Kubernetes integration
This image is designed to work with the manifests in `kubernetes/` and connect to the database defined in `kubernetes/mysql.yaml` via `Service/mautic-db`.

### ConfigMap for non-secret settings
File: `kubernetes/mautic-config.yaml`
- Supplies non-secret environment variables consumed by the pod:
  - `MAUTIC_DB_HOST`, `MAUTIC_DB_PORT`, `MAUTIC_DB_NAME`, `MAUTIC_DB_USER`, `MAUTIC_DB_DRIVER`, `MAUTIC_SITE_URL`
  - Optional PHP limits e.g., `PHP_MEMORY_LIMIT`, `PHP_MAX_EXECUTION_TIME`, `PHP_MAX_UPLOAD` if you tune php.ini via env.

Apply:
```bash
kubectl apply -f kubernetes/mautic-config.yaml
```

### Secret for DB password
File: `kubernetes/db-secret.yaml`
- Provides `mysql-user-password` and `mysql-root-password` (base64 encoded).

Apply:
```bash
kubectl apply -f kubernetes/db-secret.yaml
```

### Deployment
File: `kubernetes/mautic-deployment.yaml`
- Uses `ghcr.io/expona-ai/mautic-web-service:6.0.2` for the main container.
- No initContainer: the image renders `config/local.php` at runtime from env vars (via the entrypoint) when missing.
- Injects env vars via:
  - `envFrom: configMapRef: mautic-config` (non-secrets)
  - `env: MAUTIC_DB_PASSWORD` from `Secret/mautic-db-secret`
- Mounts `PVC/mautic-pvc` at `/var/www/html`.
- Probes (added):
  - ReadinessProbe: HTTP GET `/` port 80; `initialDelaySeconds: 20`, `periodSeconds: 10`, `timeoutSeconds: 5`, `failureThreshold: 6`.
  - LivenessProbe: HTTP GET `/` port 80; `initialDelaySeconds: 60`, `periodSeconds: 20`, `timeoutSeconds: 5`, `failureThreshold: 3`.

Apply:
```bash
kubectl apply -f kubernetes/mautic-deployment.yaml
```

### Database (MySQL/MariaDB)
File: `kubernetes/mysql.yaml`
- Deploys DB at `Service/mautic-db:3306`.
- Ensure `MAUTIC_DB_HOST=mautic-db` and other DB envs match this Service.

Apply:
```bash
kubectl apply -f kubernetes/mysql-pvc.yaml
kubectl apply -f kubernetes/mysql.yaml
```

### Ingress and Service
- `kubernetes/mautic-service.yaml`: Exposes port 8090 → pod port 80.
- `kubernetes/mautic-ingress.yaml`: Routes `campaign.expona.ai` to `Service/mautic:8090` (TLS configured via cert-manager).

## Local run (for smoke tests)
```bash
docker run --rm -p 8080:80 \
  -e MAUTIC_DB_HOST=127.0.0.1 \
  -e MAUTIC_DB_PORT=3306 \
  -e MAUTIC_DB_NAME=mautic \
  -e MAUTIC_DB_USER=mautic \
  -e MAUTIC_DB_PASSWORD=secret \
  -e MAUTIC_SITE_URL=http://localhost:8080 \
  ghcr.io/expona-ai/mautic-web-service:6.0.2
```

Notes:
- By default the container won’t run the installer; it will render `config/local.php` from env and start Apache/PHP-FPM.
- Mount a volume to `/var/www/html` if you want persistence.

## Security considerations
- Secrets (DB password, secret keys) are not baked into the image; they are provided at runtime via Kubernetes Secrets and env vars.
- `MAUTIC_SECRET_KEY` and `MAUTIC_REMEMBERME_KEY` are generated if not provided—override with your own for deterministic values across upgrades.

## Troubleshooting
- Check container logs for DB connectivity messages from `mariadb-admin`/`mariadb-check`.
- Verify `config/local.php` exists inside the pod:
```bash
kubectl -n mautic exec -it deploy/mautic-web -- ls -l /var/www/html/config/local.php
kubectl -n mautic exec -it deploy/mautic-web -- grep -E "db_host|db_name|db_user|db_port|site_url" /var/www/html/config/local.php
```
- Ensure `Service/mautic-db` is reachable from the web pod and credentials match `db-secret.yaml`.
