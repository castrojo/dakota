kind: meson

# Saturn — GNOME launcher written in C + Embedded Common Lisp.
# Tracks main branch per-commit since it is prerelease software.
#
# ECL path patch: upstream src/meson.build hardcodes /app/lib/ecl-24.5.10/
# (the Flatpak path). BST installs ECL to /usr/lib/ecl-24.5.10/.
# We patch it via configure-commands before meson setup runs.
#
# Keybinding: Super+Space → saturn, installed as a dconf distro keyfile.

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-meson.bst
  - freedesktop-sdk.bst:components/pkg-config.bst
  - gnome-build-meta.bst:sdk/blueprint-compiler.bst
  - gnome-build-meta.bst:sdk/gtksourceview.bst
  - bluefin/ecl.bst
  - bluefin/saturn-cl-deps.bst

depends:
  - gnome-build-meta.bst:sdk/gtk.bst
  - gnome-build-meta.bst:sdk/libadwaita.bst
  - gnome-build-meta.bst:sdk/gtksourceview.bst
  - gnome-build-meta.bst:sdk/libglycin-gtk4.bst
  - bluefin/gtk4-layer-shell.bst
  - bluefin/ripgrep.bst
  - bluefin/ecl.bst

config:
  configure-commands:
    - sed -i "s|/app/lib/ecl-24.5.10/|/usr/lib/ecl-24.5.10/|g" src/meson.build
    - "%{meson}"

  install-commands:
    - "%{meson-install}"
    - install -Dm644 10-saturn-keybinding
        "%{install-root}%{sysconfdir}/dconf/db/distro.d/10-saturn-keybinding"

sources:
  - kind: git_repo
    url: github:kolunmi/Saturn.git
    track: main
    ref: 868b15407fd9c8b58ed07e3c5d4a778c1d1db9bd
  - kind: local
    path: files/dconf/10-saturn-keybinding
