# Standalone Docker Compose deployment

Use the root `docker-compose.yml` to run Vibe Kanban Team on a single Linux machine. The stack uses the published release images and includes:

- Caddy reverse proxy with automatic HTTPS
- Vibe Kanban Team Remote app/API
- PostgreSQL with `wal_level=logical`
- ElectricSQL
- Optional Relay tunnel service

## Prerequisites

- Docker Engine with Docker Compose v2
- A DNS record for `DOMAIN` pointing at the machine
- Open inbound ports 80 and 443, unless another reverse proxy terminates TLS
- At least 2 GB RAM; 4 GB is safer for production

## 1. Configure environment

```bash
cp .env.example .env
```

Edit `.env` and set at least these values:

```bash
DOMAIN=vibe-kanban.example.com
SERVER_PUBLIC_BASE_URL=https://vibe-kanban.example.com
VKT_IMAGE_TAG=latest
VIBEKANBAN_REMOTE_JWT_SECRET=<base64 secret>
DB_PASSWORD=<url-safe password>
ELECTRIC_ROLE_PASSWORD=<url-safe password>
```

Generate compatible secrets:

```bash
# JWT secret: must decode to at least 32 bytes.
openssl rand -base64 48

# Database passwords are embedded in connection URLs, so use URL-safe hex.
openssl rand -hex 24
openssl rand -hex 24
```

Configure at least one authentication method:

- OAuth: set GitHub, Google, or Zoho client ID/secret variables.
- Bootstrap local auth: set `SELF_HOST_LOCAL_AUTH_EMAIL` and `SELF_HOST_LOCAL_AUTH_PASSWORD`.

For local auth, add values like:

```bash
SELF_HOST_LOCAL_AUTH_EMAIL=admin@example.com
SELF_HOST_LOCAL_AUTH_PASSWORD=<strong password>
```

Local auth is useful for initial setup, but treat it as a bootstrap credential and use a strong password.

## 2. Start the stack

```bash
docker compose up -d
```

Watch startup:

```bash
docker compose ps
docker compose logs -f remote-server electric
```

Open `https://$DOMAIN`. The remote server should show the Vibe Kanban Team login page.

## Optional: enable relay/tunnel support

The compose file includes `relay-server` behind a Compose profile and Caddy proxies the relay paths under the main domain.

```bash
docker compose --profile relay up -d
```

Relay routes:

- `https://$DOMAIN/v1/relay*`
- `https://$DOMAIN/relay/h*`

This mirrors the Helm chart's `relay.proxyUnderRemoteIngress` mode, so the same remote image can run without a relay-specific frontend build.

## Updating

Pin `VKT_IMAGE_TAG` in `.env` to a release tag for controlled production rollouts. To update:

```bash
docker compose pull
docker compose up -d
```

If you use `latest`, this pulls the newest published stable image.

## Backup and restore

Back up PostgreSQL:

```bash
docker compose exec -T remote-db pg_dump -U remote remote > backup_$(date +%Y%m%d).sql
```

Restore into an empty database volume:

```bash
docker compose exec -T remote-db psql -U remote remote < backup_YYYYMMDD.sql
```

The persistent volumes are:

- `remote-db-data` — PostgreSQL data
- `electric-data` — Electric persistent state
- `caddy-data` / `caddy-config` — Caddy certificates and config state

## Troubleshooting

### Remote server exits immediately

Check logs:

```bash
docker compose logs remote-server
```

Common causes:

- `VIBEKANBAN_REMOTE_JWT_SECRET` is not valid base64 or decodes to fewer than 32 bytes.
- No authentication provider is configured.
- `DB_PASSWORD` or `ELECTRIC_ROLE_PASSWORD` contains URL-unsafe characters.

### Electric cannot connect

Electric starts after `remote-server` is healthy because the remote server runs migrations and sets the `electric_sync` role password. If Electric still fails:

```bash
docker compose logs electric
docker compose restart electric
```

Ensure `ELECTRIC_ROLE_PASSWORD` is unchanged from the first run unless you intentionally rotated it.

### Caddy cannot obtain a certificate

Verify DNS and firewall rules:

```bash
dig +short "$DOMAIN"
docker compose logs caddy
```

For private-network deployments without public ACME, replace `standalone/Caddyfile` with your internal TLS or reverse-proxy policy.
