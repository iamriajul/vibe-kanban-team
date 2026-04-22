# Repository Guidelines

> **Rules for this file** (apply to both `CLAUDE.md` and `AGENTS.md`):
> 1. **Sync**: both files must be identical. Update both in the same commit.
> 2. **Size**: max 200 lines, target ~150. If exceeding, condense — don't split.
> 3. **Style**: no paraphrasing, no repetitive words. Every line earns its place.
> 4. **Currency**: when architecture, paths, env vars, release flows, or owned components change — update this file in the same commit.

## Purpose

Downstream deployment and integration layer for Vibe Kanban. Owns the Helm chart, downstream patch stack, helper scripts, and release wiring. Not the upstream application source.

## Ownership

- `helm/vibe-kanban-team/`: Helm chart for Remote, Relay, ElectricSQL, and optional Frontend
- `.github/workflows/`: GitHub Actions for image/chart/npm releases and nightly upstream checks
- `scripts/`: `apply-patches.sh`, `update-vibe-kanban.sh`, `deploy.sh`, `publish-npm.sh`, `nightly-check-release.sh`
- `patches/`: linear downstream patch stack (`series` + `*.patch`)
- `vibe-kanban/`: single upstream submodule for frontend, backend, remote, and relay

## Shared Submodule Model

- `vibe-kanban/` is the only upstream checkout.
- All downstream patches live directly in `patches/`.
- `patches/series` is the only ordering source. Patches apply top to bottom.
- `scripts/apply-patches.sh [repo]` applies the full downstream stack.
- `scripts/update-vibe-kanban.sh` is the only manual submodule bump entrypoint.

## Current Release State

- GitHub Actions own the checked-in release automation.
- `remote-v*` tags build Remote and Relay images, publish them to GHCR, optionally mirror them to Docker Hub, and publish the Helm chart to GHCR as an OCI artifact.
- `v*` tags publish the `vibe-kanban-team` npm package via `scripts/publish-npm.sh`.
- `nightly-release-check.yml` runs on schedule for `frontend` and `remote`, compares upstream tags, verifies patch applicability, updates submodule + patch metadata, and pushes commit/tag for release workflows.
- Manual workflow dispatch must target an existing `git_ref`; versions are derived from that ref.
- Keep tag naming stable:
  - frontend/npm: `v<upstream-semver>-<YYYYMMDDHHmmss>`
  - remote/relay: `remote-v<upstream-semver>`

## Agent Operating Model

1. Deployment and integration first. Prefer `helm/`, `scripts/`, `patches/`, release docs.
2. Submodule edits are intermediate only. Durable changes belong in patches or top-level repo files.
3. Never leave final changes only in the submodule working tree.
4. Every change must pass verification before committing.
5. See [ARCHITECTURE.md](./ARCHITECTURE.md) for the shared-reference patch model.

## Development Workflow

Closed loop: **Edit → Verify → Commit**. Never commit unverified changes.

### Prerequisites

```bash
helm version || (curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash)
which cargo || (curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y && . "$HOME/.cargo/env")
sudo apt-get install -y libssl-dev libsqlite3-dev libclang-dev pkg-config 2>/dev/null
```

### Patch Creation

Edit `vibe-kanban/` → commit → `git -C vibe-kanban format-patch -1 -o ../patches/` → rename to the next linear `NNNN-...patch` slot → append to `patches/series` → verify.

### Verify (mandatory before every commit)

**Helm chart changes**:
```bash
helm template test helm/vibe-kanban-team/ \
  -f helm/vibe-kanban-team/values-example.yaml > /dev/null
```

**Patch or submodule changes**:
```bash
git submodule update --init vibe-kanban
git -C vibe-kanban reset --hard HEAD
scripts/apply-patches.sh
(cd vibe-kanban && cargo check --manifest-path crates/relay-tunnel/Cargo.toml)
```

Run full-workspace or private-dependency checks explicitly when needed and document blockers.

**Shell script changes**:
```bash
bash -n scripts/<modified-script>.sh
```

### Deploy (reference)

```bash
helm upgrade --install vibe-kanban ./helm/vibe-kanban-team \
  -n vibe-kanban-team -f helm/vibe-kanban-team/values-example.yaml
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
- App env: `VIBE_KANBAN_EDITOR_TYPE`, `VIBE_KANBAN_CODE_SERVER_URL`, `VIBE_KANBAN_BYPASS_ONBOARDING`
- Skel copied from `/etc/skel` on first boot

## Security and Secrets

Committed values should reference secrets via `secretKeyRef`. Real credentials belong in untracked overlays or deployment-time secret creation steps.

Local publish credentials should stay in an untracked file outside committed history.

Nightly release automation expects repository secrets:
- `NIGHTLY_RELEASE_PUSH_TOKEN`: PAT/fine-grained token with `contents:write` to push commits + tags (tag pushes trigger release workflows)
- `DISCORD_WEBHOOK_URL`: Discord webhook used for patch-failure alerts

NPM release automation uses npm trusted publishing / OIDC for `.github/workflows/publish-npm.yml`; no `NPM_TOKEN` is required in Actions. `scripts/publish-npm.sh` still supports `NPM_PUBLISH_AUTH=token` for local fallback.

**Gitignore** (do not modify): `values-production.yaml`, `*-secrets.yaml`, `*-secret.yaml`, `.env*`

## Commit Conventions

Use Conventional Commits (`fix:`, `feat:`, `docs:`, `ci:`, `chore:`). Include verification results in PR descriptions.

## Gotchas

- `{{ "{{port}}" }}` escapes `{{port}}` in Helm templates
- `set -euo pipefail` + `read -r -d ''` exits on EOF
- ConfigMap updates need `rollout restart`
- Container env vars do not reach systemd services or login shells; use `EnvironmentFile` + `.bashrc.d/`
- `hostUsers: false` is required for sysbox on containerd 2.x / Ubuntu 24.04+
- `cp -rn /etc/skel/. /home/coder/` is needed because PVC mounts block `useradd` skel copy
