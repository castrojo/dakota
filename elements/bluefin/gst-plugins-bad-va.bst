kind: manual

build-depends:
- freedesktop-sdk.bst:components/gstreamer-plugins-bad.bst

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
- freedesktop-sdk.bst:components/gstreamer.bst
- freedesktop-sdk.bst:components/gstreamer-plugins-base.bst
- freedesktop-sdk.bst:components/libva.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - |
    install -Dm755 \
      "%{libdir}/gstreamer-1.0/libgstva.so" \
      "%{install-root}%{libdir}/gstreamer-1.0/libgstva.so"
  - "%{install-extra}"
