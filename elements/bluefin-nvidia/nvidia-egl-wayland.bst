# NVIDIA's EGL-Wayland external platform library (MIT). Provides direct
# EGL/GBM Wayland support; without it GNOME Shell only talks to NVIDIA
# via XWayland. Released independently from the driver itself.
kind: meson

build-depends:
- freedesktop-sdk.bst:components/meson.bst
- freedesktop-sdk.bst:components/pkg-config.bst
- freedesktop-sdk.bst:components/gcc-base.bst
- freedesktop-sdk.bst:bootstrap/binutils.bst
- freedesktop-sdk.bst:components/wayland.bst
- freedesktop-sdk.bst:components/wayland-protocols.bst
- freedesktop-sdk.bst:components/libdrm.bst
# FDSDK's libglvnd is built with -Dheaders=false (and rm's egl.pc),
# so we pull mesa-headers for EGL/GL headers + .pc files. libglvnd
# itself comes in transitively as a runtime-dep of mesa-headers.
- freedesktop-sdk.bst:components/mesa-headers.bst
- bluefin-nvidia/egl-external-platform.bst

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
- freedesktop-sdk.bst:components/wayland.bst
- freedesktop-sdk.bst:components/libdrm.bst

sources:
- kind: git_repo
  url: github:NVIDIA/egl-wayland.git
  track: '*'
  ref: 1.1.9-0-gcd0d19aa2742b1318527cabbcf279fb651c45d30

variables:
  strip-binaries: ''
