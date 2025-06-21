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

# Define repositories with proper quoting and error handling
declare -A REPOS
initialize_repositories() {
    local version
    if [ "$VEROP" = "snapshots" ]; then
        REPOS=(
            ["KIDDIN9"]="https://dl.openwrt.ai/snapshots/packages/${ARCH_3}/kiddin9"
            ["IMMORTALWRT"]="https://downloads.immortalwrt.org/snapshots/packages/${ARCH_3}"
            ["OPENWRT"]="https://downloads.openwrt.org/snapshots/packages/${ARCH_3}"
            ["GSPOTX2F"]="https://github.com/gSpotx2f/packages-openwrt/tree/refs/heads/master/snapshot"
            ["FANTASTIC"]="https://fantastic-packages.github.io/packages/SNAPSHOT/packages/mipsel_24kc"
        )
    else
        version="${VEROP}"
        REPOS=(
            ["KIDDIN9"]="https://dl.openwrt.ai/releases/${version}/packages/${ARCH_3}/kiddin9"
            ["IMMORTALWRT"]="https://downloads.immortalwrt.org/releases/packages-${version}/${ARCH_3}"
            ["OPENWRT"]="https://downloads.openwrt.org/releases/packages-${version}/${ARCH_3}"
            ["GSPOTX2F"]="https://github.com/gSpotx2f/packages-openwrt/raw/refs/heads/master/current"
            ["FANTASTIC"]="https://fantastic-packages.github.io/packages/releases/${version}/packages/mipsel_24kc"
        )
    fi
}

# Define package categories with improved structure
declare_packages() {
    packages_custom=(
        # OPENWRT packages
        "modemmanager-rpcd|${REPOS[OPENWRT]}/packages"
        "luci-proto-modemmanager|${REPOS[OPENWRT]}/luci"
        "libqmi|${REPOS[OPENWRT]}/packages"
        "libmbim|${REPOS[OPENWRT]}/packages"
        "modemmanager|${REPOS[OPENWRT]}/packages"
        "sms-tool|${REPOS[OPENWRT]}/packages"
        "tailscale|${REPOS[OPENWRT]}/packages"
        "python3-speedtest-cli|${REPOS[OPENWRT]}/packages"

        # KIDDIN9 packages
        "luci-app-tailscale|${REPOS[KIDDIN9]}"
        "modeminfo-serial-zte|${REPOS[KIDDIN9]}"
        "modeminfo-serial-gosun|${REPOS[KIDDIN9]}"
        "modeminfo-qmi|${REPOS[KIDDIN9]}"
        "modeminfo-serial-yuge|${REPOS[KIDDIN9]}"
        "modeminfo-serial-thales|${REPOS[KIDDIN9]}"
        "modeminfo-serial-tw|${REPOS[KIDDIN9]}"
        "modeminfo-serial-meig|${REPOS[KIDDIN9]}"
        "modeminfo-serial-styx|${REPOS[KIDDIN9]}"
        "modeminfo-serial-mikrotik|${REPOS[KIDDIN9]}"
        "modeminfo-serial-dell|${REPOS[KIDDIN9]}"
        "modeminfo-serial-sierra|${REPOS[KIDDIN9]}"
        "modeminfo-serial-quectel|${REPOS[KIDDIN9]}"
        "modeminfo-serial-huawei|${REPOS[KIDDIN9]}"
        "modeminfo-serial-xmm|${REPOS[KIDDIN9]}"
        "modeminfo-serial-telit|${REPOS[KIDDIN9]}"
        "modeminfo-serial-fibocom|${REPOS[KIDDIN9]}"
        "modeminfo-serial-simcom|${REPOS[KIDDIN9]}"
        "modeminfo|${REPOS[KIDDIN9]}"
        "luci-app-modeminfo|${REPOS[KIDDIN9]}"
        "atinout|${REPOS[KIDDIN9]}"
        "luci-app-poweroffdevice|${REPOS[KIDDIN9]}"
        "xmm-modem|${REPOS[KIDDIN9]}"
        "luci-app-lite-watchdog|${REPOS[KIDDIN9]}"
        "luci-theme-alpha|${REPOS[KIDDIN9]}"
        "luci-app-adguardhome|${REPOS[KIDDIN9]}"
        # "sing-box|${REPOS[KIDDIN9]}"
        # "mihomo|${REPOS[KIDDIN9]}"
        # "luci-app-droidmodem|${REPOS[KIDDIN9]}"

        # IMMORTALWRT packages
        "luci-app-diskman|${REPOS[IMMORTALWRT]}"
        "luci-app-zerotier|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-ramfree|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-3ginfo-lite|${REPOS[IMMORTALWRT]}/luci"
        "modemband|${REPOS[IMMORTALWRT]}/packages"
        "luci-app-modemband|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-sms-tool-js|${REPOS[IMMORTALWRT]}/luci"
        "dns2tcp|${REPOS[IMMORTALWRT]}/packages"
        "luci-app-argon-config|${REPOS[IMMORTALWRT]}/luci"
        "luci-theme-argon|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-openclash|${REPOS[IMMORTALWRT]}/luci"
        "luci-app-passwall|${REPOS[IMMORTALWRT]}/luci"

        # GSPOTX2F packages
        "luci-app-internet-detector|${REPOS[GSPOTX2F]}"
        "internet-detector|${REPOS[GSPOTX2F]}"
        "internet-detector-mod-modem-restart|${REPOS[GSPOTX2F]}"
        "luci-app-cpu-status-mini|${REPOS[GSPOTX2F]}"
        "luci-app-disks-info|${REPOS[GSPOTX2F]}"
        "luci-app-log-viewer|${REPOS[GSPOTX2F]}"
        "luci-app-temp-status|${REPOS[GSPOTX2F]}"

        # FANTASTIC packages
        "luci-app-netspeedtest|${REPOS[FANTASTIC]}/luci"

        # GitHub packages
        "luci-app-alpha-config|https://api.github.com/repos/animegasan/luci-app-alpha-config/releases/latest"
        "luci-theme-material3|https://api.github.com/repos/AngelaCooljx/luci-theme-material3/releases/latest"
        #"luci-app-neko|https://api.github.com/repos/nosignals/openwrt-neko/releases/latest"
        "luci-theme-rtawrt|https://api.github.com/repos/rizkikotet-dev/luci-theme-rtawrt/releases/latest"
        "luci-app-netmonitor|https://api.github.com/repos/rizkikotet-dev/luci-app-netmonitor/releases/latest"
    )

    if [[ "${TYPE}" == "OPHUB" ]]; then
        log "INFO" "Adding Amlogic-specific packages..."
        packages_custom+=(
            "luci-app-amlogic|https://api.github.com/repos/ophub/luci-app-amlogic/releases/latest"
        )
    fi
}

# Main execution function
main() {
    local rc=0

    initialize_repositories
    declare_packages

    # Download Custom packages
    log "INFO" "Downloading Custom packages..."
    if ! download_packages packages_custom; then
        rc=1
    fi

    if [[ $rc -eq 0 ]]; then
        log "SUCCESS" "All packages downloaded and verified successfully"
    else
        error_msg "Some packages failed to download or verify"
    fi

    return $rc
}

# Run main function if script is not sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi