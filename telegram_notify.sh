#!/usr/bin/env bash

# Set strict error handling
set -euo pipefail
IFS=$'\n\t'

# Script configuration - Environment variables
readonly BOT_TOKEN="${BOT_TOKEN:?'BOT_TOKEN is required'}"
readonly CHAT_ID="${CHAT_ID:?'CHAT_ID is required'}"
readonly THREAD_ID="${THREAD_ID:-734}"  # Default to 734 if not set

# Build configuration - Environment variables
readonly SOURCE="${SOURCE:?'SOURCE is required'}"
readonly VERSION="${VERSION:?'VERSION is required'}"
readonly BUILD_TYPE="${BUILD_TYPE:?'BUILD_TYPE is required'}"
readonly FOR="${FOR:?'FOR is required'}"
readonly RELEASE_TAG="${RELEASE_TAG:-}"  # Optional

# Constants
readonly MAX_RETRIES=3
readonly RETRY_DELAY=2
readonly MAX_BUTTONS_PER_BATCH=20
readonly ARTIFACTS_FILE="combined_artifacts.txt"
readonly API_BASE_URL="https://api.telegram.org/bot${BOT_TOKEN}"

# Logging functions
log_info() {
    echo "ℹ️ [INFO] $*"
}

log_warning() {
    echo "⚠️ [WARNING] $*"
    echo "::warning::$*"
}

log_error() {
    echo "❌ [ERROR] $*"
    echo "::error::$*"
    return 1
}

# Helper functions
get_image_url() {
    case "$SOURCE" in
        "immortalwrt")
            echo "https://avatars.githubusercontent.com/u/53193414?s=200&v=4"
            ;;
        *)
            echo "https://avatars.githubusercontent.com/u/2528830?s=200&v=4"
            ;;
    esac
}

generate_message() {
    local current_date
    current_date=$(date '+%d-%m-%Y %H:%M:%S')
    
    if [ "$FOR" = "main" ]; then
        cat << EOF
━━━━━━━━━━━━━━━━━━━━━━
🎯 *RTA-WRT Firmware Update*
✅ _Stable Release_

🔹 *Version:* ${SOURCE}:${VERSION}
🔹 *Date:* ${current_date}
🔹 *Build Type:* ${BUILD_TYPE}

📌 *Release Notes:*
• Stable version release
• Recommended for all users
• Includes latest features and bug fixes
━━━━━━━━━━━━━━━━━━━━━━
EOF
    else
        cat << EOF
━━━━━━━━━━━━━━━━━━━━━━
🚀 *RTA-WRT Firmware Update*
🌟 _Development Release_

🔹 *Version:* ${SOURCE}:${VERSION}
🔹 *Date:* ${current_date}
🔹 *Build Type:* ${BUILD_TYPE}

📌 *Development Notes:*
• Suitable for testing
• Please provide feedback
• Report any bugs found
• Your feedback helps development
━━━━━━━━━━━━━━━━━━━━━━
EOF
    fi
}

# Function to make HTTP requests with retry logic
make_telegram_request() {
    local endpoint=$1
    local data=$2
    local attempt=1
    local max_attempts=$MAX_RETRIES
    
    while [ $attempt -le $max_attempts ]; do
        local response
        response=$(curl -s -X POST "${API_BASE_URL}/${endpoint}" \
                  --header "Content-Type: application/json" \
                  --data "$data")
        
        if [ "$(echo "$response" | jq -r '.ok')" = "true" ]; then
            echo "$response"
            return 0
        fi
        
        local error_code
        local error_desc
        error_code=$(echo "$response" | jq -r '.error_code')
        error_desc=$(echo "$response" | jq -r '.description')
        
        if [ $attempt -lt $max_attempts ]; then
            if [ "$error_code" = "429" ]; then
                local retry_after
                retry_after=$(echo "$response" | jq -r '.parameters.retry_after // 5')
                log_warning "Rate limited. Waiting ${retry_after}s before retry ${attempt}/${max_attempts}"
                sleep "$retry_after"
            else
                local wait_time=$((RETRY_DELAY * attempt))
                log_warning "Request failed (${error_code}: ${error_desc}). Retrying in ${wait_time}s..."
                sleep "$wait_time"
            fi
        else
            log_error "Failed after ${max_attempts} attempts: ${error_desc}"
            return 1
        fi
        
        ((attempt++))
    done
}

# Function to validate and parse artifacts
parse_artifacts() {
    local artifacts_file=$1
    local -n buttons_ref=$2
    local count=0
    
    if [ ! -f "$artifacts_file" ]; then
        log_error "Artifacts file not found: $artifacts_file"
        return 1
    fi
    
    while IFS='|' read -r target_name file_url || [ -n "${target_name:-}" ]; do
        # Skip empty lines
        [ -z "${target_name:-}" ] && continue
        
        target_name=$(echo "$target_name" | xargs)
        file_url=$(echo "$file_url" | xargs)
        
        if [[ -n "$target_name" && -n "$file_url" ]]; then
            if [[ "$file_url" =~ ^https?:// ]]; then
                buttons_ref+=("$target_name" "$file_url")
                ((count++))
            else
                log_warning "Invalid URL format for target '$target_name': $file_url"
            fi
        fi
    done < "$artifacts_file"
    
    return $count
}

# Function to send button batches
send_buttons_batch() {
    local -n buttons=$1
    local message_id=$2
    local batch_num=$3
    local start=$4
    local end=$5
    
    local rows=()
    
    for ((i=start; i<end; i+=2)); do
        if [[ $i -ge ${#buttons[@]} ]]; then
            break
        fi
        
        local name="${buttons[i]}"
        local url="${buttons[i+1]}"
        
        # Add emoji based on button type
        local button_name
        if [ "$name" = "View Release" ]; then
            button_name="🔗 View Release"
        else
            button_name="📥 $name"
        fi
        
        # Create a row with one button
        local row="[{\"text\": \"$button_name\", \"url\": \"$url\"}]"
        rows+=("$row")
    done
    
    # Join rows into keyboard array
    local keyboard_json=$(printf '%s,' "${rows[@]}" | sed 's/,$//')
    keyboard_json="[$keyboard_json]"
    
    log_info "Sending buttons batch ${batch_num} with ${#rows[@]} buttons..."
    
    local json_data=$(jq -n \
        --arg chat_id "$CHAT_ID" \
        --arg thread_id "$THREAD_ID" \
        --arg text "📦 *Download Options (Group ${batch_num})*" \
        --arg message_id "$message_id" \
        --argjson keyboard "$keyboard_json" \
        '{
            chat_id: $chat_id,
            message_thread_id: $thread_id,
            text: $text,
            parse_mode: "Markdown",
            reply_to_message_id: $message_id,
            reply_markup: {
                inline_keyboard: $keyboard
            }
        }')
    
    if ! make_telegram_request "sendMessage" "$json_data"; then
        log_error "Failed to send button batch ${batch_num}"
        return 1
    fi
    
    # Prevent rate limiting
    sleep 2
    return 0
}

main() {
    log_info "Starting Telegram notification for ${SOURCE}:${VERSION} (${BUILD_TYPE})"
    
    # Initialize buttons array
    declare -a ALL_BUTTONS
    
    # Parse artifacts and populate buttons
    local button_count
    if ! button_count=$(parse_artifacts "$ARTIFACTS_FILE" ALL_BUTTONS); then
        log_error "Failed to parse artifacts file"
        exit 1
    fi
    
    log_info "Successfully parsed $button_count artifacts"
    
    # Add release button if tag is provided
    if [ -n "$RELEASE_TAG" ]; then
        ALL_BUTTONS+=("View Release" "https://github.com/rizkikotet-dev/RTA-WRT/releases/tag/$RELEASE_TAG")
        ((button_count++))
        log_info "Added release button for tag: $RELEASE_TAG"
    fi
    
    # Check if we have any buttons to send
    if [ ${#ALL_BUTTONS[@]} -eq 0 ]; then
        log_warning "No valid buttons found. Proceeding with main message only."
    else
        log_info "Preparing to send notification with ${button_count} buttons"
    fi
    
    # Send main message with photo
    local message
    message=$(generate_message)
    
    local json_data=$(jq -n \
        --arg chat_id "$CHAT_ID" \
        --arg thread_id "$THREAD_ID" \
        --arg photo "$(get_image_url)" \
        --arg caption "$message" \
        '{
            chat_id: $chat_id,
            message_thread_id: $thread_id,
            photo: $photo,
            caption: $caption,
            parse_mode: "Markdown"
        }')
    
    local response
    if ! response=$(make_telegram_request "sendPhoto" "$json_data"); then
        log_error "Failed to send main message"
        exit 1
    fi
    
    local message_id
    message_id=$(echo "$response" | jq -r '.result.message_id')
    log_info "Main message sent successfully with ID: $message_id"
    
    # Skip button sending if no buttons available
    if [ ${#ALL_BUTTONS[@]} -eq 0 ]; then
        log_info "✅ Telegram notification sent successfully (without buttons)!"
        exit 0
    fi
    
    # Send buttons in batches
    local total_elements=${#ALL_BUTTONS[@]}
    local elements_per_batch=$((MAX_BUTTONS_PER_BATCH * 2))
    local batch_count=$(( (total_elements + elements_per_batch - 1) / elements_per_batch ))
    
    log_info "Sending buttons in ${batch_count} batches"
    
    local batch_num=1
    for ((i=0; i<total_elements; i+=elements_per_batch)); do
        local end=$((i + elements_per_batch))
        [[ $end -gt $total_elements ]] && end=$total_elements
        
        if ! send_buttons_batch ALL_BUTTONS "$message_id" "$batch_num" "$i" "$end"; then
            log_error "Failed to send button batch $batch_num"
            exit 1
        fi
        ((batch_num++))
    done
    
    log_info "✅ Telegram notification sent successfully with all buttons!"
}

# Execute main function
main "$@"