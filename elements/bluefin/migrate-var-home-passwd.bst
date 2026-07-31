kind: manual
description: |
  One-shot, idempotent boot-time migration of legacy /var/home/<user> (and
  /var/roothome) passwd home fields to the post-#1117 bind-mount layout.
  Installs from before 2026-06-29 carry the old fields, which breaks snapd
  and makes path-identity comparisons disagree, which can break GNOME file
  operations such as sending files to Trash; see projectbluefin/dakota#1184.

  Ships the migration script, its oneshot unit (ordered before
  systemd-user-sessions), and a preset to enable it.

sources:
- kind: local
  path: files/migrate-var-home-passwd

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

config:
  install-commands:
  - |
    install -Dm755 bluefin-migrate-var-home-passwd \
            "%{install-root}/usr/libexec/bluefin-migrate-var-home-passwd"
  - |
    install -Dm644 bluefin-migrate-var-home-passwd.service \
            "%{install-root}%{indep-libdir}/systemd/system/bluefin-migrate-var-home-passwd.service"
  - |
    PRESET="%{install-root}%{indep-libdir}/systemd/system-preset/80-bluefin-migrate-var-home-passwd.preset"
    install -Dm644 /dev/null "$PRESET"
    cat > "$PRESET" <<'PRESET'
    enable bluefin-migrate-var-home-passwd.service
    PRESET
