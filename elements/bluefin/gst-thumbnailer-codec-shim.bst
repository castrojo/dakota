kind: manual

sources:
  - kind: local
    path: files/gst-thumbnailer-codec-shim

build-depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

depends:
  - freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
    - |
      install -Dm755 gst-thumbnailer-codec-shim \
        "%{install-root}/usr/lib/bluefin/gst-thumbnailer-codec-shim"
    - |
      install -Dm644 z-gst-video-thumbnailer-bluefin.thumbnailer \
        "%{install-root}/usr/share/thumbnailers/z-gst-video-thumbnailer-bluefin.thumbnailer"
