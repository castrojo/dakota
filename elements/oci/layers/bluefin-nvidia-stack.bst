kind: stack

depends:
  - oci/layers/bluefin-stack.bst
  - bluefin-nvidia/deps.bst

public:
  bst:
    integration-commands:
    # Re-run depmod against the composed root so modprobe sees the
    # NVIDIA modules alongside FDSDK's modules.dep entries for the
    # in-tree modules (nvidia-drm → nvidia-modeset → nvidia).
    - |
      KVER=$(ls /usr/lib/modules | head -n1)
      if [ -z "$KVER" ]; then
          echo "FATAL: no kernel under /usr/lib/modules at integration time" >&2
          exit 1
      fi
      depmod -a "$KVER"
