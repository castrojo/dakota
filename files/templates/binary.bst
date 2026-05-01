# Template: pre-built binary (multi-arch GitHub Release tarball)
#
# Instructions:
#   1. Replace TEMPLATE_NAME with the binary name (e.g. glow)
#   2. Replace TEMPLATE_REPO with github owner/repo (e.g. charmbracelet/glow)
#   3. Replace VERSION with the initial version (e.g. 2.1.2)
#   4. Set base-dir: "" only if the tarball has no wrapping directory
#      (e.g. fzf ships a bare binary; most tarballs wrap in a subdir — remove base-dir if so)
#   5. Adjust the URL filename pattern to match the upstream release naming
#   6. Run: just bst source track elements/bluefin/TEMPLATE_NAME.bst
#   7. Add bluefin/TEMPLATE_NAME.bst to elements/bluefin/deps.bst
#   8. Run: just validate elements/bluefin/TEMPLATE_NAME.bst
#   9. Run: just bst build elements/bluefin/TEMPLATE_NAME.bst
#
# Common URL filename patterns (check upstream releases page):
#   glow:  glow_VERSION_Linux_x86_64.tar.gz
#   fzf:   fzf-VERSION-linux_amd64.tar.gz
#   other: TEMPLATE_NAME-VERSION-linux-amd64.tar.gz

kind: manual

sources:
- kind: tar
  base-dir: ""
  (?):
  - arch == "x86_64":
      url: github_files:TEMPLATE_REPO/releases/download/vVERSION/TEMPLATE_NAME-VERSION-linux_amd64.tar.gz
      ref: PLACEHOLDER_SHA256_X86_64
  - arch == "aarch64":
      url: github_files:TEMPLATE_REPO/releases/download/vVERSION/TEMPLATE_NAME-VERSION-linux_arm64.tar.gz
      ref: PLACEHOLDER_SHA256_AARCH64

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - |
    install -Dm755 -t "%{install-root}%{bindir}" TEMPLATE_NAME
  - |
    %{install-extra}
