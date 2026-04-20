kind: autotools

# Embedded Common Lisp runtime — required by saturn-cl-deps and saturn at runtime.
# Version pinned to 24.5.10 (same as Saturn's Flatpak manifest).

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

environment:
  # ECL has known compiler issues without c99 mode and these optimisation flags
  CFLAGS: "-std=c99 -O2 -fasm"

sources:
  - kind: git_repo
    url: gitlab:embeddable-common-lisp/ecl.git
    ref: 24.5.10-0-ge4269ea51fffd742f92cb19a89f52af3cdf0d9f8  # 24.5.10
