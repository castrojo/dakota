kind: autotools

# Embedded Common Lisp runtime — required by saturn-cl-deps and saturn at runtime.
# Version pinned to 24.5.10 (same as Saturn's Flatpak manifest).
#
# Use system GMP to avoid ECL's bundled GMP inheriting CFLAGS and failing its
# configure ABI detection. CFLAGS: -std=c99 -O2 are sufficient (no -fasm needed).

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-autotools.bst
  - freedesktop-sdk.bst:components/gmp.bst

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
  - freedesktop-sdk.bst:components/gmp.bst

variables:
  conf-local: "--with-gmp=/usr"

environment:
  CFLAGS: "-std=c99 -O2"

sources:
  - kind: git_repo
    url: gitlab:embeddable-common-lisp/ecl.git
    ref: 24.5.10-0-ge4269ea51fffd742f92cb19a89f52af3cdf0d9f8  # 24.5.10
