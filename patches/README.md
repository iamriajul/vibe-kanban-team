# Patch Directory Structure

This directory contains patches for downstream customizations to Vibe Kanban.

## Organization

```
patches/
├── common/          # Applied to both vibe-kanban/ and vibe-kanban-remote/
│   └── series
├── frontend/        # Applied only to vibe-kanban/ (NPM package)
│   ├── series
│   └── *.patch
└── remote/          # Applied only to vibe-kanban-remote/ (Docker image)
    ├── series
    └── *.patch
```

## Patch Categories

### Common Patches (`common/`)
Patches that need to apply to both the frontend NPM package and the remote server.
Examples: build system fixes, shared configuration changes.

### Frontend Patches (`frontend/`)
Patches specific to the NPM package (`npx vibe-kanban`).
Currently includes:
- `0005-fix-restore-old-vibe-kanban-experience.patch` - Restores v0.1.14 UX (disables migration prompts)

### Remote Server Patches (`remote/`)
Patches specific to the remote server deployment.
Currently includes:
- `0003-update-loops-template-ids.patch` - Custom Loops email template IDs

## Usage

Patches are applied automatically by CI/CD pipelines and the `scripts/apply-patches.sh` script.

### Apply patches to a specific submodule:

```bash
# Frontend (vibe-kanban/)
./scripts/apply-patches.sh vibe-kanban

# Remote server (vibe-kanban-remote/)
./scripts/apply-patches.sh vibe-kanban-remote
```

### Creating a new patch:

#### For frontend:
```bash
cd vibe-kanban/
# Make your changes
git add -A
git commit -m "fix: your change description"
git format-patch -1 -o ../patches/frontend/
echo "NNNN-your-patch-name.patch" >> ../patches/frontend/series
```

#### For remote server:
```bash
cd vibe-kanban-remote/
# Make your changes
git add -A
git commit -m "feat: your change description"
git format-patch -1 -o ../patches/remote/
echo "NNNN-your-patch-name.patch" >> ../patches/remote/series
```

## Migration Notes

**Previous structure** (removed):
- All patches were in the root `patches/` directory
- Single `patches/series` file
- Applied to single `vibe-kanban/` submodule

**New structure** (current):
- Patches organized by target: `common/`, `frontend/`, `remote/`
- Separate `series` files for each category
- Support for dual submodules: `vibe-kanban/` and `vibe-kanban-remote/`

## See Also

- [ARCHITECTURE.md](../ARCHITECTURE.md) - Dual submodule architecture overview
- [scripts/apply-patches.sh](../scripts/apply-patches.sh) - Patch application script
