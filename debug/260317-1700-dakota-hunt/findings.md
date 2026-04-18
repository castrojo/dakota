# Confirmed Findings — dakota debug hunt 260317-1700

> Scope: x86_64 only. All element files, CI workflows, Justfile, Containerfile, patches/, files/.
> 15 iterations completed 2026-03-17.

---

## BUG-1 — HIGH — Greek Unicode typo in CI env-var check (cache push permanently disabled)

**File:** `.github/workflows/build.yml:87`

**Evidence:**
```
if [[ -n "$CASD_CLIENT_CERT" ]] && [[ -n "$CASD_CLIENT_ΚΕΥ" ]]; then
```
The variable name `CASD_CLIENT_ΚΕΥ` contains Greek uppercase letters:
- `Κ` U+039A (GREEK CAPITAL LETTER KAPPA)
- `Ε` U+0395 (GREEK CAPITAL LETTER EPSILON)
- `Υ` U+03A5 (GREEK CAPITAL LETTER UPSILON)

The actual environment variable is set on line 61 as `CASD_CLIENT_KEY` (pure ASCII).
The secret is injected as `CASD_CLIENT_KEY: ${{ secrets.CASD_CLIENT_KEY }}`.

**Impact:** The condition `[[ -n "$CASD_CLIENT_ΚΕΥ" ]]` references a variable that is never set
(shell treats unknown variables as empty). It is therefore **always false**, regardless of whether
the secret is configured. The entire `cat >> buildstream-ci.conf <<'BSTCONFPUSH'` block — which
configures `artifacts`, `source-caches`, `cache`, and `remote-execution` to push to
`cache.projectbluefin.io:11002` — is **never appended**. CI builds never push artifacts to the
remote cache server, even when the `CASD_CLIENT_KEY` secret is populated.

**Reproduction:**
```bash
# In any bash shell:
export CASD_CLIENT_KEY="some-real-value"
if [[ -n "$CASD_CLIENT_ΚΕΥ" ]]; then echo "push enabled"; else echo "push disabled"; fi
# Output: push disabled   (always)
```

**Fix:** Change `$CASD_CLIENT_ΚΕΥ` to `$CASD_CLIENT_KEY` (ASCII) on line 87.

---

## BUG-2 — MEDIUM — BST log directory inside container, never surfaced; artifact upload is always empty

**File:** `.github/workflows/build.yml:79-80` and `200-210`

**Evidence:**
- Line 79-80 of `buildstream-ci.conf` heredoc sets `logdir: /srv/logs`
- The `bst` recipe in Justfile mounts only two volumes:
  ```
  -v "{{justfile_directory()}}:/src:rw"
  -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw"
  ```
  `/srv/logs` is never mounted to the runner filesystem.
- Line 63: `mkdir -p logs` creates a `logs/` directory on the runner.
- The "Upload build logs" step (lines 203-210) uploads `logs/`:
  ```yaml
  path: logs/
  if-no-files-found: ignore
  ```

**Impact:** Build logs from inside the bst2 container are written to `/srv/logs` (inside the
container, ephemeral). The runner-side `logs/` directory is always empty. The artifact upload
step silently succeeds with zero files (`if-no-files-found: ignore`). When a BST build fails in
CI, there are no logs to download from the GitHub Actions artifacts panel — the failure is
completely undiagnosable via the artifact mechanism.

**Fix options:**
1. Mount a runner path to `/srv/logs` inside the bst2 container: add `-v "$(pwd)/logs:/srv/logs:rw"` to the podman run invocation in the `bst` Justfile recipe (but that recipe must receive this mount only when invoked from CI, not locally).
2. Simpler: Change `logdir` in the CI config to `/src/logs` (which is already mounted via `/src`).

---

## BUG-3 — LOW — `generate_cargo_sources.py` uses third-party `toml` package (not stdlib `tomllib`)

**File:** `files/scripts/generate_cargo_sources.py:1`

**Evidence:**
```python
import toml
```
Python 3.11+ ships `tomllib` in the stdlib. The `toml` package is a separate third-party package
not installed by default on the runner or in the bst2 container.

Verified locally:
```
ModuleNotFoundError: No module named 'toml'
tomllib ok   (stdlib)
```

**Impact:** If `generate_cargo_sources.py` is run in any environment without `toml` installed
(e.g. a bare runner, or inside bst2 container), it will fail with an import error. The script
is not invoked in CI automatically — it is a developer helper for regenerating cargo2 source
lists — so this is LOW severity, but it will silently break for contributors who don't have
`toml` installed.

**Also:** Line 40 of the same file has a stale script name in its error message: it says
`generate_bst.py` but the file is `generate_cargo_sources.py`. This is cosmetic only.

**Fix:** Replace `import toml` with:
```python
import sys
if sys.version_info >= (3, 11):
    import tomllib
else:
    try:
        import tomllib
    except ImportError:
        import tomli as tomllib  # pip install tomli
```
Or simply: `import tomllib` (requires Python 3.11+, acceptable for a dev helper).

---

## BUG-4 — LOW — `include/aliases.yml` uses `http://` for `thekelleys` alias (no TLS)

**File:** `include/aliases.yml:59`

**Evidence:**
```yaml
thekelleys: http://www.thekelleys.org.uk/
```

All other aliases in the file use `https://`. This alias is used for dnsmasq downloads. Fetching
over plain HTTP means the download is not integrity-protected by transport encryption (though
BuildStream refs do verify content hashes, so this is low-exploitability). However it may be
blocked by corporate proxies or network policies that enforce HTTPS-only.

**Fix:** Change to `https://www.thekelleys.org.uk/` (the site serves HTTPS).

---

## BUG-5 — LOW — `Containerfile` silences `bootc container lint` failures with `|| true`

**File:** `Containerfile:3`

**Evidence:**
```dockerfile
RUN bootc container lint || true
```

**Impact:** If the image fails `bootc container lint`, the Containerfile build succeeds anyway.
The lint result is printed to stdout (visible in the build log) but does not cause a build
failure. This means the `just build-containerfile` path (the Containerfile-based alternative
build) cannot be used as a quality gate.

**Note:** The `just lint` recipe (Justfile:569) correctly runs `bootc container lint` **without**
`|| true`, so the lint check is properly enforced there.

**Fix:** Remove `|| true` from Containerfile:3 if Containerfile builds are meant to be a quality
gate. Or document that `just lint` (not `just build-containerfile`) is the canonical lint path.

---

## OBSERVATION — `os-release.bst` image metadata is hardcoded (not configurable)

**File:** `elements/oci/os-release.bst:10-16`

The FIXME comment (`# FIXME: configurable`) acknowledges that `IMAGE_NAME`, `IMAGE_VENDOR`,
`IMAGE_REF`, `IMAGE_FLAVOR`, `IMAGE_TAG` are hardcoded to `dakota` / `projectbluefin` / `latest`.
These are environment variables in the element, not BuildStream options, so they cannot be
overridden without editing the file. This affects anyone forking dakota to build their own image.
Not a bug per se — it is an acknowledged limitation — but worth noting.

---

## OBSERVATION — JWT authentication for BST remote execution is commented out and incomplete

**File:** `.github/workflows/build.yml:25-40`

Two `# FIXME: Make the build with JWT work` comments bracket commented-out OIDC/JWT token
setup. The remote execution configuration in the push block (BUG-1) also references
`cache.projectbluefin.io:11002` using mTLS client certificates rather than JWT. The commented
code was never completed.

---

## OBSERVATION — `gnome-shell-extensions.bst` FIXME about disable-ext-validator

**File:** `elements/bluefin/gnome-shell-extensions.bst:12-13`

```yaml
  # Since we use gnomeos nightly atm, no extension works with the current shell version
  - bluefin/shell-extensions/disable-ext-validator.bst
```

This is a known workaround: the GNOME Shell extension validator is disabled because the gnomeos
nightly shell version is newer than all extensions support. This means extension compatibility is
not checked at install time.

---

## OBSERVATION — `patches/gnome-build-meta/4289.patch` references upstream CI scripts not present in dakota

The 4289.patch introduces a `source-plugins/generated.py` custom BST source plugin and a
`generated:` source kind for boot keys. This patch is from upstream gnome-build-meta (a GNOME
project). The patch also references `.gitlab-ci/scripts/` and `files/boot-keys/` which are
upstream gnome-build-meta infrastructure. This patch is applied to the `gnome-build-meta`
junction — it is upstream infrastructure, not dakota's own code — but worth noting that dakota
carries a significant upstream patch.
