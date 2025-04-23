#!/bin/bash

# Source the include file containing common functions and variables
if [[ ! -f "./scripts/INCLUDE.sh" ]]; then
    echo "ERROR: INCLUDE.sh not found in ./scripts/" >&2
    exit 1
fi

. ./scripts/INCLUDE.sh

# Constants
readonly SYNC_TIME_SCRIPT="https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/sbin/sync_time.sh"
readonly CLOCK_SCRIPT="https://raw.githubusercontent.com/frizkyiman/auto-sync-time/main/usr/bin/clock"
readonly FIX_READONLY_SCRIPT="https://raw.githubusercontent.com/frizkyiman/fix-read-only/main/install2.sh"

# Initialize environment
init_environment() {
    log "INFO" "Starting custom configuration setup"
    log "DEBUG" "Working directory: ${PWD}"
}

# Update initialization settings
update_init_settings() {
    log "INFO" "Updating initialization settings"
    
    local init_file="files/etc/uci-defaults/99-init-settings.sh"
    
    if [[ ! -f "${init_file}" ]]; then
        error_msg "Init settings file not found: ${init_file}"
        return 1
    fi

    # Update date in init settings
    if ! sed -i "s/Ouc3kNF6/${DATE}/g" "${init_file}"; then
        error_msg "Failed to update date in init settings"
        return 1
    fi

    return 0
}

# Setup base-specific configurations
setup_base_config() {
    local init_file="files/etc/uci-defaults/99-init-settings.sh"
    
    case "${BASE}" in
        "openwrt")
            log "INFO" "Configuring OpenWrt specific settings"
            if ! sed -i '/# setup misc settings/ a\mv \/www\/luci-static\/resources\/view\/status\/include\/29_temp.js \/www\/luci-static\/resources\/view\/status\/include\/17_temp.js' "${init_file}"; then
                error_msg "Failed to add OpenWrt temp.js configuration"
                return 1
            fi
            ;;
        "immortalwrt")
            log "INFO" "Configuring ImmortalWrt specific settings"
            # Add ImmortalWrt specific configurations here
            ;;
        *)
            log "WARNING" "Unknown base system: ${BASE}"
            ;;
    esac
    
    return 0
}

# Handle Amlogic-specific files
handle_amlogic_files() {
    case "${TYPE}" in
        "OPHUB"|"ULO")
            log "INFO" "Removing Amlogic-specific files"
            local amlogic_files=(
                "files/etc/uci-defaults/70-rootpt-resize"
                "files/etc/uci-defaults/80-rootfs-resize"
                "files/etc/sysupgrade.conf"
            )
            
            for file in "${amlogic_files[@]}"; do
                if [[ -f "${file}" ]]; then
                    rm -f "${file}" || {
                        log "WARNING" "Failed to remove Amlogic file: ${file}"
                    }
                fi
            done
            ;;
        *)
            log "DEBUG" "No Amlogic files to handle for system type: ${TYPE}"
            ;;
    esac
    
    return 0
}

# Setup branch-specific configurations
setup_branch_config() {
    local branch_major=$(echo "${BRANCH}" | cut -d'.' -f1)
    
    case "${branch_major}" in
        "24")
            log "INFO" "Configuring for branch 24.x"
            # Add branch 24 specific configurations here
            ;;
        "23")
            log "INFO" "Configuring for branch 23.x"
            # Add branch 23 specific configurations here
            ;;
        *)
            log "WARNING" "Unknown branch version: ${BRANCH}"
            ;;
    esac
    
    return 0
}

# Configure file permissions for Amlogic
configure_amlogic_permissions() {
    case "${TYPE}" in
        "OPHUB"|"ULO")
            log "INFO" "Setting up Amlogic file permissions"
            local init_file="files/etc/uci-defaults/99-init-settings.sh"
            local netifd_files=(
                "/lib/netifd/proto/3g.sh"
                "/lib/netifd/proto/dhcp.sh"
                "/lib/netifd/proto/dhcpv6.sh"
                "/lib/netifd/proto/ncm.sh"
                "/lib/netifd/proto/wwan.sh"
                "/lib/netifd/wireless/mac80211.sh"
                "/lib/netifd/dhcp-get-server.sh"
                "/lib/netifd/dhcp.script"
                "/lib/netifd/dhcpv6.script"
                "/lib/netifd/hostapd.sh"
                "/lib/netifd/netifd-proto.sh"
                "/lib/netifd/netifd-wireless.sh"
                "/lib/netifd/utils.sh"
                "/lib/wifi/mac80211.sh"
            )
            
            for file in "${netifd_files[@]}"; do
                if ! sed -i "/# setup misc settings/ a\chmod +x ${file}" "${init_file}"; then
                    log "WARNING" "Failed to add permission setting for ${file}"
                fi
            done
            ;;
        *)
            log "INFO" "Removing lib directory for non-Amlogic build"
            if [[ -d "files/lib" ]]; then
                rm -rf "files/lib" || {
                    error_msg "Failed to remove lib directory"
                    return 1
                }
            fi
            ;;
    esac
    
    return 0
}

# Download a single script with retries
download_script() {
    local url="$1"
    local dest_dir="$2"
    local max_retries=3
    local retry_delay=2
    local retries=0
    local success=false
    
    # Create destination directory if it doesn't exist
    mkdir -p "${dest_dir}" || {
        error_msg "Failed to create directory: ${dest_dir}"
        return 1
    }
    
    local filename=$(basename "${url}")
    local dest_path="${dest_dir}/${filename}"
    
    while [[ ${retries} -lt ${max_retries} && ${success} == false ]]; do
        if wget --no-check-certificate -nv -O "${dest_path}" "${url}"; then
            success=true
            # Make the script executable
            chmod +x "${dest_path}" || {
                log "WARNING" "Failed to make script executable: ${dest_path}"
            }
        else
            ((retries++))
            log "WARNING" "Download failed (attempt ${retries}/${max_retries}): ${url}"
            sleep ${retry_delay}
        fi
    done
    
    if [[ ${success} == false ]]; then
        error_msg "Failed to download script after ${max_retries} attempts: ${url}"
        return 1
    fi
    
    return 0
}

# Download custom scripts
download_custom_scripts() {
    log "INFO" "Downloading custom scripts"
    
    local scripts=(
        "${SYNC_TIME_SCRIPT}|files/sbin"
        "${CLOCK_SCRIPT}|files/usr/bin"
        "${FIX_READONLY_SCRIPT}|files/root"
    )
    
    local any_failed=false
    
    for script in "${scripts[@]}"; do
        IFS='|' read -r url dest <<< "${script}"
        if ! download_script "${url}" "${dest}"; then
            any_failed=true
        fi
    done
    
    if [[ ${any_failed} == true ]]; then
        error_msg "Some script downloads failed"
        return 1
    fi
    
    return 0
}

# Main execution
main() {
    local exit_code=0
    
    init_environment
    
    # Execute each configuration step and track failures
    update_init_settings || exit_code=1
    setup_base_config || exit_code=1
    handle_amlogic_files || exit_code=1
    setup_branch_config || exit_code=1
    configure_amlogic_permissions || exit_code=1
    download_custom_scripts || exit_code=1
    
    if [[ ${exit_code} -eq 0 ]]; then
        log "SUCCESS" "All custom configuration setup completed successfully!"
    else
        error_msg "Configuration setup completed with errors"
    fi
    
    exit ${exit_code}
}

# Execute main function
main "$@"