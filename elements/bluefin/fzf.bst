kind: manual

sources:
- kind: tar
  base-dir: ""
  (?):
  - arch == "x86_64":
      url: github_files:junegunn/fzf/releases/download/v0.72.0/fzf-0.72.0-linux_amd64.tar.gz
      ref: 0e58e4bd0b3c5d68c56b54c460a6863d0de79633ed18d388575a960ab447b006
  - arch == "aarch64":
      url: github_files:junegunn/fzf/releases/download/v0.72.0/fzf-0.72.0-linux_arm64.tar.gz
      ref: a0a5b50730f568c5f08b8dbba1e6e598db253e1856d371290086786b889b996b

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - |
    install -Dm755 -t "%{install-root}%{bindir}" fzf
  - |
    %{install-extra}
