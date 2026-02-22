# Dual Submodule Migration Summary

## What Was Implemented

Successfully migrated from single submodule to dual submodule architecture, enabling independent versioning of frontend (NPM package) and remote server deployments.

## Changes Made

### 1. Submodule Structure
**Before:**
```
vibe-kanban-cloud/
└── vibe-kanban/  @ v0.1.14
```

**After:**
```
vibe-kanban-cloud/
├── vibe-kanban/         @ v0.1.14 (NPM package - frozen)
└── vibe-kanban-remote/  @ v0.1.18 (Remote server - tracks latest)
```

### 2. Patch Organization
**Before:**
```
patches/
├── series
├── 0003-update-loops-template-ids.patch
└── 0005-fix-restore-old-vibe-kanban-experience.patch
```

**After:**
```
patches/
├── README.md
├── common/
│   └── series (empty)
├── frontend/
│   ├── series
│   └── 0005-fix-restore-old-vibe-kanban-experience.patch
└── remote/
    ├── series
    └── 0003-update-loops-template-ids.patch
```

### 3. Scripts Updated
- ✅ `scripts/apply-patches.sh` - Now accepts submodule argument
- ✅ `scripts/update-vibe-kanban-remote.sh` - New script for remote updates
- ✅ `scripts/update-vibe-kanban.sh` - Unchanged (for frontend updates)

### 4. CI/CD Pipeline Changes
**NPM Publish (`npm-publish.yml`):**
- Initializes only `vibe-kanban/` submodule
- Applies frontend patches
- Builds from v0.1.14 codebase

**Docker Image Build (`image-build.yml`):**
- Initializes only `vibe-kanban-remote/` submodule
- Applies remote patches
- Builds from v0.1.18 codebase

### 5. Documentation Updated
- ✅ `ARCHITECTURE.md` - Complete dual submodule design document (NEW)
- ✅ `AGENTS.md` - Updated workflows for both submodules
- ✅ `patches/README.md` - Patch organization guide (NEW)

## Verification Steps

### Test Patch Application (Frontend)
```bash
cd /home/coder/scratch/opensource/vibe-kanban-cloud
git submodule update --init vibe-kanban
./scripts/apply-patches.sh vibe-kanban
```

Expected output:
```
Applying patches to vibe-kanban (category: frontend)
Step 1/2: No common patches to apply
Step 2/2: Applying frontend patches...
  [frontend] Applying: 0005-fix-restore-old-vibe-kanban-experience.patch
  [frontend] Applied 1 patch(es)
Patch application complete for vibe-kanban
```

### Test Patch Application (Remote)
```bash
cd /home/coder/scratch/opensource/vibe-kanban-cloud
git submodule update --init vibe-kanban-remote
./scripts/apply-patches.sh vibe-kanban-remote
```

Expected output:
```
Applying patches to vibe-kanban-remote (category: remote)
Step 1/2: No common patches to apply
Step 2/2: Applying remote patches...
  [remote] Applying: 0003-update-loops-template-ids.patch
  [remote] Applied 1 patch(es)
Patch application complete for vibe-kanban-remote
```

## Release Workflows

### NPM Package Release (Frontend - Rarely)
```bash
# Update frontend to new version (if needed)
./scripts/update-vibe-kanban.sh v0.1.15

# Re-apply patches
./scripts/apply-patches.sh vibe-kanban

# Test and commit
git add vibe-kanban patches/frontend/
git commit -m "chore: update NPM package to v0.1.15"

# Release
git tag v0.1.15
git push origin v0.1.15
```

CI will:
- Build NPM package from `vibe-kanban/` @ v0.1.15
- Apply frontend patches
- Publish to npm registry

### Remote Server Release (Frequently)
```bash
# Update remote to latest version
./scripts/update-vibe-kanban-remote.sh v0.1.20

# Re-apply patches
./scripts/apply-patches.sh vibe-kanban-remote

# Test and commit
git add vibe-kanban-remote patches/remote/
git commit -m "chore: upgrade remote server to v0.1.20"

# Release
git tag remote-v0.1.20
git push origin remote-v0.1.20
```

CI will:
- Build Docker image from `vibe-kanban-remote/` @ v0.1.20
- Apply remote patches
- Push to GitLab Container Registry
- Package Helm chart

## Current State

| Component | Submodule | Version | Patches Applied |
|-----------|-----------|---------|-----------------|
| NPM Package | `vibe-kanban/` | v0.1.14 | Frontend (old UX) |
| Remote Server | `vibe-kanban-remote/` | v0.1.18 | Remote (Loops templates) |

## Benefits Achieved

1. ✅ **Version Independence**: Frontend frozen at v0.1.14, remote at v0.1.18
2. ✅ **Selective Updates**: Can update remote without touching frontend
3. ✅ **Clear Separation**: Different patches for different purposes
4. ✅ **Reduced Conflicts**: Frontend patches don't interfere with remote updates
5. ✅ **Efficient CI/CD**: Each pipeline only clones/patches what it needs

## Next Steps

### Immediate Actions (Optional)
1. **Test the changes locally** by running verification steps above
2. **Push to remote** to trigger CI/CD validation
3. **Monitor pipelines** to ensure both NPM and Docker builds work

### Future Workflow
- **Keep frontend frozen** at v0.1.14 (unless UX changes are desired)
- **Update remote regularly** to get latest features:
  ```bash
  ./scripts/update-vibe-kanban-remote.sh v0.1.XX
  ./scripts/apply-patches.sh vibe-kanban-remote
  git commit -am "chore: upgrade remote server to v0.1.XX"
  git tag remote-v0.1.XX
  git push origin remote-v0.1.XX
  ```

## Rollback Plan (If Needed)

If issues arise, you can rollback by:

```bash
# Revert the implementation commit
git revert 7ad5d2d

# Revert the architecture doc
git revert 8975706

# Remove the submodule addition (from main repo)
cd /home/coder/scratch/opensource/vibe-kanban-cloud
git revert da5834a
```

This will restore the single submodule architecture.

## Files Changed

### New Files
- `ARCHITECTURE.md` - Design documentation
- `patches/README.md` - Patch usage guide
- `patches/common/series` - Common patches (empty)
- `patches/frontend/series` - Frontend patch list
- `patches/remote/series` - Remote patch list
- `scripts/update-vibe-kanban-remote.sh` - Remote update script
- `MIGRATION-SUMMARY.md` - This file

### Modified Files
- `.gitmodules` - Added vibe-kanban-remote submodule
- `.gitlab/ci/image-build.yml` - Use vibe-kanban-remote submodule
- `.gitlab/ci/npm-publish.yml` - Use vibe-kanban submodule + frontend patches
- `AGENTS.md` - Updated workflows
- `scripts/apply-patches.sh` - Support for both submodules

### Moved Files
- `patches/0005-*.patch` → `patches/frontend/0005-*.patch`
- `patches/0003-*.patch` → `patches/remote/0003-*.patch`

### Deleted Files
- `patches/series` - Replaced by category-specific series files
- `patches/0001-*.patch` - Obsolete (billing removal)
- `patches/0002-*.patch` - Obsolete (billing dependency)
- `patches/0004-*.patch` - Obsolete (runtime API base)

## Support

For questions or issues:
1. Review [ARCHITECTURE.md](./ARCHITECTURE.md) for design rationale
2. Check [patches/README.md](./patches/README.md) for patch workflows
3. See [AGENTS.md](./AGENTS.md) for repository guidelines
