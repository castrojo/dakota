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
export bst2_image := env("BST2_IMAGE", "registry.gitlab.com/freedesktop-sdk/infrastructure/freedesktop-sdk-docker-images/bst2:f89b4aef847ef040b345acceda15a850219eb8f1")

# VM settings
export vm_ram := env("VM_RAM", "8192")
export vm_cpus := env("VM_CPUS", "4")

# OCI metadata (dynamic labels)
export OCI_IMAGE_CREATED := env("OCI_IMAGE_CREATED", "")
export OCI_IMAGE_REVISION := env("OCI_IMAGE_REVISION", "")
export OCI_IMAGE_VERSION := env("OCI_IMAGE_VERSION", "latest")

# ── Dev registry (local zot) ──────────────────────────────────────────
registry_image := "ghcr.io/project-zot/zot-minimal-linux-amd64:latest"
registry_name  := "egg-registry"
registry_port  := env("REGISTRY_PORT", "5000")

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
[group('build')]
build:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "==> Building OCI image with BuildStream (inside bst2 container)..."
    just bst build oci/bluefin.bst

    just export

# ── Export ─────────────────────────────────────────────────────────────
# Checkout the built OCI image from BuildStream and load it into podman.
# Assumes `bst build oci/bluefin.bst` has already completed.
# Used by: `just build` (after building) and CI (as a separate step).
#
# Uses SUDO_CMD to handle root vs non-root: CI runs as root (no sudo),
# local dev needs sudo for podman access to containers-storage.
[group('build')]
export:
    #!/usr/bin/env bash
    set -euo pipefail

    # Use sudo unless already root (CI runners are root)
    SUDO_CMD=""
    if [ "$(id -u)" -ne 0 ]; then
        SUDO_CMD="sudo"
    fi

    echo "==> Exporting OCI image..."
    rm -rf .build-out
    just bst artifact checkout oci/bluefin.bst --directory /src/.build-out

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
        | $SUDO_CMD podman build --pull=never --security-opt label=type:unconfined_t --squash-all ${LABEL_ARGS} -t "{{image_name}}:{{image_tag}}" -f - .
    $SUDO_CMD podman rmi "$IMAGE_ID" || true

    echo "==> Export complete. Image loaded as {{image_name}}:{{image_tag}}"
    $SUDO_CMD podman images | grep -E "{{image_name}}|REPOSITORY" || true

    # Step: Chunkify (reorganize layers)
    just chunkify "{{image_name}}:{{image_tag}}"

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
[group('test')]
generate-bootable-image $base_dir=base_dir $filesystem=filesystem:
    #!/usr/bin/env bash
    set -euo pipefail

    if ! sudo podman image exists "{{image_name}}:{{image_tag}}"; then
        echo "ERROR: Image '{{image_name}}:{{image_tag}}' not found in podman." >&2
        echo "Run 'just build' first to build and export the OCI image." >&2
        exit 1
    fi

    if [ ! -e "${base_dir}/bootable.raw" ] ; then
        echo "==> Creating 30G sparse disk image..."
        fallocate -l 30G "${base_dir}/bootable.raw"
    fi

    echo "==> Installing OS to disk image via bootc..."
    just bootc install to-disk \
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
    run_step "Build OCI image" just build
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

    # files/filemap.json and files/fakecap-manifest.tsv are pre-committed so CI can
    # use them without a local BST artifact cache. To regenerate after BST element
    # changes, delete both files and re-run: python3 scripts/gen-filemap.py
    if [ ! -s "files/filemap.json" ] || [ ! -s "files/fakecap-manifest.tsv" ]; then
        echo "==> Generating component filemap..."
        python3 scripts/gen-filemap.py
    else
        echo "==> Using pre-committed component filemap."
    fi

    # Mount the image as a writable overlay so we can physically set
    # user.component xattrs.  chunkah uses rustix raw syscalls for xattr
    # reads (bypassing libc/LD_PRELOAD), so real xattrs must be present.
    # See coreos/chunkah#113.
    LOWER=$($SUDO_CMD podman image mount "{{image_ref}}")

    cleanup() {
        $SUDO_CMD umount "$MERGED" 2>/dev/null || true
        $SUDO_CMD rm -rf "$UPPER" "$WORK" "$MERGED"
        $SUDO_CMD podman image umount "{{image_ref}}" 2>/dev/null || true
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
    LOADED=$($SUDO_CMD podman run --rm \
        --security-opt label=type:unconfined_t \
        -v "${MERGED}:/chunkah:ro" \
        -e "CHUNKAH_ROOTFS=/chunkah" \
        -e "CHUNKAH_CONFIG_STR=$CONFIG" \
        quay.io/coreos/chunkah@sha256:306371251e61cc870c8546e225b13bdf2e333f79461dc5e0fc280cc170cee070 build --max-layers 120 --prune /sysroot/ \
        --label ostree.commit- --label ostree.final-diffid- \
        | $SUDO_CMD podman load)

    echo "$LOADED"

    # Parse the loaded image reference
    NEW_REF=$(echo "$LOADED" | grep -oP '(?<=Loaded image: ).*' || \
              echo "$LOADED" | grep -oP '(?<=Loaded image\(s\): ).*')

    if [ -n "$NEW_REF" ] && [ "$NEW_REF" != "{{image_ref}}" ]; then
        echo "==> Retagging chunked image to {{image_ref}}..."
        $SUDO_CMD podman tag "$NEW_REF" "{{image_ref}}"
    fi

# ── Dev registry + publish ───────────────────────────────────────────

# Check prerequisites for publish pipeline
[group('dev')]
preflight:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "==> Checking prerequisites..."
    command -v podman >/dev/null || { echo "ERROR: podman not found" >&2; exit 1; }
    command -v skopeo >/dev/null || { echo "ERROR: skopeo not found" >&2; exit 1; }
    AVAIL_GB=$(df -BG /var/tmp | awk 'NR==2{gsub("G",""); print $4}')
    [ "${AVAIL_GB}" -ge 20 ] || { echo "ERROR: /var/tmp has only ${AVAIL_GB}GB free (need 20GB)" >&2; exit 1; }
    SUDO_CMD=""; if [ "$(id -u)" -ne 0 ]; then SUDO_CMD="sudo"; fi
    $SUDO_CMD podman image exists "localhost/{{image_name}}:{{image_tag}}" \
        || { echo "ERROR: image localhost/{{image_name}}:{{image_tag}} not found — run just build first" >&2; exit 1; }
    curl -sf "http://localhost:{{registry_port}}/v2/" >/dev/null \
        || echo "WARN: registry not reachable at localhost:{{registry_port}} — run just registry-start"
    echo "PASS: prerequisites met"

# Start local zot OCI registry (idempotent)
[group('dev')]
registry-start:
    #!/usr/bin/env bash
    set -euo pipefail
    SUDO_CMD=""; if [ "$(id -u)" -ne 0 ]; then SUDO_CMD="sudo"; fi
    if $SUDO_CMD podman ps --filter name={{registry_name}} --filter status=running -q | grep -q .; then
        echo "Registry {{registry_name}} already running on port {{registry_port}}"
        exit 0
    fi
    echo "==> Starting {{registry_name}} on port {{registry_port}}..."
    $SUDO_CMD podman run -d --name {{registry_name}} --replace \
        -p "{{registry_port}}:5000" \
        -v "{{registry_name}}-data:/var/lib/registry" \
        "{{registry_image}}"
    sleep 2
    curl -sf "http://localhost:{{registry_port}}/v2/" >/dev/null \
        && echo "Registry ready at localhost:{{registry_port}}" \
        || { echo "ERROR: registry failed to start" >&2; exit 1; }

# Stop local zot OCI registry (preserves volume data)
[group('dev')]
registry-stop:
    #!/usr/bin/env bash
    set -euo pipefail
    SUDO_CMD=""; if [ "$(id -u)" -ne 0 ]; then SUDO_CMD="sudo"; fi
    $SUDO_CMD podman stop {{registry_name}} 2>/dev/null || true
    echo "Registry stopped (data preserved in {{registry_name}}-data volume)"

# Show registry status and catalog
[group('dev')]
registry-status:
    #!/usr/bin/env bash
    set -euo pipefail
    SUDO_CMD=""; if [ "$(id -u)" -ne 0 ]; then SUDO_CMD="sudo"; fi
    echo "==> Container status:"
    $SUDO_CMD podman ps --filter name={{registry_name}}
    echo ""
    echo "==> Catalog:"
    curl -sf "http://localhost:{{registry_port}}/v2/_catalog" 2>/dev/null \
        | python3 -m json.tool 2>/dev/null || echo "(registry not reachable)"

# Chunkify, export via OCI dir (bypasses zstd:chunked blob cache), push plain zstd to local registry.
# Plain zstd required: bootc composefs-oci uses a plain ZstdDecoder and cannot consume zstd:chunked blobs.
# oci-dir export produces raw uncompressed tar streams; skopeo compresses fresh (no cache reuse).
[group('dev')]
publish:
    #!/usr/bin/env bash
    set -euo pipefail
    SUDO_CMD=""; if [ "$(id -u)" -ne 0 ]; then SUDO_CMD="sudo"; fi

    # Gate: registry must be running
    if ! $SUDO_CMD podman ps --filter name={{registry_name}} --filter status=running -q | grep -q .; then
        echo "ERROR: Registry '{{registry_name}}' not running. Start with: just registry-start" >&2
        exit 1
    fi

    # Disk-space preflight: need 20 GB on /var/tmp for OCI dir + overlay headroom
    AVAIL_GB=$(df -BG /var/tmp | awk 'NR==2{gsub("G",""); print $4}')
    if [ "${AVAIL_GB}" -lt 20 ]; then
        echo "ERROR: /var/tmp has only ${AVAIL_GB}GB free (need 20GB)" >&2
        exit 1
    fi

    # Chunkify: splits into 120 content-addressed layers with xattrs on /var/tmp overlay
    just chunkify "{{image_name}}:{{image_tag}}"

    # Export to OCI dir — uncompressed, bypasses zstd:chunked blob cache in containers-storage
    OCI_DIR=$(mktemp -d -p /var/tmp dakota-publish-XXXX)
    trap 'sudo rm -rf "$OCI_DIR"' EXIT

    echo "==> Exporting to OCI dir: $OCI_DIR"
    $SUDO_CMD podman image save --format=oci-dir \
        -o "$OCI_DIR" "localhost/{{image_name}}:{{image_tag}}"

    # Push from OCI dir with plain zstd via skopeo (skopeo supports oci: source transport;
    # reads raw uncompressed tars from disk — no blob cache, no chunked annotations)
    echo "==> Pushing plain zstd to localhost:{{registry_port}}/{{image_name}}:{{image_tag}}..."
    skopeo copy \
        --insecure-policy \
        --dest-tls-verify=false \
        --dest-compress-format=zstd \
        --dest-compress-level=1 \
        "oci:${OCI_DIR}" \
        "docker://localhost:{{registry_port}}/{{image_name}}:{{image_tag}}"

    # Verify manifest: assert plain zstd mediaType + no zstd:chunked annotations
    echo "==> Verifying manifest..."
    MANIFEST=$(curl -sf \
        "http://localhost:{{registry_port}}/v2/{{image_name}}/manifests/{{image_tag}}" \
        -H 'Accept: application/vnd.oci.image.manifest.v1+json')
    LAYER_COUNT=$(echo "$MANIFEST" | python3 -c "import sys,json; print(len(json.load(sys.stdin)['layers']))")
    BAD_LAYERS=$(echo "$MANIFEST" | python3 -c "import sys,json; m=json.load(sys.stdin); print(len([l for l in m['layers'] if 'tar+zstd' not in l.get('mediaType','')]))")
    CHUNKED_ANNS=$(echo "$MANIFEST" | python3 -c "import sys,json; m=json.load(sys.stdin); print(sum(1 for l in m['layers'] for k in l.get('annotations',{}) if 'zstd-chunked' in k))")
    echo "==> Published: ${LAYER_COUNT} layers, ${BAD_LAYERS} bad mediaTypes, ${CHUNKED_ANNS} zstd:chunked annotations"
    if [ "$BAD_LAYERS" -gt 0 ] || [ "$CHUNKED_ANNS" -gt 0 ]; then
        echo "FAIL: manifest contains non-zstd layers or zstd:chunked annotations" >&2
        exit 1
    fi
    echo "PASS: ${LAYER_COUNT} layers, all plain zstd, no chunked annotations"

# Print bootc switch command for NUC (uses LAN IP — NUC cannot reach ghost's localhost)
[group('dev')]
vm-switch-local:
    @echo "Run on NUC (192.168.1.247):"
    @echo "  sudo bootc switch 192.168.1.102:{{registry_port}}/{{image_name}}:{{image_tag}}"

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

# ── NUC hardware validation ─────────────────────────────────────────

# Validate the current NUC state after a bootc upgrade + reboot.
# SSHes to NUC and checks GDM, booted digest, os-release, ldconfig stamp.
# Usage: just validate-nuc [NUC_IP]
# Observed reboot time: ~90-120s. Use 180s timeout in automated loops.
#
# Future: just test-nuc = just publish + bootc upgrade on NUC + reboot + validate-nuc
# Prerequisite for full automation: passwordless SSH key auth on NUC.
[group('dev')]
validate-nuc nuc_ip="192.168.1.247":
    #!/usr/bin/env bash
    set -euo pipefail
    NUC="{{nuc_ip}}"
    echo "==> Validating NUC at ${NUC}..."
    ssh jorge@${NUC} "
        echo '=== bootc status ==='
        sudo bootc status --format=json | grep -o '"imageDigest":"[^"]*"' | head -1
        echo '=== os-release ==='
        grep -E 'VERSION_ID|IMAGE_VERSION' /usr/lib/os-release
        echo '=== GDM ==='
        systemctl is-active gdm
        echo '=== ldconfig stamp ==='
        ls /etc/ld.so.cache.stamp-* 2>/dev/null && echo stamp OK || echo WARNING: no stamp
    "
    echo "==> Validation complete."
