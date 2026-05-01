# List available commands
[group('info')]
default:
    @just --list

# ── Configuration ─────────────────────────────────────────────────────
export image_name := env("BUILD_IMAGE_NAME", "dakota")
export image_tag := env("BUILD_IMAGE_TAG", "latest")
export base_dir := env("BUILD_BASE_DIR", ".")
export filesystem := env("BUILD_FILESYSTEM", "btrfs")

# Same bst2 container image CI uses -- pinned by SHA for reproducibility
export bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:64eb0b4930d57a92710822898fb73af6cc1ae35d")

# VM settings
export vm_ram := env("VM_RAM", "8192")
export vm_cpus := env("VM_CPUS", "4")

# OCI metadata (dynamic labels)
export OCI_IMAGE_CREATED := env("OCI_IMAGE_CREATED", "")
export OCI_IMAGE_REVISION := env("OCI_IMAGE_REVISION", "")
export OCI_IMAGE_VERSION := env("OCI_IMAGE_VERSION", "latest")

# ── BuildStream wrapper ──────────────────────────────────────────────
# Runs any bst command inside the bst2 container via podman.
# Set BST_FLAGS env var to prepend flags (e.g. --no-interactive --config ...).
# Usage: just bst build oci/bluefin.bst
#        just bst show oci/bluefin.bst
#        BST_FLAGS="--no-interactive" just bst build oci/bluefin.bst
[group('dev')]
bst *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "${HOME}/.cache/buildstream"
    # BST_FLAGS env var allows CI to inject --no-interactive, --config, etc.
    # Word-splitting is intentional here (flags are space-separated).
    # shellcheck disable=SC2086
    podman run --rm \
        --privileged \
        --device /dev/fuse \
        --network=host \
        -v "{{justfile_directory()}}:/src:rw" \
        -v "${HOME}/.cache/buildstream:/root/.cache/buildstream:rw" \
        -w /src \
        "{{bst2_image}}" \
        bash -c 'bst --colors "$@"' -- ${BST_FLAGS:-} {{ARGS}}

# ── Build ─────────────────────────────────────────────────────────────
# Build the OCI image and load it into podman.
#
# Variant selects which top-level OCI element to build:
#   all     → both default and nvidia, sequentially  (refs below)
#   default → oci/bluefin.bst                        ({{image_name}}:{{image_tag}})
#   nvidia  → oci/bluefin-nvidia.bst                 ({{image_name}}-nvidia:{{image_tag}})
#
# Usage:
#   just build              # builds BOTH variants (default + nvidia)
#   just build default      # only default bluefin variant
#   just build nvidia       # only nvidia variant
#
# When variant=all we run the per-variant build recursively so each one
# also runs its own export + chunkify, leaving two podman refs:
# dakota:latest and dakota-nvidia:latest.
[group('build')]
build variant="all":
    #!/usr/bin/env bash
    set -euo pipefail

    if [ "{{variant}}" = "all" ]; then
        just build default
        just build nvidia
        exit 0
    fi

    case "{{variant}}" in
        default) ELEMENT="oci/bluefin.bst" ;;
        nvidia)  ELEMENT="oci/bluefin-nvidia.bst" ;;
        *) echo "ERROR: unknown variant '{{variant}}' (expected: all | default | nvidia)" >&2; exit 1 ;;
    esac

    echo "==> Building $ELEMENT with BuildStream (inside bst2 container)..."
    just bst build "$ELEMENT"

    just export {{variant}}

# ── Export ─────────────────────────────────────────────────────────────
# Checkout the built OCI image from BuildStream and load it into podman.
# Assumes the matching `just bst build` has already completed.
# Used by: `just build` (after building) and CI (as a separate step).
#
# Uses SUDO_CMD to handle root vs non-root: CI runs as root (no sudo),
# local dev needs sudo for podman access to containers-storage.
[group('build')]
export variant="default":
    #!/usr/bin/env bash
    set -euo pipefail

    case "{{variant}}" in
        default) ELEMENT="oci/bluefin.bst";        FINAL_NAME="{{image_name}}" ;;
        nvidia)  ELEMENT="oci/bluefin-nvidia.bst"; FINAL_NAME="{{image_name}}-nvidia" ;;
        *) echo "ERROR: unknown variant '{{variant}}' (expected: default | nvidia)" >&2; exit 1 ;;
    esac
    FINAL_TAG="{{image_tag}}"

    # Use sudo unless already root (CI runners are root)
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi

    echo "==> Exporting OCI image ($ELEMENT → ${FINAL_NAME}:${FINAL_TAG})..."
    rm -rf .build-out
    just bst artifact checkout "$ELEMENT" --directory /src/.build-out

    # Load the multi-layer OCI image and squash into a single layer.
    # BuildStream produces separate layers (platform + gnomeos + bluefin);
    # bootc and registry distribution work better with one squashed layer.
    # Using podman (not skopeo) ensures the squashed view is preserved on push.
    echo "==> Loading and squashing OCI image..."
    IMAGE_ID=$($SUDO_CMD podman pull -q oci:.build-out)
    rm -rf .build-out

    # Build label arguments for dynamic OCI metadata
    LABEL_ARGS=""
    if [ -n "${OCI_IMAGE_CREATED}" ]; then
        LABEL_ARGS="${LABEL_ARGS} --label org.opencontainers.image.created=${OCI_IMAGE_CREATED}"
    fi
    if [ -n "${OCI_IMAGE_REVISION}" ]; then
        LABEL_ARGS="${LABEL_ARGS} --label org.opencontainers.image.revision=${OCI_IMAGE_REVISION}"
    fi
    if [ -n "${OCI_IMAGE_VERSION}" ]; then
        LABEL_ARGS="${LABEL_ARGS} --label org.opencontainers.image.version=${OCI_IMAGE_VERSION}"
    fi

    # Squash, inject build-date VERSION_ID, and apply dynamic labels.
    # BST has no string option type, so VERSION_ID is set to "0" in os-release.bst
    # and replaced here at export time — after the BST cache key is already fixed.
    DATE_TAG="$(date -u +%Y%m%d)"
    # shellcheck disable=SC2086
    printf 'FROM %s\nRUN sed -i "s/^VERSION_ID=.*/VERSION_ID=\\"%s\\"/" /usr/lib/os-release \\\n    && sed -i "s/^IMAGE_VERSION=.*/IMAGE_VERSION=\\"%s\\"/" /usr/lib/os-release\n' "$IMAGE_ID" "$DATE_TAG" "$DATE_TAG" \
        | $SUDO_CMD podman build --pull=never --security-opt label=type:unconfined_t --squash-all ${LABEL_ARGS} -t "${FINAL_NAME}:${FINAL_TAG}" -f - .
    $SUDO_CMD podman rmi "$IMAGE_ID" || true

    echo "==> Export complete. Image loaded as ${FINAL_NAME}:${FINAL_TAG}"
    $SUDO_CMD podman images | grep -E "{{image_name}}|REPOSITORY" || true

    # Step: Chunkify (reorganize layers)
    just chunkify "${FINAL_NAME}:${FINAL_TAG}"

# ── Clean ─────────────────────────────────────────────────────────────
# Remove generated artifacts (disk image, OVMF vars, build output).
[group('build')]
clean:
    rm -f bootable.raw .ovmf-vars.fd
    rm -rf .build-out

# ── Containerfile build (alternative) ────────────────────────────────
[group('build')]
build-containerfile $image_name=image_name:
    sudo podman build --security-opt label=type:unconfined_t --squash-all -t "${image_name}:latest" .

# ── bootc helper ─────────────────────────────────────────────────────
[group('dev')]
bootc *ARGS:
    sudo podman run \
        --rm --privileged --pid=host \
        -it \
        -v /var/lib/containers:/var/lib/containers \
        -v /dev:/dev \
        -v "{{base_dir}}:/data" \
        --security-opt label=type:unconfined_t \
        "{{image_name}}:{{image_tag}}" bootc {{ARGS}}

# ── Generate bootable disk image ─────────────────────────────────────
# Variant selects which loaded image to install (default | nvidia).
# Mirrors `just build` / `just export`'s tag scheme.
[group('test')]
generate-bootable-image variant="default" $base_dir=base_dir $filesystem=filesystem:
    #!/usr/bin/env bash
    set -euo pipefail

    case "{{variant}}" in
        default) FINAL_NAME="{{image_name}}" ;;
        nvidia)  FINAL_NAME="{{image_name}}-nvidia" ;;
        *) echo "ERROR: unknown variant '{{variant}}' (expected: default | nvidia)" >&2; exit 1 ;;
    esac

    REF="${FINAL_NAME}:{{image_tag}}"
    if ! sudo podman image exists "$REF"; then
        echo "ERROR: Image '$REF' not found in podman." >&2
        echo "Run 'just build {{variant}}' first to build and export the OCI image." >&2
        exit 1
    fi

    if [ ! -e "${base_dir}/bootable.raw" ] ; then
        echo "==> Creating 30G sparse disk image..."
        fallocate -l 30G "${base_dir}/bootable.raw"
    fi

    echo "==> Installing $REF to disk image via bootc..."
    BUILD_IMAGE_NAME="$FINAL_NAME" just bootc install to-disk \
        --via-loopback /data/bootable.raw \
        --filesystem "${filesystem}" \
        --wipe \
        --composefs-backend \
        --bootloader systemd \
        --karg systemd.firstboot=no \
        --karg splash \
        --karg quiet \
        --karg console=tty0 \
        --karg console=ttyS0 \
        --karg systemd.debug_shell=ttyS1

    echo "==> Bootable disk image ready: ${base_dir}/bootable.raw"
    sync

    # Remove stale qcow2 so boot-vm uses the fresh raw image
    rm -f "${base_dir}/bootable.qcow2"

# ── Boot VM ──────────────────────────────────────────────────────────
# Boot the raw disk image.
# If qemu-system-x86_64 is installed, runs natively (UEFI/OVMF).
# Otherwise, falls back to running via docker.io/qemux/qemu-docker.
[group('test')]
boot-vm $base_dir=base_dir:
    #!/usr/bin/env bash
    set -euo pipefail

    # Resolve absolute path for Docker volume mount
    DISK=$(realpath "{{base_dir}}/bootable.raw")
    if [ ! -e "$DISK" ]; then
        echo "ERROR: ${DISK} not found. Run 'just generate-bootable-image' first." >&2
        exit 1
    fi

    # Check for native QEMU
    if command -v qemu-system-x86_64 &>/dev/null; then
        echo "==> Using native qemu-system-x86_64..."
        
        # Auto-detect OVMF firmware paths
        OVMF_CODE=""
        for candidate in \
            /usr/share/edk2/ovmf/OVMF_CODE.fd \
            /usr/share/OVMF/OVMF_CODE.fd \
            /usr/share/OVMF/OVMF_CODE_4M.fd \
            /usr/share/edk2/x64/OVMF_CODE.4m.fd \
            /usr/share/qemu/OVMF_CODE.fd; do
            if [ -f "$candidate" ]; then
                OVMF_CODE="$candidate"
                break
            fi
        done
        if [ -z "$OVMF_CODE" ]; then
            echo "ERROR: OVMF firmware not found. Install edk2-ovmf (Fedora) or ovmf (Debian/Ubuntu)." >&2
            exit 1
        fi

        # OVMF_VARS must be writable -- use a local copy
        OVMF_VARS="{{base_dir}}/.ovmf-vars.fd"
        if [ ! -e "$OVMF_VARS" ]; then
            OVMF_VARS_SRC=""
            for candidate in \
                /usr/share/edk2/ovmf/OVMF_VARS.fd \
                /usr/share/OVMF/OVMF_VARS.fd \
                /usr/share/OVMF/OVMF_VARS_4M.fd \
                /usr/share/edk2/x64/OVMF_VARS.4m.fd \
                /usr/share/qemu/OVMF_VARS.fd; do
                if [ -f "$candidate" ]; then
                    OVMF_VARS_SRC="$candidate"
                    break
                fi
            done
            if [ -z "$OVMF_VARS_SRC" ]; then
                echo "ERROR: OVMF_VARS not found alongside OVMF_CODE." >&2
                exit 1
            fi
            cp "$OVMF_VARS_SRC" "$OVMF_VARS"
        fi

        echo "==> Booting ${DISK} in QEMU (UEFI, KVM)..."
        echo "    Firmware: ${OVMF_CODE}"
        echo "    RAM: {{vm_ram}}M, CPUs: {{vm_cpus}}"
        echo "    Serial debug shell on ttyS1 available via QEMU monitor"
        echo ""

        qemu-system-x86_64 \
            -enable-kvm \
            -m "{{vm_ram}}" \
            -cpu host \
            -smp "{{vm_cpus}}" \
            -drive file="${DISK}",format=raw,if=virtio \
            -drive if=pflash,format=raw,readonly=on,file="${OVMF_CODE}" \
            -drive if=pflash,format=raw,file="${OVMF_VARS}" \
            -device virtio-vga \
            -display gtk \
            -device virtio-keyboard \
            -device virtio-mouse \
            -device virtio-net-pci,netdev=net0 \
            -netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22 \
            -chardev stdio,id=char0,mux=on,signal=off \
            -serial chardev:char0 \
            -serial chardev:char0 \
            -mon chardev=char0

    else
        echo "==> qemu-system-x86_64 not found, falling back to docker.io/qemux/qemu-docker..."

        # Check for qcow2 image, prefer it if exists
        BOOT_MOUNT="/boot.img"
        if [ -e "{{base_dir}}/bootable.qcow2" ]; then
            DISK=$(realpath "{{base_dir}}/bootable.qcow2")
            BOOT_MOUNT="/boot.qcow2"
        fi

        # Determine which port to use (adapted from user snippet)
        port=8006
        while grep -q :${port} <<< $(ss -tunalp); do
            port=$(( port + 1 ))
        done
        echo "==> Web/VNC accessible at http://localhost:${port}"
        
        # Try to open browser
        xdg-open "http://localhost:${port}" &>/dev/null || true

        # Run via podman
        # Per docs: mounting to /boot.img or /boot.qcow2 bypasses BOOT and uses the local file directly
        podman run \
            --rm --privileged \
            --device /dev/kvm \
            --pull=always \
            --publish "127.0.0.1:${port}:8006" \
            --publish "127.0.0.1:2222:22" \
            --env "USER_PORTS=22" \
            --env "NETWORK=user" \
            --env "CPU_CORES={{vm_cpus}}" \
            --env "RAM_SIZE={{vm_ram}}" \
            --env "TPM=y" \
            --env "BOOT_MODE=${BOOT_MODE:-uefi}" \
            --env "ARGUMENTS=-snapshot" \
            --volume "${DISK}:${BOOT_MOUNT}" \
            ghcr.io/qemus/qemu:latest
    fi

# ── Convert to qcow2 ──────────────────────────────────────────────────
# Convert raw disk image to qcow2 format for better performance/compat.
[group('test')]
convert-to-qcow2 $base_dir=base_dir:
    #!/usr/bin/env bash
    set -euo pipefail
    
    RAW="{{base_dir}}/bootable.raw"
    QCOW2="{{base_dir}}/bootable.qcow2"
    
    if [ ! -e "$RAW" ]; then
        echo "ERROR: ${RAW} not found. Run 'just generate-bootable-image' first." >&2
        exit 1
    fi
    
    echo "==> Converting ${RAW} to ${QCOW2}..."
    
    if command -v qemu-img &>/dev/null; then
        qemu-img convert -f raw -O qcow2 "$RAW" "$QCOW2"
    else
        # Use the same container image to run qemu-img
        echo "    Using containerized qemu-img..."
        podman run --rm \
            -v "{{base_dir}}:/data" \
            --entrypoint qemu-img \
            ghcr.io/qemus/qemu:latest \
            convert -f raw -O qcow2 "/data/bootable.raw" "/data/bootable.qcow2"
    fi
    echo "==> Conversion complete: ${QCOW2}"

# ── Show me the future ────────────────────────────────────────────────
# The full end-to-end: build the OCI image, install it to a bootable
# disk, and launch it in a QEMU VM. One command to rule them all.
# Uses charm.sh gum for styled output when available.
[group('test')]
show-me-the-future:
    #!/usr/bin/env bash
    set -euo pipefail

    # ── Helpers ───────────────────────────────────────────────────
    HAS_GUM=false
    command -v gum &>/dev/null && [[ -t 1 ]] && HAS_GUM=true

    OVERALL_START=$SECONDS

    format_time() {
        local secs=$1
        if (( secs >= 3600 )); then
            printf '%dh %02dm %02ds' $((secs / 3600)) $(((secs % 3600) / 60)) $((secs % 60))
        elif (( secs >= 60 )); then
            printf '%dm %02ds' $((secs / 60)) $((secs % 60))
        else
            printf '%ds' "$secs"
        fi
    }

    step_start() {
        local name=$1
        if $HAS_GUM; then
            gum style --foreground 212 --bold "◔ ${name}..."
        else
            echo "==> ${name}..."
        fi
    }

    step_done() {
        local name=$1 elapsed=$2
        if $HAS_GUM; then
            gum style --foreground 46 "● ${name} ($(format_time "$elapsed"))"
        else
            echo "==> ${name} done ($(format_time "$elapsed"))"
        fi
    }

    step_failed() {
        local name=$1 elapsed=$2
        if $HAS_GUM; then
            gum style --foreground 196 "◍ ${name} FAILED ($(format_time "$elapsed"))"
        else
            echo "==> ${name} FAILED ($(format_time "$elapsed"))"
        fi
    }

    run_step() {
        local name=$1; shift
        step_start "$name"
        local start=$SECONDS
        if "$@"; then
            step_done "$name" $((SECONDS - start))
        else
            step_failed "$name" $((SECONDS - start))
            echo ""
            if $HAS_GUM; then
                gum style --foreground 196 --border rounded --align center --padding "1 2" \
                    'BUILD FAILED' \
                    "Failed: ${name}" \
                    "Total elapsed: $(format_time $((SECONDS - OVERALL_START)))"
            else
                echo "BUILD FAILED: ${name}"
                echo "Total elapsed: $(format_time $((SECONDS - OVERALL_START)))"
            fi
            exit 1
        fi
    }

    # ── Banner ────────────────────────────────────────────────────
    if $HAS_GUM; then
        TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
        BANNER_WIDTH=$((TERM_WIDTH > 62 ? 60 : TERM_WIDTH - 4))
        gum style \
            --foreground 212 \
            --border-foreground 212 \
            --border double \
            --align center \
            --width $BANNER_WIDTH \
            --margin "1 2" \
            --padding "1 4" \
            'SHOW ME THE FUTURE' \
            'Building Bluefin from source and booting it in a VM'
    else
        echo ""
        echo "=== SHOW ME THE FUTURE ==="
        echo "Building Bluefin from source and booting it in a VM"
    fi
    echo ""

    # ── Steps ─────────────────────────────────────────────────────
    # Pinned to the `default` variant so we don't double the wall time
    # building the nvidia variant the user never boots in this flow.
    run_step "Build OCI image" just build default
    echo ""
    run_step "Bootable disk" just generate-bootable-image
    echo ""

    # Step 3: VM is interactive -- just announce it
    step_start "Launch VM"
    just boot-vm
    echo ""

    # ── Completion ────────────────────────────────────────────────
    if $HAS_GUM; then
        gum style --foreground 46 "● Launch VM"
        echo ""
        gum style \
            --foreground 46 \
            --border-foreground 46 \
            --border rounded \
            --align center \
            --width 42 \
            --padding "1 2" \
            'ALL STEPS COMPLETE' \
            "Total: $(format_time $((SECONDS - OVERALL_START)))"
    else
        echo "==> All steps complete. Total: $(format_time $((SECONDS - OVERALL_START)))"
    fi

# ── Chunkah ──────────────────────────────────────────────────────────
# Use the pre-built chunkah image from quay.io
# TODO: once coreos/chunkah#113 lands (libc fallback for xattr reads),
# the overlay + xattr-apply step can be removed. chunkah can then be run
# with LD_PRELOAD=fakecap.so FAKECAP_MANIFEST=.../fakecap-manifest.tsv.
# See also: projectbluefin/dakota#231.
chunkify image_ref:
    #!/usr/bin/env bash
    set -euo pipefail

    # Use sudo unless already root (CI runners are root)
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi

    echo "==> Chunkifying {{image_ref}}..."

    # Get config from existing image
    CONFIG=$($SUDO_CMD podman inspect "{{image_ref}}")

    # Compile fakecap-restore from source if not already built.
    FAKECAP_RESTORE="{{justfile_directory()}}/files/fakecap/fakecap-restore"
    if [ ! -x "$FAKECAP_RESTORE" ]; then
        echo "==> Compiling fakecap-restore..."
        gcc -O2 -o "$FAKECAP_RESTORE" "{{justfile_directory()}}/files/fakecap/fakecap-restore.c"
    fi



    # Mount the image as a writable overlay so we can physically set
    # user.component xattrs.  chunkah uses rustix raw syscalls for xattr
    # reads (bypassing libc/LD_PRELOAD), so real xattrs must be present.
    # See coreos/chunkah#113.
    LOWER=$($SUDO_CMD podman image mount "{{image_ref}}")

    cleanup() {
        $SUDO_CMD umount "$MERGED" 2>/dev/null || true
        $SUDO_CMD rm -rf "$UPPER" "$WORK" "$MERGED"
        $SUDO_CMD podman image umount "{{image_ref}}" >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    UPPER=$(mktemp -d -p /var/tmp); WORK=$(mktemp -d -p /var/tmp); MERGED=$(mktemp -d -p /var/tmp)
    $SUDO_CMD chmod 755 "$UPPER" "$WORK" "$MERGED"
    $SUDO_CMD mount -t overlay overlay \
        -o "lowerdir=${LOWER},upperdir=${UPPER},workdir=${WORK}" \
        "$MERGED"

    echo "==> Applying user.component xattrs via fakecap-restore..."
    $SUDO_CMD "$FAKECAP_RESTORE" files/fakecap-manifest.tsv "$MERGED"

    # Run chunkah against the overlay (bind-mounted read-only).
    # --max-layers 120 balances layer granularity with registry storage space.
    # CHUNKAH_CONFIG_STR preserves OCI labels (containers.bootc=1).
    # Image pinned from quay.io/coreos/chunkah:latest as of 2026-04-21.
    # Pre-pull with retries so transient registry 5xx errors don't abort the run.
    CHUNKAH_REF="quay.io/coreos/chunkah@sha256:306371251e61cc870c8546e225b13bdf2e333f79461dc5e0fc280cc170cee070"
    for attempt in 1 2 3; do
        $SUDO_CMD podman pull "$CHUNKAH_REF" && break
        echo "==> chunkah pull attempt $attempt failed, retrying in 10s..."
        [ "$attempt" -lt 3 ] && sleep 10
    done
    LOADED=$($SUDO_CMD podman run --rm \
        --pull never \
        --security-opt label=type:unconfined_t \
        -v "${MERGED}:/chunkah:ro" \
        -e "CHUNKAH_ROOTFS=/chunkah" \
        -e "CHUNKAH_CONFIG_STR=$CONFIG" \
        "$CHUNKAH_REF" build --max-layers 120 --prune /sysroot/ \
        --label ostree.commit- --label ostree.final-diffid- \
        | $SUDO_CMD podman load)

    echo "$LOADED"

    # Parse the loaded image reference. Handles all podman output formats:
    #   "Loaded image: <ref>"     — podman ≥4 with tagged OCI archive
    #   "Loaded image(s): <ref>"  — older podman
    #   bare 64-char hex sha256   — Ubuntu 24.04 podman for untagged archives
    NEW_REF=$(echo "$LOADED" | sed -n 's/^Loaded image(s): //p; s/^Loaded image: //p' | head -1)
    if [ -z "$NEW_REF" ]; then
        NEW_REF=$(echo "$LOADED" | grep -oP '^[0-9a-f]{64}$' | head -1 || true)
    fi

    if [ -n "$NEW_REF" ] && [ "$NEW_REF" != "{{image_ref}}" ]; then
        echo "==> Retagging chunked image to {{image_ref}}..."
        $SUDO_CMD podman tag "$NEW_REF" "{{image_ref}}"
    fi

# ── bcvk (fast VM testing) ───────────────────────────────────────────

# Ensure bcvk is installed (auto-installs via cargo if missing)
_ensure-bcvk:
    #!/usr/bin/env bash
    set -euo pipefail
    if command -v bcvk &>/dev/null; then
        exit 0
    fi
    echo "bcvk not found. Attempting to install via cargo..."
    if command -v cargo &>/dev/null; then
        cargo install --locked --git https://github.com/bootc-dev/bcvk bcvk
    else
        echo "ERROR: bcvk is not installed and cargo is not available for auto-install." >&2
        echo "" >&2
        echo "Install bcvk manually:" >&2
        echo "  Cargo:       cargo install --locked --git https://github.com/bootc-dev/bcvk bcvk" >&2
        echo "  Fedora 42+:  sudo dnf install bcvk" >&2
        echo "" >&2
        echo "Also ensure qemu-kvm and virtiofsd are installed on the host." >&2
        exit 1
    fi

# Boot the built image instantly in an ephemeral VM via bcvk.
# No disk image needed -- boots directly from the container via virtiofs.
# Requires: bcvk, qemu-kvm, virtiofsd (sudo dnf install bcvk qemu-kvm virtiofsd)
[group('test')]
boot-fast: _ensure-bcvk
    #!/usr/bin/env bash
    set -euo pipefail

    # Use sudo unless already root
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi

    if ! $SUDO_CMD podman image exists "{{image_name}}:{{image_tag}}"; then
        echo "ERROR: Image '{{image_name}}:{{image_tag}}' not found in podman." >&2
        echo "Run 'just build' first to build and export the OCI image." >&2
        exit 1
    fi

    echo "==> Booting {{image_name}}:{{image_tag}} in ephemeral VM (bcvk)..."
    echo "    RAM: {{vm_ram}}M, CPUs: {{vm_cpus}}"
    echo "    No disk image -- boots directly via virtiofs"
    echo ""
    $SUDO_CMD bcvk ephemeral run-ssh \
        --memory "{{vm_ram}}M" \
        --vcpus "{{vm_cpus}}" \
        "localhost/{{image_name}}:{{image_tag}}"

# Inspect the built bootc image.
[group('info')]
inspect: _ensure-bcvk
    #!/usr/bin/env bash
    set -euo pipefail

    # Use sudo unless already root
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi

    $SUDO_CMD bcvk images list

# ── Lint ─────────────────────────────────────────────────────────────
[group('test')]
lint:
    #!/usr/bin/env bash
    set -euo pipefail

    # Use sudo unless already root
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi

    echo "==> Linting {{image_name}}:{{image_tag}} with bootc container lint..."
    $SUDO_CMD podman run --rm --privileged --pull=never \
        "{{image_name}}:{{image_tag}}" \
        bootc container lint

# ── Agent / maintenance recipes ───────────────────────────────────────
#
# These recipes are the primary interface for automated agents (dakotaraptor)
# performing routine dakota maintenance: adding packages, removing packages,
# updating refs, and scaffolding new elements.
#
# Every recipe:
#   - Fails fast with a clear error message
#   - Prints exactly what it did and what to do next
#   - Leaves a 'git diff' that reviewers can verify

# Validate a single element resolves in the dependency graph (no build).
# Run this before 'just bst build' to catch YAML and dependency errors early.
[group('dev')]
validate element:
    just bst show {{element}}

# Track a single element's upstream source and show the resulting diff.
# Only works for elements with a track: field (git_repo sources).
# For tarball elements use 'just track-tarball' instead.
[group('dev')]
track-one element:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Tracking {{element}}..."
    just bst source track {{element}}
    echo ""
    echo "==> Changes:"
    git diff {{element}} || true

# Update a tarball element to a new version.
# Replaces the version string in URLs then recomputes SHA256 via bst source track.
# Usage: just track-tarball elements/bluefin/glow.bst 2.2.0
[group('dev')]
track-tarball element new_version:
    #!/usr/bin/env bash
    set -euo pipefail
    BST="{{element}}"
    NEW="{{new_version}}"

    if [ ! -f "$BST" ]; then
        echo "ERROR: $BST not found" >&2; exit 1
    fi

    # Detect current version from URL patterns: /v0.1.2/, _0.1.2_, -0.1.2-
    OLD=$(grep -oP '(?<=/v)\d+\.\d+[\d.]*(?=[/_-])' "$BST" | head -1 || \
          grep -oP '(?<=_)\d+\.\d+[\d.]*(?=_)' "$BST" | head -1 || \
          grep -oP '(?<=-)\d+\.\d+[\d.]*(?=-)' "$BST" | head -1 || true)

    if [ -z "$OLD" ]; then
        echo "ERROR: Could not detect current version in $BST" >&2
        echo "       Check the URL pattern and update manually." >&2
        exit 1
    fi

    echo "==> $BST: v$OLD -> v$NEW"
    # Replace version in URL patterns (handles /v0.1.2/, _0.1.2_, -0.1.2-)
    sed -i \
        "s|/v${OLD}/|/v${NEW}/|g; \
         s|_${OLD}_|_${NEW}_|g; \
         s|-${OLD}-|-${NEW}-|g; \
         s|/${OLD}/|/${NEW}/|g" \
        "$BST"

    echo "==> Recomputing SHA256 refs via bst source track..."
    just bst source track "$BST"

    echo ""
    echo "==> Result:"
    git diff "$BST"

# Scaffold a new pre-built binary element from template.
# Copies files/templates/binary.bst, substitutes name and repo, prints next steps.
# Usage: just scaffold-binary fastfetch fastfetch-linux/fastfetch
[group('dev')]
scaffold-binary name repo:
    #!/usr/bin/env bash
    set -euo pipefail
    DEST="elements/bluefin/{{name}}.bst"
    if [ -f "$DEST" ]; then
        echo "ERROR: $DEST already exists — use 'just track-tarball' to update it" >&2; exit 1
    fi
    cp files/templates/binary.bst "$DEST"
    sed -i \
        "s|TEMPLATE_NAME|{{name}}|g; \
         s|TEMPLATE_REPO|{{repo}}|g" \
        "$DEST"
    echo "==> Created $DEST"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $DEST"
    echo "       - Fix the URL filename pattern to match upstream release naming"
    echo "       - Set the initial VERSION (e.g. 1.2.3)"
    echo "       - Remove 'base-dir: \"\"' if the tarball wraps its contents in a subdir"
    echo "  2. Run: just bst source track $DEST"
    echo "  3. Add 'bluefin/{{name}}.bst' to elements/bluefin/deps.bst"
    echo "  4. Run: just validate $DEST"
    echo "  5. Run: just bst build $DEST"
    echo "  6. Register tracking: just register-tracking elements/bluefin/{{name}}.bst auto-merge"

# Scaffold a new GNOME Shell extension element from template.
# Usage: just scaffold-gnome-ext blur-my-shell aunetx/gnome-shell-extension-blur-my-shell
[group('dev')]
scaffold-gnome-ext name repo:
    #!/usr/bin/env bash
    set -euo pipefail
    DEST="elements/bluefin/shell-extensions/{{name}}.bst"
    if [ -f "$DEST" ]; then
        echo "ERROR: $DEST already exists" >&2; exit 1
    fi
    cp files/templates/gnome-ext.bst "$DEST"
    sed -i \
        "s|GITHUB_ORG/GITHUB_REPO|{{repo}}|g; \
         s|TEMPLATE_NAME|{{name}}|g" \
        "$DEST"
    echo "==> Created $DEST"
    echo ""
    echo "Next steps:"
    echo "  1. Edit $DEST"
    echo "       - Replace EXT_UUID with the actual extension UUID from metadata.json"
    echo "       - Verify the track: pattern (v* for tagged releases, main for rolling)"
    echo "  2. Run: just bst source track $DEST"
    echo "  3. Add 'bluefin/shell-extensions/{{name}}.bst' to elements/bluefin/gnome-shell-extensions.bst"
    echo "  4. Run: just validate $DEST"
    echo "  5. Run: just bst build $DEST"
    echo "  6. Register tracking: just register-tracking $DEST auto-merge"

# Scaffold a new Rust/Cargo element from template.
# Usage: just scaffold-rust sudo-rs memorysafety/sudo-rs
[group('dev')]
scaffold-rust name repo:
    #!/usr/bin/env bash
    set -euo pipefail
    DEST="elements/bluefin/{{name}}.bst"
    if [ -f "$DEST" ]; then
        echo "ERROR: $DEST already exists" >&2; exit 1
    fi
    ORG=$(echo "{{repo}}" | cut -d/ -f1)
    REPO=$(echo "{{repo}}" | cut -d/ -f2)
    cp files/templates/rust.bst "$DEST"
    sed -i \
        "s|GITHUB_ORG|${ORG}|g; \
         s|GITHUB_REPO|${REPO}|g; \
         s|TEMPLATE_NAME|{{name}}|g" \
        "$DEST"
    echo "==> Created $DEST"
    echo ""
    echo "IMPORTANT: cargo2 bootstrap required before 'bst source track' works."
    echo ""
    echo "Next steps:"
    echo "  1. Clone upstream to generate initial cargo2 block:"
    echo "       cd /tmp && git clone https://github.com/{{repo}} && cd ${REPO}"
    echo "       python3 $(pwd)/files/scripts/generate_cargo_sources.py Cargo.lock"
    echo "       # Paste output into the 'ref:' block in $DEST"
    echo "  2. Edit $DEST — fix build-commands/install-commands for this binary"
    echo "  3. Run: just bst source track $DEST"
    echo "       (updates git ref AND regenerates cargo2 crate list automatically)"
    echo "  4. Add 'bluefin/{{name}}.bst' to elements/bluefin/deps.bst"
    echo "  5. Run: just validate $DEST"
    echo "  6. Run: just bst build $DEST"
    echo "  7. Register tracking: just register-tracking $DEST manual-merge"
    echo "       (Rust elements always go in manual-merge — cargo2 changes need review)"

# Guided package removal: prints a preflight checklist before any files are deleted.
# Review the output, then delete files manually and run 'just validate oci/bluefin.bst'.
# Usage: just remove-package glow
[group('dev')]
remove-package name:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Dakota removal preflight: {{name}}"
    echo "    Review each section. STOP if reverse deps or alias conflicts are found."
    echo ""

    echo "━━━ [1/6] Element files ━━━"
    FOUND=$(ls \
        elements/bluefin/{{name}}.bst \
        elements/bluefin/{{name}}-*.bst \
        elements/bluefin/shell-extensions/{{name}}.bst \
        elements/core/{{name}}.bst \
        2>/dev/null || true)
    if [ -n "$FOUND" ]; then
        echo "$FOUND"
    else
        echo "  (none — check spelling)"
    fi

    echo ""
    echo "━━━ [2/6] Reverse dependencies ━━━"
    REVDEPS=$(grep -rl "{{name}}.bst" elements/ 2>/dev/null | grep -v "^elements/bluefin/{{name}}" || true)
    if [ -n "$REVDEPS" ]; then
        echo "$REVDEPS"
        echo "  ⚠ WARNING: resolve these before deleting"
    else
        echo "  (none — safe to proceed)"
    fi

    echo ""
    echo "━━━ [3/6] Tracking workflow refs ━━━"
    grep -n "{{name}}" .github/workflows/track-bst-sources.yml 2>/dev/null || echo "  (none)"

    echo ""
    echo "━━━ [4/6] Renovate refs ━━━"
    grep -n "{{name}}" .github/renovate.json5 2>/dev/null || echo "  (none)"

    echo ""
    echo "━━━ [5/6] Static files ━━━"
    grep -rn "{{name}}" files/ 2>/dev/null || echo "  (none)"
    ls files/{{name}}/ 2>/dev/null || true

    echo ""
    echo "━━━ [6/6] deps.bst / gnome-shell-extensions.bst entries ━━━"
    grep -n "{{name}}" \
        elements/bluefin/deps.bst \
        elements/bluefin/gnome-shell-extensions.bst \
        2>/dev/null || echo "  (none)"

    echo ""
    echo "━━━ Commands to execute after review ━━━"
    echo "  rm elements/bluefin/{{name}}.bst"
    echo "  # Edit deps.bst / gnome-shell-extensions.bst (see [6] above)"
    echo "  # Edit track-bst-sources.yml (see [3] above)"
    echo "  # Edit renovate.json5 (see [4] above)"
    echo "  just validate oci/bluefin.bst"
    echo "  just build"

# List everything that depends on an element.
# Usage: just reverse-deps elements/bluefin/glow.bst
[group('info')]
reverse-deps element:
    #!/usr/bin/env bash
    NAME=$(basename "{{element}}" .bst)
    RESULTS=$(grep -rl "${NAME}.bst" elements/ 2>/dev/null | grep -v "{{element}}" || true)
    if [ -n "$RESULTS" ]; then
        echo "$RESULTS"
    else
        echo "(no dependents found)"
    fi

# Print the CI tracking matrix snippet for a new element.
# Paste the output into .github/workflows/track-bst-sources.yml under the given group.
# Usage: just register-tracking elements/bluefin/glow.bst auto-merge
[group('info')]
register-tracking element group:
    #!/usr/bin/env bash
    set -euo pipefail
    NAME=$(basename "{{element}}" .bst)
    REL=$(echo "{{element}}" | sed 's|^elements/||')
    BRANCH="auto/track-${NAME}"

    # Validate the element resolves before printing registration snippet
    if ! just bst show "{{element}}" &>/dev/null; then
        echo "ERROR: 'just validate {{element}}' failed — fix element before registering" >&2
        exit 1
    fi

    echo "==> Add this block to .github/workflows/track-bst-sources.yml"
    echo "    under the '# ── {{group}}' section:"
    echo ""
    echo "          - group: {{group}}"
    echo "            element: ${REL}"
    echo "            branch: ${BRANCH}"
    echo "            title: \"chore(deps): update ${NAME}\""

# Infrastructure preflight: checks disk, NUC reachability, and registry before a build.
# Exits non-zero if any check fails — run before 'just build' on ghost.
# Usage: just preflight
[group('dev')]
preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    PASS=true

    echo "==> Dakota preflight checks"
    echo ""

    # 1. Disk: BST CAS lives on /, warn at 80%, hard-fail at 90%
    DISK_PCT=$(df / --output=pcent | tail -1 | tr -d '% ')
    if [ "$DISK_PCT" -ge 90 ]; then
        echo "✗ DISK: ${DISK_PCT}% used — CRITICAL: free space before building (bst cas clean-cache)" >&2
        PASS=false
    elif [ "$DISK_PCT" -ge 80 ]; then
        echo "⚠ DISK: ${DISK_PCT}% used — WARNING: consider running 'bst cas clean-cache' soon"
    else
        echo "✓ DISK: ${DISK_PCT}% used"
    fi

    # 2. NUC reachability
    if ping -c 1 -W 2 192.168.1.247 >/dev/null 2>&1; then
        echo "✓ NUC:  192.168.1.247 reachable"
    else
        echo "⚠ NUC:  192.168.1.247 not responding — may be asleep (not a build failure)"
    fi

    # 3. Zot registry
    if podman inspect egg-registry &>/dev/null 2>&1; then
        REG_STATE=$(podman inspect egg-registry --format '{{.State.Status}}' 2>/dev/null || echo "unknown")
        if [ "$REG_STATE" = "running" ]; then
            echo "✓ REG:  egg-registry running"
        else
            echo "⚠ REG:  egg-registry exists but state=${REG_STATE} — run 'just registry-start'"
        fi
    else
        echo "⚠ REG:  egg-registry not found — run 'just registry-start' before publishing"
    fi

    echo ""
    if [ "$PASS" = "true" ]; then
        echo "==> All checks passed"
    else
        echo "==> Preflight FAILED — resolve errors above before building" >&2
        exit 1
    fi
