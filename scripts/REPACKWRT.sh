#!/bin/bash

# Source the include file containing common functions and variables
if [[ ! -f "./scripts/INCLUDE.sh" ]]; then
    echo "ERROR: INCLUDE.sh not found in ./scripts/" >&2
    exit 1
fi

. ./scripts/INCLUDE.sh

repackwrt() {
    local builder_type=""
    local target_board=""
    local target_kernel=""
    local tunnel_type=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ophub|--OPHUB|--ulo|--ULO)
                builder_type="${1,,}"  # Convert to lowercase
                shift
                ;;
            -t|--target)
                target_board="$2"; shift 2 ;;
            -k|--kernel)
                target_kernel="$2"; shift 2 ;;
            -tn|--tunnel)
                tunnel_type="$2"; shift 2 ;;
            *)
                error_msg "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    if [[ -z "$builder_type" || -z "$target_board" || -z "$target_kernel" || -z "$tunnel_type" ]]; then
        error_msg "Missing required parameters: builder, board, kernel, or tunnel type"
        exit 1
    fi

    readonly work_dir="$GITHUB_WORKSPACE/$WORKING_DIR"
    readonly output_dir="${work_dir}/compiled_images"

    declare -A repo_urls=(
        ["--ophub"]="https://github.com/ophub/amlogic-s9xxx-openwrt/archive/refs/heads/main.zip"
        ["--ulo"]="https://github.com/armarchindo/ULO-Builder/archive/refs/heads/main.zip"
    )

    local repo_url="${repo_urls[$builder_type]}"
    local builder_folder="${repo_url##*/}"
    builder_folder="${builder_folder%%.*}-main"

    local builder_dir="${work_dir}/${builder_folder}"

    log "STEPS" "Preparing environment for builder: ${builder_type^^}"

    cd "$work_dir" || {
        error_msg "Failed to access working directory: $work_dir"
        exit 1
    }

    ariadl "$repo_url" "main.zip" || {
        error_msg "Download failed from: $repo_url"
        exit 1
    }

    unzip -q main.zip && rm -f main.zip || {
        error_msg "Failed to extract builder archive"
        exit 1
    }

    # Setup builder directory
    if [[ "$builder_type" == "--ophub" ]]; then
        mkdir -p "${builder_dir}/openwrt-armvirt"
    else
        mkdir -p "${builder_dir}/rootfs"
    fi

    # Validate and copy rootfs
    local rootfs_files=("${output_dir}/"*"_${tunnel_type}-rootfs.tar.gz")
    if [[ ${#rootfs_files[@]} -ne 1 ]]; then
        error_msg "Expected one rootfs file, found ${#rootfs_files[@]}"
        exit 1
    fi
    local rootfs_file="${rootfs_files[0]}"
    local target_path="${builder_dir}/$( [[ "$builder_type" == "--ophub" ]] && echo "openwrt-armvirt" || echo "rootfs" )/${BASE}-armsr-armv8-generic-rootfs.tar.gz"

    cp -f "$rootfs_file" "$target_path" || {
        error_msg "Failed to copy rootfs file"
        exit 1
    }

    cd "$builder_dir" || {
        error_msg "Cannot change to builder directory: $builder_dir"
        exit 1
    }

    # Run builder
    if [[ "$builder_type" == "--ophub" ]]; then
        log "INFO" "Running Ophub builder..."
        sudo ./remake -b "$target_board" -k "$target_kernel" -s 1024 || {
            error_msg "Ophub builder failed"
            exit 1
        }
        device_output_dir="./openwrt/out"
    else
        log "INFO" "Running ULO builder..."
        [[ -f ./.github/workflows/ULO_Workflow.patch ]] && mv ./.github/workflows/ULO_Workflow.patch ./ULO_Workflow.patch
        [[ -f ./ULO_Workflow.patch ]] && patch -p1 < ./ULO_Workflow.patch >/dev/null 2>&1 \
            && log "SUCCESS" "ULO patch applied" || log "WARNING" "ULO patch failed or missing"

        local rootfs_basename
        rootfs_basename=$(basename "$target_path")
        sudo ./ulo -y -m "$target_board" -r "$rootfs_basename" -k "$target_kernel" -s 1024 || {
            error_msg "ULO builder failed"
            exit 1
        }
        device_output_dir="./out/$target_board"
    fi

    # Copy output files
    [[ -d "$device_output_dir" ]] || {
        error_msg "Builder output directory not found: $device_output_dir"
        exit 1
    }

    log "INFO" "Copying firmware to output directory..."
    cp -rf "${device_output_dir}"/* "${output_dir}/" || {
        error_msg "Failed to copy firmware"
        exit 1
    }

    ls -lh "${output_dir}"/* || {
        error_msg "No files found in output directory"
        exit 1
    }

    [[ -d "$builder_dir" && "$builder_dir" != "/" ]] && sudo rm -rf "$builder_dir"

    sync && sleep 2
    log "SUCCESS" "Firmware repacking completed successfully!"
}

# Call the function
repackwrt --"$1" -t "$2" -k "$3" -tn "$4"