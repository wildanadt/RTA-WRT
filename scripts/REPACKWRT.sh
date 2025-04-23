#!/bin/bash

. ./scripts/INCLUDE.sh

# Constants
readonly OPHUB_REPO="https://github.com/ophub/amlogic-s9xxx-openwrt/archive/refs/heads/main.zip"
readonly ULO_REPO="https://github.com/armarchindo/ULO-Builder/archive/refs/heads/main.zip"

repackwrt() {
    # Parse arguments
    local builder_type=""
    local target_board=""
    local target_kernel=""
    local tunnel_type=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --OPHUB|--ULO|--ophub|--ulo)
                builder_type="${1^^}"  # Convert to uppercase for consistency
                shift
                ;;
            -t|--target)
                target_board="$2"
                shift 2
                ;;
            -k|--kernel)
                target_kernel="$2"
                shift 2
                ;;
            -tn|--tunnel)
                tunnel_type="$2"
                shift 2
                ;;
            *)
                error_msg "Unknown option: $1"
                exit 1
                ;;
        esac
    done

    # Validate required parameters
    validate_parameters() {
        if [[ -z "$builder_type" ]]; then
            error_msg "Builder type (--OPHUB/--ophub or --ULO/--ulo) is required"
            return 1
        fi
        
        if [[ -z "$target_board" ]]; then
            error_msg "Target board (-t) is required"
            return 1
        fi
        
        if [[ -z "$target_kernel" ]]; then
            error_msg "Target kernel (-k) is required"
            return 1
        fi

        if [[ -z "$tunnel_type" ]]; then
            error_msg "Tunnel type (-tn) is required"
            return 1
        fi
        return 0
    }

    if ! validate_parameters; then
        exit 1
    fi

    # Setup environment
    local readonly work_dir="$GITHUB_WORKSPACE/$WORKING_DIR"
    local readonly output_dir="${work_dir}/compiled_images"
    
    # Determine builder type
    setup_builder() {
        local builder_dir repo_url
        
        if [[ "$builder_type" =~ OPHUB ]]; then
            builder_dir="${work_dir}/amlogic-s9xxx-openwrt-main"
            repo_url="${OPHUB_REPO}"
            log "STEPS" "Starting firmware repackaging with Ophub..."
        else
            builder_dir="${work_dir}/ULO-Builder-main"
            repo_url="${ULO_REPO}"
            log "STEPS" "Starting firmware repackaging with UloBuilder..."
        fi

        # Create output directory if it doesn't exist
        mkdir -p "${output_dir}" || {
            error_msg "Failed to create output directory: ${output_dir}"
            return 1
        }

        echo "${builder_dir}|${repo_url}"
        return 0
    }

    local builder_info
    if ! builder_info=$(setup_builder); then
        exit 1
    fi

    IFS='|' read -r builder_dir repo_url <<< "${builder_info}"

    # Navigate to working directory
    if ! cd "${work_dir}"; then
        error_msg "Failed to access working directory: ${work_dir}"
        exit 1
    fi

    # Download and extract builder
    download_builder() {
        log "INFO" "Downloading builder..."
        if ! ariadl "${repo_url}" "main.zip"; then
            error_msg "Failed to download builder"
            return 1
        fi

        log "INFO" "Extracting builder..."
        if ! unzip -q main.zip; then
            error_msg "Failed to extract builder archive"
            return 1
        fi
        rm -f main.zip
        return 0
    }

    if ! download_builder; then
        exit 1
    fi

    # Prepare builder directory
    prepare_builder() {
        if [[ "$builder_type" =~ OPHUB ]]; then
            mkdir -p "${builder_dir}/openwrt-armvirt" || return 1
        else
            mkdir -p "${builder_dir}/rootfs" || return 1
        fi
        return 0
    }

    if ! prepare_builder; then
        error_msg "Failed to prepare builder directory"
        exit 1
    fi

    # Find and validate rootfs file
    local rootfs_file
    find_rootfs() {
        local rootfs_files=("${work_dir}/compiled_images/"*"_${tunnel_type}-rootfs.tar.gz")
        if [[ ${#rootfs_files[@]} -ne 1 ]]; then
            error_msg "Expected exactly one rootfs file, found ${#rootfs_files[@]}"
            return 1
        fi
        rootfs_file="${rootfs_files[0]}"
        return 0
    }

    if ! find_rootfs; then
        exit 1
    fi

    # Copy rootfs file
    copy_rootfs() {
        local target_path
        if [[ "$builder_type" =~ OPHUB ]]; then
            target_path="${builder_dir}/openwrt-armvirt/${BASE}-armsr-armv8-generic-rootfs.tar.gz"
        else
            target_path="${builder_dir}/rootfs/${BASE}-armsr-armv8-generic-rootfs.tar.gz"
        fi

        log "INFO" "Copying rootfs file to ${target_path}..."
        if ! cp -f "${rootfs_file}" "${target_path}"; then
            error_msg "Failed to copy rootfs file"
            return 1
        fi
        return 0
    }

    if ! copy_rootfs; then
        exit 1
    fi

    # Change to builder directory
    if ! cd "${builder_dir}"; then
        error_msg "Failed to access builder directory: ${builder_dir}"
        exit 1
    fi

    # Run builder
    run_builder() {
        local device_output_dir
        
        if [[ "$builder_type" =~ OPHUB ]]; then
            log "INFO" "Running OphubBuilder..."
            if ! sudo ./remake -b "${target_board}" -k "${target_kernel}" -s 1024; then
                error_msg "OphubBuilder execution failed"
                return 1
            fi
            device_output_dir="./openwrt/out"
        else
            # Apply ULO patches if available
            apply_ulo_patch() {
                if [[ -f "./.github/workflows/ULO_Workflow.patch" ]]; then
                    log "INFO" "Applying UloBuilder patches..."
                    mv ./.github/workflows/ULO_Workflow.patch ./ULO_Workflow.patch
                    if patch -p1 < ./ULO_Workflow.patch >/dev/null 2>&1; then
                        log "SUCCESS" "UloBuilder patch applied successfully"
                    else
                        log "WARNING" "Failed to apply UloBuilder patch"
                    fi
                else
                    log "WARNING" "UloBuilder patch not found"
                fi
                return 0
            }

            apply_ulo_patch

            # Run UloBuilder
            log "INFO" "Running UloBuilder..."
            local readonly rootfs_basename=$(basename "${target_path}")
            if ! sudo ./ulo -y -m "${target_board}" -r "${rootfs_basename}" -k "${target_kernel}" -s 1024; then
                error_msg "UloBuilder execution failed"
                return 1
            fi
            device_output_dir="./out/${target_board}"
        fi

        # Verify output directory exists
        if [[ ! -d "${device_output_dir}" ]]; then
            error_msg "Builder output directory not found: ${device_output_dir}"
            return 1
        fi

        echo "${device_output_dir}"
        return 0
    }

    local device_output_dir
    if ! device_output_dir=$(run_builder); then
        exit 1
    fi

    # Copy output files
    copy_output_files() {
        log "INFO" "Copying firmware files to ${output_dir}..."
        if ! cp -rf "${device_output_dir}"/* "${output_dir}/"; then
            error_msg "Failed to copy firmware files to output directory"
            return 1
        fi

        # Verify output files exist
        if ! ls "${output_dir}"/* >/dev/null 2>&1; then
            error_msg "No firmware files found in output directory"
            return 1
        fi
        return 0
    }

    if ! copy_output_files; then
        exit 1
    fi

    # Cleanup
    cleanup() {
        if [[ -d "${builder_dir}" && "${builder_dir}" != "/" ]]; then
            log "INFO" "Cleaning up builder directory..."
            sudo rm -rf "${builder_dir}" || {
                error_msg "Failed to clean up builder directory"
                return 1
            }
        fi
        return 0
    }

    if ! cleanup; then
        exit 1
    fi

    # Final status
    sync && sleep 3
    log "INFO" "Generated files:"
    ls -lh "${output_dir}"/*
    log "SUCCESS" "Firmware repacking completed successfully!"
}

# Call the function with all parameters
repackwrt --"$1" -t "$2" -k "$3" -tn "$4"