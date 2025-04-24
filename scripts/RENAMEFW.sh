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

rename_firmware() {
    echo -e "${STEPS} Renaming firmware files..."

    # Validate firmware directory
    local firmware_dir="$GITHUB_WORKSPACE/$WORKING_DIR/compiled_images"
    if [[ ! -d "$firmware_dir" ]]; then
        error_msg "Invalid firmware directory: ${firmware_dir}"
        return 1
    fi

    # Move to firmware directory
    cd "${firmware_dir}" || {
        error_msg "Failed to change directory to ${firmware_dir}"
        return 1
    }

    # Create artifacts.txt if it doesn't exist
    > artifacts.txt

    # Release URL for linking
    local RELEASE_URL="https://github.com/rizkikotet-dev/RTA-WRT/releases/download/${RELEASE_TAG}"
    
    # Define pattern groups for better organization
    declare -A pattern_groups
    
    # Broadcom/Raspberry Pi patterns
    pattern_groups["raspberry_pi"]=(
        "-bcm27xx-bcm2710-rpi-3-ext4-factory|Broadcom_RaspberryPi_3B-Ext4_Factory"
        "-bcm27xx-bcm2710-rpi-3-ext4-sysupgrade|Broadcom_RaspberryPi_3B-Ext4_Sysupgrade"
        "-bcm27xx-bcm2710-rpi-3-squashfs-factory|Broadcom_RaspberryPi_3B-Squashfs_Factory"
        "-bcm27xx-bcm2710-rpi-3-squashfs-sysupgrade|Broadcom_RaspberryPi_3B-Squashfs_Sysupgrade"
        "-bcm27xx-bcm2711-rpi-4-ext4-factory|Broadcom_RaspberryPi_4B-Ext4_Factory"
        "-bcm27xx-bcm2711-rpi-4-ext4-sysupgrade|Broadcom_RaspberryPi_4B-Ext4_Sysupgrade"
        "-bcm27xx-bcm2711-rpi-4-squashfs-factory|Broadcom_RaspberryPi_4B-Squashfs_Factory"
        "-bcm27xx-bcm2711-rpi-4-squashfs-sysupgrade|Broadcom_RaspberryPi_4B-Squashfs_Sysupgrade"
    )
    
    # Allwinner patterns
    pattern_groups["allwinner"]=(
        "-h5-orangepi-pc2-|Allwinner_OrangePi_PC2"
        "-h5-orangepi-prime-|Allwinner_OrangePi_Prime"
        "-h5-orangepi-zeroplus-|Allwinner_OrangePi_ZeroPlus"
        "-h5-orangepi-zeroplus2-|Allwinner_OrangePi_ZeroPlus2"
        "-h6-orangepi-1plus-|Allwinner_OrangePi_1Plus"
        "-h6-orangepi-3-|Allwinner_OrangePi_3"
        "-h6-orangepi-3lts-|Allwinner_OrangePi_3LTS"
        "-h6-orangepi-lite2-|Allwinner_OrangePi_Lite2"
        "-h616-orangepi-zero2-|Allwinner_OrangePi_Zero2"
        "-h618-orangepi-zero2w-|Allwinner_OrangePi_Zero2W"
        "-h618-orangepi-zero3-|Allwinner_OrangePi_Zero3"
    )
    
    # Rockchip patterns
    pattern_groups["rockchip"]=(
        "-rk3566-orangepi-3b-|Rockchip_OrangePi_3B"
        "-rk3588s-orangepi-5-|Rockchip_OrangePi_5"
        "_rk3318-box_|Rockchip_rk3318_H96-MAX"
    )
    
    # Amlogic patterns
    pattern_groups["amlogic"]=(
        "-s905x-|Amlogic_s905x"
        "-s905x2-|Amlogic_s905x2"
        "-s905x3-|Amlogic_s905x3"
        "-s905x4-|Amlogic_s905x4"
        "_amlogic_s912_|Amlogic_s912"
        "_amlogic_s905x2_|Amlogic_s905x2"
        "_amlogic_s905x3_|Amlogic_s905x3"
        "_s905_|Amlogic_s905"
        "_s905-beelink-mini_|Amlogic_s905-Beelink_Mini"
        "_s905-mxqpro-plus_|Amlogic_s905-MXQPro_Plus"
        "_s905w_|Amlogic_s905w"
        "_s905w-w95_|Amlogic_s905w-W95"
        "_s905w-x96-mini_|Amlogic_s905w-X96_Mini"
        "_s905w-x96w_|Amlogic_s905w-X96W"
        "_s905x-nexbox-a95x_|Amlogic_s905x-Nexbox_A95X"
        "_s905x2_|Amlogic_s905x2"
        "_s905x2-km3_|Amlogic_s905x2-KM3"
        "_s905x2-x96max-2g_|Amlogic_s905x2-X96Max-2G"
        "_s905x3_|Amlogic_s905x3"
        "_s905x3-h96max_|Amlogic_s905x3-H96Max"
        "_s905x3-hk1_|Amlogic_s905x3-HK1"
        "_s905x3-x96max_|Amlogic_s905x3-X96Max"
        "_s912_|Amlogic_s912"
        "_s912-h96pro-plus_|Amlogic_s912-H96Pro_Plus"
        "_s912-x92_|Amlogic_s912-X92"
        "_s905x_|Amlogic_s905x-HG680P"
        "_s905x-b860h_|Amlogic_s905x-B860H_v1-v2"
        "Amlogic_s905x-Mod_SDCard-HG680P|Amlogic_s905x-Mod_SDCard-HG680P"
        "Amlogic_s905x-Mod_SDCard-B860H_v1-v2|Amlogic_s905x-Mod_SDCard-B860H_v1-v2"
    )
    
    # x86_64 patterns
    pattern_groups["x86_64"]=(
        "x86-64-generic-ext4-combined-efi|X86_64_Generic_Ext4_Combined_EFI"
        "x86-64-generic-ext4-combined|X86_64_Generic_Ext4_Combined"
        "x86-64-generic-ext4-rootfs|X86_64_Generic_Ext4_Rootfs"
        "x86-64-generic-squashfs-combined-efi|X86_64_Generic_Squashfs_Combined_EFI"
        "x86-64-generic-squashfs-combined|X86_64_Generic_Squashfs_Combined"
        "x86-64-generic-squashfs-rootfs|X86_64_Generic_Squashfs_Rootfs"
        "x86-64-generic-rootfs|X86_64_Generic_Rootfs"
    )

    # Function to process a single file
    process_file() {
        local file="$1"
        local search="$2"
        local replace="$3"
        local extension="${file##*.}"
        local filebase="${file%.*}"
        
        # For img.gz files
        if [[ "$file" == *".img.gz" ]]; then
            local kernel=""
            if [[ "$file" =~ k[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9-]+)? ]]; then
                kernel="${BASH_REMATCH[0]}"
            fi
            
            local new_name
            if [[ -n "$kernel" ]]; then
                new_name="RTA-WRT-${OP_BASE}-${BRANCH}-${replace}-${kernel}-${TUNNEL}.img.gz"
                echo "${replace}-${kernel}-${TUNNEL}|${RELEASE_URL}/${new_name}" >> artifacts.txt
            else
                new_name="RTA-WRT-${OP_BASE}-${BRANCH}-${replace}-${TUNNEL}.img.gz"
                echo "${replace}-${TUNNEL}|${RELEASE_URL}/${new_name}" >> artifacts.txt
            fi
        # For tar.gz files
        elif [[ "$file" == *".tar.gz" ]]; then
            local new_name="RTA-WRT-${OP_BASE}-${BRANCH}-${replace}-${TUNNEL}.tar.gz"
        else
            # Skip unknown file types
            echo -e "${WARNING} Unknown file type: $file (skipping)"
            return 0
        fi

        echo -e "${INFO} Renaming: $file → $new_name"
        mv "$file" "$new_name" || {
            echo -e "${WARNING} Failed to rename $file"
            return 1
        }
        
        return 0
    }

    # Process files for each pattern group
    local total_files=0
    local renamed_files=0
    
    echo -e "${INFO} Starting firmware renaming process by platform group..."
    
    for group_name in "${!pattern_groups[@]}"; do
        echo -e "${INFO} Processing ${group_name} files..."
        local patterns=("${pattern_groups[$group_name][@]}")
        
        for pattern in "${patterns[@]}"; do
            local search="${pattern%%|*}"
            local replace="${pattern##*|}"
            
            # Find files matching the search pattern
            for file in *"${search}"*.{img.gz,tar.gz}; do
                # Skip if no matches found (to avoid processing "*search*.img.gz")
                [[ -f "$file" ]] || continue
                
                ((total_files++))
                process_file "$file" "$search" "$replace" && ((renamed_files++))
            done
        done
    done

    echo -e "${INFO} Rename operation completed."
    echo -e "${INFO} Processed $total_files files, successfully renamed $renamed_files files."
    
    # Sort the artifacts file alphabetically for better readability
    if [[ -f "artifacts.txt" ]]; then
        sort -o artifacts.txt artifacts.txt
        echo -e "${INFO} Created artifacts.txt with ${renamed_files} entries."
    fi
    
    sync
    return 0
}

# Execute the function
rename_firmware