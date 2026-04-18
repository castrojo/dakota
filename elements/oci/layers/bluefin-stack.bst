kind: stack

depends:
  - bluefin/deps.bst
  - gnome-build-meta.bst:oci/gnomeos/stack.bst

public:
  bst:
    integration-commands:
      # Wipe /var (may contain build-time state) and all FHS dirs that should
      # be symlinks into /var, then recreate with the correct structure.
      # Relative symlinks (var/home not /var/home) match zirconium-hawaii and
      # are safer in chroot/deploy tooling flows.
      - rm -rfv /home /root /opt /mnt /srv /var
      - mkdir -p /var/home /var/roothome /var/opt /var/mnt /var/srv /var/tmp
      - ln -s var/home /home
      - ln -s var/roothome /root
      - ln -s var/opt /opt
      - ln -s var/mnt /mnt
      - ln -s var/srv /srv
