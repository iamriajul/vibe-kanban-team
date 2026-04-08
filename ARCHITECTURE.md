# Shared Submodule Architecture

## Overview

This repository now manages Vibe Kanban through a single upstream reference:

1. `vibe-kanban/` is the only submodule.
2. NPM/frontend releases and Remote/Relay image releases share that git ref.
3. One linear downstream patch stack is applied to every build.

## Layout

```text
vibe-kanban-cloud/
├── vibe-kanban/              # Shared upstream checkout
├── patches/
│   ├── series                # Linear patch order
│   └── *.patch               # All downstream patches
├── scripts/
│   ├── apply-patches.sh      # apply-patches.sh [repo]
│   ├── update-vibe-kanban.sh # Update the shared submodule
│   ├── deploy.sh
│   └── publish-npm.sh
├── .github/workflows/
│   ├── release-images.yml
│   └── publish-npm.yml
└── helm/vibe-kanban-cloud/
    └── ...
```

## Patch Stack

- All downstream patches live directly in `patches/`.
- `patches/series` is the single source of order.
- Earlier entries are shared prerequisites for later ones.

Application order is always:

```bash
scripts/apply-patches.sh
```

That script walks `patches/series` from top to bottom.

## Release Model

### Frontend

- Source ref: `vibe-kanban/`
- Patch stack: full ordered stack
- Release tag: `v<upstream-semver>-<YYYYMMDDHHmmss>`
- Workflow: `.github/workflows/publish-npm.yml`

### Remote / Relay

- Source ref: `vibe-kanban/`
- Patch stack: full ordered stack
- Release tag: `remote-v<upstream-semver>`
- Workflow: `.github/workflows/release-images.yml`

## Update Flow

### Manual update

```bash
git submodule update --init vibe-kanban
./scripts/update-vibe-kanban.sh v0.1.20
./scripts/apply-patches.sh
```

### Patch creation

```bash
cd vibe-kanban
# make and commit upstream-facing changes
git format-patch -1 -o ../patches/
```

Rename the new patch into the next `NNNN-...patch` slot, update `patches/series`, then verify the full stack.

## Verification

```bash
git submodule update --init vibe-kanban
./scripts/apply-patches.sh
(cd vibe-kanban && cargo check --manifest-path crates/relay-tunnel/Cargo.toml)
```

## Why This Model

- One git reference to review, bump, and resolve during merges.
- There is one patch application path to maintain across local and GitHub Actions workflows.
- Removing the duplicate submodule eliminates drift where the same upstream repo could be pinned twice to different commits.
