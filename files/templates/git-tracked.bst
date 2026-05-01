# Template: git_repo source tracked by bst source track
#
# Instructions:
#   1. Replace TEMPLATE_NAME with the package name
#   2. Replace GITHUB_ORG / GITHUB_REPO with the upstream values
#   3. Set track: to the appropriate pattern:
#        main          — latest commit on main
#        master        — latest commit on master
#        v*            — latest tag matching v*
#        [0-9]*        — latest tag matching 0.x.y (no v prefix)
#   4. Run: just bst source track elements/bluefin/TEMPLATE_NAME.bst
#      (this replaces PLACEHOLDER_REF with the real commit SHA)
#   5. Fill in build-commands and install-commands below
#   6. Add bluefin/TEMPLATE_NAME.bst to elements/bluefin/deps.bst
#   7. Run: just validate elements/bluefin/TEMPLATE_NAME.bst
#   8. Run: just bst build elements/bluefin/TEMPLATE_NAME.bst
#   9. Add to .github/workflows/track-bst-sources.yml under auto-merge matrix

kind: manual

sources:
- kind: git_repo
  url: github:GITHUB_ORG/GITHUB_REPO.git
  track: main
  ref: PLACEHOLDER_REF

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  build-commands: []

  install-commands:
  - |
    install -Dm755 -t "%{install-root}%{bindir}" TEMPLATE_NAME
  - |
    %{install-extra}
