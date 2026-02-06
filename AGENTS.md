# Repository Guidelines

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
- `scripts/`: operational helpers (`apply-patches.sh`, `update-vibe-kanban.sh`, `deploy.sh`).
- `patches/` and `patches/series`: downstream patch architecture.
- `.gitlab-ci.yml` and `.gitlab/ci/`: build/release pipeline behavior.
- `vibe-kanban/` submodule pointer (which upstream commit/tag we track).

## What This Repository Does Not Own
- Upstream implementation policy for backend/frontend internals.
- Upstream coding conventions beyond what is required to produce a downstream patch.

If work must happen inside `vibe-kanban/`, use `vibe-kanban/AGENTS.md` for
implementation guidance there, then return to this repo workflow to persist
changes as patch files.

## Agent Operating Model
1. Treat this repo as deployment/integration first.
2. Prefer edits in `helm/`, `k8s/`, `scripts/`, CI config, docs, and `patches/`.
3. Use `vibe-kanban/` direct edits only as an intermediate step to generate/update patches.
4. Never leave durable behavior changes only in submodule working tree state.
5. Keep downstream patch stack small, explicit, and reproducible.

## Mandatory Patch Architecture
Downstream app behavior changes must be represented in `patches/*.patch` and
ordered in `patches/series`.

CI expectation:
- patch series is applied to `vibe-kanban/` before image build.

Required workflow for app behavior changes:
1. Make the code change in `vibe-kanban/`.
2. Commit in submodule (local temporary commit is acceptable for patch export).
3. Export patch: `git -C vibe-kanban format-patch -1 -o ../patches`.
4. Add/update filename in `patches/series` in exact apply order.
5. Validate: `scripts/apply-patches.sh`.
6. Commit patch artifacts in this repo (`patches/*`, `patches/series`, and related deployment changes).

## Common Repository Workflows

### 1) Deployment/config change (no app code change)
- Edit Helm/K8s/CI/scripts/docs in this repository.
- Validate rendered/manifests or command syntax as appropriate.
- Commit only downstream deployment/integration files.

### 2) Upstream version bump
- Update submodule ref: `scripts/update-vibe-kanban.sh <tag-or-commit>`.
- Re-apply/refresh downstream patch stack.
- Ensure `patches/series` still applies cleanly and in order.
- Commit updated submodule pointer plus any patch refresh.

### 3) Downstream app behavior change
- Implement in `vibe-kanban/` only to generate patch artifacts.
- Persist final change in `patches/` and `patches/series`.
- Verify patch application with `scripts/apply-patches.sh`.

## Build, Test, and Deployment Commands
Run from repository root unless noted.

- `scripts/apply-patches.sh`: apply `patches/series` onto submodule.
- `scripts/update-vibe-kanban.sh <tag-or-commit>`: move submodule to target upstream ref.
- `scripts/deploy.sh <commit-sha>`: deploy specific image tag.
- `helm upgrade --install vibe-kanban ./helm/vibe-kanban-cloud -n vibe-kanban-cloud -f values-production.yaml`: deploy/update chart.

When patching app code, useful upstream checks are run from `vibe-kanban/`:
- `pnpm run lint`
- `pnpm run check`
- `cargo test --workspace`

## Commit and PR Expectations
- Use Conventional Commits (`fix:`, `feat:`, `docs:`, `ci:`, `chore:`).
- Keep commits focused on one operational concern.
- Describe deployment impact clearly (image tag, chart values, secrets, patches, submodule bumps).
- Include verification commands run and results in PR description.

## Security and Secrets
- Never commit secrets or inline credentials.
- Use Kubernetes secrets via `secretKeyRef`.
- `values-production.yaml`, `*-secret.yaml`, and `.env*` are intentionally ignored; keep it that way.
