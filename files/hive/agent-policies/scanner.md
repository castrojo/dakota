# Hive scanner agent policy — dakota
#
# The scanner triages issues, implements straightforward fixes, and opens PRs.
# This file is loaded at kick time via hive-project.yaml.
#
# Dakota context: this is a BuildStream 2 project that produces Bluefin —
# a bootc OCI desktop image built entirely from source. No RPMs. BST elements only.

## Your job
Pick up issues labeled `needs-human/agent-ready`. Implement the acceptance criteria.
Open a PR. Comment `/claim` on the issue first so actionadon records it.

## Before touching any file

1. Branch from `upstream/main` — NEVER from local `main`.
   ```bash
   git fetch upstream
   git checkout upstream/main -b fix/my-change
   ```
   Verify: `git diff upstream/main...HEAD --stat` should show only your changes.

2. Read the acceptance criteria on the issue. Implement exactly that — no more.

3. Run `just validate` before opening a PR:
   ```bash
   BST_FLAGS="--no-interactive" just validate
   ```
   If validate fails, fix it before opening the PR.

## Key rules (non-negotiable)

- `kind: compose` for layer elements, NOT `kind: stack` — stack produces zero filesystem output silently.
- `ln -sf` commands must be preceded by `mkdir -p` for the target directory.
- No `$(date)`, `$(hostname)`, or network calls in `install-commands` — breaks BST caching.
- New systemd units: enable via BST install commands, not post-install scripts.
- Rust elements: run `python3 files/scripts/generate_cargo_sources.py path/to/Cargo.lock` for cargo sources — never hand-write crate entries.
- No `/issues/NNN` paths in PR or issue bodies — GitHub autolinks fire cross-repo notifications.

## PR checklist

- [ ] Branch from `upstream/main`
- [ ] `just validate` passes
- [ ] PR body has `Closes #NNN`
- [ ] PR checklist from `.github/PULL_REQUEST_TEMPLATE.md` filled in
- [ ] `[ ] I am using an agent and I take responsibility for this PR` checked

## What you must NOT do

- Force-push to `main`
- Use `rpm-ostree`, `pip install`, or `apt-get` in element commands
- Patch junction files directly (use `patch_queue` source)
- Close issues via API or comment — `Closes #NNN` in the PR body handles it
- Submit WIP code that breaks `just validate`
