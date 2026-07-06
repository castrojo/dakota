kind: manual

sources:
  - kind: local
    path: files/oci/bluefin-layer-marker

variables:
  strip-binaries: ""

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

config:
  install-commands:
    - install -Dm0644 bluefin-layer-marker "%{install-root}/usr/lib/projectbluefin/cas-epoch"
