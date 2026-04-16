kind: manual

depends:
  - gnome-build-meta.bst:sdk/glib.bst
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - mkdir -p "%{install-root}%{datadir}/glib-2.0/schemas/"
    - |
      cat <<EOF > "%{install-root}%{datadir}/glib-2.0/schemas/zz3-bluefin-unsupported-stuff.gschema.override"
      [org.gnome.shell]
      disable-extension-version-validation=true
      enabled-extensions=['caffeine@patapon.info', 'appindicatorsupport@rgcjonas.gmail.com', 'blur-my-shell@aunetx', 'dash-to-dock@micxgx.gmail.com', 'gsconnect@andyholmes.github.io', 'custom-command-list@storageb.github.com', 'search-light@icedman.github.com']
      EOF

    - "%{install-extra}"
