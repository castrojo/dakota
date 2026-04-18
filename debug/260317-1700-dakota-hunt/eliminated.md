# Eliminated Hypotheses — dakota debug hunt 260317-1700

> These are hypotheses investigated and disproven. Recording them is as important as confirmed
> bugs — it prevents re-investigation of the same dead ends.

---

## ELIMINATED-1 — riscv64 / missing arch in binary dispatcher elements causes silent failures

**Hypothesis:** Binary dispatcher elements (tailscale, zig, 1password, fzf, glow, gum,
brew-tarball) only define `x86_64` and `aarch64` conditions. A missing arch (like riscv64)
would silently produce an empty stack element, causing a confusing build failure.

**Why eliminated:**
1. BuildStream produces an empty stack for non-matching arch conditions — this is valid and
   intentional behavior, not a bug.
2. User confirmed: "we don't care about arm or riscv" — x86_64 is the only target in scope.
3. All x86_64 dispatcher paths are correctly defined in every relevant element.

---

## ELIMINATED-2 — `just bst source track "$ELEMENTS"` passes elements as single string

**Hypothesis:** The `track-bst-sources.yml` workflow sets `ELEMENTS` as a multi-line string
and passes it as `just bst --no-interactive source track "$ELEMENTS"`, which would pass the
entire list as a single quoted argument rather than multiple arguments.

**Why eliminated:**
- `ELEMENTS` is set with a `>-` YAML block scalar (folded, no newlines), becoming a single
  space-separated string.
- The Justfile `bst` recipe uses `{{ARGS}}` (just's variadic splat, unquoted), which performs
  word-splitting on the space-separated string.
- The `bash -c 'bst --colors "$@"' -- ${BST_FLAGS:-} {{ARGS}}` idiom correctly passes each
  space-separated element as a separate positional arg via `"$@"`.
- Evidence: commit `f314395 chore(deps): track Bluefin element sources (#115)` confirms this
  has worked in practice.

---

## ELIMINATED-3 — 1password desktop version Debian revision suffix causes format mismatch

**Hypothesis:** The Debian Packages file returns version `8.12.6.7200-1` (with Debian revision
`-1` suffix). The URL format is `1password-8.12.6.7200.x64.tar.gz`. The comparison would always
be unequal (triggering daily spurious updates), and the sed substitution would produce an invalid
URL like `1password-8.12.6.7200-1.x64.tar.gz` (with revision embedded), breaking the download.

**Why eliminated:**
- Actual fetch from `downloads.1password.com` Packages file returns `Version: 8.12.8` — a clean
  semantic version with no Debian revision suffix.
- The CURRENT extraction regex `grep -oP '1password-\K[0-9.]+(?=\.x64)'` correctly extracts
  `8.12.6` from the bst URL.
- The comparison `8.12.6 != 8.12.8` correctly triggers an update.
- The sed substitution `s|1password-8.12.6.x64|1password-8.12.8.x64|g` produces the correct
  URL `1password-8.12.8.x64.tar.gz`.
- Logic is sound. No bug here.

---

## ELIMINATED-4 — Non-ASCII characters in Justfile/build.yml comment decorators are bugs

**Hypothesis:** The Unicode box-drawing characters (U+2500 `─`, U+25CF `●`, U+25CD `◍`,
U+25D4 `◔`) scattered throughout Justfile section headers and gum output strings might cause
shell parsing errors on some locales/terminals.

**Why eliminated:**
- These characters appear exclusively in shell comments (`# ── Section ──`) or in `gum style`
  string arguments — never in variable names, condition expressions, or command names.
- Shell comments are not parsed. String arguments to `gum` are passed as-is.
- Only the Greek chars in `build.yml:87` (BUG-1) are in an expression context (`"$CASD_CLIENT_ΚΕΥ"`).
- All other non-ASCII in build.yml is in YAML comments (lines 49, 154, 166, 188, 200, 212) —
  not evaluated by bash or the YAML parser.

---

## ELIMINATED-5 — `|| true` on `podman rmi` and `podman images` in export recipe is dangerous

**Hypothesis:** `|| true` on cleanup commands might mask real errors.

**Why eliminated:**
- `podman rmi "$IMAGE_ID" || true` (Justfile:106) — `rmi` on an intermediate image ID that may
  already be gone (e.g. if the squash failed and nothing was loaded). This is a legitimate cleanup
  guard; failing to remove an intermediate image is not a build error.
- `podman images | grep ... || true` (Justfile:109) — diagnostic only; grep returns non-zero when
  nothing matches. Silencing this is correct.
- Neither affects build correctness.

---

## ELIMINATED-6 — `validate-renovate.yml` contains bugs

**Hypothesis:** The Renovate config validation workflow might have issues (pinned action SHA,
wrong config path, etc.).

**Why eliminated:**
- The workflow is minimal (21 lines) and correct: it uses `actions/checkout` pinned by SHA and
  `suzuki-shunsuke/github-action-renovate-config-validator` pinned by SHA.
- Config path `.github/renovate.json5` is correct (the file exists).
- No issues found.

---

## ELIMINATED-7 — `sudo-rs` build missing install of PAM config files

**Hypothesis:** `sudo-rs` installs the binary but might be missing PAM configuration files
needed at runtime, causing sudo to fail with PAM errors on boot.

**Why eliminated:**
- `sudo-rs` depends on `freedesktop-sdk.bst:components/linux-pam.bst` at runtime, which should
  provide the PAM infrastructure.
- The `sudo-rs` project itself handles PAM configuration differently from traditional sudo; it
  reads `/etc/pam.d/sudo` which is provided by the PAM stack.
- No evidence of missing PAM config in the element; the overlap-whitelist correctly lists the
  binary paths (suggesting the authors are aware of the conflict with system sudo).
- Cannot confirm without actually building and running — classified as out-of-scope for static
  analysis.

---

## ELIMINATED-8 — `jetbrains-mono-nerd-font.bst` `kind: remote` without `track:` means version is frozen

**Hypothesis:** Using `kind: remote` with a hardcoded URL and no `track:` means the nerd font
version is never automatically updated.

**Why eliminated:**
- This is intentional design, not a bug. The `track-bst-sources.yml` workflow does not include
  `jetbrains-mono-nerd-font.bst` in any tracking group — it is manually updated.
- The comment `# FIXME: build the nerd fonts ourselves` acknowledges this is a known limitation.
- Same pattern is used for wallpapers. Intentional, not a defect.

---

## ELIMINATED-9 — `plymouthd.defaults` sets wrong theme

**Hypothesis:** `plymouthd.defaults` sets `Theme=bgrt` but the element installs a `spinner/`
watermark — these might conflict, causing the wrong boot splash.

**Why eliminated:**
- The `bgrt` theme is the default GNOME OS theme that reads the system BGRT (ACPI Boot Graphics
  Resource Table) logo. The element also installs `watermark.png` into the `spinner` theme and a
  pixmap `bluefin-boot-logo.png`. The `plymouthd.defaults` file is installed to override the
  default, setting the theme to `bgrt`. This is standard plymouth configuration; the two themes
  serve different purposes and there is no conflict.
- `ShowDelay=0` and `DeviceTimeout=8` are normal production values.

---

## ELIMINATED-10 — `track-bst-sources.yml` matrix `auto_merge` for shell-extensions is dangerous

**Hypothesis:** Auto-merging shell extension updates could break the GNOME Shell integration
silently since the `disable-ext-validator.bst` workaround means extensions are never validated.

**Why eliminated:**
- While technically a concern (extensions may be incompatible with the nightly GNOME Shell),
  this is an explicit architectural decision documented in `gnome-shell-extensions.bst:12-13`.
  The auto-merge is a workflow policy choice, not a code bug.
- Out of scope for this bug hunt (policy, not defect).
