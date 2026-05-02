kind: compose

build-depends:
  - oci/layers/bluefin-nvidia-stack.bst

config:
  exclude:
    - devel
    - debug
    - static-blocklist
