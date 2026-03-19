# Repository Guidelines

> **Sync rule**: `CLAUDE.md` and `AGENTS.md` must always have identical content. When either file is modified, copy the updated content to the other file in the same commit.

## Purpose of This Repository
This repository is the downstream deployment and integration layer for Vibe
Kanban.

It exists to:
- package and deploy Vibe Kanban on our infrastructure,
- manage Kubernetes/Helm/CI behavior,
- maintain downstream customizations as a patch stack.

It is not the upstream application source of truth.

## What This Repository Owns
- `helm/vibe-kanban-cloud/`: Helm chart and chart defaults.
- `k8s/`: cluster manifests and environment-specific Kubernetes resources.
- `scripts/`: operational helpers (`apply-patches.sh`, `update-vibe-kanban.sh`, `update-vibe-kanban-remote.sh`, `deploy.sh`).
- `patches/`: downstream patch architecture with subdirectories:
  - `patches/common/`: patches for both submodules
  - `patches/frontend/`: NPM package-specific patches
  - `patches/remote/`: remote server-specific patches
- `.gitlab-ci.yml` and `.gitlab/ci/`: build/release pipeline behavior.
- `vibe-kanban/` submodule pointer (NPM package, frozen at v0.1.14)
- `vibe-kanban-remote/` submodule pointer (remote server, tracks latest upstream)

## Submodule Architecture (Critical)

- `vibe-kanban/` = the **full application**: local backend (`crates/server/`, `crates/db/` with SQLite), frontend (`packages/web-core/`), AND `crates/remote/` (the remote/cloud server code). Frozen at v0.1.14 for preferred UX. Built as NPM package.
- `vibe-kanban-remote/` = exists **for managing `vibe-kanban/crates/remote/` ref separately**, so the remote server can be deployed independently. Tracks latest upstream. Built as Docker image for K8s deployment.

**Key distinction**: `vibe-kanban-remote/` is NOT the "local backend". It is a separate deployment ref for the remote/cloud server. The local backend (SQLite, workspace creation, `crates/server/`, `crates/db/`) lives in `vibe-kanban/`.

### Patch targeting rules
- Changes to local backend code (SQLite migrations, `crates/db/`, `crates/server/`, workspace creation) → `patches/frontend/` (applied to `vibe-kanban/`)
- Changes to remote/cloud server (`crates/remote/`, PostgreSQL, Electric sync) → `patches/remote/` (applied to `vibe-kanban-remote/`)
- Frontend UI changes (`packages/web-core/`, `shared/types.ts`) → `patches/frontend/` (applied to `vibe-kanban/`)

## What This Repository Does Not Own
- Upstream implementation policy for backend/frontend internals.
- Upstream coding conventions beyond what is required to produce a downstream patch.

If work must happen inside `vibe-kanban/` or `vibe-kanban-remote/`, use their
respective `AGENTS.md` files for implementation guidance, then return to this
repo workflow to persist changes as patch files in the appropriate directory.

## Agent Operating Model
1. Treat this repo as deployment/integration first.
2. Prefer edits in `helm/`, `k8s/`, `scripts/`, CI config, docs, and `patches/`.
3. Use submodule direct edits (`vibe-kanban/` or `vibe-kanban-remote/`) only as intermediate steps to generate/update patches.
4. Never leave durable behavior changes only in submodule working tree state.
5. Keep downstream patch stack small, explicit, and reproducible.
6. See [ARCHITECTURE.md](./ARCHITECTURE.md) for dual submodule design rationale.

## Mandatory Patch Architecture
Downstream app behavior changes must be represented as patches organized by target:
- `patches/common/` - patches for both submodules
- `patches/frontend/` - patches for NPM package (`vibe-kanban/`)
- `patches/remote/` - patches for remote server (`vibe-kanban-remote/`)

CI expectation:
- Frontend patches applied to `vibe-kanban/` before NPM publish
- Remote patches applied to `vibe-kanban-remote/` before Docker image build

Required workflow for app behavior changes:

**For frontend/NPM changes:**
1. Make code changes in `vibe-kanban/`.
2. Commit in submodule (local temporary commit is acceptable).
3. Export patch: `git -C vibe-kanban format-patch -1 -o ../patches/frontend/`.
4. Add filename to `patches/frontend/series` in apply order.
5. Validate: `scripts/apply-patches.sh vibe-kanban`.
6. Commit patch artifacts in this repo.

**For remote server changes:**
1. Make code changes in `vibe-kanban-remote/`.
2. Commit in submodule (local temporary commit is acceptable).
3. Export patch: `git -C vibe-kanban-remote format-patch -1 -o ../patches/remote/`.
4. Add filename to `patches/remote/series` in apply order.
5. Validate: `scripts/apply-patches.sh vibe-kanban-remote`.
6. Commit patch artifacts in this repo.

## Common Repository Workflows

### 1) Deployment/config change (no app code change)
- Edit Helm/K8s/CI/scripts/docs in this repository.
- Validate rendered/manifests or command syntax as appropriate.
- Commit only downstream deployment/integration files.

### 2) Upstream version bump (frontend/NPM)
- Update submodule: `scripts/update-vibe-kanban.sh <tag-or-commit>`.
- Re-apply frontend patches: `scripts/apply-patches.sh vibe-kanban`.
- Ensure `patches/frontend/series` still applies cleanly.
- Commit updated submodule pointer plus any patch refresh.

### 3) Upstream version bump (remote server)
- Update submodule: `scripts/update-vibe-kanban-remote.sh <tag-or-commit>`.
- Re-apply remote patches: `scripts/apply-patches.sh vibe-kanban-remote`.
- Ensure `patches/remote/series` still applies cleanly.
- Commit updated submodule pointer plus any patch refresh.

### 4) Downstream app behavior change
- Implement in appropriate submodule to generate patch artifacts.
- Persist in `patches/frontend/` or `patches/remote/` with updated series file.
- Verify patch application with `scripts/apply-patches.sh <submodule>`.

## Build, Test, and Deployment Commands
Run from repository root unless noted.

**Patch management:**
- `scripts/apply-patches.sh vibe-kanban`: apply frontend patches
- `scripts/apply-patches.sh vibe-kanban-remote`: apply remote server patches

**Submodule updates:**
- `scripts/update-vibe-kanban.sh <tag>`: update NPM package submodule
- `scripts/update-vibe-kanban-remote.sh <tag>`: update remote server submodule

**Deployment:**
- `scripts/deploy.sh <commit-sha>`: deploy specific image tag
- `helm upgrade --install vibe-kanban ./helm/vibe-kanban-cloud -n vibe-kanban-cloud -f values-production.yaml`: deploy/update chart

**Testing (run from appropriate submodule):**
- `pnpm run lint` - from `vibe-kanban/` or `vibe-kanban-remote/`
- `pnpm run check` - from `vibe-kanban/` or `vibe-kanban-remote/`
- `cargo test --workspace` - from `vibe-kanban/` or `vibe-kanban-remote/`

## Commit and PR Expectations
- Use Conventional Commits (`fix:`, `feat:`, `docs:`, `ci:`, `chore:`).
- Keep commits focused on one operational concern.
- Describe deployment impact clearly (image tag, chart values, secrets, patches, submodule bumps).
- Include verification commands run and results in PR description.

## Security and Secrets
- Never commit secrets or inline credentials. (exception: [publish-credentials.bashrc](scripts/publish-credentials.bashrc))
- Use Kubernetes secrets via `secretKeyRef`.
- `values-production.yaml`, `*-secret.yaml`, and `.env*` are intentionally ignored; keep it that way.
