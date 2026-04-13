kind: manual

sources:
  - kind: git_repo
    url: github:StorageB/custom-command-menu.git
    track: v*
    ref: f7d4eb671aece43c9ee8b52bf8d740f948202bf4

build-depends:
  - freedesktop-sdk.bst:public-stacks/buildsystem-make.bst
  - freedesktop-sdk.bst:components/jq.bst

depends:
  - freedesktop-sdk.bst:components/gettext.bst
  - gnome-build-meta.bst:sdk/glib.bst
  - gnome-build-meta.bst:core/gnome-shell.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - |
      _uuid="$(jq -r .uuid metadata.json)"

      glib-compile-schemas --strict schemas/
      install -d "%{install-root}/usr/share/gnome-shell/extensions/${_uuid}"
      cp -R ./* "%{install-root}/usr/share/gnome-shell/extensions/${_uuid}/"
    - |
      %{install-extra}
