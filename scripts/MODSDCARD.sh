#!/bin/bash

. ./scripts/INCLUDE.sh

# Constants
readonly MOD_BOOT_REPO="https://github.com/rizkikotet-dev/mod-boot-sdcard/archive/refs/heads/main.zip"
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2

# Function to validate input parameters
validate_input() {
    local image_path="$1"
    local dtb="$2"
    local suffix="$3"

    if [[ -z "$suffix" || -z "$dtb" || -z "$image_path" ]]; then
        error_msg "Missing required parameters. Usage: build_mod_sdcard <image_path> <dtb> <image_suffix>"
        return 1
    fi

    if [[ ! -f "$image_path" ]]; then
        error_msg "Image file not found: ${image_path}"
        return 1
    fi

    return 0
}

# Function to setup working environment
setup_environment() {
    local suffix="$1"
    local img_dir="$GITHUB_WORKSPACE/$WORKING_DIR/compiled_images"

    if ! cd "$img_dir"; then
        error_msg "Failed to change directory to $img_dir"
        return 1
    fi

    # Create working directory
    mkdir -p "${suffix}/boot" || {
        error_msg "Failed to create working directory"
        return 1
    }

    return 0
}

# Function to download and extract modification files
get_mod_files() {
    local retries=0
    local success=false

    while [[ $retries -lt $MAX_RETRIES && $success == false ]]; do
        if ariadl "$MOD_BOOT_REPO" "main.zip"; then
            if unzip -q main.zip; then
                success=true
                rm -f main.zip
                log "SUCCESS" "mod-boot-sdcard successfully extracted."
            else
                rm -f main.zip
            fi
        fi

        if [[ $success == false ]]; then
            ((retries++))
            log "WARNING" "Download/extraction failed, retry ${retries}/${MAX_RETRIES}"
            sleep $RETRY_DELAY
        fi
    done

    if [[ $success == false ]]; then
        error_msg "Failed to download and extract mod-boot-sdcard after ${MAX_RETRIES} attempts"
        return 1
    fi

    return 0
}

# Function to prepare image files
prepare_image() {
    local image_path="$1"
    local suffix="$2"

    # Copy required files
    cp "$image_path" "${suffix}/" || {
        error_msg "Failed to copy image file"
        return 1
    }

    if ! sudo cp mod-boot-sdcard-main/BootCardMaker/u-boot.bin \
              mod-boot-sdcard-main/files/mod-boot-sdcard.tar.gz "${suffix}/"; then
        error_msg "Failed to copy bootloader or modification files"
        return 1
    fi

    return 0
}

# Function to process the image
process_image() {
    local suffix="$1"
    local dtb="$2"
    local file_name="$3"

    cd "${suffix}" || {
        error_msg "Failed to change directory to ${suffix}"
        return 1
    }

    # Decompress the OpenWRT image
    if ! sudo gunzip "${file_name}.gz"; then
        error_msg "Failed to decompress image"
        return 1
    fi

    # Set up loop device
    local device=""
    for i in {1..3}; do
        device=$(sudo losetup -fP --show "${file_name}" 2>/dev/null)
        [[ -n "$device" ]] && break
        sleep 1
    done

    if [[ -z "$device" ]]; then
        error_msg "Failed to set up loop device"
        return 1
    fi

    # Mount the image
    local attempts=0
    while [[ $attempts -lt 3 ]]; do
        if sudo mount "${device}p1" boot; then
            break
        fi
        ((attempts++))
        sleep 1
    done

    if [[ $attempts -eq 3 ]]; then
        error_msg "Failed to mount image"
        sudo losetup -d "${device}"
        return 1
    fi

    # Apply modifications
    if ! sudo tar -xzf mod-boot-sdcard.tar.gz -C boot; then
        error_msg "Failed to extract boot modifications"
        sudo umount boot
        sudo losetup -d "${device}"
        return 1
    fi

    # Update configuration files
    update_configs "$dtb" || {
        sudo umount boot
        sudo losetup -d "${device}"
        return 1
    }

    sync
    sudo umount boot

    # Write bootloader
    if ! sudo dd if=u-boot.bin of="${device}" bs=1 count=444 conv=fsync 2>/dev/null || \
       ! sudo dd if=u-boot.bin of="${device}" bs=512 skip=1 seek=1 conv=fsync 2>/dev/null; then
        error_msg "Failed to write bootloader"
        sudo losetup -d "${device}"
        return 1
    fi

    sudo losetup -d "${device}"
    return 0
}

# Function to update configuration files
update_configs() {
    local dtb="$1"
    local uenv=$(sudo cat boot/uEnv.txt | grep APPEND | awk -F "root=" '{print $2}')
    local extlinux=$(sudo cat boot/extlinux/extlinux.conf | grep append | awk -F "root=" '{print $2}')
    local boot=$(sudo cat boot/boot.ini | grep dtb | awk -F "/" '{print $4}' | cut -d'"' -f1)

    sudo sed -i "s|$extlinux|$uenv|g" boot/extlinux/extlinux.conf
    sudo sed -i "s|$boot|$dtb|g" boot/boot.ini
    sudo sed -i "s|$boot|$dtb|g" boot/extlinux/extlinux.conf
    sudo sed -i "s|$boot|$dtb|g" boot/uEnv.txt

    return 0
}

# Function to finalize the image
finalize_image() {
    local file_name="$1"
    local suffix="$2"

    # Compress the image
    if ! sudo gzip "${file_name}"; then
        error_msg "Failed to compress image"
        return 1
    fi

    # Generate new filename
    local kernel
    kernel=$(grep -oP 'k[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9-]+)?' <<<"${file_name}")
    local new_name="RTA-WRT-${OP_BASE}-${BRANCH}-Amlogic_s905x-Mod_SDCard-${suffix}-${kernel}-${TUNNEL}.img.gz"

    # Move and clean up
    if [[ -f "../${file_name}.gz" ]]; then
        rm -f "../${file_name}.gz"
    fi

    mv "${file_name}.gz" "../${new_name}" || {
        error_msg "Failed to rename image file"
        return 1
    }

    return 0
}

# Cleanup function
cleanup() {
    log "INFO" "Cleaning up temporary files..."
    sudo umount boot 2>/dev/null || true
    sudo losetup -D 2>/dev/null || true
    rm -rf "${suffix}" mod-boot-sdcard-main 2>/dev/null || true
}

# Main function to modify SD card image
build_mod_sdcard() {
    local image_path="$1"
    local dtb="$2"
    local suffix="$3"
    local file_name=$(basename "${image_path%.gz}")

    trap cleanup EXIT

    # Validate input
    if ! validate_input "$image_path" "$dtb" "$suffix"; then
        return 1
    fi

    # Setup environment
    if ! setup_environment "$suffix"; then
        return 1
    fi

    # Get modification files
    if ! get_mod_files; then
        return 1
    fi

    # Prepare image
    if ! prepare_image "$image_path" "$suffix"; then
        return 1
    fi

    # Process image
    if ! process_image "$suffix" "$dtb" "$file_name"; then
        return 1
    fi

    # Finalize image
    if ! finalize_image "$file_name" "$suffix"; then
        return 1
    fi

    log "SUCCESS" "Successfully processed ${suffix}"
    return 0
}

# Function to process builds
process_builds() {
    local img_dir="$1"
    local builds=("${@:2}")
    local exit_code=0
    
    for build in "${builds[@]}"; do
        IFS=: read -r device dtb model <<< "$build"
        local image_file=$(find "$img_dir" -name "*${device}*.img.gz")
        
        if [[ -n "$image_file" ]]; then
            log "INFO" "Processing build for $model ($device)"
            if ! build_mod_sdcard "$image_file" "$dtb" "$model"; then
                error_msg "Failed to process build for $model ($device)"
                exit_code=1
            fi
        else
            log "WARNING" "No image file found for $model ($device)"
        fi
    done
    
    return $exit_code
}

# Main execution function
main() {
    local exit_code=0
    local img_dir="$GITHUB_WORKSPACE/$WORKING_DIR/compiled_images"
    
    # Configuration array with format device:dtb:model
    local builds=()
    case $MATRIXTARGET in
        "OPHUB Amlogic s905X HG680P"|"ULO Amlogic s905X HG680P")
            builds=(
                "_s905x_k5:meson-gxl-s905x-p212.dtb:HG680P"
                "_s905x_k6:meson-gxl-s905x-p212.dtb:HG680P"
                "-s905x-:meson-gxl-s905x-p212.dtb:HG680P"
            )
            ;;
        "OPHUB Amlogic s905X B860H"|"ULO Amlogic s905X B860H")
            builds=(
                "_s905x-b860h_k5:meson-gxl-s905x-b860h.dtb:B860H_v1-v2"
                "_s905x-b860h_k6:meson-gxl-s905x-b860h.dtb:B860H_v1-v2"
                "-s905x-:meson-gxl-s905x-b860h.dtb:B860H_v1-v2"
            )
            ;;
        *)
            log "INFO" "No SD card modifications needed for target: $MATRIXTARGET"
            return 0
            ;;
    esac
    
    # Validate environment
    if [[ ! -d "$img_dir" ]]; then
        error_msg "Image directory not found: $img_dir"
        return 1
    fi
    
    # Process builds
    if ! process_builds "$img_dir" "${builds[@]}"; then
        exit_code=1
    fi
    
    return $exit_code
}

# Execute main function
main "$@"