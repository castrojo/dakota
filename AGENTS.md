# Dakota Agent Routing (dakotaraptor)

Agent entry point for automated maintenance of the dakota BuildStream repo.
Read this first. Load the skill listed under "Skill load order" for details.

## Environment requirements

```bash
podman   # runs the bst2 container — all bst commands go through it
just     # task runner — use this instead of calling bst directly
gh       # GitHub CLI — for PR creation and issue queries
git      # version control
```

BST always runs inside the pinned bst2 container via `just bst`. Never call `bst` directly.

## Task routing table

| Task | Just recipe | Skill to load |
|------|------------|--------------|
| Add binary package | `just scaffold-binary <name> <gh-owner/repo>` | `dakota-add-package` → `dakota-package-binaries` |
| Add Rust package | `just scaffold-rust <name> <gh-owner/repo>` | `dakota-add-package` → `dakota-package-rust` |
| Add GNOME extension | `just scaffold-gnome-ext <name> <gh-owner/repo>` | `dakota-add-package` → `dakota-package-gnome-extensions` |
| Add Go package | copy `files/templates/git-tracked.bst` | `dakota-add-package` → `dakota-package-go` |
| Remove package | `just remove-package <name>` | `dakota-remove-package` |
| Update tarball version | `just track-tarball elements/bluefin/<name>.bst <version>` | `dakota-update-refs` |
| Update git ref | `just track-one elements/bluefin/<name>.bst` | `dakota-update-refs` |
| Validate element | `just validate elements/bluefin/<name>.bst` | `dakota-buildstream` |
| Build one element | `just bst build elements/bluefin/<name>.bst` | `dakota-debugging` |
| Register CI tracking | `just register-tracking elements/bluefin/<name>.bst <group>` | `dakota-update-refs` |
| Debug build failure | `just bst shell --build elements/bluefin/<name>.bst` | `dakota-debugging` |
| Full image build | `just build` | `dakota-ci` |
| VM smoke test | `just boot-fast` | `dakota-testlab` |

## Template locations

```
files/templates/binary.bst      Pre-built multi-arch binary (GitHub Releases)
files/templates/git-tracked.bst Git source with bst source track
files/templates/rust.bst        Rust/Cargo project (requires cargo2 bootstrap)
files/templates/gnome-ext.bst   GNOME Shell extension
```

## Add-package workflow (all types)

```bash
# 1. Scaffold (creates elements/bluefin/<name>.bst from template)
just scaffold-binary <name> <owner/repo>   # or scaffold-rust, scaffold-gnome-ext

# 2. Edit the created file — fill in version, URL pattern, install commands

# 3. Populate refs
just bst source track elements/bluefin/<name>.bst

# 4. Wire into image
#    Binary packages: add to elements/bluefin/deps.bst
#    GNOME extensions: add to elements/bluefin/gnome-shell-extensions.bst

# 5. Validate and build
just validate elements/bluefin/<name>.bst
just bst build elements/bluefin/<name>.bst

# 6. Register automated tracking
just register-tracking elements/bluefin/<name>.bst auto-merge   # or manual-merge for Rust/junctions
```

## Remove-package workflow

```bash
# 1. Run preflight — review every section before touching files
just remove-package <name>

# 2. Follow the printed checklist:
#    - Delete element files
#    - Edit deps.bst or gnome-shell-extensions.bst
#    - Edit track-bst-sources.yml
#    - Edit renovate.json5 if listed

# 3. Verify
just validate oci/bluefin.bst
just build
```

## Tracking group rules

| Group | Elements | PR behavior |
|-------|----------|-------------|
| `auto-merge` | App-level packages, shell extensions | Squash-merged automatically |
| `manual-merge` | Junctions (freedesktop-sdk, gnome-build-meta), Rust elements (cargo2), bootc | Requires human review |

## Pre-build checks

Run before any full build:

```bash
just preflight   # disk (<80% required), NUC reachability, zot registry
```

Ghost's root filesystem runs the BST CAS. At 80%+ disk usage builds will slow; at 90%+ they may fail with cache write errors. If `just preflight` fails on disk:

```bash
just bst cas clean-cache   # prune unused CAS objects
```

### Chunkah stability warning

Every chunkah invocation prints `WARN no stability data available, packing may be suboptimal`. This is expected — `--stability-reports` is not integrated. Layer ordering is suboptimal but functional. Do not treat this warning as a build failure.

### NUC freshness

The NUC boots images from ghost's local zot registry. After any ghost build + publish cycle, the NUC must run `sudo bootc upgrade` to pull the new image. An unupgraded NUC is stale — do not validate hardware against a stale image.

## Hard rules — never break these

- **Never edit** `elements/freedesktop-sdk.bst` or `elements/gnome-build-meta.bst` without human review
- **Never run** `just bst source track elements/freedesktop-sdk.bst` or `elements/gnome-build-meta.bst` autonomously
- **Never open a PR** to `projectbluefin/dakota` without explicit permission from a human reviewer
- **Always run** `just preflight` before `just build` on ghost
- **Always run** `just validate <element>` before `just bst build`
- **Always add** new elements to `deps.bst` (binary) or `gnome-shell-extensions.bst` (extensions)
- **Do not** add a Renovate entry for any element already in the `track-tarballs` CI job — dual-tracking causes conflicting PRs
- **bst2 pin**: the bst2 container SHA must match in both `Justfile` and `track-bst-sources.yml` — CI will fail if they drift

## Commit conventions

```
feat(bluefin): add <name>          # new package
chore(deps): update <name>         # version bump
fix(bluefin): <description>        # bug fix in element
chore: remove <name>               # package removal
```

## Skill load order (if context permits)

1. `dakota-buildstream` — BST variables, element kinds, source kinds (load first for any BST work)
2. Task skill: `dakota-add-package`, `dakota-remove-package`, or `dakota-update-refs`
3. Package-type skill: `dakota-package-binaries`, `dakota-package-rust`, `dakota-package-go`, `dakota-package-gnome-extensions`

## Key file locations

```
elements/bluefin/          All Bluefin-specific elements
elements/bluefin/deps.bst  Central dependency manifest — add new packages here
elements/bluefin/shell-extensions/            GNOME Shell extension elements
elements/bluefin/gnome-shell-extensions.bst   Extension stack — add new extensions here
elements/bluefin/brew.bst, common.bst         Upstream submodule/config tracking
elements/freedesktop-sdk.bst                  Junction — do not edit without review
elements/gnome-build-meta.bst                 Junction — do not edit without review
include/aliases.yml                           URL aliases for bst source kinds
files/templates/                              Element scaffolds for new packages
.github/workflows/track-bst-sources.yml      Automated tracking matrix
.github/renovate.json5                        Renovate dependency update config
```
