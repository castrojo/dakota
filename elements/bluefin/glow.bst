kind: manual

sources:
- kind: tar
  (?):
  - arch == "x86_64":
      url: github_files:charmbracelet/glow/releases/download/v2.1.2/glow_2.1.2_Linux_x86_64.tar.gz
      ref: 6063d4f2af8a82a5f4bba0831e165de9381660aa8b41df4816d0106a265b07d5
  - arch == "aarch64":
      url: github_files:charmbracelet/glow/releases/download/v2.1.2/glow_2.1.2_Linux_arm64.tar.gz
      ref: cf63abebcb50b72909db965d78290e7cecbf17a900e84705dc84addbb6952099

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - |
    install -Dm755 -t "%{install-root}%{bindir}" glow
  - |
    install -Dm644 -t "%{install-root}%{datadir}/bash-completion/completions" completions/glow.bash
    install -Dm644 -t "%{install-root}%{datadir}/zsh/site-functions" completions/glow.zsh
    install -Dm644 -t "%{install-root}%{datadir}/fish/vendor_completions.d" completions/glow.fish
  - |
    install -Dm644 -t "%{install-root}%{datadir}/man/man1" manpages/glow.1.gz
  - |
    %{install-extra}
