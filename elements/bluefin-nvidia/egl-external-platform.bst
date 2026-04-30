# Header-only library that defines NVIDIA's pluggable EGL platform API.
# Build-dep for nvidia-egl-wayland.bst (consumes eglexternalplatform.pc).
kind: meson

build-depends:
- freedesktop-sdk.bst:components/meson.bst
- freedesktop-sdk.bst:components/pkg-config.bst

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

sources:
- kind: git_repo
  url: github:NVIDIA/eglexternalplatform.git
  track: '*'
  ref: 1.2.1-0-gcf9f10589775c1b4d90f1df6f417f8cf1bed7ec6

variables:
  strip-binaries: ''
