#!/usr/bin/env bash
set -e

BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
THREAD_ID="734"

# Build parameters
SOURCE="${SOURCE}"
VERSION="${VERSION}"
BUILD_TYPE="${BUILD_TYPE}"
FOR="${FOR}"
RELEASE_TAG="${RELEASE_TAG}"

# Set image URL
if [ "$SOURCE" = "immortalwrt" ]; then
    image_url="https://avatars.githubusercontent.com/u/53193414?s=200&v=4"
else
    image_url="https://avatars.githubusercontent.com/u/2528830?s=200&v=4"
fi

# Generate message
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

declare -a ALL_BUTTONS
button_count=0
mkdir -p artifacts

# Combine artifact files
if [ -d "artifacts" ] && [ ! -f "combined_artifacts.txt" ]; then
    find artifacts -name "artifacts.txt" -exec cat {} \; > combined_artifacts.txt 2>/dev/null || true
fi

[ -f combined_artifacts.txt ] || touch combined_artifacts.txt
[ -s combined_artifacts.txt ] || echo "::warning::combined_artifacts.txt is empty"

# Parse artifact links
while IFS='|' read -r target_name file_url || [[ -n "$target_name" ]]; do
    [[ -z "$target_name" && -z "$file_url" ]] && continue
    target_name=$(echo "$target_name" | xargs)
    file_url=$(echo "$file_url" | xargs)
    if [[ "$file_url" =~ ^https?:// ]]; then
        ALL_BUTTONS+=("$target_name" "$file_url")
        ((button_count++))
    fi
done < combined_artifacts.txt

# Add release button
if [ -n "$RELEASE_TAG" ]; then
    ALL_BUTTONS+=("View Release" "https://github.com/rizkikotet-dev/RTA-WRT/releases/tag/$RELEASE_TAG")
    ((button_count++))
fi

[ $button_count -eq 0 ] && echo "::error::No buttons to send, exiting" && exit 1
[ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ] && echo "::error::Missing BOT_TOKEN or CHAT_ID" && exit 1

# Send photo with caption
for attempt in {1..3}; do
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "message_thread_id=${THREAD_ID}" \
        --data-urlencode "photo=${image_url}" \
        --data-urlencode "caption=${message}" \
        --data-urlencode "parse_mode=Markdown")

    if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
        message_id=$(echo "$response" | jq -r '.result.message_id')
        break
    else
        [ $attempt -lt 3 ] && sleep $((attempt * 3)) || exit 1
    fi
done

# Function to send buttons in batch
send_buttons_batch() {
    local start=$1 end=$2 batch_num=$3
    local buttons_json='[]'
    for ((i=start; i<end; i+=2)); do
        [ $i -ge ${#ALL_BUTTONS[@]} ] && break
        local name="${ALL_BUTTONS[i]}"
        local url="${ALL_BUTTONS[i+1]}"
        [[ "$name" == "View Release" ]] && name="🔗 View Release" || name="📥 $name"
        buttons_json=$(echo "$buttons_json" | jq --arg name "$name" --arg url "$url" '. += [[{"text": $name, "url": $url}]]')
    done

    for attempt in {1..3}; do
        batch_response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            --data-urlencode "chat_id=${CHAT_ID}" \
            --data-urlencode "message_thread_id=${THREAD_ID}" \
            --data-urlencode "text=📦 *Download Options (Group ${batch_num})*" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "reply_to_message_id=${message_id}" \
            --data-urlencode "reply_markup={\"inline_keyboard\":$(echo "$buttons_json" | jq -c)}")
        if [[ $(echo "$batch_response" | jq -r '.ok') == "true" ]]; then
            break
        else
            [ $attempt -lt 3 ] && sleep $((attempt * 2)) || echo "::warning::Batch $batch_num failed"
        fi
    done
    sleep 2
}

# Send batches
total_elements=${#ALL_BUTTONS[@]}
max_buttons_per_batch=40
batch_count=$(( (total_elements + max_buttons_per_batch - 1) / max_buttons_per_batch ))

batch_num=1
for ((i=0; i<total_elements; i+=max_buttons_per_batch)); do
    end=$((i + max_buttons_per_batch))
    ((end > total_elements)) && end=$total_elements
    send_buttons_batch $i $end $batch_num
    ((batch_num++))
done

echo "✅ Telegram notification sent successfully!"