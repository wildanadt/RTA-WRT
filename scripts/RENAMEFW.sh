#!/bin/bash

. ./scripts/INCLUDE.sh

rename_firmware() {
    echo -e "${STEPS} Renaming firmware files..."

    # Validate firmware directory
    local firmware_dir="$GITHUB_WORKSPACE/$WORKING_DIR/compiled_images"
    if [[ ! -d "$firmware_dir" ]]; then
        error_msg "Invalid firmware directory: ${firmware_dir}"
        return 1
    fi

    # Change to firmware directory
    cd "${firmware_dir}" || {
        error_msg "Failed to change directory to ${firmware_dir}"
        return 1
    }

    # Define RELEASE_URL before the loop
    RELEASE_URL="https://github.com/rizkikotet-dev/RTA-WRT/releases/download/${RELEASE_TAG}"
    
    # Initialize artifacts file
    > artifacts.txt

    # Create a function to handle the renaming process to reduce code duplication
    process_file() {
        local file="$1"
        local search="$2"
        local replace="$3"
        local ext="$4"
        
        if [[ ! -f "$file" ]]; then
            return 0
        fi
        
        local kernel=""
        local new_name=""
        
        if [[ "$ext" == "img.gz" && "$file" =~ k([0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9-]+)?) ]]; then
            kernel="${BASH_REMATCH[0]}"
            new_name="RTA-WRT-${OP_BASE}-${BRANCH}-${replace}-${kernel}-${TUNNEL}.${ext}"
            echo "${replace}-${kernel}-${TUNNEL}|${RELEASE_URL}/${new_name}" >> artifacts.txt
        else
            new_name="RTA-WRT-${OP_BASE}-${BRANCH}-${replace}-${TUNNEL}.${ext}"
            [[ "$ext" == "img.gz" ]] && echo "${replace}-${TUNNEL}|${RELEASE_URL}/${new_name}" >> artifacts.txt
        fi
        
        echo -e "${INFO} Renaming: $file → $new_name"
        mv "$file" "$new_name" || {
            echo -e "${WARNING} Failed to rename $file"
            return 1
        }
        
        return 0
    }

    # Use simple arrays instead of associative arrays
    # BCM27xx (Raspberry Pi) patterns
    bcm27xx_patterns=(
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
    allwinner_patterns=(
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
    rockchip_patterns=(
        "-rk3566-orangepi-3b-|Rockchip_OrangePi_3B"
        "-rk3588s-orangepi-5-|Rockchip_OrangePi_5"
        "_rk3318-box_|Rockchip_rk3318_H96-MAX"
    )
    
    # Amlogic patterns
    amlogic_patterns=(
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
    x86_64_patterns=(
        "x86-64-generic-ext4-combined-efi|X86_64_Generic_Ext4_Combined_EFI"
        "x86-64-generic-ext4-combined|X86_64_Generic_Ext4_Combined"
        "x86-64-generic-ext4-rootfs|X86_64_Generic_Ext4_Rootfs"
        "x86-64-generic-squashfs-combined-efi|X86_64_Generic_Squashfs_Combined_EFI"
        "x86-64-generic-squashfs-combined|X86_64_Generic_Squashfs_Combined"
        "x86-64-generic-squashfs-rootfs|X86_64_Generic_Squashfs_Rootfs"
        "x86-64-generic-rootfs|X86_64_Generic_Rootfs"
    )

    # Counter for tracking renamed files
    local renamed_count=0
    local failed_count=0
    
    # Process each category
    echo -e "${INFO} Processing BCM27xx devices..."
    for pattern in "${bcm27xx_patterns[@]}"; do
        local search="${pattern%%|*}"
        local replace="${pattern##*|}"
        
        # Process img.gz files
        for file in *"${search}"*.img.gz; do
            if process_file "$file" "$search" "$replace" "img.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
        
        # Process tar.gz files
        for file in *"${search}"*.tar.gz; do
            if process_file "$file" "$search" "$replace" "tar.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
    done
    
    echo -e "${INFO} Processing Allwinner devices..."
    for pattern in "${allwinner_patterns[@]}"; do
        local search="${pattern%%|*}"
        local replace="${pattern##*|}"
        
        # Process files
        for file in *"${search}"*.img.gz; do
            if process_file "$file" "$search" "$replace" "img.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
        
        for file in *"${search}"*.tar.gz; do
            if process_file "$file" "$search" "$replace" "tar.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
    done
    
    echo -e "${INFO} Processing Rockchip devices..."
    for pattern in "${rockchip_patterns[@]}"; do
        local search="${pattern%%|*}"
        local replace="${pattern##*|}"
        
        # Process files
        for file in *"${search}"*.img.gz; do
            if process_file "$file" "$search" "$replace" "img.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
        
        for file in *"${search}"*.tar.gz; do
            if process_file "$file" "$search" "$replace" "tar.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
    done
    
    echo -e "${INFO} Processing Amlogic devices..."
    for pattern in "${amlogic_patterns[@]}"; do
        local search="${pattern%%|*}"
        local replace="${pattern##*|}"
        
        # Process files
        for file in *"${search}"*.img.gz; do
            if process_file "$file" "$search" "$replace" "img.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
        
        for file in *"${search}"*.tar.gz; do
            if process_file "$file" "$search" "$replace" "tar.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
    done
    
    echo -e "${INFO} Processing x86_64 devices..."
    for pattern in "${x86_64_patterns[@]}"; do
        local search="${pattern%%|*}"
        local replace="${pattern##*|}"
        
        # Process files
        for file in *"${search}"*.img.gz; do
            if process_file "$file" "$search" "$replace" "img.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
        
        for file in *"${search}"*.tar.gz; do
            if process_file "$file" "$search" "$replace" "tar.gz"; then
                ((renamed_count++))
            else
                ((failed_count++))
            fi
        done
    done

    # Ensure all write operations are completed
    sync
    
    # Summary report
    echo -e "${INFO} Rename operation completed."
    echo -e "${INFO} Successfully renamed ${renamed_count} files."
    [[ $failed_count -gt 0 ]] && echo -e "${WARNING} Failed to rename ${failed_count} files."
    
    # Return success only if all files were renamed successfully
    return $((failed_count > 0))
}

# Execute the function
rename_firmware