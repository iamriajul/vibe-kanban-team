Read `AGENTS.md` at the repository root and follow it as the single source of instructions.

## Submodule Architecture (Critical)

- `vibe-kanban/` = the **full application**: local backend (`crates/server/`, `crates/db/` with SQLite), frontend (`packages/web-core/`), AND `crates/remote/` (the remote/cloud server code). Frozen at v0.1.14 for preferred UX. Built as NPM package.
- `vibe-kanban-remote/` = exists **for managing `vibe-kanban/crates/remote/` ref separately**, so the remote server can be deployed independently. Tracks latest upstream. Built as Docker image for K8s deployment.

**Key distinction**: `vibe-kanban-remote/` is NOT the "local backend". It is a separate deployment ref for the remote/cloud server. The local backend (SQLite, workspace creation, `crates/server/`, `crates/db/`) lives in `vibe-kanban/`.

### Patch targeting rules
- Changes to local backend code (SQLite migrations, `crates/db/`, `crates/server/`, workspace creation) → `patches/frontend/` (applied to `vibe-kanban/`)
- Changes to remote/cloud server (`crates/remote/`, PostgreSQL, Electric sync) → `patches/remote/` (applied to `vibe-kanban-remote/`)
- Frontend UI changes (`packages/web-core/`, `shared/types.ts`) → `patches/frontend/` (applied to `vibe-kanban/`)
