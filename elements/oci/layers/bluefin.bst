kind: compose

build-depends:
  - freedesktop-sdk.bst:components/gcc.bst
  - oci/layers/bluefin-runtime.bst
  - oci/layers/bluefin-layer-marker.bst

config:
  exclude:
    - debug
    - extra
    - static-blocklist
