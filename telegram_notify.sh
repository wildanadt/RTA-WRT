#!/usr/bin/env bash

# --- Configuration ---
# Set these environment variables before running the script
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
THREAD_ID="${THREAD_ID:-}" # Optional, for group chats

# Build specific variables
SOURCE="${SOURCE}"             # e.g., "immortalwrt", "openwrt"
VERSION="${VERSION}"           # Firmware version
BUILD_TYPE="${BUILD_TYPE}"     # e.g., "stable", "snapshot", "developer"
FOR="${FOR}"                   # "main" for stable release, anything else for dev build
RELEASE_TAG="${RELEASE_TAG}"   # GitHub release tag, if applicable

# --- Functions ---

# Function to validate essential environment variables
validate_env_vars() {
    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        echo "::error::BOT_TOKEN or CHAT_ID is not set. Please provide these variables."
        exit 1
    fi
}

# Function to set image/sticker URL based on source
get_theme_image_url() {
    local source_type="$1"
    if [[ "$source_type" = "immortalwrt" ]]; then
        echo "https://avatars.githubusercontent.com/u/53193414?s=200&v=4" # ImmortalWRT theme
    else
        echo "https://avatars.githubusercontent.com/u/2528830?s=200&v=4"   # OpenWRT theme
    fi
}

# Function to get current date, time, and time of day
get_time_info() {
    CURRENT_DATE=$(date '+%d %B %Y')
    CURRENT_TIME=$(date '+%H:%M:%S %Z')
    HOUR=$(date '+%H')

    if [[ $HOUR -ge 5 && $HOUR -lt 12 ]]; then
        TIME_OF_DAY="morning"
        TIME_EMOJI="🌅"
    elif [[ $HOUR -ge 12 && $HOUR -lt 18 ]]; then
        TIME_OF_DAY="afternoon"
        TIME_EMOJI="☀️"
    else
        TIME_OF_DAY="evening"
        TIME_EMOJI="🌙"
    fi
}

# Function to extract and format changelog from CHANGELOG.md
extract_changelog() {
    local changelog_file="CHANGELOG.md"
    local today_date=$(date '+%d-%m-%Y') # e.g., 20-05-2025

    CHANGELOG_FULL=""
    CHANGELOG=""

    if [[ -f "$changelog_file" ]]; then
        # Extract the full changelog section for the given date
        CHANGELOG_FULL=$(awk -v today="$today_date" '
            BEGIN { RS="\n"; print_changelog=0 }
            /\*\*Changelog Firmware\*\*/ {
                if ($0 ~ today) {
                    print_changelog=1
                } else if (print_changelog) {
                    print_changelog=0
                }
            }
            print_changelog && /^\- / && !/Version:/ {
                sub(/^- /, "│ • ")
                print
            }
        ' "$changelog_file")

        # Truncate changelog for Telegram caption (max 5 entries)
        CHANGELOG=$(echo "$CHANGELOG_FULL" | head -n 5)
        if [[ $(echo "$CHANGELOG_FULL" | wc -l) -gt 5 ]]; then
            CHANGELOG+="\n│ • And More..."
        fi
    else
        echo "Debug: CHANGELOG.md not found in current directory."
    fi

    # Fallback if no changelog found
    if [[ -z "$CHANGELOG_FULL" ]]; then
        CHANGELOG="│ • No changelog entries found for version ${VERSION} on date ${today_date}. Verify CHANGELOG.md format and version."
        CHANGELOG_FULL="$CHANGELOG"
    fi
}

# Function to generate the Telegram message caption
generate_telegram_caption() {
    local message_type="$1" # "main" or "dev"
    local changelog_content="$2"

    local title_block
    local section_title
    local tips_guidelines_title
    local tips_guidelines_content

    if [[ "$message_type" = "main" ]]; then
        title_block="╔══════════════════════╗
          🎯 RTA-WRT FIRMWARE
               ✅ STABLE RELEASE
╚══════════════════════╝"
        section_title="📌 *Release Highlights*"
        tips_guidelines_title="💡 *Installation Tips*"
        tips_guidelines_content="│ 1. Backup your settings first
│ 2. Download for your specific device
│ 3. Verify checksums before flashing"
    else
        title_block="╔══════════════════════╗
        🚀 *RTA-WRT FIRMWARE*
           🧪 *DEVELOPER BUILD*
╚══════════════════════╝"
        section_title="🧪 *Development Notes*"
        tips_guidelines_title="💡 *Testing Guidelines*"
        tips_guidelines_content="│ 1. Test WiFi stability over 24 hours
│ 2. Check CPU temperatures under load
│ 3. Verify all services function properly"
    fi

    cat <<EOF
$title_block

${TIME_EMOJI} Good ${TIME_OF_DAY}, $([[ "$message_type" = "main" ]] && echo "firmware enthusiasts!" || echo "beta testers!")

📱 *$(echo "$message_type" | sed 's/main/Release/; s/dev/Build/') Information*
┌─────────────────────
│ 🔹 *Version:* \`${SOURCE}:${VERSION}\`
│ 🔹 *Build:* \`${BUILD_TYPE}\`
│ 🔹 *Date:* ${CURRENT_DATE}
│ 🔹 *Time:* ${CURRENT_TIME}
└─────────────────────

$section_title (see full changelog in firmware.html)
┌─────────────────────
$changelog_content
└─────────────────────

$tips_guidelines_title
┌─────────────────────
$tips_guidelines_content
└─────────────────────
EOF
}

# Function to send a photo with caption to Telegram
send_photo_to_telegram() {
    local photo_url="$1"
    local caption_text="$2"
    local max_retries=3
    local attempt=0
    local response
    local message_id=""

    echo "Sending main firmware announcement..."
    while [[ $attempt -lt $max_retries ]]; do
        attempt=$((attempt + 1))
        response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
            --data-urlencode "chat_id=${CHAT_ID}" \
            --data-urlencode "photo=${photo_url}" \
            --data-urlencode "caption=${caption_text}" \
            --data-urlencode "parse_mode=Markdown" \
            --data-urlencode "message_thread_id=${THREAD_ID}")

        if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
            message_id=$(echo "$response" | jq -r '.result.message_id')
            echo "Main message sent successfully with ID: $message_id"
            echo "$message_id" # Return message_id
            return 0
        else
            local error_code=$(echo "$response" | jq -r '.error_code')
            local error_desc=$(echo "$response" | jq -r '.description')
            echo "Attempt $attempt failed to send main message: Code $error_code - $error_desc"
            if [[ $attempt -lt $max_retries ]]; then
                local sleep_time=$((attempt * 3))
                echo "Retrying in $sleep_time seconds..."
                sleep "$sleep_time"
            else
                echo "::error::Failed to send main message after $max_retries attempts. Verify BOT_TOKEN, CHAT_ID, and message length."
                exit 1
            fi
        fi
    done
    return 1 # Should not reach here if successful
}

# Function to parse combined_artifacts.txt into a button array
parse_buttons() {
    local button_array=()
    local file="combined_artifacts.txt"

    if [[ ! -f "$file" ]]; then
        echo "Warning: combined_artifacts.txt not found. No download buttons will be generated."
        return
    fi

    while IFS='|' read -r name url || [[ -n "$name" ]]; do
        name=$(echo "$name" | xargs)
        url=$(echo "$url" | xargs)

        # Skip empty lines or specific unwanted patterns
        if [[ -z "$name" || -z "$url" || "$name" == *"all-tunnelall-tunnel"* ]]; then
            continue
        fi

        if [[ "$url" =~ ^https?:// ]]; then
            button_array+=("$name" "$url")
        fi
    done < "$file"

    # Add "View Release" button if RELEASE_TAG is set
    if [[ -n "$RELEASE_TAG" ]]; then
        button_array+=("View Release" "https://github.com/rizkikotet-dev/RTA-WRT/releases/tag/$RELEASE_TAG")
    fi

    # Return the array elements separated by newline for easier processing outside
    printf "%s\n" "${button_array[@]}"
}

# Function to generate firmware.html
generate_firmware_html() {
    local firmware_js_escaped="$1"
    local changelog_js_escaped="$2"
    local source_val="$3"
    local version_val="$4"

    cat <<EOF > firmware.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="theme-color" content="#0F172A" />
  <title>RTA-WRT Firmware Downloads</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" integrity="sha512-iecdLmaskl7CVkqkXNQ/ZH/XLlvWZOJyj7Yy7tcenmpD1ypASozpmT/E0iPtmFIB46ZmdtAc9eNBvH0H/ZpiBw==" crossorigin="anonymous" referrerpolicy="no-referrer" />
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            primary: {
              50: '#eff6ff', 100: '#dbeafe', 200: '#bfdbfe', 300: '#93c5fd', 400: '#60a5fa',
              500: '#3b82f6', 600: '#2563eb', 700: '#1d4ed8', 800: '#1e40af', 900: '#1e3a8a', 950: '#172554',
            },
          },
          fontFamily: {
            sans: ['Inter', 'ui-sans-serif', 'system-ui', '-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto', 'Helvetica Neue', 'Arial', 'sans-serif'],
          },
          animation: {
            'fade-in': 'fadeIn 0.5s ease-out forwards',
            'fade-in-up': 'fadeInUp 0.6s ease-out forwards',
            'pulse-slow': 'pulse 3s cubic-bezier(0.4, 0, 0.6, 1) infinite',
            'spin-slow': 'spin 2s linear infinite',
          },
          keyframes: {
            fadeIn: { '0%': { opacity: '0' }, '100%': { opacity: '1' } },
            fadeInUp: { '0%': { opacity: '0', transform: 'translateY(10px)' }, '100%': { opacity: '1', transform: 'translateY(0)' } },
          },
          boxShadow: {
            'glow': '0 0 15px rgba(59, 130, 246, 0.5)',
            'card': '0 4px 6px -1px rgba(0, 0, 0, 0.1), 0 2px 4px -1px rgba(0, 0, 0, 0.06)',
            'card-hover': '0 10px 15px -3px rgba(0, 0, 0, 0.1), 0 4px 6px -2px rgba(0, 0, 0, 0.05)',
          }
        }
      }
    }
  </script>
  <style>
    @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
    html { scroll-behavior: smooth; }
    .bg-gradient-radial {
      background-image: radial-gradient(circle at 25% 25%, rgba(59, 130, 246, 0.08) 0%, transparent 50%),
                        radial-gradient(circle at 75% 75%, rgba(59, 130, 246, 0.03) 0%, transparent 50%);
    }
    .text-gradient {
      background: linear-gradient(90deg, #3b82f6 0%, #60a5fa 100%);
      -webkit-background-clip: text;
      background-clip: text;
      color: transparent;
    }
    .card-gradient-top { position: relative; overflow: hidden; }
    .card-gradient-top::before {
      content: ""; position: absolute; top: 0; left: 0; width: 100%; height: 4px;
      background: linear-gradient(90deg, #3b82f6 0%, #60a5fa 100%);
      transform: scaleX(0); transform-origin: left; transition: transform 0.3s ease;
    }
    .card-gradient-top:hover::before, .card-gradient-top:focus-within::before { transform: scaleX(1); }
    .btn-shine { position: relative; overflow: hidden; }
    .btn-shine::after {
      content: ""; position: absolute; top: 0; left: 0; width: 100%; height: 100%;
      background-color: rgba(255, 255, 255, 0.1);
      transform: translateX(-100%); transition: transform 0.6s ease;
    }
    .btn-shine:hover::after { transform: translateX(100%); }
  </style>
</head>
<body>
  <div class="min-h-screen bg-slate-900 bg-gradient-radial text-slate-100 font-sans pb-12">
    <div class="container mx-auto px-4 py-8 animate-fade-in">
      <div class="text-center mb-12">
        <h1 class="text-4xl md:text-5xl font-bold mb-3 text-gradient tracking-tight">
          RTA-WRT Firmware Downloads
        </h1>
        <p class="text-slate-400 text-lg max-w-2xl mx-auto">
          Find and download the latest firmware images for your device
        </p>
      </div>

      <div class="max-w-3xl mx-auto mb-12 opacity-0 animate-fade-in-up" style="animation-delay: 200ms;">
        <div class="bg-slate-800 rounded-xl border border-slate-700 p-6 shadow-lg">
          <h2 class="text-2xl font-semibold text-slate-100 mb-4">Changelog for ${source_val}:${version_val}</h2>
          <ul class="text-slate-300 list-disc list-inside space-y-2">
            ${changelog_js_escaped//│ • /<li>}
          </ul>
        </div>
      </div>

      <div class="max-w-3xl mx-auto opacity-0 animate-fade-in-up" style="animation-delay: 400ms;">
        <div class="relative mb-6">
          <div class="absolute inset-y-0 left-0 flex items-center pl-4 pointer-events-none">
            <i class="fa-solid fa-magnifying-glass text-slate-400"></i>
          </div>
          <input
            id="search"
            type="text"
            class="w-full p-4 pl-11 rounded-xl border-2 border-slate-700 bg-slate-800/80 text-slate-100 focus:outline-none focus:border-primary-500 focus:ring-2 focus:ring-primary-500/30 transition-all backdrop-blur-md"
            placeholder="Search firmware by device name..."
            autocomplete="off"
          />
        </div>

        <div class="flex justify-between items-center mb-6 text-sm text-slate-400">
          <div id="count-display">Loading firmware data...</div>
          <div id="last-updated" class="flex items-center">
            <i class="fa-regular fa-clock mr-2"></i>
            <span>Updating...</span>
          </div>
        </div>
      </div>

      <div id="loader" class="flex justify-center my-12">
        <div class="w-12 h-12 border-4 border-primary-200/30 border-t-primary-500 rounded-full animate-spin-slow"></div>
      </div>

      <div id="firmware-list" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 opacity-0 animate-fade-in-up" style="animation-delay: 600ms;"></div>
    </div>

    <div class="mt-16 text-center text-slate-500 text-sm">
      <p>RTA-WRT Firmware Portal © <span id="current-year"></span></p>
    </div>
  </div>

  <script>
    const firmwareDataRaw = \`
${firmware_js_escaped}
    \`;

    const firmwareData = firmwareDataRaw.trim().split('\\n')
      .filter(line => line.trim().length > 0)
      .map(line => {
        const [name, url] = line.trim().split('|');
        return { 
          name: name.trim(), 
          url: url.trim(),
          id: Math.random().toString(36).substring(2, 10)
        };
      });

    const container = document.getElementById("firmware-list");
    const searchInput = document.getElementById("search");
    const countDisplay = document.getElementById("count-display");
    const lastUpdated = document.getElementById("last-updated");
    const loader = document.getElementById("loader");
    const currentYear = document.getElementById("current-year");
    
    currentYear.textContent = new Date().getFullYear().toString();
    lastUpdated.querySelector('span').textContent = "Updated: " + new Date().toLocaleDateString();
    
    function escapeHTML(str) {
      return str
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;")
        .replace(/"/g, "&quot;")
        .replace(/'/g, "&#39;");
    }

    function renderFirmwareList(data, animate = false) {
      container.innerHTML = "";
      
      if (data.length === 0) {
        container.innerHTML = \`
          <div class="col-span-full py-12 px-6 border-2 border-dashed border-slate-700 rounded-2xl text-center">
            <i class="fa-regular fa-face-frown text-4xl text-slate-500 mb-4"></i>
            <h3 class="text-xl font-semibold text-slate-300 mb-2">No firmware found</h3>
            <p class="text-slate-400">Try adjusting your search query</p>
          </div>
        \`;
        container.style.opacity = "1";
        return;
      }
      
      countDisplay.textContent = \`Showing \${data.length} firmware \${data.length === 1 ? 'image' : 'images'}\`;
      container.style.opacity = "1";
      
      data.forEach((item, index) => {
        const card = document.createElement("div");
        card.className = "card-gradient-top bg-slate-800 rounded-xl border border-slate-700 p-6 shadow-lg transition-all duration-300 hover:transform hover:-translate-y-1 hover:shadow-xl hover:bg-slate-700/80 hover:shadow-glow";
        
        if (animate && index < 20) {
          card.style.opacity = "0";
          card.style.transform = "translateY(10px)";
          
          setTimeout(() => {
            card.style.transition = "all 0.5s ease";
            card.style.opacity = "1";
            card.style.transform = "translateY(0)";
          }, index * 50);
        }

        card.innerHTML = \`
          <div class="mb-5">
            <div class="flex items-start mb-3">
              <i class="fa-solid fa-cube text-primary-500 text-xl mr-3 mt-0.5"></i>
              <h2 class="text-lg font-semibold text-slate-100 leading-tight">
                \${escapeHTML(item.name)}
              </h2>
            </div>
            <p class="text-slate-400 text-sm mb-5">
              Download the latest firmware image for this device. Compatible with RTA-WRT.
            </p>
          </div>
          <a href="\${escapeHTML(item.url)}" target="_blank" rel="noopener noreferrer" 
              class="btn-shine inline-flex items-center bg-primary-600 hover:bg-primary-700 text-white font-medium py-2.5 px-4 rounded-lg transition-all duration-300 hover:shadow-lg" 
              data-id="\${item.id}">
            <i class="fa-solid fa-download mr-2"></i>
            Download Firmware
          </a>
        \`;

        container.appendChild(card);
      });
      
      document.querySelectorAll('[data-id]').forEach(button => {
        button.addEventListener('click', function() {
          console.log("Download started:", this.dataset.id);
        });
      });
    }

    function debounce(func, wait) {
      let timeout;
      return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
      };
    }

    searchInput.addEventListener("input", debounce(() => {
      const keyword = searchInput.value.toLowerCase();
      const filtered = firmwareData.filter(item => 
        item.name.toLowerCase().includes(keyword)
      );
      renderFirmwareList(filtered, true);
    }, 300));

    setTimeout(() => {
      loader.style.display = "none";
      container.parentElement.querySelectorAll('.max-w-3xl').forEach(el => {
        el.style.opacity = "1";
      });
      renderFirmwareList(firmwareData, true);
    }, 800);
    
    setTimeout(() => {
      searchInput.focus();
    }, 1000);
  </script>
</body>
</html>
EOF
}

# Function to send a document (HTML file) to Telegram
send_document_to_telegram() {
    local file_path="$1"
    local en_caption_text="$2"
    local id_caption_text="$3"
    local reply_to_message_id="$4"

    echo -e "${YELLOW}[INFO] Sending ${file_path} to Telegram...${NC}"

    local caption="🌟 *RTA-WRT FIRMWARE UPDATE* 🌟

🇬🇧 *ENGLISH*
${en_caption_text}

🇮🇩 *BAHASA INDONESIA*
${id_caption_text}"

    local response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F "chat_id=${CHAT_ID}" \
        -F "document=@${file_path}" \
        -F "caption=${caption}" \
        -F "parse_mode=Markdown" \
        -F "reply_to_message_id=${reply_to_message_id}" \
        -F "message_thread_id=${THREAD_ID}")

    if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
        echo -e "${GREEN}[SUCCESS] File ${file_path} sent successfully${NC}"
        return 0
    else
        echo -e "${RED}[ERROR] Failed to send file ${file_path}${NC}"
        echo -e "${RED}Response: ${response}${NC}"
        return 1
    fi
}

# --- Main Script Logic ---

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print banner
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                      ║${NC}"
echo -e "${BLUE}║  ${YELLOW}RTA-WRT FIRMWARE NOTIFICATION SYSTEM${BLUE}            ║${NC}"
echo -e "${BLUE}║  ${YELLOW}SISTEM NOTIFIKASI FIRMWARE RTA-WRT${BLUE}              ║${NC}"
echo -e "${BLUE}║                                                      ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"

# 1. Validate environment variables
validate_env_vars

# 2. Get theme image URL
image_url=$(get_theme_image_url "$SOURCE")

# 3. Get current time information
get_time_info

# 4. Extract changelog
extract_changelog

# 5. Generate main Telegram message caption
# We need to decide if the message needs truncation based on its length
# Telegram caption limit for sendPhoto is 1024 characters.
# We will generate the message once, check its length, and re-generate if needed.

# First attempt to generate message with current CHANGELOG (max 5 entries)
MAIN_MESSAGE=$(generate_telegram_caption "$FOR" "$CHANGELOG")

# Check message length and truncate changelog if necessary
if [[ ${#MAIN_MESSAGE} -gt 1024 ]]; then
    echo "Debug: Message length (${#MAIN_MESSAGE} chars) exceeds 1024 characters, truncating changelog further..."
    TRUNCATED_CHANGELOG=$(echo "$CHANGELOG_FULL" | head -n 3)
    if [[ $(echo "$CHANGELOG_FULL" | wc -l) -gt 3 ]]; then
        TRUNCATED_CHANGELOG+="
│ • And More..."
    fi
    MAIN_MESSAGE=$(generate_telegram_caption "$FOR" "$TRUNCATED_CHANGELOG")
    echo "Debug: Truncated message length: ${#MAIN_MESSAGE} characters"
else
    echo "Debug: Message length: ${#MAIN_MESSAGE} characters"
fi

# 6. Send the main photo message and capture its ID
MESSAGE_ID=$(send_photo_to_telegram "$image_url" "$MAIN_MESSAGE")
if [[ -z "$MESSAGE_ID" ]]; then
    echo -e "${RED}❌ Failed to get message ID for reply. Exiting.${NC}"
    exit 1
fi

# 7. Parse buttons for HTML file
ALL_BUTTONS=($(parse_buttons))
# Escape button data for JavaScript in HTML
FIRMWARE_JS_ESCAPED=""
for (( i=0; i<${#ALL_BUTTONS[@]}; i+=2 )); do
    name_esc=$(echo "${ALL_BUTTONS[i]}" | sed 's/"/\\"/g; s/|/\\|/g')
    url_esc=$(echo "${ALL_BUTTONS[i+1]}" | sed 's/"/\\"/g; s/|/\\|/g')
    FIRMWARE_JS_ESCAPED+="${name_esc}|${url_esc}\n"
done

# Escape full changelog for JavaScript in HTML
CHANGELOG_JS_ESCAPED=$(echo "$CHANGELOG_FULL" | sed 's/"/\\"/g; s/|/\\|/g; s/\r//g') # Remove carriage returns

# 8. Generate firmware.html
generate_firmware_html "$FIRMWARE_JS_ESCAPED" "$CHANGELOG_JS_ESCAPED" "$SOURCE" "$VERSION"

# 9. Send firmware.html as a document
echo -e "${BLUE}[PROCESS] Sending firmware.html to Telegram...${NC}"

# English caption for HTML file
HTML_EN_CAPTION="Click the document above to open the full firmware download page in your browser.
This page contains all available firmware images and a complete changelog.
If the document does not display correctly, please download and open it manually."

# Indonesian caption for HTML file
HTML_ID_CAPTION="Klik dokumen di atas untuk membuka halaman unduhan firmware lengkap di browser Anda.
Halaman ini berisi semua gambar firmware yang tersedia dan changelog lengkap.
Jika dokumen tidak ditampilkan dengan benar, harap unduh dan buka secara manual."

if send_document_to_telegram "firmware.html" "$HTML_EN_CAPTION" "$HTML_ID_CAPTION" "$MESSAGE_ID"; then
    echo -e "\n${GREEN}✅ All notifications sent successfully!${NC}"
else
    echo -e "\n${RED}❌ Error occurred during notification process${NC}"
    exit 1
fi

echo "✅ Telegram message + HTML preview + data file sent!"