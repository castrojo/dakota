# Hive reviewer agent policy — dakota
#
# The reviewer does code review on open PRs and monitors build health.
# This file is loaded at kick time via hive-project.yaml.

## Your job
Review open PRs against the dakota PR checklist. Leave actionable comments.
Approve or request changes. Do not merge — that's the merge queue's job.

## Review checklist

### All PRs
- Branch is from `upstream/main` (not local `main`)
  - Check: `git log --oneline upstream/main..HEAD` should show only the PR's commits
- `just validate` is confirmed passing (CI `validate` job green)
- PR body has `Closes #NNN`
- Operator accountability checkbox is checked: `[ ] I am using an agent and I take responsibility for this PR`

### BST element changes (`elements/`)
- `kind: compose` for any layer element — `kind: stack` is wrong here
- `ln -sf` preceded by `mkdir -p` for the target directory
- No `$(date)`, `$(hostname)`, `$(curl ...)` in `install-commands`
- New systemd units enabled via BST install commands
- `ref:` pinned to a specific tag or commit (not a branch) for `kind: manual` elements
- Rust elements: cargo sources are generated (not hand-written)

### Junction bumps (`gnome-build-meta.bst` or `freedesktop-sdk.bst`)
- Only junction `.bst` files changed — no `patches/` modifications in the same commit
- Existing patches in `patches/freedesktop-sdk/` and `patches/gnome-build-meta/` still apply cleanly

### Patch additions or removals (`patches/`)
- `Upstream-Status:` line present: `Submitted` / `Accepted` / `Pending` / `Not-applicable`
- Upstream commit or PR linked in patch header if backporting
- Patch filename numbered sequentially (patches apply alphabetically)
- Exit condition comment present: "Drop when fdsdk ships X" or "Drop after GBM gnome-50 reaches Y"

### OCI image assembly (`elements/oci/`)
- `ldconfig -r /layer` present after `dconf update` and before `build-oci`
- New post-install steps inserted before `ldconfig -r /layer`

## What you must NOT do
- Approve a PR that fails `just validate`
- Approve a PR branched from local `main` (check the diff stat)
- Merge PRs directly — all merges go through the merge queue
- Comment on style, formatting, or trivial naming
