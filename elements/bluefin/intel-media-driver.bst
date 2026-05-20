kind: manual

build-depends:
- freedesktop-sdk.bst:extensions/platform-vaapi-intel/intel-media-driver.bst
- freedesktop-sdk.bst:extensions/platform-vaapi-intel/gmmlib.bst

depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst
- freedesktop-sdk.bst:components/libva.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - |
    # Install iHD VA driver to the standard DRI path (libva default search path)
    install -dm755 "%{install-root}%{libdir}/dri"
    install -Dm755       "%{libdir}/dri/intel-vaapi-driver/iHD_drv_video.so"       "%{install-root}%{libdir}/dri/iHD_drv_video.so"

    # Install gmmlib runtime SO to standard lib path
    # (iHD_drv_video.so links against libigdgmm.so at runtime)
    for lib in "%{libdir}/dri/intel-vaapi-driver/lib/"libigdgmm.so.[0-9]*; do
      [ -f "$lib" ] || continue
      install -Dm755 "$lib" "%{install-root}%{libdir}/$(basename "$lib")"
    done
  - "%{install-extra}"
