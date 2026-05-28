# AGENTS.md

> This file tells AI coding agents (GitHub Copilot, Claude, Gemini, etc.) how to
> contribute safely and test PRs in this repository. Human contributors can
> follow the same steps.

Dakota is a [BuildStream 2](https://buildstream.build/) project that produces
**Bluefin** - a bootc OCI desktop image built entirely from source using
freedesktop-sdk and gnome-build-meta as upstream foundations. No RPMs. No dnf.
BST elements only.

This document establishes the **Mandatory Behavioral Gates** for all AI agents, automated contributors, and their human operators. Dakota is a human-managed repository; AI agents exist to accelerate human workflows, not to replace human oversight or bypass deterministic standards.

**Non-compliance with these gates will result in an immediate, automated rejection of the contribution.**

---

## 1. The Read-First Gate

**Agents MUST read the top-level `README.md` and `.github/copilot-instructions.md` before initiating any file modifications.**

* You are prohibited from making assumptions about the project structure, dependency management, or architectural patterns.
* Your first action in any session must be a systematic scan of the project's documentation to ensure context alignment.

## 2. The Rate Limiting Gate

**Agents MUST NOT overwhelm human maintainers with high-volume or redundant submissions.**

* **Concurrency Limit:** An agent (or its operator) MUST NOT have more than **four (4) active Pull Requests** pending review at any given time.
* **Batching:** Small, incremental changes are preferred, but do not fragment a single logical feature into dozens of micro-PRs. Squash is your friend.
* **Cooldown:** If a PR is closed due to poor quality, the agent (or its operator) must not submit a replacement PR until the root cause has been identified and documented as a comment on the closed PR. One PR at a time for the same issue.

## 3. The Operator Accountability Gate

**The human operator deploying the agent is strictly responsible for every line of code and every technical decision made by the agent.**

This is in the pull request template: `[ ] I am using an agent and I take responsibility for this PR`

## 4. The Verification Gate

**No contribution shall be considered for merge without a deterministic verification report.**

* **Justfile Execution:** Agents MUST run `just lint` and `just boot-fast` (or `just boot-vm`) on their local environment before submission. These are the canonical local verification targets.
* **Report Requirement:** The PR description MUST include confirmation that `just lint` passed and the image booted successfully.
* **Zero-Failure Tolerance:** If lint fails or the image does not boot, the PR is considered non-compliant. Agents MUST NOT submit "Work In Progress" (WIP) code that breaks the build.
* **Note:** `just verify` checks cosign/SBOM/SLSA signatures on published GHCR images — it requires a pushed image and is not part of the local contributor verification loop.

## 5. The Justfile Integrity Gate

**The `Justfile` is the single, canonical source of truth for all maintenance tasks.**

* **No "Loose" Commands:** Agents are strictly forbidden from suggesting or using shell commands that are not encapsulated within the `Justfile`.
* **Validation command:** Run `just validate` for CI-equivalent element graph checks (`oci/bluefin.bst` + `oci/bluefin-nvidia.bst`).
* **Gap Closure:** If an agent identifies a maintenance task, setup step, or deployment requirement not currently covered by a `just` recipe, the agent **MUST** submit a PR to update the `Justfile` before or alongside the feature code.
* **Determinism:** All recipes added by agents must be idempotent and deterministic.

## 6. The Human Maintainability Gate

**Agents are tools for acceleration; they do not dictate the evolution of the codebase.**

* **Manual Parity:** Any process an agent performs must be fully replicable by a human using only the `Justfile`.
* **No Black Boxes:** Contributions that introduce dependencies, obfuscated logic, or "AI-optimized" code that a standard human contributor cannot easily debug or maintain via the provided tooling will be rejected.
* **Interface Stability:** Agents must not alter the CLI interface or existing `just` recipe names without explicit human approval, as this breaks human mental models of the system.

---

### Failure to Comply

Any Pull Request that bypasses these gates-specifically those lacking a `Justfile` verification report or the Operator Acknowledgment-will be **closed without review**.

**Dakota prioritizes codebase integrity and human bandwidth over the speed of automated contributions.**

---

## Requirements

| Tool | Why | Install |
|---|---|---|
| `podman` (rootful + rootless) | BST runs inside a container; export + boot need rootful | Pre-installed on Bluefin ✓ |
| `just` | All build and test commands | Pre-installed on Bluefin ✓ |
| `qemu` | VM boot | `brew install qemu` |
| `virtiofsd` | Required for `just boot-fast` only | `rpm-ostree install virtiofsd` then reboot |
| `bcvk` | Fast ephemeral VM from container (no disk image) | Auto-installed by `just boot-fast` via cargo - or install manually: `cargo install --locked --git https://github.com/bootc-dev/bcvk bcvk` |
| ~100 GB free disk | BST cache + image | - |
| ~16 GB RAM | BST builds are parallel and hungry | - |

---

## Repo layout

| Path | Purpose |
|---|---|
| `elements/freedesktop-sdk.bst` | fdsdk junction - pinned to a release tag |
| `elements/gnome-build-meta.bst` | GBM junction - tracks `gnome-50` branch |
| `elements/bluefin/` | Bluefin-specific elements (~40 elements) |
| `elements/oci/` | OCI image assembly - layers + final image |
| `patches/freedesktop-sdk/` | Patches applied to fdsdk via `patch_queue` |
| `patches/gnome-build-meta/` | Patches applied to GBM via `patch_queue` |
| `patches/linux/` | Kernel patches (via fdsdk linux element) |
| `files/` | Static files installed by elements |
| `.github/workflows/build.yml` | CI: `validate` on PRs, full `build` on merge queue |
| `Justfile` | All local dev commands - run `just --list` first |

---

## Quick start - build and boot in one command

```bash
just show-me-the-future
```

This runs the full loop: BST build → export → bootable disk image → QEMU VM.
Expect 45-90 minutes on first run (cold BST cache). Subsequent runs are fast
because BST caches artifacts by content hash.

---

## Standard dev loop

### 1. Validate - fast, no build

Always run this first. It checks the full element dependency graph without
building anything. Same check CI runs on every PR.

```bash
just validate
```

`just validate` mirrors CI by checking both default and nvidia element graphs.
The `just bst` wrapper defaults to `-o x86_64_v3 true --no-interactive`, so
local graph checks match CI without extra environment variables.

Exits non-zero if any element has a missing dep, bad ref, or patch that fails
to apply. If this passes, the graph is structurally sound.

### 2. Build

```bash
export BUILD_SKIP_NVIDIA=1    # skip nvidia variant - saves ~15 min

just build default
```

BST pulls cached artifacts from upstream caches (`cache.freedesktop-sdk.io`,
`gbm.gnome.org`) for anything it hasn't built locally. Most elements will be
cache hits. A warm-cache build of a small element change takes 2–5 minutes.

**First run:** cold cache means BST must build everything from source.
Expect 60–90 minutes. Subsequent runs are fast — BST's content-addressed
cache skips anything unchanged.

### 3. Lint

```bash
just lint
```

Runs `bootc container lint` on the built image. Must pass before any PR is ready.

### 4. Boot and verify

**Fast path - ephemeral VM, no disk image (preferred for quick checks):**

```bash
just boot-fast
```

Boots directly from the container via virtiofs. No install step. Requires
`bcvk` (auto-installed by `just boot-fast` via cargo) and `virtiofsd`
(`rpm-ostree install virtiofsd` then reboot, one-time setup).

**Full path - installed disk image:**

```bash
just generate-bootable-image   # installs image to bootable.raw (~5 min)
just boot-vm                   # boots in QEMU (native) or container fallback
```

### 5. Verify what's running inside the VM

Once booted, open a terminal and check:

```bash
uname -r                       # kernel version
bootc status                   # booted image + digest
systemctl is-active gdm        # desktop session healthy
```

---

## PR review checklist

### Any PR

- [ ] Validate passes: `just validate`
- [ ] `just lint` passes on a built image
- [ ] `just boot-fast` or `just boot-vm` - desktop comes up, no regressions
- [ ] Commit has exactly one `Assisted-by:` or `Signed-off-by:` trailer - no `Co-authored-by:`
- [ ] PR body references the issue it closes (`Closes #NNN`)

### Junction bumps (`gnome-build-meta.bst` or `freedesktop-sdk.bst`)

- [ ] Only junction `.bst` files changed - no `patches/` modifications in the same commit
- [ ] CI `validate` passes
- [ ] Validate that existing patches in `patches/freedesktop-sdk/` and `patches/gnome-build-meta/` still apply cleanly after the bump (a patch that targeted an old `ref:` will now fail)

Junction-only bumps from `mergeraptor[bot]` that touch no patch files are
pre-approved once `validate` passes. See issue #501 for the auto-merge roadmap.

> **When bumping manually:** run `just validate` with the new junction ref before opening the PR to confirm all patches still apply.

### Patch additions or removals (`patches/`)

- [ ] Patch has a clear `Upstream-Status:` line: `Submitted` / `Accepted` / `Pending` / `Not-applicable`
- [ ] If backporting a fix: upstream commit or PR linked in the patch header
- [ ] If the fix is already upstream in the new junction ref: **drop the patch** rather than keep it
- [ ] Patch filename is numbered sequentially (patches apply alphabetically)
- [ ] Patch adds an exit condition comment: "Drop when fdsdk ships X" or "Drop after GBM gnome-50 reaches Y"

### OCI image assembly (`elements/oci/`)

- [ ] `ldconfig -r /layer` is present after `dconf update` and before `build-oci` — see [docs/oci-assembly.md](docs/oci-assembly.md)
- [ ] Any new post-install step is inserted **before** `ldconfig -r /layer`

### Element changes (`elements/bluefin/`)

- [ ] `ln -sf` commands are preceded by `mkdir -p` for the target directory
- [ ] `kind: manual` binary elements have a `ref:` pinned to a specific tag or commit - not a branch
- [ ] No `date`, `hostname`, `whoami`, `curl`, or other non-reproducible / network calls in `install-commands`
- [ ] New systemd units are enabled via the BST install commands, not via a post-install script

---

## Community workflow

Dakota uses a structured issue lifecycle so that the community shapes what gets built and agents build exactly what was agreed on — no more, no less.

This workflow is **opt-in** in the issue form. Issues only enter it automatically when the author selects **Raptor Current**. Otherwise they stay ordinary issues unless a maintainer or wrangler chooses to route them into the workflow later with `status/approved` plus `/ready`.

```
New issue
  │
  ▼ actionadon labels status/discussing, posts welcome comment
Discussion happens in the issue if people want it
  │
  ▼ Maintainer adds status/approved when the issue is ready for approval
Maintainer writes acceptance criteria in the issue body
  │
  ▼ Maintainer adds needs-human/agent-ready
Any human or agent can claim it — comment /claim on the issue
  │
  ▼ actionadon adds agent/claimed, assigns the claimer
Implement the acceptance criteria, open a PR with Closes #NNN
  │
  ▼ CI validate passes, maintainer reviews, lab:pass applied
Merge queue → issue closes automatically
```

### actionadon

`actionadon` is the bot that drives this. It runs as a GitHub Actions workflow (`.github/workflows/actionadon.yml`) and posts one short comment each time an issue advances a stage.

| Comment `/claim` | Takes the issue. actionadon assigns you and adds `agent/claimed`. |
|---|---|
| Comment `/ready` | Wranglers and maintainers can move an approved, spec-complete issue into the queue. It requires a `### Acceptance criteria` section with real checklist items. |
| Comment `/unclaim` | Returns it to the queue. The assignee, a wrangler, or a maintainer can unclaim. |

If a claimed issue has no PR activity for 7 days, actionadon automatically returns it to the queue.

### Wrangler role

Wranglers are the humans who keep the queue moving. This is intentionally a lower-barrier role than maintainer: they do not need to merge code or own every repo, they just need enough project context to shape issues into buildable specs and steer the bots.

All projectbluefin maintainers are implicit wranglers. The list below is the extra named group for trusted contributors who should be able to drive the bots without becoming the merge gate.

Wranglers can:
- help turn discussion into acceptance criteria
- comment `/ready` when an approved issue is spec-complete and should enter the queue
- comment `/unclaim` when a claimed issue has gone stale and needs to go back in circulation
- nudge Hive toward the right issues without becoming the merge gate

Initial wranglers:
- `castrojo`
- `ahmedadan`
- `alatiera`
- `hanthor`
- `coxde`
- `renner0e`

### Hive integration

If you're running [Hive](https://github.com/kubestellar/hive) against this repo, copy `files/hive/hive-project.yaml.example` to `/etc/hive/hive-project.yaml` and load the agent policy files from `files/hive/agent-policies/` as your per-agent CLAUDE.md overrides. Hive's scanner will pick up `needs-human/agent-ready` issues and claim them via the `/claim` protocol above.

---

## Label protocol

### Triage labels

| Label | What it means |
|---|---|
| `status/discussing` | Community discussion underway — not yet approved. |
| `status/approved` | Approved for queue preparation — needs acceptance criteria before queue. |
| `agent/claimed` | Someone is actively working this issue. |
| `agent/blocked` | Work stalled — needs human input before it can continue. |
| `needs-human/agent-ready` | Issue is scoped with clear acceptance criteria. Ready for an agent or contributor to pick up and open a PR. |
| `lgtm` | PR approved by a maintainer. |
| `help wanted` | Good for any contributor, including agents. |
| `kind:bug` | Something is broken and needs fixing. |
| `kind:improvement` | Enhancement or cleanup — no spec required for small items. |
| `kind:tech-debt` | Cleanup with no user-visible change. |
| `kind:github-action` | CI or automation changes. |
| `lab:pass` | Maintainer lab validation passed; enables label-gated auto-merge for maintainer-owned PR branches. After `lab:pass`, one maintainer ack/approval is sufficient for merge-queue entry. |
| `human-needed/agent-oops` | An agent made a mistake here — wrong assumption, bad output, filed a spurious issue, broke something. This label builds a learning corpus. |

### `needs-human/agent-ready` - how to use it

When you see this label on an issue:
1. Read the full issue - the acceptance criteria are there
2. Run `just --list` to understand the build system
3. Make the change, validate, build, boot, lint
4. Open a PR with `Closes #NNN` in the body
5. CI `validate` must pass

### `lab:pass` - how to use it

- Apply this to a maintainer PR only after human/lab validation passes.
- `.github/workflows/lab-pr-automerge.yml` then enables `gh pr merge --auto --merge`.
- Queue policy: once `lab:pass` is set, only one maintainer ack/approval is required to proceed to the merge queue.
- The workflow only acts on same-repo PR branches owned by the repository owner (no forks).

### `human-needed/agent-oops` — how to use it

When an agent makes an error:
- A maintainer adds `human-needed/agent-oops` to the relevant issue or PR
- Do **not** remove this label — it is intentional signal
- If you are the agent that made the error, note what went wrong in your response to the maintainer (so the pattern can be captured in agent skill files)
- Examples: filed a duplicate issue, proposed a fix for something already upstream, broke a patch apply, failed to check hardware after a build

---

## Patch management rules

Patches in `patches/freedesktop-sdk/` and `patches/gnome-build-meta/` are
applied in **alphabetical filename order** via BuildStream's `patch_queue`
source. The numbers in filenames control application order.

**When bumping a junction ref:**
1. Check every existing patch in the relevant `patches/` directory
2. If a patch targets a `ref:` that no longer exists in the new junction - the patch will fail to apply. Either update the patch to match the new context or drop it if the fix is upstream.
3. Kernel patches (`patches/linux/`) are applied to the kernel source by fdsdk's linux element - verify they still apply against the new kernel version

**Patch lifecycle:**
```
Add patch → document Upstream-Status → track upstream PR →
upstream merges → junction bump includes fix → drop patch
```

Never carry a patch longer than needed. Every patch is maintenance debt.

---

## CI overview

| Job | Fires on | What it does |
|---|---|---|
| `validate` | `pull_request` | `bst show` - checks element graph, applies patches, validates deps. Fast (~5 min). |
| `build` | `merge_group`, `schedule`, `workflow_dispatch` | Full OCI build + push artifact to remote CAS. Slow (~60-90 min). |
| `build-aarch64` | disabled | ARM64 build — disabled pending investigation |

The daily cron fires at **13:00 UTC** - after gnome-build-meta nightly (~08:00 UTC).

**Never** bypass the merge queue with `--admin`. The queue's `build` job is the
gate. If `validate` passes on a PR but `build` fails in the queue, that failure
is real and must be fixed.

---

## What NOT to do

| Don't | Why |
|---|---|
| `rpm-ostree`, `pip install`, `apt-get` in element commands | This is a BST-only build. All deps come from junctions. |
| `$(date)`, `$(hostname)`, `$(curl ...)` in `install-commands` | Breaks BST's content-addressed caching and reproducibility |
| Patch junction files directly | Use the `patch_queue` source in the junction `.bst` element |
| Force-push to `main` | The merge queue owns merges |
| Close issues via API or comment | Use `Closes #NNN` in the PR body - the issue closes automatically on merge |
| Open a PR without running `validate` first | Saves everyone time |

---

## Useful BST commands

```bash
# Check if your element changes are sound before building
just validate

# Build just one element (faster iteration)
just bst build elements/bluefin/tailscale.bst

# Open a shell inside the build sandbox for an element
just bst shell --build elements/bluefin/tailscale.bst

# Check what depends on an element (what will rebuild if this changes)
just bst show --deps all --format '%{name}' oci/bluefin.bst \
  | grep -F "$(just bst show --format '%{name}' elements/bluefin/tailscale.bst)"
```

---

## Links

- BuildStream docs: https://docs.buildstream.build/
- freedesktop-sdk: https://gitlab.com/freedesktop-sdk/freedesktop-sdk
- gnome-build-meta (GitHub mirror): https://github.com/GNOME/gnome-build-meta - branch `gnome-50`
- Existing issues: https://github.com/projectbluefin/dakota/issues
- Project board: https://github.com/orgs/projectbluefin/projects/2
