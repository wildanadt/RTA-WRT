#!/bin/bash

# Source the include file containing common functions and variables
if [[ ! -f "./scripts/INCLUDE.sh" ]]; then
    echo "ERROR: INCLUDE.sh not found in ./scripts/" >&2
    exit 1
fi

set -o errexit  # Exit on error
set -o nounset  # Exit on unset variables
set -o pipefail # Exit if any command in a pipe fails

. ./scripts/INCLUDE.sh

# Initialize environment
init_environment() {
    log "INFO" "Starting builder patch..."
    log "INFO" "Current path: $PWD"

    # Set GITHUB_WORKSPACE to current directory if not set (for local builds)
    GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
    WORKING_DIR="${WORKING_DIR:-imagebuilder}"
    
    local target_dir="${GITHUB_WORKSPACE}/${WORKING_DIR}"
    
    if [ ! -d "$target_dir" ]; then
        log "INFO" "Creating directory: $target_dir"
        mkdir -p "$target_dir"
    fi
    
    cd "$target_dir" || error "Failed to change directory to $target_dir"
    log "INFO" "Changed to directory: $target_dir"
}

# Apply distribution-specific patches
apply_distro_patches() {
    if [ "$VEROP" = "snapshots" ]; then
        log "INFO" "Applying snapshots-specific patches"
        # Add specific patches for snapshots if needed
        patch_signature_check  # Always disable signature check for snapshots
    fi

    case "${BASE}" in
        openwrt)
            log "INFO" "Applying OpenWrt-specific patches"
            if [ "$VEROP" = "snapshots" ]; then
                log "INFO" "Applying OpenWrt snapshots patches"
            fi
            ;;
        immortalwrt)
            log "INFO" "Applying ImmortalWrt-specific patches"
            if [ "$VEROP" = "snapshots" ]; then
                log "INFO" "Applying ImmortalWrt snapshots patches"
            else
                log "INFO" "Removing default package: luci-app-cpufreq"
                sed -i "/luci-app-cpufreq/d" include/target.mk
            fi
            ;;
        *)
            log "WARN" "Unknown distribution: ${BASE}, skipping specific patches"
            ;;
    esac
}

# Patch package signature checking
patch_signature_check() {
    log "INFO" "Disabling package signature checking in repositories.conf"
    sed -i '\|option check_signature| s|^|#|' repositories.conf
}

# Patch Makefile for package installation
patch_makefile() {
    log "INFO" "Forcing package overwrite and downgrade during installation"
    sed -i 's|install \$(BUILD_PACKAGES)|install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade|' Makefile
}

# Configure partition sizes
configure_partitions() {
    log "INFO" "Setting kernel and rootfs partition sizes"
    sed -i 's|CONFIG_TARGET_KERNEL_PARTSIZE=.*|CONFIG_TARGET_KERNEL_PARTSIZE=128|' .config
    sed -i 's|CONFIG_TARGET_ROOTFS_PARTSIZE=.*|CONFIG_TARGET_ROOTFS_PARTSIZE=1024|' .config
}

# Apply Amlogic-specific configurations
configure_amlogic() {
    case "${TYPE}" in
        OPHUB|ULO)
            log "INFO" "Applying Amlogic-specific image options"
            local configs=(
                CONFIG_TARGET_ROOTFS_CPIOGZ
                CONFIG_TARGET_ROOTFS_EXT4FS
                CONFIG_TARGET_ROOTFS_SQUASHFS
                CONFIG_TARGET_IMAGES_GZIP
            )

            for config in "${configs[@]}"; do
                sed -i "s|${config}=.*|# ${config} is not set|" .config
            done
            ;;
        *)
            log "INFO" "Non-Amlogic system type detected: ${TYPE}, skipping Amlogic config"
            ;;
    esac
}

# Apply x86_64-specific configurations
configure_x86_64() {
    if [[ "${ARCH_2}" == "x86_64" ]]; then
        log "INFO" "Applying x86_64-specific image options"
        sed -i 's|CONFIG_ISO_IMAGES=y|# CONFIG_ISO_IMAGES is not set|' .config
        sed -i 's|CONFIG_VHDX_IMAGES=y|# CONFIG_VHDX_IMAGES is not set|' .config
    fi
}

# Main execution flow
main() {
    init_environment
    apply_distro_patches
    patch_signature_check
    patch_makefile
    configure_partitions
    configure_amlogic
    configure_x86_64
    log "INFO" "Builder patch completed successfully!"
}

main
