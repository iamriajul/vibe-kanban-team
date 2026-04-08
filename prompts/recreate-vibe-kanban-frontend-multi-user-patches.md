# Prompt: Recreate Vibe Kanban Frontend Multi-User Patch Stack (From Scratch)

Use this prompt when upgrading to a new major upstream `vibe-kanban` release and rebuilding our downstream frontend patch stack without relying on old patch hunks.

## Goal
Recreate the current downstream behavior as a clean, minimal patch stack in this repo (`vibe-kanban-cloud`) using patch architecture only.

Canonical output patch stack (frontend):
1. `0001-feat-support-browser-scoped-auth-sessions-and-per-us.patch`
2. `0002-feat-require-workspace-auth-and-add-admin-scoped-creator-visibility.patch`

Do **not** leave durable behavior only in submodule working tree state.

---

## 1) Intentions
1. Support browser/session-scoped auth in shared/web deployment mode.
2. Allow concurrent authenticated users in one deployment (per-session identity, not global singleton auth).
3. Preserve one shared workspace pool while improving user focus in Workspaces UI.
4. Lock non-admin users to their own workspaces in Workspaces screen UX.
5. Allow admins to inspect all creators via Creator filter UI.
6. Set Git commit identity from authenticated user context (name/email) so commits are attributable per user.

---

## 2) Decisions Made
1. Patch architecture is source of truth (not submodule commits/pointers).
2. Streamlined stack to two frontend patches for maintainability.
3. Workspaces access model:
   - Shared mode requires login for workspace APIs.
   - No strict org-level workspace ACL hardening was added in this scope.
   - Non-admin users do not see Creator filter UI and are effectively `Mine` in Workspaces screen.
   - Non-admin users may still inspect colleagues' workspaces indirectly via Kanban dashboard/task navigation.
   - Admin users retain Creator filter (`Mine`/`All`/specific creators).
4. Workspaces layout must avoid React hook-order regressions on unauthenticated hard-refresh.
5. Keep behavior extensible for future org-security hardening if needed.

---

## 3) Critical Reproduction Information

### Files/areas covered by Patch 0001 (session + git identity foundation)
- Rust backend/session/auth + terminal/execution context:
  - `crates/server/src/middleware/auth_session.rs`
  - `crates/server/src/middleware/mod.rs`
  - `crates/server/src/routes/mod.rs`
  - `crates/server/src/routes/oauth.rs`
  - `crates/server/src/routes/terminal.rs`
  - `crates/local-deployment/src/container.rs`
  - `crates/local-deployment/src/lib.rs`
  - `crates/local-deployment/src/pty.rs`
  - `crates/services/src/services/auth.rs`
  - `crates/services/src/services/oauth_credentials.rs`
  - `crates/services/src/services/remote_client.rs`
  - `crates/git/src/cli.rs`
  - `crates/git/src/lib.rs`

### Files/areas covered by Patch 0002 (workspace auth + UI behavior)
- Shared-mode workspace auth gate:
  - `crates/server/src/routes/task_attempts.rs`
- Frontend config/user system plumbing:
  - `packages/local-web/src/app/providers/ConfigProvider.tsx`
  - `packages/web-core/src/shared/hooks/useUserSystem.ts`
  - `packages/web-core/src/shared/providers/WorkspaceProvider.tsx`
  - `packages/web-core/src/shared/hooks/useWorkspaces.ts`
- Workspaces UX/auth behavior:
  - `packages/web-core/src/pages/workspaces/WorkspacesLayout.tsx`
  - `packages/web-core/src/pages/workspaces/WorkspacesSidebarContainer.tsx`

### Behavioral requirements to preserve
1. In shared mode, unauthenticated users cannot use workspace APIs and see login-required UI.
2. Hard-refreshing `/workspaces/create` unauthenticated must not throw React hook-order errors.
3. Non-admin: no Creator filter control; effective filter is `Mine` for direct Workspaces screen listing.
4. Non-admin: colleagues' workspaces remain reachable indirectly from Kanban dashboard/task flows.
5. Admin: Creator filter shown and functional across users.
6. Git commits from workspace/agent flow use logged-in user identity.

---

## 4) Rebuild Procedure (for a new major release)

1. Update submodule to target upstream release.
2. Ensure clean baseline:
   - `git -C vibe-kanban reset --hard`
   - `git -C vibe-kanban clean -fd`
3. Rebuild Patch 0001:
   - Implement session-scoped auth + git identity behavior in the 0001 file set.
   - Commit locally in submodule (temporary commit acceptable).
   - Export patch: `git -C vibe-kanban format-patch -1 -o ../patches/`
   - Rename it into the next `NNNN-...patch` slot and update `patches/series`.
4. Rebuild Patch 0002 on top of 0001:
   - Implement shared-mode workspace auth requirement + WorkspacesLayout auth rendering + admin-scoped creator visibility logic.
   - Ensure non-admin forced `Mine`, admin retains dropdown.
   - Commit locally in submodule.
   - Export patch and name as `0002-...patch`, update series.
5. Validate patch stack reproducibility from clean clone/worktree:
   - Apply series to clean `vibe-kanban` checkout.
   - Confirm apply order succeeds with no rejects.
6. Validate code health:
   - `pnpm --filter @vibe/web-core run check`
   - (Recommended) `pnpm --filter @vibe/local-web run check`
   - (Recommended) `pnpm run web-core:format`
7. Commit only patch artifacts in this repo:
   - `patches/0001-...patch`
   - `patches/0002-...patch`
   - `patches/series`

---

## 5) Conflict-Avoidance Rules
1. Do not commit submodule pointer updates as the durable solution for behavior changes.
2. Keep each patch concern-focused (foundation in 0001, workspace/auth UX in 0002).
3. If upstream changed the same files, re-derive intent semantically (do not blindly replay old hunks).
4. Validate hook-order safety after auth gating changes in React components.
5. Validate both admin and non-admin UX paths explicitly.

---

## 6) Manual QA Checklist
1. Shared mode: login in browser A does not implicitly authenticate browser B.
2. Unauthenticated direct hard-refresh on `/workspaces/create` shows login-required UI without runtime hook errors.
3. Admin account sees Creator filter and can view all users.
4. Non-admin account does not see Creator filter and only sees own workspaces in direct Workspaces screen listing.
5. Non-admin can still navigate indirectly to colleagues' workspaces through Kanban dashboard/task-level entry points.
6. Kanban/task-level workspace visibility remains intact for collaboration context.
7. Git commit author/committer reflects authenticated user identity.
