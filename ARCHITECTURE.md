# Dual Submodule Architecture

## Overview

This repository maintains **two independent versions** of Vibe Kanban:

1. **Frontend/NPM Package** (`vibe-kanban/`) - Frozen at v0.1.14 for preferred UX
2. **Remote Server** (`vibe-kanban-remote/`) - Tracks latest upstream for server features

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│ vibe-kanban-cloud (this repo)                               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌─────────────────────┐      ┌─────────────────────┐      │
│  │ vibe-kanban/        │      │ vibe-kanban-remote/ │      │
│  │ (submodule)         │      │ (submodule)         │      │
│  │                     │      │                     │      │
│  │ Pinned: v0.1.14     │      │ Tracks: latest      │      │
│  │ Purpose: NPM pkg    │      │ Purpose: K8s deploy │      │
│  └─────────────────────┘      └─────────────────────┘      │
│           │                              │                  │
│           ▼                              ▼                  │
│  ┌─────────────────────┐      ┌─────────────────────┐      │
│  │ patches/frontend/   │      │ patches/remote/     │      │
│  │ - Old UX restore    │      │ - Remote configs    │      │
│  │ - Loops templates   │      │ - Server tweaks     │      │
│  └─────────────────────┘      └─────────────────────┘      │
│           │                              │                  │
│           └──────────┬───────────────────┘                  │
│                      ▼                                       │
│           ┌─────────────────────┐                           │
│           │ patches/common/     │                           │
│           │ - Shared patches    │                           │
│           └─────────────────────┘                           │
│                                                              │
├─────────────────────────────────────────────────────────────┤
│ Release Workflows:                                          │
│                                                              │
│  NPM: v{VERSION} → npm publish (uses vibe-kanban/)          │
│  Remote: remote-v{VERSION} → Docker image (uses -remote/)   │
└─────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
vibe-kanban-cloud/
├── vibe-kanban/                    # Frontend/NPM submodule
│   └── [Vibe Kanban v0.1.14]
├── vibe-kanban-remote/             # Remote server submodule
│   └── [Vibe Kanban latest]
├── patches/
│   ├── common/                     # Applied to both submodules
│   │   ├── series                  # List of common patches
│   │   └── *.patch
│   ├── frontend/                   # NPM/frontend-specific
│   │   ├── series
│   │   ├── 0003-update-loops-template-ids.patch
│   │   └── 0005-fix-restore-old-vibe-kanban-experience.patch
│   └── remote/                     # Remote server-specific
│       ├── series
│       └── *.patch (if any)
├── scripts/
│   ├── apply-patches.sh            # Apply patches to specified submodule
│   ├── update-vibe-kanban.sh       # Update frontend submodule
│   └── update-vibe-kanban-remote.sh # Update remote submodule
└── .gitlab/ci/
    ├── image-build.yml             # Uses vibe-kanban-remote/
    └── npm-publish.yml             # Uses vibe-kanban/
```

## Patch Application Strategy

### Patch Categories

1. **Common Patches** (`patches/common/`)
   - Applied to both submodules
   - Typically: build system fixes, shared configuration
   - Applied first, before specific patches

2. **Frontend Patches** (`patches/frontend/`)
   - Applied only to `vibe-kanban/` submodule
   - Currently: Old UX restoration, Loops template updates
   - Applied during NPM package builds

3. **Remote Patches** (`patches/remote/`)
   - Applied only to `vibe-kanban-remote/` submodule
   - Future: Remote-specific configurations, server optimizations
   - Applied during Docker image builds

### Patch Application Order

```bash
# For vibe-kanban/ (NPM builds):
1. Apply patches/common/* (if any)
2. Apply patches/frontend/*

# For vibe-kanban-remote/ (Docker builds):
1. Apply patches/common/* (if any)
2. Apply patches/remote/* (if any)
```

## Workflow Examples

### Updating NPM Package (Rarely)

```bash
# Update frontend submodule to a new upstream version
./scripts/update-vibe-kanban.sh v0.1.15

# Re-apply patches (may need manual conflict resolution)
./scripts/apply-patches.sh vibe-kanban

# Test and commit
git add vibe-kanban patches/frontend/
git commit -m "chore: update NPM package to v0.1.15"

# Release
git tag v0.1.15
git push origin v0.1.15
```

### Updating Remote Server (Frequently)

```bash
# Update remote submodule to latest upstream
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

### Creating a New Patch

#### For Frontend
```bash
cd vibe-kanban/
# Make changes
git add -A
git commit -m "fix: restore old UX"

# Export patch
git format-patch -1 -o ../patches/frontend/

# Add to series
echo "0006-new-frontend-patch.patch" >> ../patches/frontend/series

# Validate
cd ..
./scripts/apply-patches.sh vibe-kanban
```

#### For Remote Server
```bash
cd vibe-kanban-remote/
# Make changes
git add -A
git commit -m "feat: optimize remote server config"

# Export patch
git format-patch -1 -o ../patches/remote/

# Add to series
echo "0001-remote-optimization.patch" >> ../patches/remote/series

# Validate
cd ..
./scripts/apply-patches.sh vibe-kanban-remote
```

## CI/CD Integration

### NPM Publish Pipeline

**Trigger:** Tags matching `^v?[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$` (NOT `remote-*`)

**Process:**
```yaml
before_script:
  - git submodule update --init vibe-kanban  # Only frontend
  - ./scripts/apply-patches.sh vibe-kanban
script:
  - cd vibe-kanban && ./local-build.sh
  - npm publish
```

### Docker Image Build Pipeline

**Trigger:** Tags matching `^remote-v?[0-9]+\.[0-9]+\.[0-9]+([-.].*)?$`

**Process:**
```yaml
before_script:
  - git submodule update --init vibe-kanban-remote  # Only remote
  - ./scripts/apply-patches.sh vibe-kanban-remote
script:
  - docker build -f vibe-kanban-remote/crates/remote/Dockerfile ./vibe-kanban-remote
```

## Benefits of This Architecture

1. ✅ **Version Independence**: Frontend and remote server can evolve separately
2. ✅ **Clear Separation**: Different patch series avoid conflicts
3. ✅ **Selective Updates**: Update remote server without touching frontend
4. ✅ **Simplified CI/CD**: Each pipeline only clones/patches what it needs
5. ✅ **Reduced Conflicts**: Frontend patches don't interfere with remote updates
6. ✅ **Easy Rollback**: Independent git submodule refs for each component

## Migration from Single Submodule

### Current State (Before Migration)
```
vibe-kanban-cloud/
├── vibe-kanban/ → v0.1.14
└── patches/
    ├── series
    ├── 0003-update-loops-template-ids.patch
    └── 0005-fix-restore-old-vibe-kanban-experience.patch
```

### Migration Steps

1. **Add second submodule**
   ```bash
   git submodule add <upstream-repo> vibe-kanban-remote
   cd vibe-kanban-remote && git checkout v0.1.15
   ```

2. **Reorganize patches**
   ```bash
   mkdir -p patches/{common,frontend,remote}
   mv patches/*.patch patches/frontend/
   mv patches/series patches/frontend/series
   touch patches/common/series
   touch patches/remote/series
   ```

3. **Update scripts**
   - Modify `apply-patches.sh` to accept submodule argument
   - Create `update-vibe-kanban-remote.sh`

4. **Update CI/CD**
   - `.gitlab/ci/npm-publish.yml` → use `vibe-kanban/`
   - `.gitlab/ci/image-build.yml` → use `vibe-kanban-remote/`

5. **Update documentation**
   - `AGENTS.md`, `README.md`, `DEPLOY.md`

## Future Considerations

### Potential Common Patches

If you find yourself applying the same patch to both submodules:
- Move it to `patches/common/`
- Update both `series` files to exclude it from specific directories
- Example: Database migration fixes, build system updates

### When to Create Remote-Specific Patches

- Remote server performance optimizations
- K8s-specific configurations
- ElectricSQL integration tweaks
- Production logging/monitoring changes

### When to Keep Frontend Patches Separate

- UI/UX changes (already doing this)
- Frontend routing modifications
- Client-side feature flags
- Template/email customizations

## FAQ

**Q: Can I have different versions of the same file in both submodules?**
A: Yes! That's the whole point. Frontend can have old UX while remote has new features.

**Q: What if a common patch conflicts with a specific patch?**
A: Common patches are applied first. Specific patches can override or modify common changes.

**Q: Do I need to keep both submodules in sync?**
A: No! That's the beauty of this architecture. Update independently as needed.

**Q: How do I know which patches to put in common/?**
A: Start with none. Only move patches to common/ when you need the same change in both.

**Q: What happens if I forget to apply patches before building?**
A: CI/CD will apply them automatically. Locally, the build will use unpatched code (tests will catch issues).

## References

- [AGENTS.md](./AGENTS.md) - Repository workflow guidelines
- [RELEASE.md](./RELEASE.md) - Tag-based release process
- [DEPLOY.md](./DEPLOY.md) - Kubernetes deployment guide
