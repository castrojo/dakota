kind: manual

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

runtime-depends:
  - bluefin/brew.bst

sources:
  - kind: remote
    url: github_files:ublue-os/packages/releases/download/homebrew-2026-03-03-01-31-47/homebrew-x86_64.tar.zst
    ref: 46e546da7ac2a4e916f0c89db61e9c0292b90e8b4b6b5662d2c5df5f668fb40c
variables:
  strip-binaries: ""

config:
  install-commands:
    - |
      mkdir -p "%{install-root}%{datadir}"
      mv homebrew-x86_64.tar.zst "%{install-root}%{datadir}/homebrew.tar.zst"
    - |
      %{install-extra}
