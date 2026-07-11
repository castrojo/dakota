# ⚠️ WARNING: DO NOT ADD LOCAL PATCHES OR PATCH QUEUES TO THIS JUNCTION.
# Applying any patch to this junction alters its source hash and invalidates
# the cache keys for ALL downstream elements imported from it (including WebKit).
# This completely destroys cache reuse against gbm.gnome.org:11003 and forces
# hours of compile time from scratch. Keep this junction 100% clean of patches.

kind: junction

sources:
- kind: git_repo
  url: gnome:gnome-build-meta.git
  track: gnome-50
  ref: 50.2-4-g01ed76232baf1063f0ef3ca1f3b2c16f30e82f35

config:
  options:
    arch: '%{arch}'
    (?):
    - x86_64_v3:
        x86_64_v3: true

  overrides:
    # This along with the patches is required and has to match what gnome-build-meta is using
    freedesktop-sdk.bst: freedesktop-sdk.bst

    # Replace the element so the OCI image doesn't have any apps
    core/meta-gnome-core-apps.bst: core/meta-gnome-core-apps.bst

    # Permanent policy: dakota always ships pure upstream bootc (bootc-dev/bootc,
    # tracked via auto/track-bootc), never gnome-build-meta's pinned version.
    # Do not remove this override even if gnome-50 catches up.
    gnomeos-deps/bootc.bst: gnomeos-deps/bootc.bst

    gnomeos-deps/plymouth-gnome-theme.bst: bluefin/plymouth-bluefin-theme.bst

    # Replace the element so the OCI image generates Bluefin's os-release file
    oci/integration/os-release.bst: oci/os-release.bst

    # Override the signed kernel modules with the plain ones
    gnomeos/initramfs/signed-modules.bst: bluefin/unsigned-modules.bst

    plugins/buildstream-plugins.bst: plugins/buildstream-plugins.bst
    plugins/buildstream-plugins-community.bst: plugins/buildstream-plugins-community.bst
