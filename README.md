# Vibe Kanban Team

Open-source deployment and release layer for [Vibe Kanban](https://github.com/BloopAI/vibe-kanban).

This project has **four parts**:

| Part | What it is | Who uses it |
|------|-----------|-------------|
| **NPM Package** (`vibe-kanban-team`) | Desktop/web app that runs on your machine and connects to a remote server | Developers on the team |
| **Standalone Docker Compose** | Single-machine production stack with Caddy, Remote, PostgreSQL, ElectricSQL, and optional Relay | Self-hosters / small teams |
| **Helm Chart** (`vibe-kanban-team`) | Deploys the remote server, relay, and ElectricSQL to Kubernetes | Platform / DevOps engineers |
| **Server-Side** (Remote + Relay) | Backend API that stores projects, syncs data, and handles auth | Deployed by Docker Compose or the Helm chart |

---

## Table of Contents

- [Part 1 — NPM Package (Developer Desktop/Web App)](#part-1--npm-package-developer-desktopweb-app)
- [Standalone Docker Compose (Single-Machine Production)](#standalone-docker-compose-single-machine-production)
- [Part 2 — Helm Chart (Server Deployment)](#part-2--helm-chart-server-deployment)
- [Part 3 — Server-Side Components](#part-3--server-side-components)
- [Architecture](#architecture)
- [Downstream Feature Snapshot](#downstream-feature-snapshot)
- [Patch Stack (Downstream Changes)](#patch-stack-downstream-changes)
- [Upgrading Vibe Kanban](#upgrading-vibe-kanban)
- [Release Automation](#release-automation)
- [Troubleshooting](#troubleshooting)
- [License](#license)

---

## Part 1 — NPM Package (Developer Desktop/Web App)

The `vibe-kanban-team` NPM package is what developers run on their machines. It downloads and starts the Vibe Kanban frontend, which connects to your organization's remote server.

### Prerequisites

- **Node.js 18+** and `npm` (or `npx`) installed
- **A deployed remote server** — someone on your team must have deployed the Helm chart first (see [Part 2](#part-2--helm-chart-server-deployment))
- The remote server URL (e.g. `https://remote.vk.example.com`)
- *(Optional)* The relay server URL, if tunnels are enabled (e.g. `https://relay.vk.example.com`)

### Quick Start

Run the app with `npx`:

```bash
PORT=13479 \
VK_SHARED_API_BASE=https://remote.vk.example.com \
  npx --yes vibe-kanban-team
```

Then open `http://localhost:13479` in your browser.

### Setting Up a Shell Alias (Recommended)

Instead of typing environment variables every time, add an alias to your shell profile.

**macOS** (`~/.zprofile` or `~/.zshrc`):

```bash
alias vk="PORT=13479 VK_SHARED_API_BASE=https://remote.vk.example.com npx --yes vibe-kanban-team"
```

**Linux** (`~/.bashrc` or `~/.zshrc`):

```bash
alias vk="PORT=13479 VK_SHARED_API_BASE=https://remote.vk.example.com npx --yes vibe-kanban-team"
```

After saving, reload your shell (`source ~/.zshrc`) and simply run:

```bash
vk
```

If your organization also uses the relay for tunnels, include the relay URL:

```bash
alias vk="PORT=13479 VK_SHARED_RELAY_API_BASE=https://relay.vk.example.com VK_SHARED_API_BASE=https://remote.vk.example.com npx --yes vibe-kanban-team"
```

### Environment Variables (NPM Package)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `PORT` | No | `5233` | Port the local web UI listens on |
| `HOST` | No | `127.0.0.1` | Host/IP to bind to (`0.0.0.0` for all interfaces) |
| `VK_SHARED_API_BASE` | **Yes** | *(none)* | URL of your organization's remote server (e.g. `https://remote.vk.example.com`) |
| `VK_SHARED_RELAY_API_BASE` | No | *(none)* | URL of the relay server, if tunnels are enabled |
| `VIBE_KANBAN_EDITOR_TYPE` | No | *(none)* | Pre-configure the editor type during onboarding (e.g. `CODE_SERVER`) |
| `VIBE_KANBAN_CODE_SERVER_URL` | No | *(none)* | URL of a code-server instance (also accepts `CODE_SERVER_URL`) |
| `VIBE_KANBAN_BYPASS_ONBOARDING` | No | `false` | Set to `true` to skip the onboarding wizard |
| `VIBE_KANBAN_BROWSER_SCOPED_AUTH` | No | `true` | Set to `false` to persist OAuth credentials in the shared file path instead of browser-specific sessions |
| `XDG_DATA_HOME` | No | *(system default)* | Override the data directory location |

### Example: Running in the Background

```bash
PORT=13479 \
VK_SHARED_API_BASE=https://remote.vk.example.com \
  nohup npx --yes vibe-kanban-team > ~/.vibe-kanban.log 2>&1 &
```

---

## Standalone Docker Compose (Single-Machine Production)

For teams that do not run Kubernetes, this repository includes a production-oriented Docker Compose stack at the repository root:

- `docker-compose.yml` — Caddy, Remote, PostgreSQL, ElectricSQL, and optional Relay
- `.env.example` — required secrets and deployment settings
- `standalone/Caddyfile` — HTTPS reverse-proxy routing
- `STANDALONE.md` — full setup, update, backup, and troubleshooting guide

Quick start:

```bash
cp .env.example .env
# Edit .env, generate secrets, and configure at least one auth method.
docker compose up -d
```

Enable relay/tunnel support with:

```bash
docker compose --profile relay up -d
```

See [STANDALONE.md](./STANDALONE.md) before using this in production.

---

## Part 2 — Helm Chart (Server Deployment)

The Helm chart deploys the **remote server**, **ElectricSQL** (sync layer), and optionally the **relay server** and a **shared frontend** to a Kubernetes cluster.

### Prerequisites

- Kubernetes cluster (1.24+)
- Helm 3.x
- `kubectl` configured to access your cluster
- PostgreSQL 14+ with `wal_level=logical` — **or** use the built-in CloudNativePG (default, zero-config)
- cert-manager installed (see [cert-manager Setup](#cert-manager-setup) below)

### Quick Start (Built-in Database)

The chart ships with a built-in PostgreSQL cluster via CloudNativePG. No manual database setup, no secret creation — just install and go.

**1. Install the CloudNativePG operator** (once per cluster):

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/releases/download/v1.24.0/cnpg-1.24.0.yaml
```

**2. Create a values file:**

```bash
export CHART_REF="oci://ghcr.io/iamriajul/helm-charts/vibe-kanban-team"
export CHART_VERSION="<version>"   # e.g. 0.1.0

curl -fsSL \
  https://raw.githubusercontent.com/iamriajul/vibe-kanban-team/main/helm/vibe-kanban-team/values-example.yaml \
  -o values-production.yaml
```

Edit `values-production.yaml`. At minimum, set:

```yaml
global:
  domain: "vk.example.com"       # The hostname users will open
  ingressClassName: "nginx"       # Your ingress controller class
  tls:
    enabled: true
    clusterIssuer: "letsencrypt-prod"
```

**3. Deploy:**

```bash
helm upgrade --install vibe-kanban "${CHART_REF}" \
  --version "${CHART_VERSION}" \
  --namespace vibe-kanban-team \
  --create-namespace \
  -f values-production.yaml
```

**4. Set up DNS:**

Point two DNS records at your ingress controller:

```text
vk.example.com    -> ingress IP
*.vk.example.com  -> ingress IP
```

The chart automatically derives service hostnames from `global.domain`:

| Service | Hostname |
|---------|----------|
| Frontend | `vk.example.com` |
| Remote API | `remote.vk.example.com` |
| Relay | `relay.vk.example.com` |
| Code Server | `code.vk.example.com` |
| Port Proxy | `<port>-code.vk.example.com` |

The wildcard DNS record covers all derived subdomains and code-server port proxying. Relay uses path-based routing on `relay.<domain>` and does not need `*.relay.<domain>`.

**5. Tell your team to connect:**

Once deployed, share the remote URL with your team. Each developer runs:

```bash
VK_SHARED_API_BASE=https://remote.vk.example.com npx --yes vibe-kanban-team
```

### Quick Start (Bring Your Own PostgreSQL)

If you already have a PostgreSQL instance (RDS, CloudSQL, etc.), disable the built-in database and provide your own secrets.

**1. Prepare the database:**

```sql
-- Ensure wal_level=logical in postgresql.conf
-- CloudNativePG has this enabled by default

CREATE ROLE electric_sync WITH LOGIN PASSWORD 'your-electric-password' REPLICATION;
GRANT ALL PRIVILEGES ON DATABASE your_database TO electric_sync;
```

**2. Create Kubernetes secrets:**

```bash
kubectl create namespace vibe-kanban-team

# Database connection URLs
kubectl create secret generic vibe-kanban-db \
  --namespace vibe-kanban-team \
  --from-literal=url='postgres://user:pass@your-db-host:5432/remote' \
  --from-literal=electric-url='postgresql://electric_sync:pass@your-db-host:5432/remote?sslmode=disable'

# Application secrets
kubectl create secret generic vibe-kanban-secrets \
  --namespace vibe-kanban-team \
  --from-literal=jwt-secret="$(openssl rand -base64 32)" \
  --from-literal=electric-role-password='your-electric-password'

# OAuth credentials (at least one provider required)
kubectl create secret generic vibe-kanban-oauth \
  --namespace vibe-kanban-team \
  --from-literal=github-client-id='your-github-client-id' \
  --from-literal=github-client-secret='your-github-client-secret'
```

**3. Configure values:**

```yaml
postgres:
  enabled: false

config:
  existingSecrets:
    database:
      name: vibe-kanban-db          # keys: url, electric-url
    app:
      name: vibe-kanban-secrets     # keys: jwt-secret, electric-role-password
    oauth:
      name: vibe-kanban-oauth       # keys: github-client-id, github-client-secret
```

**4. Deploy** (same `helm upgrade --install` command as above).

### Helm Chart Values Reference

Inspect all available values:

```bash
helm show values "${CHART_REF}" --version "${CHART_VERSION}"
```

#### Required Server Environment Variables (BYO Database)

These are only needed when `postgres.enabled=false`. With the built-in CNPG database, all of these are auto-generated.

| Variable | Description |
|----------|-------------|
| `SERVER_DATABASE_URL` | PostgreSQL connection URL |
| `VIBEKANBAN_REMOTE_JWT_SECRET` | JWT secret for auth (generate with `openssl rand -base64 32`) |
| `ELECTRIC_ROLE_PASSWORD` | Password for the `electric_sync` database role |
| `GITHUB_OAUTH_CLIENT_ID` | GitHub OAuth client ID (or use Google/Zoho instead) |
| `GITHUB_OAUTH_CLIENT_SECRET` | GitHub OAuth client secret |

#### Optional Server Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `RUST_LOG` | `info` | Log level (`debug`, `info`, `warn`, `error`) |
| `SERVER_LISTEN_ADDR` | `0.0.0.0:8081` | Address the remote server binds to |
| `SERVER_PUBLIC_BASE_URL` | *(auto)* | Public URL for OAuth callbacks |
| `ALLOWED_EMAIL_DOMAINS` | *(none)* | Comma-separated list of allowed email domains for login |

#### Frontend Pod Environment Variables

When the optional shared frontend is deployed (`frontend.enabled=true`), these env vars can be set on the frontend container:

| Variable | Default | Description |
|----------|---------|-------------|
| `VIBE_KANBAN_EDITOR_TYPE` | *(none)* | Pre-configure editor type (e.g. `CODE_SERVER`) |
| `VIBE_KANBAN_CODE_SERVER_URL` | *(auto)* | URL of the code-server instance (also accepts `CODE_SERVER_URL`) |
| `VIBE_KANBAN_BYPASS_ONBOARDING` | `false` | Skip the onboarding wizard |
| `VIBE_KANBAN_BROWSER_SCOPED_AUTH` | `true` | Set `false` to persist OAuth credentials in the shared file path instead of browser-specific sessions |

### Relay Server (Optional)

The relay enables tunnel features. Enable it in your values file:

```yaml
relay:
  enabled: true
```

When `relay.proxyUnderRemoteIngress.enabled` is `true` (the default), relay endpoints are also available under the main remote API host at `/v1/relay` and `/relay/h`. This keeps frontend images reusable across environments.

### OAuth Setup

#### GitHub OAuth

1. Go to **GitHub → Settings → Developer settings → OAuth Apps**
2. Create a new OAuth App:
   - Homepage URL: `https://remote.vk.example.com`
   - Callback URL: `https://remote.vk.example.com/v1/oauth/callback/github`
3. Copy the Client ID and Client Secret into your Kubernetes secret

#### Google OAuth

1. Go to **Google Cloud Console → APIs & Services → Credentials**
2. Create an OAuth 2.0 Client ID:
   - Application type: Web application
   - Authorized redirect URI: `https://remote.vk.example.com/v1/oauth/callback/google`
3. Copy the Client ID and Client Secret

#### Zoho OAuth

1. Go to **Zoho API Console** (`https://api-console.zoho.com`)
2. Create a Server-based Application:
   - Authorized redirect URI: `https://remote.vk.example.com/v1/oauth/callback/zoho`
3. Set the following env vars: `ZOHO_OAUTH_CLIENT_ID`, `ZOHO_OAUTH_CLIENT_SECRET`
4. Optionally set `ZOHO_ACCOUNTS_URL` (e.g. `https://accounts.zoho.eu` for EU)

### cert-manager Setup

TLS certificates require cert-manager. Install it using the upstream Helm chart.

> **Note:** If you use MicroK8s, do **not** use `microk8s enable cert-manager`. Use the Helm chart instead.

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version "1.19.4" \
  --set crds.enabled=true

kubectl -n cert-manager rollout status deploy/cert-manager --timeout=180s
```

Create a ClusterIssuer (Cloudflare DNS-01 example — supports wildcard certificates):

```bash
kubectl -n cert-manager create secret generic cloudflare-dns-api-token \
  --from-literal=API_TOKEN='<cloudflare-api-token>'

kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: cert-manager-global
spec:
  acme:
    email: you@example.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: cert-manager-global-account-key
    solvers:
      - dns01:
          cloudflare:
            apiTokenSecretRef:
              name: cloudflare-dns-api-token
              key: API_TOKEN
EOF
```

Cloudflare token minimum permissions: `Zone:Read`, `DNS:Edit`.

### Private Image Registry

If your images are in a private registry:

```bash
kubectl create secret docker-registry registry-credentials \
  --namespace vibe-kanban-team \
  --docker-server='your-registry.example.com' \
  --docker-username='your-username' \
  --docker-password='your-token'
```

Then reference it in your values:

```yaml
imagePullSecrets:
  - name: registry-credentials
```

---

## Part 3 — Server-Side Components

The Helm chart deploys these backend components. You don't interact with them directly, but understanding them helps with debugging and configuration.

| Component | Port | Purpose |
|-----------|------|---------|
| **Remote Server** | 8081 | Core API — handles projects, auth, OAuth, workspaces |
| **Relay Server** | 8082 | Tunnel/relay for remote connections (optional) |
| **ElectricSQL** | 3000 | Real-time sync layer between frontend and PostgreSQL |
| **PostgreSQL** | 5432 | Persistent data store (built-in via CNPG or BYO) |

### How the Pieces Connect

```
Developer's Machine                     Kubernetes Cluster
┌──────────────────┐          ┌──────────────────────────────────────┐
│                  │          │                                      │
│  npx             │  HTTPS   │  ┌──────────────┐  ┌──────────────┐ │
│  vibe-kanban-    │─────────▶│  │   Remote     │  │  ElectricSQL │ │
│  team            │          │  │   Server     │──│  (Sync)      │ │
│                  │          │  │   :8081      │  │  :3000       │ │
│  (browser UI on  │          │  └──────┬───────┘  └──────┬───────┘ │
│   localhost)     │          │         │                  │         │
│                  │          │  ┌──────▼───────┐          │         │
└──────────────────┘          │  │   Relay      │          │         │
                              │  │   (optional) │          │         │
                              │  │   :8082      │          │         │
                              │  └──────────────┘          │         │
                              │                            │         │
                              └────────────────────────────┼─────────┘
                                                           │
                                                  ┌────────▼────────┐
                                                  │   PostgreSQL    │
                                                  │   (CNPG / RDS)  │
                                                  └─────────────────┘
```

---

## Architecture

### Repository Layout

```text
vibe-kanban-team/
├── vibe-kanban/              # Upstream submodule (shared checkout)
├── patches/
│   ├── series                # Linear patch order
│   └── *.patch               # Downstream patches
├── scripts/
│   ├── apply-patches.sh      # Apply the patch stack
│   ├── update-vibe-kanban.sh # Update the upstream submodule
│   ├── deploy.sh             # Deploy with a specific image tag
│   └── publish-npm.sh        # Build and publish the NPM package
├── helm/vibe-kanban-team/    # Helm chart
└── .github/workflows/        # CI/CD pipelines
```

---

## Downstream Feature Snapshot

Current upstream base: `v0.1.44-20260424091429`.

This distribution currently carries 32 downstream patches across 13 main feature and stability areas:

1. Helm-packaged Remote, Relay, ElectricSQL, and optional browser frontend deployment.
2. Shared browser-first frontend runtime with code-server and reusable workspace environments.
3. Workspace auth, browser-scoped sessions, and owner-aware standalone workspace handling.
4. Zoho OAuth support plus optional allowed-email-domain restrictions.
5. Kimi Code and Antigravity CLI executor support, opt-in Cladup support for Claude Code configurations, plus refreshed stable CLI pins for Claude Code, Codex, Gemini, Qwen, Copilot, and OpenCode, with Codex `npx` cache isolation for shared-cache workspaces.
6. GitLab merge request integration alongside existing GitHub flows.
7. Markdown preview controls in workspace change review.
8. Browser notifications for workspace and execution events.
9. R2-backed attachment storage for the remote service.
10. `VSCODE_PROXY_URI`, localhost link rewriting, and preview proxy support for managed frontend pods.
11. Release and deployment automation for npm, images, relay, and Helm chart publishing.
12. Operational stability fixes for relay builds, WebSocket keepalives, org selection, editor onboarding, and cloud UI behavior.
13. Project kanban restoration for self-hosted cloud deployments.

---

## Patch Stack (Downstream Changes)

Downstream changes are kept as an ordered patch series in `patches/` (similar to quilt). Both local scripts and CI apply the same stack.

### Creating a Patch

```bash
cd vibe-kanban
git checkout <upstream-tag>
# Make your change(s)
git add .
git commit -m "fix: <summary>"
git format-patch -1 -o ../patches
cd ..
```

Rename the patch into the next `NNNN-...patch` slot and add it to `patches/series`.

### Applying Patches Locally

```bash
scripts/apply-patches.sh
```

Keep the patch stack minimal and prefer upstreaming when possible.

---

## Upgrading Vibe Kanban

```bash
# 1. Update the upstream submodule
scripts/update-vibe-kanban.sh v1.4.0

# 2. Verify patches still apply
scripts/apply-patches.sh

# 3. Commit and push
git add .
git commit -m "chore: bump vibe-kanban to v1.4.0"
git push

# 4. Deploy the new build (after CI finishes)
scripts/deploy.sh <commit-sha>
```

---

## Release Automation

GitHub Actions handle all releases:

| Tag Format | What it triggers |
|------------|-----------------|
| `remote-v*` | Builds Remote + Relay container images, pushes to GHCR, publishes the Helm chart as an OCI artifact |
| `v*` | Publishes the `vibe-kanban-team` NPM package |

A nightly workflow checks for new upstream releases, verifies patches, and auto-publishes if everything passes.

For stable releases, the image workflow also updates the `latest` tag. Prereleases publish only their version tag.

---

## Troubleshooting

### Check Pod Status

```bash
kubectl get pods -n vibe-kanban-team
kubectl describe pod <pod-name> -n vibe-kanban-team
```

### View Logs

```bash
# Remote server
kubectl logs -n vibe-kanban-team -l app.kubernetes.io/name=vibe-kanban-team -f

# ElectricSQL
kubectl logs -n vibe-kanban-team -l app.kubernetes.io/component=electric -f
```

### ElectricSQL Health Check

```bash
kubectl port-forward -n vibe-kanban-team svc/<release>-electric 3000:3000
curl http://localhost:3000/v1/health
```

### NPM Package Not Connecting

1. Verify the remote server is reachable: `curl https://remote.vk.example.com/health`
2. Ensure `VK_SHARED_API_BASE` is set correctly (no trailing slash)
3. Check that OAuth is configured on the server (you need at least one provider)

---

## License

This deployment configuration is provided under the MIT License.
Vibe Kanban is licensed under the [BSL License](https://github.com/BloopAI/vibe-kanban/blob/main/LICENSE).
