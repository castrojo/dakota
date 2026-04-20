kind: manual

sources:
- kind: git_repo
  url: github:Vladimir-csp/xdg-terminal-exec.git
  track: 'v[0-9]*.[0-9]*.[0-9]*'
  ref: v0.14.2-0-ge675f61c1fa1175b1295f9d2ed5338f73a2cb679

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - |
    install -Dm755 xdg-terminal-exec "%{install-root}%{bindir}/xdg-terminal-exec"
  - |
    install -Dm644 xdg-terminals.list "%{install-root}%{datadir}/xdg-terminal-exec/xdg-terminals.list"
  - |
    %{install-extra}
