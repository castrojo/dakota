kind: manual

sources:
- kind: local
  path: files/just-overrides
- kind: local
  path: files/otel

build-depends:
- freedesktop-sdk.bst:public-stacks/runtime-minimal.bst

variables:
  strip-binaries: ""

public:
  bst:
    overlap-whitelist:
    - /usr/share/ublue-os/just/default.just
    - /usr/share/ublue-os/just/changelog.just
    - /usr/share/ublue-os/just/system.just
    - /usr/share/ublue-os/just/otel/ujust-report-config.yaml
    - /usr/share/ublue-os/just/update.just

config:
  install-commands:
  - install -Dm644 default.just "%{install-root}/usr/share/ublue-os/just/default.just"
  - install -Dm644 changelog.just "%{install-root}/usr/share/ublue-os/just/changelog.just"
  - install -Dm644 system.just "%{install-root}/usr/share/ublue-os/just/system.just"
  - install -Dm644 ujust-report-config.yaml "%{install-root}/usr/share/ublue-os/just/otel/ujust-report-config.yaml"
  - install -Dm644 flutter.just "%{install-root}/usr/share/ublue-os/just/flutter.just"
  - install -Dm644 update.just "%{install-root}/usr/share/ublue-os/just/update.just"
  - "%{install-extra}"
