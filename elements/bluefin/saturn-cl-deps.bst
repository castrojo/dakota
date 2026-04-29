kind: manual

# Compiles Saturn's Common Lisp dependencies (CFFI GTK4 bindings etc.) into
# static .a archives that saturn.bst links against.
# build-cl-deps.lsp loads all CL systems via ASDF and produces one monolithic
# static library.

build-depends:
  - bluefin/ecl.bst
  - gnome-build-meta.bst:sdk/gtk.bst          # headers needed for CL GTK4 bindings
  - freedesktop-sdk.bst:components/pkg-config.bst  # build-cl-deps.lsp calls pkg-config --libs gtk4
  - freedesktop-sdk.bst:components/gcc.bst    # ECL spawns gcc to compile Lisp→C intermediates

depends:
  - bluefin/ecl.bst  # CL static archives link against ECL at runtime

variables:
  strip-binaries: ""  # static archives are not ELF executables

config:
  build-commands:
    - ecl --load build-cl-deps.lsp

  install-commands:
    # Install the monolithic static archive where saturn.bst expects it
    - install -d "%{install-root}%{libdir}/ecl-24.5.10/"
    - install -m644 saturn-cl-deps--all-systems.a "%{install-root}%{libdir}/ecl-24.5.10/"

sources:
  # Saturn source files (build-cl-deps.lsp + saturn-cl-deps.asd must be at root)
  - kind: git_repo
    url: github:kolunmi/Saturn.git
    track: main
    ref: 868b15407fd9c8b58ed07e3c5d4a778c1d1db9bd

  # Common Lisp library dependencies — directory: names must match build-cl-deps.lsp expectations
  - kind: git_repo
    url: github:sionescu/bordeaux-threads.git
    directory: bordeaux-threads
    ref: v0.8.8-0-g076fe2380abbc59b06e495dc7a35aea8eb26ba3b  # v0.8.8

  - kind: git_repo
    url: github:sharplispers/split-sequence.git
    directory: split-sequence
    ref: 89a10b4d697f03eb32ade3c373c4fd69800a841a

  - kind: git_repo
    url: codeberg:pcostanza/closer-mop.git
    directory: closer-mop
    ref: c6b1f2db0d77aea961e871f268b6fdcdc90c7510

  - kind: git_repo
    url: github:trivial-garbage/trivial-garbage.git
    directory: trivial-garbage
    ref: 3474f6414b73d4e3aa2d5c53080f4247a34f6380

  - kind: git_repo
    url: github:lmj/global-vars.git
    directory: global-vars
    ref: c749f32c9b606a1457daa47d59630708ac0c266e

  # iterate and alexandria are on gitlab.common-lisp.net whose git protocol
  # is incompatible with BST's dulwich version. Use GitLab tarball archives instead.
  - kind: tar
    url: https://gitlab.common-lisp.net/iterate/iterate/-/archive/d27d7ff4821b9d8b011afaaa866d7993942430f4/iterate-d27d7ff4821b9d8b011afaaa866d7993942430f4.tar.gz
    ref: 83f214fbb0688040c5b869854deacef39a42def8a0e66690464b222dbfda7e00
    directory: iterate

  - kind: git_repo
    url: github:cl-babel/babel.git
    directory: babel
    ref: 4eaf3f228be4f6860ccc0b0fbb4c1781a1ee6597

  - kind: tar
    url: https://gitlab.common-lisp.net/alexandria/alexandria/-/archive/390a096b4e1f9f85878ac313908c1c2ab2223ab6/alexandria-390a096b4e1f9f85878ac313908c1c2ab2223ab6.tar.gz
    ref: 09a27388470cf98f3749cb9909b27dc2d3949fccefdf16bbfbca304a981dbda6
    directory: alexandria

  - kind: git_repo
    url: github:trivial-features/trivial-features.git
    directory: trivial-features
    ref: 18a5cfafa5ca2565f4297d1d986409facff68f00

  - kind: git_repo
    url: github:cffi/cffi.git
    directory: cffi
    ref: 71fdf5d4864dd07a74534c953350041ceaa93f0e

  - kind: git_repo
    url: github:kolunmi/cl-cffi-glib.git
    directory: cl-cffi-glib
    ref: c781aa21650f388a4617972252902d0da1969d98

  - kind: git_repo
    url: github:kolunmi/cl-cffi-gtk4.git
    directory: cl-cffi-gtk4
    ref: fabe1c82341b227ffbb6c4d9ec681aaa337bcc06

  - kind: git_repo
    url: github:kolunmi/cl-cffi-cairo.git
    directory: cl-cffi-cairo
    ref: b0d52cbd0d956f1ca1d154c872f6ff5696e3f7a6

  - kind: git_repo
    url: github:kolunmi/cl-cffi-pango.git
    directory: cl-cffi-pango
    ref: 3996c3865367609b870d271945a32262f04bf846

  - kind: git_repo
    url: github:kolunmi/cl-cffi-graphene.git
    directory: cl-cffi-graphene
    ref: bedeb6c5f8b82b524079729907d55fcf201b91c9

  - kind: git_repo
    url: github:kolunmi/cl-cffi-gdk-pixbuf.git
    directory: cl-cffi-gdk-pixbuf
    ref: b8bf37fb111c434e1adaa242044c03408940ea37
