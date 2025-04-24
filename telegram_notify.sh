#!/usr/bin/env bash

ls -lh

BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
THREAD_ID="734"

# Build parameters
SOURCE="${SOURCE}"
VERSION="${VERSION}"
BUILD_TYPE="${BUILD_TYPE}"
FOR="${FOR}"
RELEASE_TAG="${RELEASE_TAG}"

# Set image URL based on source
if [ "$SOURCE" = "immortalwrt" ]; then
    image_url="https://avatars.githubusercontent.com/u/53193414?s=200&v=4"
else
    image_url="https://avatars.githubusercontent.com/u/2528830?s=200&v=4"
fi

 # Generate message based on branch
if [ "$FOR" = "main" ]; then
    message="━━━━━━━━━━━━━━━━━━━━━━
🎯 *RTA-WRT Firmware Update*
✅ _Stable Release_

🔹 *Version:* ${SOURCE}:${VERSION}
🔹 *Date:* $(date '+%d-%m-%Y %H:%M:%S')
🔹 *Build Type:* ${BUILD_TYPE}

 📌 *Release Notes:*
• Stable version release
• Recommended for all users
• Includes latest features and bug fixes
━━━━━━━━━━━━━━━━━━━━━━"
else
    message="━━━━━━━━━━━━━━━━━━━━━━
🚀 *RTA-WRT Firmware Update*
🌟 _Development Release_

🔹 *Version:* ${SOURCE}:${VERSION}
🔹 *Date:* $(date '+%d-%m-%Y %H:%M:%S')
🔹 *Build Type:* ${BUILD_TYPE}

 📌 *Development Notes:*
• Suitable for testing
• Please provide feedback
• Report any bugs found
• Your feedback helps development
━━━━━━━━━━━━━━━━━━━━━━"
fi

 # Collect all buttons into an array
declare -a ALL_BUTTONS
button_count=0

 # Validate and parse the artifacts file
echo "Parsing artifact links..."
while IFS='|' read -r target_name file_url || [[ -n "$target_name" ]]; do
    target_name=$(echo "$target_name" | xargs)
    file_url=$(echo "$file_url" | xargs)

     if [[ -n "$target_name" && -n "$file_url" ]]; then
        # Validate URL format to prevent errors (basic check)
        if [[ "$file_url" =~ ^https?:// ]]; then
            ALL_BUTTONS+=("$target_name" "$file_url")
            ((button_count++))
        else
            echo "::warning::Skipping invalid URL format: $file_url"
        fi
    fi
done < combined_artifacts.txt

 # Check if we have any buttons
if [ $button_count -eq 0 ]; then
    echo "::warning::No valid download links found in artifacts file"
fi

 # Add a button to view the release
if [ -n "$RELEASE_TAG" ]; then
    ALL_BUTTONS+=("View Release" "https://github.com/rizkikotet-dev/RTA-WRT/releases/tag/$RELEASE_TAG")
    ((button_count++))
    echo "Added release button: View Release -> $RELEASE_TAG"
else
    echo "::warning::Release tag is empty, skipping View Release button"
fi

 echo "Total buttons: $button_count"

 # Send the initial message with photo
echo "Sending main message with photo..."
for attempt in {1..3}; do
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "message_thread_id=${THREAD_ID}" \
        --data-urlencode "photo=${image_url}" \
        --data-urlencode "caption=${message}" \
        --data-urlencode "parse_mode=Markdown")

     # Check if the message was sent successfully
    if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
        # Get the message ID of the sent message
        message_id=$(echo "$response" | jq -r '.result.message_id')
        echo "Main message sent successfully with ID: $message_id"
        break
    else
        error_code=$(echo "$response" | jq -r '.error_code')
        error_desc=$(echo "$response" | jq -r '.description')
        echo "Attempt $attempt failed to send initial message: Code $error_code - $error_desc"
        
        if [ $attempt -lt 3 ]; then
            sleep_time=$((attempt * 3))
            echo "Retrying in $sleep_time seconds..."
            sleep $sleep_time
        else
            echo "::error::Failed to send initial message after 3 attempts"
            exit 1
        fi
    fi
done

 # Function to send buttons in batches with retry mechanism
send_buttons_batch() {
    local start=$1
    local end=$2
    local batch_num=$3
    local max_retries=3
    local retry_delay=2
    local buttons_json='[]'
    
    for ((i=start; i<end; i+=2)); do
        if [[ $i -ge ${#ALL_BUTTONS[@]} ]]; then
            break
        fi
        
        local name="${ALL_BUTTONS[i]}"
        local url="${ALL_BUTTONS[i+1]}"
        
        # For View Release button, add a special emoji
        if [[ "$name" == "View Release" ]]; then
            name="🔗 View Release"
        else
            name="📥 $name"
        fi
        
        buttons_json=$(echo "$buttons_json" | jq --arg name "$name" --arg url "$url" \
            '. += [[{"text": $name, "url": $url}]]')
    done
    
    # Debug message
    echo "Preparing buttons batch ${batch_num}: ${start}-${end}"
    
    # Send the buttons with retry
    local attempts=0
    local success=false
    
    while [[ $attempts -lt $max_retries && $success == false ]]; do
        ((attempts++))
        echo "Sending batch ${batch_num}, attempt ${attempts}..."
        
        local batch_response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${CHAT_ID}" \
            --data-urlencode "message_thread_id=${THREAD_ID}" \
            --data-urlencode "text=📦 *Download Options (Group ${batch_num})*" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "reply_to_message_id=${message_id}" \
            --data-urlencode "reply_markup={\"inline_keyboard\":$(echo "$buttons_json" | jq -c)}")
        
        # Check if successful
        if [[ $(echo "$batch_response" | jq -r '.ok') == "true" ]]; then
            echo "Batch ${batch_num} sent successfully!"
            success=true
        else
            local error_code=$(echo "$batch_response" | jq -r '.error_code')
            local error_desc=$(echo "$batch_response" | jq -r '.description')
            echo "Failed to send batch ${batch_num}: Code ${error_code} - ${error_desc}"
            
            # If we hit rate limiting, wait longer
            if [[ $error_code == 429 ]]; then
                local retry_after=$(echo "$batch_response" | jq -r '.parameters.retry_after // 5')
                echo "Rate limited. Waiting for ${retry_after} seconds before retrying..."
                sleep $retry_after
            elif [[ $attempts -lt $max_retries ]]; then
                echo "Retrying in ${retry_delay} seconds..."
                sleep $retry_delay
                # Exponential backoff
                retry_delay=$((retry_delay * 2))
            fi
        fi
    done
    
    if [[ $success == false ]]; then
        echo "::warning::Failed to send batch ${batch_num} after ${max_retries} attempts."
    fi
    
    # Add delay between batches to avoid rate limiting
    sleep 2
}

 # Calculate how many button groups we need (20 buttons per message)
# Each button takes 2 elements in the array (name and URL)
total_elements=${#ALL_BUTTONS[@]}
max_buttons_per_batch=40  # 20 buttons = 40 elements in array
batch_count=$(( (total_elements + max_buttons_per_batch - 1) / max_buttons_per_batch ))

 echo "Will send buttons in ${batch_count} batches"

 # Send buttons in batches of 20
batch_num=1
for ((i=0; i<total_elements; i+=max_buttons_per_batch)); do
    end=$((i + max_buttons_per_batch))
    if ((end > total_elements)); then
        end=$total_elements
    fi
    
    send_buttons_batch $i $end $batch_num
    ((batch_num++))
done

echo "✅ Telegram notification sent successfully!"