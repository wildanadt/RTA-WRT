#!/usr/bin/env bash

# --- Konfigurasi dasar ---
BOT_TOKEN="${BOT_TOKEN}"
CHAT_ID="${CHAT_ID}"
THREAD_ID="${THREAD_ID:-734}"

SOURCE="${SOURCE}"
VERSION="${VERSION}"
BUILD_TYPE="${BUILD_TYPE}"
FOR="${FOR}"
RELEASE_TAG="${RELEASE_TAG}"

# Validate BOT_TOKEN and CHAT_ID
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "::error::BOT_TOKEN or CHAT_ID is not set"
    exit 1
fi

# Set image/sticker based on source and build type
if [ "$SOURCE" = "immortalwrt" ]; then
    # ImmortalWRT theme
    image_url="https://avatars.githubusercontent.com/u/53193414?s=200&v=4"
else
    # OpenWRT theme
    image_url="https://avatars.githubusercontent.com/u/2528830?s=200&v=4"
fi

# Get current date in a more readable format
CURRENT_DATE=$(date '+%d %B %Y')
CURRENT_TIME=$(date '+%H:%M:%S %Z')

# Determine if it's a morning, afternoon, evening release
HOUR=$(date '+%H')
if [ $HOUR -ge 5 ] && [ $HOUR -lt 12 ]; then
    TIME_OF_DAY="morning"
    TIME_EMOJI="🌅"
elif [ $HOUR -ge 12 ] && [ $HOUR -lt 18 ]; then
    TIME_OF_DAY="afternoon"
    TIME_EMOJI="☀️"
else
    TIME_OF_DAY="evening"
    TIME_EMOJI="🌙"
fi

# --- Extract changelog from CHANGELOG.md ---
CHANGELOG_FILE="CHANGELOG.md"
CHANGELOG=""
CHANGELOG_FULL=""
TODAY=$(date '+%d-%m-%Y')  # Dynamic date, e.g., 20-05-2025

# Debugging: Log input variables
#echo "Debug: VERSION=${VERSION}, TODAY=${TODAY}, CHANGELOG_FILE=${CHANGELOG_FILE}"

if [ -f "$CHANGELOG_FILE" ]; then
    # Debugging: Confirm file exists and print first few lines
    #echo "Debug: CHANGELOG.md found, first 15 lines:"
    head -n 15 "$CHANGELOG_FILE"

    # Extract the full changelog section for the given date
    CHANGELOG_FULL=$(awk -v today="$TODAY" '
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
    ' "$CHANGELOG_FILE")

    # Debugging: Log the full extracted changelog
    #echo "Debug: Full extracted CHANGELOG:"
    #echo "$CHANGELOG_FULL"
    #echo "Debug: Number of changelog entries: $(echo "$CHANGELOG_FULL" | wc -l)"

    # Truncate changelog for Telegram caption (max 5 entries)
    CHANGELOG=$(echo "$CHANGELOG_FULL" | head -n 5)
    if [ $(echo "$CHANGELOG_FULL" | wc -l) -gt 5 ]; then
        CHANGELOG="${CHANGELOG}
│ • And More..."
    fi

    # Debugging: Log the truncated changelog
    #echo "Debug: Truncated CHANGELOG for Telegram:"
    #echo "$CHANGELOG"
    #echo "Debug: Number of truncated changelog entries: $(echo "$CHANGELOG" | wc -l)"
else
    echo "Debug: CHANGELOG.md not found in current directory"
fi

# If no changelog found, provide a more informative fallback
if [ -z "$CHANGELOG_FULL" ]; then
    CHANGELOG="│ • No changelog entries found for version ${VERSION} on date ${TODAY}. Verify CHANGELOG.md format and version."
    CHANGELOG_FULL="$CHANGELOG"
fi

# Generate a more modern and visually appealing message
if [ "$FOR" = "main" ]; then
    # Stable release message
    message="╔══════════════════════╗
║  🎯 *RTA-WRT FIRMWARE*  ║
║    ✅ *STABLE RELEASE*    ║
╚══════════════════════╝

${TIME_EMOJI} Good ${TIME_OF_DAY}, firmware enthusiasts!

📱 *Release Information*
┌─────────────────────
│ 🔹 *Version:* \`${SOURCE}:${VERSION}\`
│ 🔹 *Build:* \`${BUILD_TYPE}\`
│ 🔹 *Date:* ${CURRENT_DATE}
│ 🔹 *Time:* ${CURRENT_TIME}
└─────────────────────

📌 *Release Highlights* (see full changelog in firmware.html)
┌─────────────────────
${CHANGELOG}
└─────────────────────

💡 *Installation Tips*
┌─────────────────────
│ 1. Backup your settings first
│ 2. Download for your specific device
│ 3. Verify checksums before flashing
└─────────────────────"
else
    # Development release message
    message="╔══════════════════════╗
║  🚀 *RTA-WRT FIRMWARE*  ║
║   🧪 *DEVELOPER BUILD*   ║
╚══════════════════════╝

${TIME_EMOJI} Good ${TIME_OF_DAY}, beta testers!

📱 *Build Information*
┌─────────────────────
│ 🔹 *Version:* \`${SOURCE}:${VERSION}\`
│ 🔹 *Build:* \`${BUILD_TYPE}\`
│ 🔹 *Date:* ${CURRENT_DATE}
│ 🔹 *Time:* ${CURRENT_TIME}
└─────────────────────

🧪 *Development Notes* (see full changelog in firmware.html)
┌─────────────────────
${CHANGELOG}
└─────────────────────

💡 *Testing Guidelines*
┌─────────────────────
│ 1. Test WiFi stability over 24 hours
│ 2. Check CPU temperatures under load
│ 3. Verify all services function properly
└─────────────────────"
fi

# Debugging: Log message length
echo "Debug: Message length: ${#message} characters"

# Truncate further if message exceeds 1024 characters
if [ ${#message} -gt 1024 ]; then
    $echo "Debug: Message length exceeds 1024 characters, truncating changelog further..."
    CHANGELOG=$(echo "$CHANGELOG_FULL" | head -n 3)
    if [ $(echo "$CHANGELOG_FULL" | wc -l) -gt 3 ]; then
        CHANGELOG="${CHANGELOG}
│ • And More..."
    fi
    # Rebuild message with further truncated changelog
    if [ "$FOR" = "main" ]; then
        message="╔══════════════════════╗
║  🎯 *RTA-WRT FIRMWARE*  ║
║    ✅ *STABLE RELEASE*    ║
╚══════════════════════╝

${TIME_EMOJI} Good ${TIME_OF_DAY}, firmware enthusiasts!

📱 *Release Information*
┌─────────────────────
│ 🔹 *Version:* \`${SOURCE}:${VERSION}\`
│ 🔹 *Build:* \`${BUILD_TYPE}\`
│ 🔹 *Date:* ${CURRENT_DATE}
│ 🔹 *Time:* ${CURRENT_TIME}
└─────────────────────

📌 *Release Highlights* (see full changelog in firmware.html)
┌─────────────────────
${CHANGELOG}
└─────────────────────

💡 *Installation Tips*
┌─────────────────────
│ 1. Backup your settings first
│ 2. Download for your specific device
│ 3. Verify checksums before flashing
└─────────────────────"
    else
        message="╔══════════════════════╗
║  🚀 *RTA-WRT FIRMWARE*  ║
║   🧪 *DEVELOPER BUILD*   ║
╚══════════════════════╝

${TIME_EMOJI} Good ${TIME_OF_DAY}, beta testers!

📱 *Build Information*
┌─────────────────────
│ 🔹 *Version:* \`${SOURCE}:${VERSION}\`
│ 🔹 *Build:* \`${BUILD_TYPE}\`
│ 🔹 *Date:* ${CURRENT_DATE}
│ 🔹 *Time:* ${CURRENT_TIME}
└─────────────────────

🧪 *Development Notes* (see full changelog in firmware.html)
┌─────────────────────
${CHANGELOG}
└─────────────────────

💡 *Testing Guidelines*
┌─────────────────────
│ 1. Test WiFi stability over 24 hours
│ 2. Check CPU temperatures under load
│ 3. Verify all services function properly
└─────────────────────"
    fi
    echo "Debug: Truncated message length: ${#message} characters"
    echo "Debug: Number of truncated changelog entries: $(echo "$CHANGELOG" | wc -l)"
fi

# Send the main message with photo
echo "Sending main firmware announcement..."
for attempt in {1..3}; do
    response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendPhoto" \
        --data-urlencode "chat_id=${CHAT_ID}" \
        --data-urlencode "photo=${image_url}" \
        --data-urlencode "caption=${message}" \
        --data-urlencode "parse_mode=Markdown") > /dev/null

    # Check if the message was sent successfully
    if [[ $(echo "$response" | jq -r '.ok') == "true" ]]; then
        # Get the message ID of the sent message
        message_id=$(echo "$response" | jq -r '.result.message_id')
        echo "Main message sent successfully with ID: $message_id"
        break
    else
        error_code=$(echo "$response" | jq -r '.error_code')
        error_desc=$(echo "$response" | jq -r '.description')
        echo "Attempt $attempt failed to send main message: Code $error_code - $error_desc"
        
        if [ $attempt -lt 3 ]; then
            sleep_time=$((attempt * 3))
            echo "Retrying in $sleep_time seconds..."
            sleep $sleep_time
        else
            echo "::error::Failed to send main message after 3 attempts. Verify BOT_TOKEN, CHAT_ID, and message length."
            exit 1
        fi
    fi
done

# --- Ambil tombol dari file combined_artifacts.txt ---
ALL_BUTTONS=()
button_count=0

while IFS='|' read -r name url || [[ -n "$name" ]]; do
  name=$(echo "$name" | xargs)
  url=$(echo "$url" | xargs)

  [[ -z "$name" || -z "$url" || "$name" == *"all-tunnelall-tunnel"* ]] && continue

  if [[ "$url" =~ ^https?:// ]]; then
    ALL_BUTTONS+=("$name" "$url")
    ((button_count++))
  fi
done < combined_artifacts.txt

if [ -n "$RELEASE_TAG" ]; then
  ALL_BUTTONS+=("View Release" "https://github.com/rizkikotet-dev/RTA-WRT/releases/tag/$RELEASE_TAG")
fi

# --- Buat firmware_data.txt dan firmware.html ---
FIRMWARE_JS_ESCAPED=$(printf "%s|%s\n" "${ALL_BUTTONS[@]}")
CHANGELOG_JS_ESCAPED=$(echo "$CHANGELOG_FULL" | sed 's/"/\\"/g; s/|/\\|/g')

cat <<EOF > firmware.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="theme-color" content="#0F172A" />
  <title>RTA-WRT Firmware Downloads</title>
  <!-- Tailwind CSS -->
  <script src="https://cdn.tailwindcss.com"></script>
  <!-- Font Awesome -->
  <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" integrity="sha512-iecdLmaskl7CVkqkXNQ/ZH/XLlvWZOJyj7Yy7tcenmpD1ypASozpmT/E0iPtmFIB46ZmdtAc9eNBvH0H/ZpiBw==" crossorigin="anonymous" referrerpolicy="no-referrer" />
  <script>
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          colors: {
            primary: {
              50: '#eff6ff',
              100: '#dbeafe',
              200: '#bfdbfe',
              300: '#93c5fd',
              400: '#60a5fa',
              500: '#3b82f6',
              600: '#2563eb',
              700: '#1d4ed8',
              800: '#1e40af',
              900: '#1e3a8a',
              950: '#172554',
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
            fadeIn: {
              '0%': { opacity: '0' },
              '100%': { opacity: '1' },
            },
            fadeInUp: {
              '0%': { opacity: '0', transform: 'translateY(10px)' },
              '100%': { opacity: '1', transform: 'translateY(0)' },
            },
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
    
    html {
      scroll-behavior: smooth;
    }
    
    /* Custom gradients */
    .bg-gradient-radial {
      background-image: radial-gradient(circle at 25% 25%, rgba(59, 130, 246, 0.08) 0%, transparent 50%),
                        radial-gradient(circle at 75% 75%, rgba(59, 130, 246, 0.03) 0%, transparent 50%);
    }
    
    /* Gradient text */
    .text-gradient {
      background: linear-gradient(90deg, #3b82f6 0%, #60a5fa 100%);
      -webkit-background-clip: text;
      background-clip: text;
      color: transparent;
    }
    
    /* Card hover effects */
    .card-gradient-top {
      position: relative;
      overflow: hidden;
    }
    
    .card-gradient-top::before {
      content: "";
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 4px;
      background: linear-gradient(90deg, #3b82f6 0%, #60a5fa 100%);
      transform: scaleX(0);
      transform-origin: left;
      transition: transform 0.3s ease;
    }
    
    .card-gradient-top:hover::before,
    .card-gradient-top:focus-within::before {
      transform: scaleX(1);
    }
    
    /* Button effect */
    .btn-shine {
      position: relative;
      overflow: hidden;
    }
    
    .btn-shine::after {
      content: "";
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background-color: rgba(255, 255, 255, 0.1);
      transform: translateX(-100%);
      transition: transform 0.6s ease;
    }
    
    .btn-shine:hover::after {
      transform: translateX(100%);
    }
  </style>
</head>
<body>
  <div class="min-h-screen bg-slate-900 bg-gradient-radial text-slate-100 font-sans pb-12">
    <div class="container mx-auto px-4 py-8 animate-fade-in">
      <!-- Header -->
      <div class="text-center mb-12">
        <h1 class="text-4xl md:text-5xl font-bold mb-3 text-gradient tracking-tight">
          RTA-WRT Firmware Downloads
        </h1>
        <p class="text-slate-400 text-lg max-w-2xl mx-auto">
          Find and download the latest firmware images for your device
        </p>
      </div>

      <!-- Changelog Section -->
      <div class="max-w-3xl mx-auto mb-12 opacity-0 animate-fade-in-up" style="animation-delay: 200ms;">
        <div class="bg-slate-800 rounded-xl border border-slate-700 p-6 shadow-lg">
          <h2 class="text-2xl font-semibold text-slate-100 mb-4">Changelog for ${SOURCE}:${VERSION}</h2>
          <ul class="text-slate-300 list-disc list-inside space-y-2">
            ${CHANGELOG_FULL//│ • /<li>}
          </ul>
        </div>
      </div>

      <!-- Search and Stats -->
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

      <!-- Loading spinner -->
      <div id="loader" class="flex justify-center my-12">
        <div class="w-12 h-12 border-4 border-primary-200/30 border-t-primary-500 rounded-full animate-spin-slow"></div>
      </div>

      <!-- Firmware list -->
      <div id="firmware-list" class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 opacity-0 animate-fade-in-up" style="animation-delay: 600ms;"></div>
    </div>

    <!-- Footer -->
    <div class="mt-16 text-center text-slate-500 text-sm">
      <p>RTA-WRT Firmware Portal © <span id="current-year"></span></p>
    </div>
  </div>

  <script>
    const firmwareDataRaw = \`
$FIRMWARE_JS_ESCAPED
    \`;

    // Parse firmware data
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
    
    // Set current year in footer
    currentYear.textContent = new Date().getFullYear().toString();
    
    // Set last updated date
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
        
        // Show container when empty
        container.style.opacity = "1";
        return;
      }
      
      // Update count display
      countDisplay.textContent = \`Showing \${data.length} firmware \${data.length === 1 ? 'image' : 'images'}\`;
      
      // Show container when loaded
      container.style.opacity = "1";
      
      data.forEach((item, index) => {
        const card = document.createElement("div");
        card.className = "card-gradient-top bg-slate-800 rounded-xl border border-slate-700 p-6 shadow-lg transition-all duration-300 hover:transform hover:-translate-y-1 hover:shadow-xl hover:bg-slate-700/80 hover:shadow-glow";
        
        // Apply a nice staggered animation delay when filtering
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
      
      // Add download tracking
      document.querySelectorAll('[data-id]').forEach(button => {
        button.addEventListener('click', function() {
          console.log("Download started:", this.dataset.id);
          // You can add analytics tracking here
        });
      });
    }

    // Debounce function for search
    function debounce(func, wait) {
      let timeout;
      return function(...args) {
        clearTimeout(timeout);
        timeout = setTimeout(() => func.apply(this, args), wait);
      };
    }

    // Add event listener with debounce
    searchInput.addEventListener("input", debounce(() => {
      const keyword = searchInput.value.toLowerCase();
      const filtered = firmwareData.filter(item => 
        item.name.toLowerCase().includes(keyword)
      );
      renderFirmwareList(filtered, true);
    }, 300));

    // Initial render with delay for smooth animation
    setTimeout(() => {
      // Hide loader
      loader.style.display = "none";
      
      // Show firmware list with animation
      container.parentElement.querySelectorAll('.max-w-3xl').forEach(el => {
        el.style.opacity = "1";
      });
      renderFirmwareList(firmwareData, true);
    }, 800);
    
    // Make search input focused after load
    setTimeout(() => {
      searchInput.focus();
    }, 1000);
  </script>
</body>
</html>
EOF

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print banner
echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║                                                    ║${NC}"
echo -e "${BLUE}║  ${YELLOW}RTA-WRT FIRMWARE NOTIFICATION SYSTEM${BLUE}             ║${NC}"
echo -e "${BLUE}║  ${YELLOW}SISTEM NOTIFIKASI FIRMWARE RTA-WRT${BLUE}               ║${NC}"
echo -e "${BLUE}║                                                    ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"

# Check if required variables exist
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
  echo -e "${RED}[ERROR] Missing required environment variables${NC}"
  echo -e "${RED}[KESALAHAN] Variabel lingkungan yang diperlukan tidak ditemukan${NC}"
  echo -e "${YELLOW}Please set BOT_TOKEN and CHAT_ID${NC}"
  echo -e "${YELLOW}Harap tetapkan BOT_TOKEN dan CHAT_ID${NC}"
  exit 1
fi

# Function to send files to Telegram
send_file_to_telegram() {
  local file=$1
  local en_caption=$2
  local id_caption=$3
  
  echo -e "${YELLOW}[INFO] Sending ${file} to Telegram...${NC}"
  echo -e "${YELLOW}[INFO] Mengirim ${file} ke Telegram...${NC}"
  
  # Prepare bilingual caption - use literal newlines instead of \n
  local caption="🌟 *RTA-WRT FIRMWARE UPDATE* 🌟

🇬🇧 *ENGLISH*
${en_caption}

🇮🇩 *BAHASA INDONESIA*
${id_caption}"
  
  # Send document with caption
  response=$(curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
    -F "chat_id=${CHAT_ID}" \
    -F "document=@${file}" \
    -F "caption=${caption}" \
    -F "parse_mode=Markdown" \
    -F "reply_to_message_id=${message_id}")
  
  # Check if the request was successful
  if [[ $response == *"\"ok\":true"* ]]; then
    echo -e "${GREEN}[SUCCESS] File ${file} sent successfully${NC}"
    echo -e "${GREEN}[BERHASIL] File ${file} berhasil dikirim${NC}"
  else
    echo -e "${RED}[ERROR] Failed to send file ${file}${NC}"
    echo -e "${RED}[KESALAHAN] Gagal mengirim file ${file}${NC}"
    echo -e "${RED}Response: ${response}${NC}"
    return 1
  fi
  
  return 0
}

# Function to notify channel about firmware
notify_firmware_update() {
  local file=$1
  local version=$2
  local date=$(date +"%Y-%m-%d")
  
  # English caption - use actual newlines instead of \n escape sequences
  local en_caption="📄 New firmware version *${version}* (${date})
• Click the document to view complete changelog
• Download links included in the HTML file
• Please report any issues on GitHub"
  
  # Indonesian caption - use actual newlines instead of \n escape sequences
  local id_caption="📄 Versi firmware baru *${version}* (${date})
• Klik dokumen untuk melihat changelog lengkap
• Link download tersedia dalam file HTML
• Harap laporkan masalah di GitHub"
  
  # Send the file with captions
  if send_file_to_telegram "$file" "$en_caption" "$id_caption"; then
    echo -e "${GREEN}[SUCCESS] Firmware update notification sent${NC}"
    echo -e "${GREEN}[BERHASIL] Notifikasi pembaruan firmware terkirim${NC}"
  else
    echo -e "${RED}[ERROR] Failed to send firmware update notification${NC}"
    echo -e "${RED}[KESALAHAN] Gagal mengirim notifikasi pembaruan firmware${NC}"
    return 1
  fi
  
  return 0
}

# Main process
echo -e "${BLUE}[PROCESS] Starting firmware notification process...${NC}"
echo -e "${BLUE}[PROSES] Memulai proses notifikasi firmware...${NC}"

# Get firmware version from file (example)
version=$(grep -oP 'Version: \K[0-9.]+' firmware.html 2>/dev/null || echo "Latest")

# Send firmware update notification
if notify_firmware_update "firmware.html" "$version"; then
  # Send additional info if needed
  echo -e "\n${GREEN}✅ All notifications sent successfully!${NC}"
  echo -e "${GREEN}✅ Semua notifikasi berhasil dikirim!${NC}\n"
else
  echo -e "\n${RED}❌ Error occurred during notification process${NC}"
  echo -e "${RED}❌ Terjadi kesalahan selama proses notifikasi${NC}\n"
  exit 1
fi


echo "✅ Telegram message + HTML preview + data file sent!"