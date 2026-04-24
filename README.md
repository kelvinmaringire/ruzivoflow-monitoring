# ruzivoflow-monitoring

Docker Compose stack: **Prometheus**, **Alertmanager**, **Grafana**, **Loki**, **Promtail**, **node_exporter**, and a **docker_metrics** sidecar (textfile metrics via node_exporter).

## Prerequisites

- Docker with Compose v2
- External networks (create once if missing):
  - `monitoring_net`
  - `traefik_net` (only required for Grafana behind Traefik)

## Quick start

1. Copy [`.env.example`](.env.example) to `.env` and set Grafana admin credentials.
2. Edit [`alertmanager/alertmanager.yml`](alertmanager/alertmanager.yml) for your SMTP provider (`smtp_smarthost`, `smtp_from`, `smtp_auth_username`, `email_configs.to`).
3. Put the SMTP password in [`secrets/smtp_password`](secrets/smtp_password) as a **single line** (replace the default `CHANGEME` placeholder).
4. Start:

   ```bash
   docker compose up -d
   ```

5. Check health:

   ```bash
   docker compose ps
   ```

### Local endpoints (loopback only)

| Service       | URL                     |
|---------------|-------------------------|
| Grafana       | http://localhost:3000   |
| Prometheus    | http://127.0.0.1:9090   |
| Loki          | http://127.0.0.1:3100   |
| Alertmanager  | http://127.0.0.1:9093   |

Prometheus, Loki, and Alertmanager are **not** exposed on `0.0.0.0` by default. Only **Grafana** keeps Traefik labels for public HTTPS (see `docker-compose.yml`).

## How to operate

- **Start / stop**

  ```bash
  ./scripts/up.sh
  ./scripts/down.sh
  ```

  Or: `make up`, `make down`, `make ps`, `make logs`.

- **Reload Prometheus** after editing rules (requires `--web.enable-lifecycle`):

  ```bash
  make reload-prometheus
  ```

- **Tail logs**

  ```bash
  ./scripts/tail.sh grafana loki
  ```

## Logs (Loki) retention (7 days)

- Global retention: `limits_config.retention_period: 168h` in [`loki/loki-config.yml`](loki/loki-config.yml).
- The **compactor** enforces retention (`retention_enabled: true`).
- Compaction/deletion runs on an interval; allow time after startup before expecting disk to shrink.

## How to delete logs on demand

Deletion uses Loki’s compactor API. A **cancel window** applies (`delete_request_cancel_period`, default 24h in Loki unless overridden — see `loki/loki-config.yml`).

1. Submit a delete for a LogQL **stream selector** and time range (RFC3339):

   ```bash
   ./scripts/loki-delete-range.sh '{compose_project="myproject",service="api"}' 2026-01-01T00:00:00Z 2026-01-07T00:00:00Z
   ```

2. List requests:

   ```bash
   ./scripts/loki-list-deletes.sh
   ```

3. Cancel a request (optional):

   ```bash
   ./scripts/loki-cancel-delete.sh <request_id>
   ```

Set `LOKI_URL` if Loki is not on `127.0.0.1:3100`.

## How to debug

- **Grafana**: UI → Connections → Data sources (Prometheus / Loki should be provisioned with UIDs `Prometheus` and `Loki`).
- **Prometheus targets**: http://127.0.0.1:9090/targets — all `up` expected for `prometheus`, `node_exporter`, `loki`, `grafana`, `alertmanager`, `promtail`.
- **Rules / alerts**: http://127.0.0.1:9090/alerts
- **Alertmanager**: http://127.0.0.1:9093
- **Loki ready**: `curl -s http://127.0.0.1:3100/ready`
- **Loki logs**: `docker compose logs loki --tail=100`
- **Promtail**: `docker compose logs promtail --tail=100` (also http://127.0.0.1:9080/ready from inside the network)

### SMTP / alerts not sending

- Verify [`alertmanager/alertmanager.yml`](alertmanager/alertmanager.yml) matches your provider.
- Ensure [`secrets/smtp_password`](secrets/smtp_password) has the correct **one-line** secret.
- Check Alertmanager logs: `docker compose logs alertmanager --tail=200`

## Security notes

- Do **not** commit `.env` or real SMTP secrets.
- Grafana is the primary UI; Prometheus/Loki/Alertmanager are bound to **127.0.0.1** for local admin use.
- Traefik security headers for Grafana are set via labels in `docker-compose.yml` (`grafana-sec` middleware).

## What changed (high level)

- Alertmanager + Prometheus alerting/recording rules under [`prometheus/rules/`](prometheus/rules/).
- Loki compactor retention, WAL, ingestion limits, and safe delete workflow.
- Promtail: reduced label cardinality (dropped `image` / `container_id`).
- Grafana: provisioned datasource UIDs; logs dashboard scoped to `job="docker"`.
- Compose: internal-only metrics/logs ports; Grafana-only Traefik exposure for the stack.
