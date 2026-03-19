# Repository Guidelines

> **Rules for this file** (apply to both `CLAUDE.md` and `AGENTS.md`):
> 1. **Sync**: both files must be identical. Update both in the same commit.
> 2. **Size**: max 200 lines, target ~150. If exceeding, condense — don't split.
> 3. **Style**: no paraphrasing, no repetitive words. Every line earns its place.
> 4. **Currency**: when a code change alters architecture, ports, paths, env vars, secrets, or components described here — update this file in the same commit.

## Purpose

Downstream deployment and integration layer for Vibe Kanban. Owns Helm chart, K8s manifests, CI, patches. Not the upstream application source.

## Ownership

- `helm/vibe-kanban-cloud/`: Helm chart (Remote, Relay, ElectricSQL, Frontend — all optional)
- `k8s/`: environment-specific values (`values-production-{office,dol,hetzner,ovh}.yaml`)
- `scripts/`: `apply-patches.sh`, `update-vibe-kanban.sh`, `update-vibe-kanban-remote.sh`, `deploy.sh`
- `patches/{common,frontend,remote}/`: downstream patch stack
- `.gitlab-ci.yml`, `.gitlab/ci/`: build/release pipelines
- `vibe-kanban/` submodule (NPM package) / `vibe-kanban-remote/` submodule (Docker image)

## Submodule Architecture

- `vibe-kanban/` = full app: local backend (`crates/server/`, `crates/db/`, SQLite), frontend (`packages/web-core/`), AND `crates/remote/`. Built as NPM package.
- `vibe-kanban-remote/` = separate deployment ref for `crates/remote/` only. Tracks latest upstream. Built as Docker image.

**Patch targeting**: local backend/UI → `patches/frontend/` (applied to `vibe-kanban/`). Remote/cloud server → `patches/remote/` (applied to `vibe-kanban-remote/`).

## Agent Operating Model

1. Deployment/integration first. Prefer `helm/`, `k8s/`, `scripts/`, CI, `patches/`.
2. Submodule edits only as intermediate steps to generate patches.
3. Never leave durable changes only in submodule working tree.
4. **Every change must pass verification before committing** — see Development Workflow.
5. See [ARCHITECTURE.md](./ARCHITECTURE.md) for dual submodule rationale.

## Development Workflow

Closed loop: **Edit → Verify → Commit**. Never commit unverified changes.

### Prerequisites

```bash
helm version || (curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash)
which cargo || (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env")
sudo apt-get install -y libssl-dev libsqlite3-dev libclang-dev pkg-config 2>/dev/null
```

### Patch Creation

**Frontend/NPM**: edit `vibe-kanban/` → commit → `git -C vibe-kanban format-patch -1 -o ../patches/frontend/` → update `series` → verify.

**Remote**: same flow with `vibe-kanban-remote/` and `patches/remote/`.

### Verify (mandatory before every commit)

**Helm chart or values changes** — template all environments:
```bash
for f in k8s/values-production-*.yaml; do
  [[ "$f" == *-secrets* ]] && continue
  echo "--- $f ---"
  secrets="${f%.yaml}-secrets.yaml"
  args=(-f "$f"); [[ -f "$secrets" ]] && args+=(-f "$secrets")
  helm template test helm/vibe-kanban-cloud/ "${args[@]}" > /dev/null
done
```

**Patch changes** — apply, then compile-check:
```bash
git submodule update --init <submodule>
scripts/apply-patches.sh vibe-kanban          # frontend patches
scripts/apply-patches.sh vibe-kanban-remote   # remote patches
(cd vibe-kanban && cargo check)              # frontend — full workspace
(cd vibe-kanban-remote && cargo check)       # remote — remote + relay crates
```

**Shell script changes** — `bash -n scripts/<modified-script>.sh`

### Deploy (reference — not part of verification loop)

```bash
helm upgrade --install vibe-kanban ./helm/vibe-kanban-cloud/ \
  -n vibe-kanban-cloud -f k8s/values-production-office.yaml
```

## Helm Chart Components

| Component | Port | Toggle |
|-----------|------|--------|
| Remote Server | 8081 | always on |
| Relay Tunnel | 8082 | `relay.enabled` |
| ElectricSQL | 3000 (internal) | `electric.enabled` |
| Frontend (sysbox) | 13500 (app), 13337 (code-server) | `frontend.enabled` |

### Frontend Pod

Sysbox container with systemd PID 1. Runs code-server + Vibe Kanban + Claude Code + Codex.
- `runtimeClassName: sysbox-runc`, `hostUsers: false`, `runAsUser: 0`
- `VSCODE_PROXY_URI` for port proxying; `port-url <port>` script at `/usr/local/bin/`
- AI skill `expose-port` at `~/.claude/skills/` and `~/.agents/skills/`
- Env propagation: container → `/etc/default/vibe-kanban-env` (systemd) + `~/.bashrc.d/` (shells)
- Skel copied from `/etc/skel` on first boot (PVC prevents `useradd` from doing it)

### Auth (oauth2-proxy)

Google OAuth `@community.example.com`. Per-cluster ingress annotations via `frontend.auth.protectedIngressAnnotations`:
- nginx: `auth-url`/`auth-signin` annotations
- Traefik: `createTraefikMiddleware: true` + `router.middlewares` annotation

### VPN (Hetzner only)

WireGuard + iptables kill switch + RFC1918 block. Sudo locked for network tools. Creds via gitignored secrets overlay. `required()` enforced — Helm errors if creds missing.

## Environments

| File | Cluster | Namespace | Notes |
|------|---------|-----------|-------|
| `k8s/values-production-office.yaml` | 192.168.100.76 (MicroK8s) | vibe-kanban-cloud | Dual domains, nginx ingress |
| `k8s/values-production-dol.yaml` | 165.101.23.66 (MicroK8s) | vibe-kanban | Traefik ingress |
| `k8s/values-production-hetzner.yaml` | TBD | vibe-kanban | VPN enforced |
| `k8s/values-production-ovh.yaml` | OVH | — | Existing |

## TLS

Single `cert-manager-global` ClusterIssuer with `dnsZones` solver selectors — `community.example.com` and `community.example.dev` route to different Cloudflare tokens automatically.

## Security and Secrets

**Rule**: committed values use `secretKeyRef`. Real credentials go in gitignored overlays.

| Pattern | Committed | Purpose |
|---------|-----------|---------|
| `k8s/values-production-*.yaml` | Yes | Secret refs via `secretKeyRef` |
| `k8s/*-secrets.yaml` | No | Actual credentials, deploy with `-f` |
| `k8s/*-secrets.yaml.example` | Yes | Template with empty values |

Helm-managed secrets (`resource-policy: keep`): `vibe-kanban-claude-code` (uses `lookup` to preserve Lens edits), `vibe-kanban-vpn`.

Exception: [publish-credentials.bashrc](scripts/publish-credentials.bashrc) — inline credentials, documented.

**Gitignore** (do not modify): `values-production.yaml`, `*-secrets.yaml`, `*-secret.yaml`, `.env*`

## Commit Conventions

Conventional Commits (`fix:`, `feat:`, `docs:`, `ci:`, `chore:`). Describe deployment impact. Include verification results in PR descriptions.

## Gotchas

- `{{ "{{port}}" }}` to escape `{{port}}` in Helm templates (VSCODE_PROXY_URI)
- `set -euo pipefail` + `read -r -d ''` = script death (read returns 1 on EOF)
- ConfigMap updates need `rollout restart` — pods don't auto-restart
- Container env vars don't reach systemd services or login shells — use `EnvironmentFile` + `.bashrc.d/`
- `hostUsers: false` required for sysbox on containerd 2.x / Ubuntu 24.04+
- `cp -rn /etc/skel/. /home/coder/` needed because PVC mount blocks `useradd` skel copy
