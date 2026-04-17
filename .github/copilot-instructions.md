> Pointer-only wrapper. Full rules and procedures live in the domain skills.
> Skills index: `cat ~/src/skills/INDEX.md`
> Load domain skills before any dakota work:
> - CI/workflow changes: `cat ~/src/skills/dakota-ci/SKILL.md`
> - BST element authoring: `cat ~/src/skills/dakota-buildstream/SKILL.md`
> - Package-specific: `cat ~/src/skills/dakota-package-<lang>/SKILL.md`
> - OCI layer assembly: `cat ~/src/skills/dakota-oci-layers/SKILL.md`

## ⛔ Critical — read before touching git or issues

### STOP: branch contamination kills PRs

This fork (`castrojo/dakota`) is **23+ commits ahead of `projectbluefin/dakota`**. Branching from local `main` creates PRs with hundreds of unrelated files. This has caused real pain — *"this PR is insane why is it all of these files"*.

**Always branch from `upstream/main`, never from local `main`:**

```bash
git fetch upstream
git checkout -b feat/my-change upstream/main
```

**Mandatory pre-push audit — must pass before any `git push`:**

```bash
git diff --name-only upstream/main..HEAD    # must show ONLY your files
git log --oneline upstream/main..HEAD       # must show ONLY your commits (1 line = good)
```

If `AGENTS.md`, `README.md`, or other fork-local files appear in the diff: your branch is contaminated. Fix with:

```bash
git checkout -b feat/my-change-clean upstream/main
git cherry-pick <your-sha>
```

### No /issues/ or /pull/ URLs in GitHub issue bodies

GitHub auto-links these paths and **fires a notification into the linked repo** — even inside code fences. This spams external maintainers. This has happened in real sessions.

```
# ✅ correct — no notification
bootc-dev/bootc issue 7
projectbluefin/dakota#226

# ❌ wrong — spams external repo
https://github.com/bootc-dev/bootc/issues/7
```

Only `/issues/NNN` and `/pull/NNN` paths trigger cross-repo notifications. Plain `org/repo#NNN` format is safe for same-org repos.

### Merging workflow-file PRs on the fork

`gh pr merge` returns 403 on `.github/workflows/` changes without `workflow` OAuth scope. **Never call `gh auth refresh` interactively** — it requires browser interaction and blocks the session.

The correct flow for `castrojo/dakota` (self-owned fork):
1. Open the fork-internal PR and link it to the user
2. Let the user merge it, or ask them to run `gh pr merge <number> --squash --repo castrojo/dakota`

## Build commands

```bash
just bst build oci/bluefin.bst   # full image build (inside bst2 container)
just build                        # alias for the above
just export                       # export OCI image from BST into podman
just lint                         # bootc container lint (requires exported image)
just bst show oci/bluefin.bst     # inspect element dependency graph
```

Builds run inside the pinned `bst2` container. `BST_FLAGS` env var injects flags:

```bash
BST_FLAGS="--no-interactive" just bst build oci/bluefin.bst
```

## CI overview

- **Schedule:** nightly at 13:00 UTC (after gnome-build-meta nightly ~08:00 UTC finish)
- **Publish triggers:** `merge_group`, `schedule`, `workflow_dispatch` (not `pull_request`)
- **Remote cache:** `cache.projectbluefin.io:11002` (mTLS — `CASD_CLIENT_CERT` + `CASD_CLIENT_KEY`)
- **Image:** `ghcr.io/projectbluefin/dakota:latest` and `:<sha>`

## Key architecture

- Built on gnome-build-meta + freedesktop-sdk via BST junctions
- `elements/bluefin/deps.bst` (`kind: stack`) — add new packages here
- `elements/oci/layers/` — compose chain filters artifacts into the final layer
- `elements/oci/bluefin.bst` — final OCI assembly script
- `patches/gnome-build-meta/` — drop `.patch` files here (alphabetical order, no edits to `gnome-build-meta.bst`)

## Element authoring rules (learned from real mistakes)

**`cargo2` source blocks are generated — never hand-written:**

```bash
python3 files/scripts/generate_cargo_sources.py path/to/Cargo.lock
```

The first ~65 lines of a Rust BST element are hand-authored (build commands, install paths). Everything after that is the generated crate manifest. Do not write crate entries by hand.

**Layer elements must be `kind: compose`, not `kind: stack`:**

Elements staged as `/layer` in OCI script elements **must** be `kind: compose`. `kind: stack` is a dependency aggregator that produces **zero filesystem output** — the image builds successfully but the layer is silently empty.

```yaml
# ✅ correct — produces filesystem content
kind: compose

# ❌ wrong — silently empty layer
kind: stack
```
