# Template: GNOME Shell extension
#
# Instructions:
#   1. Replace TEMPLATE_NAME with the extension slug (e.g. blur-my-shell)
#   2. Replace GITHUB_ORG / GITHUB_REPO with upstream values
#   3. Replace EXT_UUID with the extension's UUID (from metadata.json, e.g. blur-my-shell@aunetx)
#   4. Set track: to the appropriate pattern (v* for tagged releases, main for rolling)
#   5. Run: just bst source track elements/bluefin/shell-extensions/TEMPLATE_NAME.bst
#   6. Add 'bluefin/shell-extensions/TEMPLATE_NAME.bst' to the depends: list in
#      elements/bluefin/gnome-shell-extensions.bst (NOT deps.bst)
#   7. Run: just validate elements/bluefin/shell-extensions/TEMPLATE_NAME.bst
#   8. Run: just bst build elements/bluefin/shell-extensions/TEMPLATE_NAME.bst
#   9. Add to .github/workflows/track-bst-sources.yml under auto-merge matrix

kind: make

sources:
- kind: git_repo
  url: github:GITHUB_ORG/GITHUB_REPO.git
  track: v*
  ref: PLACEHOLDER_REF

build-depends:
- freedesktop-sdk.bst:public-stacks/buildsystem-make.bst
- freedesktop-sdk.bst:components/jq.bst

depends:
- freedesktop-sdk.bst:components/gettext.bst
- gnome-build-meta.bst:sdk/glib.bst
- gnome-build-meta.bst:core/gnome-shell.bst

variables:
  strip-binaries: ""

config:
  build-commands:
  - |
    %{make} build
  install-commands:
  - |
    _uuid="$(jq -r .uuid "EXT_UUID/metadata.json")"
    install -d "%{install-root}/usr/share/gnome-shell/extensions/${_uuid}"
    bsdtar xvf "${_uuid}.zip" \
      -C "%{install-root}/usr/share/gnome-shell/extensions/${_uuid}/" \
      --no-same-owner
    if [ -d "%{install-root}/usr/share/gnome-shell/extensions/${_uuid}/schemas" ]; then
      glib-compile-schemas --strict \
        "%{install-root}%{datadir}/gnome-shell/extensions/${_uuid}/schemas"
    fi
  - |
    %{install-extra}
