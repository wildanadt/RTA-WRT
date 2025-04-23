#!/bin/bash

. ./scripts/INCLUDE.sh

# Constants
readonly CONFIG_FILE=".config"
readonly REPOSITORIES_FILE="repositories.conf"
readonly TARGET_MK_FILE="include/target.mk"
readonly MAKEFILE="Makefile"

# Initialize environment
init_environment() {
    log "INFO" "Starting Builder Patch Process"
    log "DEBUG" "Current working directory: ${PWD}"
    
    local target_dir="$GITHUB_WORKSPACE/$WORKING_DIR"
    if ! cd "${target_dir}"; then
        error_msg "Failed to change directory to ${target_dir}"
        exit 1
    fi
    
    log "INFO" "Working in directory: ${PWD}"
}

# Apply distribution-specific patches
apply_distro_patches() {
    case "${BASE}" in
        "openwrt")
            log "INFO" "Applying OpenWrt specific patches"
            # Add OpenWrt specific patches here if needed
            ;;
        "immortalwrt")
            log "INFO" "Applying ImmortalWrt specific patches"
            if [[ -f "${TARGET_MK_FILE}" ]]; then
                log "DEBUG" "Removing luci-app-cpufreq from default packages"
                sed -i "/luci-app-cpufreq/d" "${TARGET_MK_FILE}" || {
                    log "WARNING" "Failed to modify ${TARGET_MK_FILE}"
                }
            else
                log "WARNING" "File not found: ${TARGET_MK_FILE}"
            fi
            ;;
        *)
            log "WARNING" "Unknown distribution: ${BASE}"
            ;;
    esac
}

# Patch package signature checking
patch_signature_check() {
    log "INFO" "Disabling package signature checking"
    if [[ -f "${REPOSITORIES_FILE}" ]]; then
        sed -i '\|option check_signature| s|^|#|' "${REPOSITORIES_FILE}" || {
            error_msg "Failed to patch signature checking in ${REPOSITORIES_FILE}"
            return 1
        }
    else
        log "WARNING" "File not found: ${REPOSITORIES_FILE}"
        return 1
    fi
    return 0
}

# Patch Makefile for package installation
patch_makefile() {
    log "INFO" "Patching Makefile for force package installation"
    if [[ -f "${MAKEFILE}" ]]; then
        sed -i "s/install \$(BUILD_PACKAGES)/install \$(BUILD_PACKAGES) --force-overwrite --force-downgrade/" "${MAKEFILE}" || {
            error_msg "Failed to patch ${MAKEFILE}"
            return 1
        }
    else
        log "WARNING" "File not found: ${MAKEFILE}"
        return 1
    fi
    return 0
}

# Configure partition sizes
configure_partitions() {
    log "INFO" "Configuring partition sizes"
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log "WARNING" "Config file not found: ${CONFIG_FILE}"
        return 1
    fi

    local partition_configs=(
        "CONFIG_TARGET_KERNEL_PARTSIZE=128"
        "CONFIG_TARGET_ROOTFS_PARTSIZE=1024"
    )

    for config in "${partition_configs[@]}"; do
        local config_key="${config%=*}"
        log "DEBUG" "Setting ${config}"
        if grep -q "^${config_key}=" "${CONFIG_FILE}"; then
            sed -i "s/^${config_key}=.*/${config}/" "${CONFIG_FILE}" || {
                log "WARNING" "Failed to set ${config_key}"
            }
        else
            echo "${config}" >> "${CONFIG_FILE}"
        fi
    done
    return 0
}

# Apply Amlogic-specific configurations
configure_amlogic() {
    case "${TYPE}" in
        "OPHUB"|"ULO")
            log "INFO" "Applying Amlogic-specific configurations"
            if [[ ! -f "${CONFIG_FILE}" ]]; then
                log "WARNING" "Config file not found: ${CONFIG_FILE}"
                return 1
            fi

            local amlogic_configs=(
                "CONFIG_TARGET_ROOTFS_CPIOGZ"
                "CONFIG_TARGET_ROOTFS_EXT4FS"
                "CONFIG_TARGET_ROOTFS_SQUASHFS"
                "CONFIG_TARGET_IMAGES_GZIP"
            )

            for config in "${amlogic_configs[@]}"; do
                log "DEBUG" "Disabling ${config}"
                sed -i "s|${config}=.*|# ${config} is not set|g" "${CONFIG_FILE}" || {
                    log "WARNING" "Failed to disable ${config}"
                }
            done
            ;;
        *)
            log "DEBUG" "No Amlogic-specific configurations needed for system type: ${TYPE}"
            ;;
    esac
    return 0
}

# Apply x86_64-specific configurations
configure_x86_64() {
    if [[ "${ARCH_2}" == "x86_64" ]]; then
        log "INFO" "Applying x86_64-specific configurations"
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            log "WARNING" "Config file not found: ${CONFIG_FILE}"
            return 1
        fi

        local x86_configs=(
            "CONFIG_ISO_IMAGES"
            "CONFIG_VHDX_IMAGES"
        )

        for config in "${x86_configs[@]}"; do
            log "DEBUG" "Disabling ${config}"
            sed -i "s/${config}=y/# ${config} is not set/" "${CONFIG_FILE}" || {
                log "WARNING" "Failed to disable ${config}"
            }
        done
    else
        log "DEBUG" "Skipping x86_64 configurations (current arch: ${ARCH_2})"
    fi
    return 0
}

# Verify all patches were applied successfully
verify_patches() {
    local success=true
    
    # Check signature patch
    if [[ -f "${REPOSITORIES_FILE}" ]] && grep -q "^#.*check_signature" "${REPOSITORIES_FILE}"; then
        log "DEBUG" "Signature check patch verified"
    else
        log "WARNING" "Signature check patch not verified"
        success=false
    fi

    # Check Makefile patch
    if [[ -f "${MAKEFILE}" ]] && grep -q "force-overwrite" "${MAKEFILE}"; then
        log "DEBUG" "Makefile patch verified"
    else
        log "WARNING" "Makefile patch not verified"
        success=false
    fi

    if [[ "${success}" == false ]]; then
        log "ERROR" "Some patches were not applied successfully"
        return 1
    fi
    return 0
}

# Main execution
main() {
    init_environment
    
    # Track if any patch fails
    local patch_failed=false
    
    apply_distro_patches || patch_failed=true
    patch_signature_check || patch_failed=true
    patch_makefile || patch_failed=true
    configure_partitions || patch_failed=true
    configure_amlogic || patch_failed=true
    configure_x86_64 || patch_failed=true
    
    # Final verification
    if ! verify_patches; then
        patch_failed=true
    fi

    if [[ "${patch_failed}" == true ]]; then
        error_msg "Builder patch completed with some errors"
        exit 1
    else
        log "SUCCESS" "Builder patch completed successfully!"
        exit 0
    fi
}

# Execute main function
main "$@"