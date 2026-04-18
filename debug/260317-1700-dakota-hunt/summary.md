# Dakota Debug Hunt — Executive Summary
**Session:** 260317-1700  
**Scope:** `castrojo/dakota` fork, x86_64 only  
**Depth:** 15 iterations, full codebase scan  
**Date:** 2026-03-17

---

## Results at a Glance

| Category         | Count |
|------------------|-------|
| Confirmed bugs   | 5     |
| HIGH severity    | 1     |
| MEDIUM severity  | 1     |
| LOW severity     | 3     |
| Eliminated hypotheses | 10 |
| Files inspected  | ~35   |

---

## Confirmed Bugs — Priority Order

### 1. BUG-1 · HIGH · `.github/workflows/build.yml:87`
**Greek Unicode chars in variable name — CI cache push is permanently broken**

```bash
# Line 87 — BROKEN: uses Κ Ε Υ (Greek letters) not ASCII K E Y
[[ -n "$CASD_CLIENT_ΚΕΥ" ]] && cat >> buildstream-ci.conf << ...
```

The condition is **always false**. The artifacts/source-caches/remote-execution push config block pointing to `cache.projectbluefin.io:11002` is never appended to `buildstream-ci.conf`, even when the `CASD_CLIENT_KEY` secret is set. CI builds run but **never populate the shared cache**.

**Fix:** Replace `$CASD_CLIENT_ΚΕΥ` with `$CASD_CLIENT_KEY` (ASCII) on line 87.

---

### 2. BUG-2 · MEDIUM · `.github/workflows/build.yml:79-80`
**BST log dir inside container is not mounted — build logs are silently lost**

- `buildstream-ci.conf` sets `logdir: /srv/logs` inside the bst2 container
- `just bst` only mounts `/src` and `~/.cache/buildstream` — `/srv/logs` is never surfaced
- The `Upload build logs` step uploads `logs/` (runner-side, always empty)
- `if-no-files-found: ignore` means this silently succeeds with zero artifacts

**Fix:** Either mount `/srv/logs` from the container to `logs/` on the runner, or change `logdir` in the CI conf to a path under `/src` which is already mounted.

---

### 3. BUG-3 · LOW · `files/scripts/generate_cargo_sources.py:1`
**Uses third-party `toml` package — will fail on clean Python 3.11+ environments**

```python
import toml  # line 1 — not stdlib
```

Python 3.11+ ships `tomllib` in stdlib. The `toml` pip package is not guaranteed to be present. Also: the error message on line 40 still says `generate_bst.py` (stale script name).

**Fix:** Replace `import toml` with `import tomllib` (stdlib) and update the read call from `toml.load(f)` to `tomllib.load(fb)` (binary mode). Fix stale script name in error message.

---

### 4. BUG-4 · LOW · `include/aliases.yml:59`
**`thekelleys` alias uses `http://` — plaintext download**

```yaml
thekelleys: http://www.thekelleys.org.uk/   # line 59
```

Every other alias uses `https://`. The site serves HTTPS correctly.

**Fix:** Change to `https://www.thekelleys.org.uk/`.

---

### 5. BUG-5 · LOW · `Containerfile:3`
**`bootc container lint || true` silences lint failures**

```dockerfile
RUN bootc container lint || true
```

Lint errors never fail the build. The `just lint` recipe (Justfile:569) correctly runs without `|| true` — this is a consistency gap.

**Fix:** Remove `|| true` so lint failures block the build.

---

## Notable FIXMEs (Not Bugs, But Tech Debt)

- `elements/oci/os-release.bst:10` — `# FIXME: configurable` — IMAGE_NAME, IMAGE_VENDOR, IMAGE_REF hardcoded
- `.github/workflows/build.yml:25,40` — two `# FIXME: Make the build with JWT work` — JWT auth was never completed; the workaround uses a raw client key instead

---

## Recommendations

1. **Fix BUG-1 first.** It's a single-character class typo that completely disables the shared cache. Every CI build since this was introduced has been wasting compute and getting no cache benefit.
2. **Fix BUG-2 next.** Lost build logs make diagnosing CI failures extremely difficult. The mount fix is low-risk.
3. **BUG-3, BUG-4, BUG-5** are minor housekeeping — fix in a single cleanup PR.
4. Consider addressing the JWT FIXME comments to move off the raw client key approach.

---

## Files Inspected

`.github/workflows/build.yml`, `.github/workflows/track-bst-sources.yml`, `.github/workflows/validate-renovate.yml`, `elements/freedesktop-sdk.bst`, `elements/gnome-build-meta.bst`, `elements/bluefin/common.bst`, `elements/bluefin/deps.bst`, `elements/bluefin/brew.bst`, `elements/bluefin/ghostty.bst`, `elements/bluefin/uutils-coreutils.bst`, `elements/bluefin/sudo-rs.bst`, `elements/bluefin/jetbrains-mono.bst`, `elements/bluefin/jetbrains-mono-nerd-font.bst`, `elements/bluefin/wallpapers.bst`, `elements/bluefin/plymouth-bluefin-theme.bst`, `elements/bluefin/gnome-shell-extensions.bst`, `elements/bluefin/1password/1password-x86_64.bst`, `elements/bluefin/1password-cli/1password-cli-x86_64.bst`, `elements/bluefin/brew-tarball/brew-tarball-x86_64.bst`, `elements/bluefin/tailscale/tailscale.bst`, `elements/bluefin/zig/zig.bst`, `elements/oci/bluefin.bst`, `elements/oci/os-release.bst`, `elements/oci/layers/` (directory), `files/scripts/generate_cargo_sources.py`, `files/plymouth/plymouthd.defaults`, `patches/gnome-build-meta/4289.patch`, `patches/freedesktop-sdk/` (directory), `include/aliases.yml`, `project.conf`, `Containerfile`, `Justfile`
