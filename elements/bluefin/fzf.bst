kind: manual

sources:
- kind: tar
  base-dir: ""
  (?):
  - arch == "x86_64":
      url: github_files:junegunn/fzf/releases/download/v0.71.0/fzf-0.71.0-linux_amd64.tar.gz
      ref: 22639bb38489dbca8acef57850cbb50231ab714d0e8e855ac52fae8b41233df4
  - arch == "aarch64":
      url: github_files:junegunn/fzf/releases/download/v0.71.0/fzf-0.71.0-linux_arm64.tar.gz
      ref: 98b7d322efae9c37e4bfbbab1cbcd8722eb742d9399511f96375feb40cc35d1d

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
