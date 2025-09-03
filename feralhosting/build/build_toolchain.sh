#!/bin/bash
#
# Toolchain Builder Script
# 
# This script builds a complete development toolchain from source code, including:
# - GNU toolchain (GCC, Binutils, Glibc)
# - Build tools (Make, Autotools, pkg-config) 
# - Essential libraries (zlib, SQLite, OpenSSL, ncurses, readline)
#
# Usage:
#   LOCAL_PREFIX=/path/to/install ./build_toolchain.sh
#
# Environment Variables:
#   LOCAL_PREFIX - Installation directory (default: $HOME/local)
#
# The script automatically:
# - Detects latest versions (with fallbacks)
# - Downloads sources to ./downloads/
# - Creates build logs in ./logs/
# - Handles build failures gracefully
# - Updates ~/.profile with environment variables
#

# Check for help flags
if [[ "$1" == "-h" || "$1" == "--help" ]]; then
    echo "Toolchain Builder Script"
    echo ""
    echo "Builds a complete development toolchain from source code."
    echo ""
    echo "Usage:"
    echo "  LOCAL_PREFIX=/path/to/install $0"
    echo "  $0  # Uses default prefix: \$HOME/local"
    echo ""
    echo "Environment Variables:"
    echo "  LOCAL_PREFIX - Installation directory (default: \$HOME/local)"
    echo ""
    echo "Components built:"
    echo "  - GNU toolchain: GCC, Binutils, Glibc"
    echo "  - Build tools: Make, Autotools, pkg-config"
    echo "  - Libraries: zlib, SQLite, OpenSSL, ncurses, readline"
    echo ""
    echo "The script will:"
    echo "  - Download sources to ./downloads/"
    echo "  - Create build logs in ./logs/"
    echo "  - Skip already installed components"
    echo "  - Update ~/.profile with environment variables"
    echo ""
    exit 0
fi

# Set installation prefix (can be overridden by user)
LOCAL_PREFIX="${LOCAL_PREFIX:-$HOME/local}"

FAILED_ITEMS=()

# Get script directory and create log folder
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGS_DIR="$SCRIPT_DIR/logs"

# Create logs directory if it doesn't exist
mkdir -p "$LOGS_DIR" || { echo "❌ Cannot create logs directory: $LOGS_DIR"; exit 1; }

# Create log file with timestamp
LOG_FILE="$LOGS_DIR/toolchain_build_$(date +%Y%m%d_%H%M%S).log"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Error handling function
handle_error() {
    local component="$1"
    local operation="$2"
    log "❌ FAILED: $operation for $component"
    FAILED_ITEMS+=("$component ($operation)")
    return 1
}

# TUI Progress Display System
TUI_ENABLED=true
STATUS_FILE="$LOGS_DIR/.status"

# Initialize TUI system
init_tui() {
    if [[ "$TUI_ENABLED" == "true" ]] && command -v tput >/dev/null 2>&1; then
        # Save terminal settings
        exec 3>&1 4>&2
        # Clear screen and hide cursor
        tput clear
        tput civis
        echo "" > "$STATUS_FILE"
        
        # Set up trap to restore terminal on exit
        trap 'cleanup_tui' EXIT INT TERM
    else
        TUI_ENABLED=false
    fi
}

# Cleanup TUI on exit
cleanup_tui() {
    if [[ "$TUI_ENABLED" == "true" ]]; then
        tput cnorm  # Show cursor
        tput sgr0   # Reset colors
        exec 1>&3 2>&4  # Restore stdout/stderr
    fi
}

# Cancel all background jobs
cancel_all_jobs() {
    log "🛑 Cancellation requested - killing all background jobs..."
    
    # Kill download jobs
    for pid in "${DOWNLOAD_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    # Kill extract jobs  
    for pid in "${EXTRACT_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    # Kill build jobs
    for pid in "${BUILD_PIDS[@]}"; do
        kill -TERM "$pid" 2>/dev/null || true
    done
    
    # Wait a moment for graceful termination
    sleep 2
    
    # Force kill any remaining jobs
    for pid in "${DOWNLOAD_PIDS[@]}" "${EXTRACT_PIDS[@]}" "${BUILD_PIDS[@]}"; do
        kill -KILL "$pid" 2>/dev/null || true
    done
    
    log "❌ Build cancelled by user"
    cleanup_tui
    exit 130  # Standard exit code for Ctrl+C
}

# Set up signal handlers
trap 'cancel_all_jobs' INT TERM

# Update component status in TUI
update_status() {
    local component="$1"
    local status="$2"
    local extra="${3:-}"
    
    # Update status file
    grep -v "^$component:" "$STATUS_FILE" > "$STATUS_FILE.tmp" 2>/dev/null || true
    echo "$component:$status:$extra" >> "$STATUS_FILE.tmp"
    mv "$STATUS_FILE.tmp" "$STATUS_FILE"
    
    # Don't refresh immediately to avoid flickering - let the main loops handle it
}

# Refresh the TUI display
refresh_tui() {
    if [[ "$TUI_ENABLED" != "true" ]]; then
        return
    fi
    
    # Move to top and clear from cursor down (less flickering than full clear)
    tput cup 0 0
    tput ed
    
    # Header
    echo "┌────────────────────────────────────────────────────────────────────────────────┐"
    echo "│                        🔨 TOOLCHAIN BUILD PROGRESS                            │"
    echo "├────────────────────────────────────────────────────────────────────────────────┤"
    printf "│ Build Started: %-30s Log: %-25s │\n" "$(date)" "$(basename "$LOG_FILE")"
    printf "│ Install Path:  %-63s │\n" "$LOCAL_PREFIX"
    echo "├────────────────────────────────────────────────────────────────────────────────┤"
    
    # Current phase indicator
    local current_phase="INITIALIZING"
    
    # Check what phase we're in based on status file and jobs
    if [[ -f "$STATUS_FILE" ]]; then
        if grep -q ":detecting_version" "$STATUS_FILE" 2>/dev/null; then
            current_phase="DETECTING VERSIONS"
        elif [[ -f "$DOWNLOADS_DIR/.download_results" ]] && ! jobs -r | grep -q .; then
            if [[ -f "$DOWNLOADS_DIR/.build_results" ]]; then
                current_phase="BUILDING"
            else
                current_phase="EXTRACTING"
            fi
        elif jobs -r | grep -q .; then
            if [[ -f "$DOWNLOADS_DIR/.download_results" ]]; then
                if grep -q ":downloading" "$STATUS_FILE" 2>/dev/null; then
                    current_phase="DOWNLOADING"
                elif grep -q ":extracting" "$STATUS_FILE" 2>/dev/null; then
                    current_phase="EXTRACTING"
                elif grep -q ":building" "$STATUS_FILE" 2>/dev/null; then
                    current_phase="BUILDING"
                fi
            fi
        fi
    fi
    
    printf "│ Current Phase: %-64s │\n" "$current_phase"
    echo "├────────────────────────────────────────────────────────────────────────────────┤"
    
    # Component status display
    local components=(
        "binutils" "gcc" "glibc" "make" "autoconf" "automake" "libtool" 
        "pkg-config" "zlib" "sqlite" "openssl" "ncurses" "readline"
    )
    
    for comp in "${components[@]}"; do
        local status_line=""
        local icon="⏸️"
        local color=""
        
        if [[ -f "$STATUS_FILE" ]]; then
            local status_info=$(grep "^$comp:" "$STATUS_FILE" 2>/dev/null || echo "$comp:pending:")
            local status=$(echo "$status_info" | cut -d: -f2)
            local extra=$(echo "$status_info" | cut -d: -f3-)
            
            case "$status" in
                "detecting_version") icon="🔍"; color="$(tput setaf 5)" ;;  # Magenta
                "version_detected") icon="📋"; color="$(tput setaf 4)" ;;  # Blue
                "version_failed") icon="⚠️"; color="$(tput setaf 3)" ;;  # Yellow
                "downloading") icon="📥"; color="$(tput setaf 3)" ;;  # Yellow
                "download_done") icon="✅"; color="$(tput setaf 2)" ;;  # Green
                "download_failed") icon="❌"; color="$(tput setaf 1)" ;;  # Red
                "extracting") icon="📦"; color="$(tput setaf 3)" ;;  # Yellow
                "extract_done") icon="✅"; color="$(tput setaf 2)" ;;  # Green
                "extract_failed") icon="❌"; color="$(tput setaf 1)" ;;  # Red
                "building") icon="🔨"; color="$(tput setaf 6)" ;;  # Cyan
                "build_done") icon="✅"; color="$(tput setaf 2)" ;;  # Green
                "build_failed") icon="❌"; color="$(tput setaf 1)" ;;  # Red
                "skipped") icon="⏭️"; color="$(tput setaf 8)" ;;  # Gray
                "pending") icon="⏸️"; color="$(tput setaf 8)" ;;  # Gray
            esac
            
            if [[ -n "$extra" ]]; then
                status_line="$status ($extra)"
            else
                status_line="$status"
            fi
        fi
        
        printf "│ %s %s%-12s%s %-55s │\n" "$icon" "$color" "$comp" "$(tput sgr0)" "$status_line"
    done
    
    echo "├────────────────────────────────────────────────────────────────────────────────┤"
    
    # Summary stats
    local total=13
    local completed=0
    local failed=0
    local in_progress=0
    
    if [[ -f "$STATUS_FILE" ]]; then
        completed=$(grep -c ":build_done:\|:skipped:" "$STATUS_FILE" 2>/dev/null || echo 0)
        failed=$(grep -c ":.*_failed:" "$STATUS_FILE" 2>/dev/null || echo 0)
        in_progress=$(grep -c ":downloading:\|:extracting:\|:building:" "$STATUS_FILE" 2>/dev/null || echo 0)
    fi
    
    local progress_percent=$((completed * 100 / total))
    printf "│ Progress: %3d%% (%d/%d complete, %d failed, %d in progress)%-17s │\n" \
           "$progress_percent" "$completed" "$total" "$failed" "$in_progress" ""
    
    # Progress bar
    local bar_width=70
    local filled_width=$((progress_percent * bar_width / 100))
    local bar="["
    for ((i=0; i<filled_width; i++)); do bar+="█"; done
    for ((i=filled_width; i<bar_width; i++)); do bar+="░"; done
    bar+="]"
    printf "│ %s │\n" "$bar"
    
    echo "└────────────────────────────────────────────────────────────────────────────────┘"
    
    # Instructions
    echo ""
    echo "💡 Detailed logs: $LOGS_DIR/"
    echo "📋 Press Ctrl+C to cancel build"
    echo ""
}

DOWNLOADS_DIR="$SCRIPT_DIR/downloads"

# Create downloads directory if it doesn't exist
mkdir -p "$DOWNLOADS_DIR" || { log "❌ Cannot create downloads directory: $DOWNLOADS_DIR"; exit 1; }
cd "$DOWNLOADS_DIR" || { log "❌ Cannot access downloads directory: $DOWNLOADS_DIR"; exit 1; }

# GNU mirrors
GNU_MIRROR="https://ftp.gnu.org/gnu"
KERNEL_MIRROR="https://www.kernel.org/pub"

# Version cache to avoid repeated API calls
declare -A VERSION_CACHE

log "=== Starting toolchain build ==="
log "Log file: $LOG_FILE"

# Initialize TUI progress display
init_tui

# Function to get latest version from GNU FTP
get_gnu_latest_version() {
    local package=$1
    local pattern=${2:-""}
    local cache_key="gnu_${package}"
    
    if [[ -n "${VERSION_CACHE[$cache_key]:-}" ]]; then
        echo "${VERSION_CACHE[$cache_key]}"
        return 0
    fi
    
    # Update TUI status
    update_status "$package" "detecting_version"
    log "🔍 Fetching latest version for $package..." >&2
    
    local url="$GNU_MIRROR/$package/"
    local version
    
    # Try to get directory listing and extract latest version
    # For GCC, look for directories; for others, look for tar files
    local pattern
    if [[ "$package" == "gcc" ]]; then
        pattern="${package}-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=/)"
    else
        pattern="${package}-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.tar)"
    fi
    
    if version=$(curl -s "$url" | grep -oP "$pattern" | sort -V | tail -1); then
        if [[ -n "$version" ]]; then
            VERSION_CACHE[$cache_key]="$version"
            update_status "$package" "version_detected" "$version"
            log "✓ Found $package version: $version" >&2
            echo "$version"
            return 0
        fi
    fi
    
    update_status "$package" "version_failed" "using fallback"
    handle_error "$package" "version detection" >&2
    return 1
}

# Function to get latest version from kernel.org
get_kernel_latest_version() {
    local path=$1
    local pattern=$2
    local cache_key="kernel_${path//\//_}"
    
    if [[ -n "${VERSION_CACHE[$cache_key]:-}" ]]; then
        echo "${VERSION_CACHE[$cache_key]}"
        return 0
    fi
    
    log "🔍 Fetching latest version from kernel.org/$path..." >&2
    
    local url="$KERNEL_MIRROR/$path/"
    local version
    
    if version=$(curl -s "$url" | grep -oP "$pattern" | sort -V | tail -1); then
        if [[ -n "$version" ]]; then
            VERSION_CACHE[$cache_key]="$version"
            log "✓ Found version: $version" >&2
            echo "$version"
            return 0
        fi
    fi
    
    handle_error "$path" "version detection" >&2
    return 1
}

# Function to get latest version from generic URL
get_latest_version() {
    local name=$1
    local base_url=$2
    local pattern=$3
    local cache_key="generic_${name}"
    
    if [[ -n "${VERSION_CACHE[$cache_key]:-}" ]]; then
        echo "${VERSION_CACHE[$cache_key]}"
        return 0
    fi
    
    update_status "$name" "detecting_version"
    log "🔍 Fetching latest version for $name..." >&2
    
    local version
    if version=$(curl -s "$base_url" | grep -oP "$pattern" | sort -V | tail -1); then
        if [[ -n "$version" ]]; then
            VERSION_CACHE[$cache_key]="$version"
            update_status "$name" "version_detected" "$version"
            log "✓ Found $name version: $version" >&2
            echo "$version"
            return 0
        fi
    fi
    
    update_status "$name" "version_failed" "using fallback"
    handle_error "$name" "version detection" >&2
    return 1
}

# Function to get SQLite latest version (special case)
get_sqlite_latest_version() {
    local cache_key="sqlite"
    
    if [[ -n "${VERSION_CACHE[$cache_key]:-}" ]]; then
        echo "${VERSION_CACHE[$cache_key]}"
        return 0
    fi
    
    update_status "sqlite" "detecting_version"
    log "🔍 Fetching latest SQLite version..." >&2
    
    # SQLite uses a special naming convention
    local version_info
    if version_info=$(curl -s "https://www.sqlite.org/download.html" | grep -oP 'sqlite-autoconf-\K[0-9]+(?=\.tar\.gz)' | head -1); then
        if [[ -n "$version_info" ]]; then
            VERSION_CACHE[$cache_key]="$version_info"
            update_status "sqlite" "version_detected" "$version_info"
            log "✓ Found SQLite version: $version_info" >&2
            echo "$version_info"
            return 0
        fi
    fi
    
    update_status "sqlite" "version_failed" "using fallback"
    handle_error "SQLite" "version detection" >&2
    return 1
}

# Function to check if package is already installed
check_installed() {
    local package=$1
    local check_command=$2

    if eval "$check_command" &>/dev/null; then
        log "✓ $package already installed, skipping..."
        return 0
    else
        log "✗ $package not found, will build..."
        return 1
    fi
}

# Function to download with retry logic
download_if_missing() {
    local url=$1
    local filename=$(basename "$url")
    local max_retries=3
    local retry_delay=5

    if [[ -f "$filename" ]]; then
        log "✓ $filename already downloaded"
        return 0
    fi

    log "📥 Downloading $filename..."
    
    for ((i=1; i<=max_retries; i++)); do
        if wget -c -t 3 -T 30 "$url"; then
            log "✓ Successfully downloaded $filename"
            return 0
        else
            if [[ $i -lt $max_retries ]]; then
                log "⚠️  Download attempt $i failed, retrying in ${retry_delay}s..."
                sleep $retry_delay
                retry_delay=$((retry_delay * 2))  # Exponential backoff
            else
                handle_error "$filename" "download"
                return 1
            fi
        fi
    done
}

# Safe extraction function
safe_extract() {
    local filename=$1
    local expected_dir=$2
    
    if [[ -d "$expected_dir" ]]; then
        log "✓ $expected_dir already extracted"
        return 0
    fi
    
    if [[ ! -f "$filename" ]]; then
        log "❌ File $filename not found, skipping extraction"
        return 1
    fi
    
    log "📦 Extracting $filename..."
    if tar -xf "$filename"; then
        log "✓ Successfully extracted $filename"
        return 0
    else
        handle_error "$filename" "extraction"
        return 1
    fi
}

# Build function with error handling
safe_build() {
    local component=$1
    local build_dir=$2
    local configure_args=$3
    local make_target=${4:-""}
    
    log "🔨 Building $component..."
    
    if [[ ! -d "$build_dir" ]]; then
        if ! mkdir -p "$build_dir"; then
            handle_error "$component" "creating build directory"
            return 1
        fi
    fi
    
    cd "$build_dir" || {
        handle_error "$component" "entering build directory"
        return 1
    }
    
    # Configure step
    if ! eval "$configure_args"; then
        handle_error "$component" "configure"
        cd "$DOWNLOADS_DIR"
        return 1
    fi
    
    # Make step
    if ! make -j$(nproc); then
        handle_error "$component" "compile"
        cd "$DOWNLOADS_DIR"
        return 1
    fi
    
    # Install step
    local install_cmd="make install"
    if [[ -n "$make_target" ]]; then
        install_cmd="make $make_target"
    fi
    
    if ! eval "$install_cmd"; then
        handle_error "$component" "install"
        cd "$DOWNLOADS_DIR"
        return 1
    fi
    
    cd "$DOWNLOADS_DIR"
    log "✓ Successfully built and installed $component"
    return 0
}

log "=== Detecting Latest Versions ==="
refresh_tui  # Show initial TUI with "DETECTING VERSIONS" phase

# Fallback versions in case detection fails
declare -A FALLBACK_VERSIONS=(
    ["binutils"]="2.41"
    ["gcc"]="13.2.0"
    ["glibc"]="2.38"
    ["make"]="4.4.1"
    ["autoconf"]="2.71"
    ["automake"]="1.16.5"
    ["libtool"]="2.4.7"
    ["ncurses"]="6.4"
    ["readline"]="8.2"
    ["pkg-config"]="0.29.2"
    ["zlib"]="1.3"
    ["sqlite"]="3440200"
    ["openssl"]="3.1.4"
)


# Detect versions for all components with fallbacks
# Start version detection with TUI updates
start_version_detection() {
    log "🔍 Starting version detection for all components..."
    
    # GNU components
    BINUTILS_VER=$(get_gnu_latest_version "binutils" || echo "${FALLBACK_VERSIONS[binutils]}")
    [[ "$BINUTILS_VER" == "${FALLBACK_VERSIONS[binutils]}" ]] && update_status "binutils" "version_failed" "using fallback $BINUTILS_VER"
    sleep 0.5; refresh_tui
    
    GCC_VER=$(get_gnu_latest_version "gcc" || echo "${FALLBACK_VERSIONS[gcc]}")
    [[ "$GCC_VER" == "${FALLBACK_VERSIONS[gcc]}" ]] && update_status "gcc" "version_failed" "using fallback $GCC_VER"
    sleep 0.5; refresh_tui
    
    GLIBC_VER=$(get_gnu_latest_version "glibc" || echo "${FALLBACK_VERSIONS[glibc]}")
    [[ "$GLIBC_VER" == "${FALLBACK_VERSIONS[glibc]}" ]] && update_status "glibc" "version_failed" "using fallback $GLIBC_VER"
    sleep 0.5; refresh_tui
    
    MAKE_VER=$(get_gnu_latest_version "make" || echo "${FALLBACK_VERSIONS[make]}")
    [[ "$MAKE_VER" == "${FALLBACK_VERSIONS[make]}" ]] && update_status "make" "version_failed" "using fallback $MAKE_VER"
    sleep 0.5; refresh_tui
    
    AUTOCONF_VER=$(get_gnu_latest_version "autoconf" || echo "${FALLBACK_VERSIONS[autoconf]}")
    [[ "$AUTOCONF_VER" == "${FALLBACK_VERSIONS[autoconf]}" ]] && update_status "autoconf" "version_failed" "using fallback $AUTOCONF_VER"
    sleep 0.5; refresh_tui
    
    AUTOMAKE_VER=$(get_gnu_latest_version "automake" || echo "${FALLBACK_VERSIONS[automake]}")
    [[ "$AUTOMAKE_VER" == "${FALLBACK_VERSIONS[automake]}" ]] && update_status "automake" "version_failed" "using fallback $AUTOMAKE_VER"
    sleep 0.5; refresh_tui
    
    LIBTOOL_VER=$(get_gnu_latest_version "libtool" || echo "${FALLBACK_VERSIONS[libtool]}")
    [[ "$LIBTOOL_VER" == "${FALLBACK_VERSIONS[libtool]}" ]] && update_status "libtool" "version_failed" "using fallback $LIBTOOL_VER"
    sleep 0.5; refresh_tui
    
    NCURSES_VER=$(get_gnu_latest_version "ncurses" || echo "${FALLBACK_VERSIONS[ncurses]}")
    [[ "$NCURSES_VER" == "${FALLBACK_VERSIONS[ncurses]}" ]] && update_status "ncurses" "version_failed" "using fallback $NCURSES_VER"
    sleep 0.5; refresh_tui
    
    READLINE_VER=$(get_gnu_latest_version "readline" || echo "${FALLBACK_VERSIONS[readline]}")
    [[ "$READLINE_VER" == "${FALLBACK_VERSIONS[readline]}" ]] && update_status "readline" "version_failed" "using fallback $READLINE_VER"
    sleep 0.5; refresh_tui
    
    # Special version detections
    PKGCONFIG_VER=$(get_latest_version "pkg-config" "https://pkgconfig.freedesktop.org/releases/" "pkg-config-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.tar)" || echo "${FALLBACK_VERSIONS[pkg-config]}")
    [[ "$PKGCONFIG_VER" == "${FALLBACK_VERSIONS[pkg-config]}" ]] && update_status "pkg-config" "version_failed" "using fallback $PKGCONFIG_VER"
    sleep 0.5; refresh_tui
    
    ZLIB_VER=$(get_latest_version "zlib" "https://zlib.net/" "zlib-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.tar)" || echo "${FALLBACK_VERSIONS[zlib]}")
    [[ "$ZLIB_VER" == "${FALLBACK_VERSIONS[zlib]}" ]] && update_status "zlib" "version_failed" "using fallback $ZLIB_VER"
    sleep 0.5; refresh_tui
    
    SQLITE_VER=$(get_sqlite_latest_version || echo "${FALLBACK_VERSIONS[sqlite]}")
    [[ "$SQLITE_VER" == "${FALLBACK_VERSIONS[sqlite]}" ]] && update_status "sqlite" "version_failed" "using fallback $SQLITE_VER"
    sleep 0.5; refresh_tui
    
    # OpenSSL - use fallback due to GitHub API rate limits
    OPENSSL_VER="${FALLBACK_VERSIONS[openssl]}"
    update_status "openssl" "version_failed" "GitHub API rate limited, using fallback $OPENSSL_VER"
    log "⚠️  Using fallback OpenSSL version: $OPENSSL_VER (GitHub API rate limited)"
    refresh_tui
    
    log "✅ Version detection complete"
    sleep 1
}

# Run version detection with TUI
start_version_detection

# Create detailed versions manifest
VERSIONS_LOG="$LOGS_DIR/versions_manifest.log"
{
    echo "=== TOOLCHAIN BUILD VERSIONS MANIFEST ==="
    echo "Generated: $(date)"
    echo "Installation Prefix: $LOCAL_PREFIX"
    echo "Build Host: $(uname -a)"
    echo ""
    echo "=== DETECTED VERSIONS ==="
    echo "Binutils: $BINUTILS_VER"
    echo "GCC: $GCC_VER"
    echo "Glibc: $GLIBC_VER"
    echo "Make: $MAKE_VER"
    echo "Autoconf: $AUTOCONF_VER"
    echo "Automake: $AUTOMAKE_VER"
    echo "Libtool: $LIBTOOL_VER"
    echo "pkg-config: $PKGCONFIG_VER"
    echo "zlib: $ZLIB_VER"
    echo "SQLite: $SQLITE_VER"
    echo "OpenSSL: $OPENSSL_VER"
    echo "ncurses: $NCURSES_VER"
    echo "readline: $READLINE_VER"
    echo ""
    echo "=== FALLBACK VERSIONS (used if detection failed) ==="
    for component in "${!FALLBACK_VERSIONS[@]}"; do
        echo "$component: ${FALLBACK_VERSIONS[$component]}"
    done | sort
    echo ""
    echo "=== DOWNLOAD URLS ==="
    echo "Binutils: $GNU_MIRROR/binutils/binutils-${BINUTILS_VER}.tar.xz"
    echo "GCC: $GNU_MIRROR/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz"
    echo "Glibc: $GNU_MIRROR/glibc/glibc-${GLIBC_VER}.tar.xz"
    echo "Make: $GNU_MIRROR/make/make-${MAKE_VER}.tar.gz"
    echo "Autoconf: $GNU_MIRROR/autoconf/autoconf-${AUTOCONF_VER}.tar.xz"
    echo "Automake: $GNU_MIRROR/automake/automake-${AUTOMAKE_VER}.tar.xz"
    echo "Libtool: $GNU_MIRROR/libtool/libtool-${LIBTOOL_VER}.tar.xz"
    echo "pkg-config: https://pkgconfig.freedesktop.org/releases/pkg-config-${PKGCONFIG_VER}.tar.gz"
    echo "zlib: https://zlib.net/zlib-${ZLIB_VER}.tar.gz"
    echo "SQLite: https://www.sqlite.org/$(date +%Y)/sqlite-autoconf-${SQLITE_VER}.tar.gz"
    echo "OpenSSL: https://github.com/openssl/openssl/archive/refs/tags/openssl-${OPENSSL_VER}.tar.gz"
    echo "ncurses: $GNU_MIRROR/ncurses/ncurses-${NCURSES_VER}.tar.gz"
    echo "readline: $GNU_MIRROR/readline/readline-${READLINE_VER}.tar.gz"
    echo ""
    echo "=== BUILD CONFIGURATION ==="
    echo "Parallel Downloads: Yes"
    echo "Parallel Extractions: Yes"
    echo "Dependency-Aware Builds: Yes"
    echo "Max Parallel Jobs (make): $(nproc)"
    echo ""
} > "$VERSIONS_LOG"

# Log which versions we'll be using (to main log and console)
log "Detected versions (detailed manifest: $VERSIONS_LOG):"
log "  Binutils: $BINUTILS_VER"
log "  GCC: $GCC_VER"
log "  Glibc: $GLIBC_VER"
log "  Make: $MAKE_VER"
log "  Autoconf: $AUTOCONF_VER"
log "  Automake: $AUTOMAKE_VER"
log "  Libtool: $LIBTOOL_VER"
log "  pkg-config: $PKGCONFIG_VER"
log "  zlib: $ZLIB_VER"
log "  SQLite: $SQLITE_VER"
log "  OpenSSL: $OPENSSL_VER"
log "  ncurses: $NCURSES_VER"
log "  readline: $READLINE_VER"

log "=== Downloading Sources (Parallel) ==="

# Set up variables for all downloads
declare -A DOWNLOAD_JOBS
declare -A DOWNLOAD_PIDS

# Function to start a download job in background
start_download_job() {
    local name=$1
    local url=$2
    local filename=$3
    
    if [[ -f "$filename" ]]; then
        log "✓ $filename already downloaded"
        update_status "$name" "download_done" "already exists"
        return 0
    fi
    
    # Update TUI status
    update_status "$name" "downloading"
    
    # Create individual log file for this download
    local download_log="$LOGS_DIR/download_${name}.log"
    
    {
        # Redirect all output to individual log file
        exec > "$download_log" 2>&1
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting download: $name"
        echo "URL: $url"
        echo "File: $filename"
        echo "----------------------------------------"
        
        if download_if_missing "$url"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Download successful: $name"
            echo "SUCCESS:$name:$filename" >> "$DOWNLOADS_DIR/.download_results"
            update_status "$name" "download_done"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Download failed: $name"
            echo "FAILED:$name:$filename" >> "$DOWNLOADS_DIR/.download_results"
            update_status "$name" "download_failed"
        fi
    } &
    
    DOWNLOAD_PIDS[$name]=$!
    log "🔄 Started download: $name (PID: ${DOWNLOAD_PIDS[$name]}) → $download_log"
}

# Initialize results file
echo "" > "$DOWNLOADS_DIR/.download_results"

# Start all downloads in parallel
if [[ -n "$BINUTILS_VER" ]]; then
    BINUTILS_FILE="binutils-${BINUTILS_VER}.tar.xz"
    BINUTILS_DIR="binutils-${BINUTILS_VER}"
    start_download_job "binutils" "$GNU_MIRROR/binutils/$BINUTILS_FILE" "$BINUTILS_FILE"
fi

if [[ -n "$GCC_VER" ]]; then
    GCC_FILE="gcc-${GCC_VER}.tar.xz"
    GCC_DIR="gcc-${GCC_VER}"
    start_download_job "gcc" "$GNU_MIRROR/gcc/gcc-${GCC_VER}/$GCC_FILE" "$GCC_FILE"
fi

if [[ -n "$GLIBC_VER" ]]; then
    GLIBC_FILE="glibc-${GLIBC_VER}.tar.xz"
    GLIBC_DIR="glibc-${GLIBC_VER}"
    start_download_job "glibc" "$GNU_MIRROR/glibc/$GLIBC_FILE" "$GLIBC_FILE"
fi

if [[ -n "$MAKE_VER" ]]; then
    MAKE_FILE="make-${MAKE_VER}.tar.gz"
    MAKE_DIR="make-${MAKE_VER}"
    start_download_job "make" "$GNU_MIRROR/make/$MAKE_FILE" "$MAKE_FILE"
fi

if [[ -n "$AUTOCONF_VER" ]]; then
    AUTOCONF_FILE="autoconf-${AUTOCONF_VER}.tar.xz"
    AUTOCONF_DIR="autoconf-${AUTOCONF_VER}"
    start_download_job "autoconf" "$GNU_MIRROR/autoconf/$AUTOCONF_FILE" "$AUTOCONF_FILE"
fi

if [[ -n "$AUTOMAKE_VER" ]]; then
    AUTOMAKE_FILE="automake-${AUTOMAKE_VER}.tar.xz"
    AUTOMAKE_DIR="automake-${AUTOMAKE_VER}"
    start_download_job "automake" "$GNU_MIRROR/automake/$AUTOMAKE_FILE" "$AUTOMAKE_FILE"
fi

if [[ -n "$LIBTOOL_VER" ]]; then
    LIBTOOL_FILE="libtool-${LIBTOOL_VER}.tar.xz"
    LIBTOOL_DIR="libtool-${LIBTOOL_VER}"
    start_download_job "libtool" "$GNU_MIRROR/libtool/$LIBTOOL_FILE" "$LIBTOOL_FILE"
fi

if [[ -n "$PKGCONFIG_VER" ]]; then
    PKGCONFIG_FILE="pkg-config-${PKGCONFIG_VER}.tar.gz"
    PKGCONFIG_DIR="pkg-config-${PKGCONFIG_VER}"
    start_download_job "pkg-config" "https://pkgconfig.freedesktop.org/releases/$PKGCONFIG_FILE" "$PKGCONFIG_FILE"
fi

if [[ -n "$ZLIB_VER" ]]; then
    ZLIB_FILE="zlib-${ZLIB_VER}.tar.gz"
    ZLIB_DIR="zlib-${ZLIB_VER}"
    start_download_job "zlib" "https://zlib.net/$ZLIB_FILE" "$ZLIB_FILE"
fi

if [[ -n "$SQLITE_VER" ]]; then
    SQLITE_FILE="sqlite-autoconf-${SQLITE_VER}.tar.gz"
    SQLITE_DIR="sqlite-autoconf-${SQLITE_VER}"
    SQLITE_YEAR=$(date +%Y)
    start_download_job "sqlite" "https://www.sqlite.org/${SQLITE_YEAR}/$SQLITE_FILE" "$SQLITE_FILE"
fi

if [[ -n "$OPENSSL_VER" ]]; then
    OPENSSL_FILE="openssl-${OPENSSL_VER}.tar.gz"
    OPENSSL_DIR="openssl-openssl-${OPENSSL_VER}"  # GitHub archives have different directory structure
    start_download_job "openssl" "https://github.com/openssl/openssl/archive/refs/tags/openssl-${OPENSSL_VER}.tar.gz" "$OPENSSL_FILE"
fi

if [[ -n "$NCURSES_VER" ]]; then
    NCURSES_FILE="ncurses-${NCURSES_VER}.tar.gz"
    NCURSES_DIR="ncurses-${NCURSES_VER}"
    start_download_job "ncurses" "$GNU_MIRROR/ncurses/$NCURSES_FILE" "$NCURSES_FILE"
fi

if [[ -n "$READLINE_VER" ]]; then
    READLINE_FILE="readline-${READLINE_VER}.tar.gz"
    READLINE_DIR="readline-${READLINE_VER}"
    start_download_job "readline" "$GNU_MIRROR/readline/$READLINE_FILE" "$READLINE_FILE"
fi

# Wait for all downloads to complete with TUI updates
log "⏳ Waiting for downloads to complete..."
while [[ ${#DOWNLOAD_PIDS[@]} -gt 0 ]]; do
    for name in "${!DOWNLOAD_PIDS[@]}"; do
        if ! kill -0 "${DOWNLOAD_PIDS[$name]}" 2>/dev/null; then
            wait "${DOWNLOAD_PIDS[$name]}"
            unset DOWNLOAD_PIDS[$name]
            log "✅ Download completed: $name"
        fi
    done
    sleep 2
    refresh_tui
done

# Check results and handle SQLite fallback if needed
if grep -q "FAILED:sqlite:" "$DOWNLOADS_DIR/.download_results" 2>/dev/null; then
    log "🔄 SQLite download failed, trying previous year..."
    PREV_YEAR=$((SQLITE_YEAR - 1))
    if download_if_missing "https://www.sqlite.org/${PREV_YEAR}/$SQLITE_FILE"; then
        log "✅ SQLite downloaded from previous year"
    fi
fi

log "=== Extracting Archives (Parallel) ==="

# Function to extract in background
start_extract_job() {
    local name=$1
    local filename=$2
    local dirname=$3
    
    # Update TUI status
    update_status "$name" "extracting"
    
    # Create individual log file for this extraction
    local extract_log="$LOGS_DIR/extract_${name}.log"
    
    {
        # Redirect all output to individual log file
        exec > "$extract_log" 2>&1
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting extraction: $name"
        echo "File: $filename"
        echo "Directory: $dirname"
        echo "----------------------------------------"
        
        if safe_extract "$filename" "$dirname"; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Extraction successful: $name"
            echo "EXTRACT_SUCCESS:$name" >> "$DOWNLOADS_DIR/.extract_results"
            update_status "$name" "extract_done"
        else
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Extraction failed: $name"
            echo "EXTRACT_FAILED:$name" >> "$DOWNLOADS_DIR/.extract_results"
            update_status "$name" "extract_failed"
        fi
    } &
    
    EXTRACT_PIDS[$name]=$!
    log "🔄 Started extraction: $name → $extract_log"
}

# Initialize extract results
echo "" > "$DOWNLOADS_DIR/.extract_results"
declare -A EXTRACT_PIDS

# Start all extractions in parallel
[[ -f "$BINUTILS_FILE" ]] && start_extract_job "binutils" "$BINUTILS_FILE" "$BINUTILS_DIR"
[[ -f "$GCC_FILE" ]] && start_extract_job "gcc" "$GCC_FILE" "$GCC_DIR"
[[ -f "$GLIBC_FILE" ]] && start_extract_job "glibc" "$GLIBC_FILE" "$GLIBC_DIR"
[[ -f "$MAKE_FILE" ]] && start_extract_job "make" "$MAKE_FILE" "$MAKE_DIR"
[[ -f "$AUTOCONF_FILE" ]] && start_extract_job "autoconf" "$AUTOCONF_FILE" "$AUTOCONF_DIR"
[[ -f "$AUTOMAKE_FILE" ]] && start_extract_job "automake" "$AUTOMAKE_FILE" "$AUTOMAKE_DIR"
[[ -f "$LIBTOOL_FILE" ]] && start_extract_job "libtool" "$LIBTOOL_FILE" "$LIBTOOL_DIR"
[[ -f "$PKGCONFIG_FILE" ]] && start_extract_job "pkg-config" "$PKGCONFIG_FILE" "$PKGCONFIG_DIR"
[[ -f "$ZLIB_FILE" ]] && start_extract_job "zlib" "$ZLIB_FILE" "$ZLIB_DIR"
[[ -f "$SQLITE_FILE" ]] && start_extract_job "sqlite" "$SQLITE_FILE" "$SQLITE_DIR"
[[ -f "$OPENSSL_FILE" ]] && start_extract_job "openssl" "$OPENSSL_FILE" "$OPENSSL_DIR"
[[ -f "$NCURSES_FILE" ]] && start_extract_job "ncurses" "$NCURSES_FILE" "$NCURSES_DIR"
[[ -f "$READLINE_FILE" ]] && start_extract_job "readline" "$READLINE_FILE" "$READLINE_DIR"

# Wait for all extractions with TUI updates
log "⏳ Waiting for extractions to complete..."
while [[ ${#EXTRACT_PIDS[@]} -gt 0 ]]; do
    for name in "${!EXTRACT_PIDS[@]}"; do
        if ! kill -0 "${EXTRACT_PIDS[$name]}" 2>/dev/null; then
            wait "${EXTRACT_PIDS[$name]}"
            unset EXTRACT_PIDS[$name]
            log "✅ Extraction completed: $name"
        fi
    done
    sleep 2
    refresh_tui
done

# Download GCC prerequisites after GCC is extracted
if [[ -d "$GCC_DIR" ]]; then
    log "📥 Downloading GCC prerequisites..."
    cd "$GCC_DIR" && ./contrib/download_prerequisites && cd "$DOWNLOADS_DIR" || {
        handle_error "GCC prerequisites" "download"
    }
fi

log "=== Building Toolchain (Dependency-Aware Parallel) ==="

# Function to build component in background with dependency checking
start_build_job() {
    local name=$1
    local component=$2
    local build_dir=$3
    local configure_args=$4
    local check_cmd=$5
    
    # Create individual log file for this build
    local build_log="$LOGS_DIR/build_${name}.log"
    
    {
        # Redirect all output to individual log file
        exec > "$build_log" 2>&1
        
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting build: $name"
        echo "Component: $component"
        echo "Build directory: $build_dir"
        echo "Configure args: $configure_args"
        echo "Check command: $check_cmd"
        echo "----------------------------------------"
        
        if eval "$check_cmd" &>/dev/null; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ $name already installed, skipping..."
            echo "SKIPPED:$name" >> "$DOWNLOADS_DIR/.build_results"
            update_status "$name" "skipped"
        else
            # Update status to building
            update_status "$name" "building"
            
            if [[ -n "$component" && -d "$build_dir" ]]; then
                if safe_build "$name" "$build_dir" "$configure_args"; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Build successful: $name"
                    echo "SUCCESS:$name" >> "$DOWNLOADS_DIR/.build_results"
                    update_status "$name" "build_done"
                else
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Build failed: $name"
                    echo "FAILED:$name" >> "$DOWNLOADS_DIR/.build_results"
                    update_status "$name" "build_failed"
                fi
            else
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] ❌ Missing source directory: $name"
                echo "FAILED:$name:missing_source" >> "$DOWNLOADS_DIR/.build_results"
                update_status "$name" "build_failed" "missing source"
            fi
        fi
    } &
    
    BUILD_PIDS[$name]=$!
    log "🔄 Started build: $name (PID: ${BUILD_PIDS[$name]}) → $build_log"
}

# Wait for specific builds to complete
wait_for_builds() {
    local -a names=("$@")
    for name in "${names[@]}"; do
        if [[ -n "${BUILD_PIDS[$name]:-}" ]]; then
            wait "${BUILD_PIDS[$name]}"
            log "✅ Build completed: $name"
        fi
    done
}

# Initialize build tracking
echo "" > "$DOWNLOADS_DIR/.build_results"
declare -A BUILD_PIDS

# PHASE 1: Independent builds (can all run in parallel)
log "🚀 Phase 1: Independent components"

# Libraries that don't depend on the toolchain
[[ -n "$ZLIB_VER" && -d "$ZLIB_DIR" ]] && start_build_job "zlib" "$ZLIB_VER" "$ZLIB_DIR" "./configure --prefix='$LOCAL_PREFIX'" "test -f '$LOCAL_PREFIX/lib/libz.so'"

[[ -n "$SQLITE_VER" && -d "$SQLITE_DIR" ]] && start_build_job "sqlite" "$SQLITE_VER" "$SQLITE_DIR" "./configure --prefix='$LOCAL_PREFIX'" "test -f '$LOCAL_PREFIX/lib/libsqlite3.so'"

[[ -n "$NCURSES_VER" && -d "$NCURSES_DIR" ]] && start_build_job "ncurses" "$NCURSES_VER" "$NCURSES_DIR" "./configure --prefix='$LOCAL_PREFIX' --with-shared --enable-widec" "test -f '$LOCAL_PREFIX/lib/libncurses.so'"

[[ -n "$OPENSSL_VER" && -d "$OPENSSL_DIR" ]] && start_build_job "openssl" "$OPENSSL_VER" "$OPENSSL_DIR" "./config --prefix='$LOCAL_PREFIX' --openssldir='$LOCAL_PREFIX/ssl'" "test -f '$LOCAL_PREFIX/lib/libssl.so'"

[[ -n "$PKGCONFIG_VER" && -d "$PKGCONFIG_DIR" ]] && start_build_job "pkg-config" "$PKGCONFIG_VER" "$PKGCONFIG_DIR" "./configure --prefix='$LOCAL_PREFIX' --with-internal-glib" "'$LOCAL_PREFIX/bin/pkg-config' --version"

# Autotools (independent)
[[ -n "$AUTOCONF_VER" && -d "$AUTOCONF_DIR" ]] && start_build_job "autoconf" "$AUTOCONF_VER" "$AUTOCONF_DIR" "./configure --prefix='$LOCAL_PREFIX'" "'$LOCAL_PREFIX/bin/autoconf' --version"

[[ -n "$AUTOMAKE_VER" && -d "$AUTOMAKE_DIR" ]] && start_build_job "automake" "$AUTOMAKE_VER" "$AUTOMAKE_DIR" "./configure --prefix='$LOCAL_PREFIX'" "'$LOCAL_PREFIX/bin/automake' --version"

[[ -n "$LIBTOOL_VER" && -d "$LIBTOOL_DIR" ]] && start_build_job "libtool" "$LIBTOOL_VER" "$LIBTOOL_DIR" "./configure --prefix='$LOCAL_PREFIX'" "'$LOCAL_PREFIX/bin/libtool' --version"

# Binutils (needed for GCC but independent otherwise)
[[ -n "$BINUTILS_VER" && -d "$BINUTILS_DIR" ]] && start_build_job "binutils" "$BINUTILS_VER" "$BINUTILS_DIR" "./configure --prefix='$LOCAL_PREFIX' --disable-werror" "test -f '$LOCAL_PREFIX/bin/ld' && '$LOCAL_PREFIX/bin/ld' --version"

# PHASE 2: GCC Stage 1 (needs binutils)
log "⏳ Waiting for binutils to complete before GCC stage 1..."
wait_for_builds "binutils"

log "🚀 Phase 2: GCC Stage 1 (C compiler)"
[[ -n "$GCC_VER" && -d "$GCC_DIR" ]] && start_build_job "gcc-stage1" "$GCC_VER" "gcc-build-stage1" "../$GCC_DIR/configure --prefix='$LOCAL_PREFIX' --enable-languages=c --disable-multilib --disable-bootstrap --disable-libsanitizer" "test -f '$LOCAL_PREFIX/bin/gcc' && '$LOCAL_PREFIX/bin/gcc' --version"

# PHASE 3: Glibc (needs GCC stage 1)
log "⏳ Waiting for GCC stage 1 to complete before glibc..."
wait_for_builds "gcc-stage1"

log "🚀 Phase 3: Glibc (C library)"
[[ -n "$GLIBC_VER" && -d "$GLIBC_DIR" ]] && start_build_job "glibc" "$GLIBC_VER" "glibc-build" "../$GLIBC_DIR/configure --prefix='$LOCAL_PREFIX' --disable-werror --enable-shared" "test -f '$LOCAL_PREFIX/lib/libc.so'"

# PHASE 4: GCC Stage 2 and remaining tools (need glibc)
log "⏳ Waiting for glibc to complete before final phase..."
wait_for_builds "glibc"

log "🚀 Phase 4: GCC Stage 2 and remaining tools"
[[ -n "$GCC_VER" && -d "$GCC_DIR" ]] && start_build_job "gcc-stage2" "$GCC_VER" "gcc-build-stage2" "../$GCC_DIR/configure --prefix='$LOCAL_PREFIX' --enable-languages=c,c++ --disable-multilib --disable-bootstrap" "test -f '$LOCAL_PREFIX/bin/g++' && '$LOCAL_PREFIX/bin/g++' --version"

[[ -n "$MAKE_VER" && -d "$MAKE_DIR" ]] && start_build_job "make" "$MAKE_VER" "$MAKE_DIR" "./configure --prefix='$LOCAL_PREFIX'" "'$LOCAL_PREFIX/bin/make' --version"

[[ -n "$READLINE_VER" && -d "$READLINE_DIR" ]] && start_build_job "readline" "$READLINE_VER" "$READLINE_DIR" "./configure --prefix='$LOCAL_PREFIX'" "test -f '$LOCAL_PREFIX/lib/libreadline.so'"

# Wait for all remaining builds with TUI updates
log "⏳ Waiting for all builds to complete..."
while [[ ${#BUILD_PIDS[@]} -gt 0 ]]; do
    for name in "${!BUILD_PIDS[@]}"; do
        if ! kill -0 "${BUILD_PIDS[$name]}" 2>/dev/null; then
            wait "${BUILD_PIDS[$name]}"
            unset BUILD_PIDS[$name]
            log "✅ Build completed: $name"
        fi
    done
    sleep 2  # Slightly longer delay for builds
    refresh_tui
done

# Create post-build verification log
INSTALLED_LOG="$LOGS_DIR/installed_versions.log"
{
    echo "=== INSTALLED TOOLCHAIN VERSIONS ==="
    echo "Generated: $(date)"
    echo "Installation Prefix: $LOCAL_PREFIX"
    echo ""
    echo "=== INSTALLED COMPONENTS ==="
    
    # Check each component and get actual installed version
    if [[ -f "$LOCAL_PREFIX/bin/ld" ]]; then
        echo "Binutils: $("$LOCAL_PREFIX/bin/ld" --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?')"
    else
        echo "Binutils: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/bin/gcc" ]]; then
        echo "GCC: $("$LOCAL_PREFIX/bin/gcc" --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?')"
    else
        echo "GCC: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/lib/libc.so" ]]; then
        echo "Glibc: $(strings "$LOCAL_PREFIX/lib/libc.so" | grep -E '^GNU C Library.*version' | head -1 || echo "Version detection failed")"
    else
        echo "Glibc: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/bin/make" ]]; then
        echo "Make: $("$LOCAL_PREFIX/bin/make" --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?')"
    else
        echo "Make: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/bin/autoconf" ]]; then
        echo "Autoconf: $("$LOCAL_PREFIX/bin/autoconf" --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?')"
    else
        echo "Autoconf: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/bin/automake" ]]; then
        echo "Automake: $("$LOCAL_PREFIX/bin/automake" --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?')"
    else
        echo "Automake: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/bin/libtool" ]]; then
        echo "Libtool: $("$LOCAL_PREFIX/bin/libtool" --version | head -1 | grep -oP '\d+\.\d+(\.\d+)?')"
    else
        echo "Libtool: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/bin/pkg-config" ]]; then
        echo "pkg-config: $("$LOCAL_PREFIX/bin/pkg-config" --version)"
    else
        echo "pkg-config: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/lib/libz.so" ]]; then
        echo "zlib: $(strings "$LOCAL_PREFIX/lib/libz.so" | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' | head -1 || echo "Version detection failed")"
    else
        echo "zlib: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/lib/libsqlite3.so" ]]; then
        echo "SQLite: $(strings "$LOCAL_PREFIX/lib/libsqlite3.so" | grep -E '^3\.[0-9]+\.[0-9]+$' | head -1 || echo "Version detection failed")"
    else
        echo "SQLite: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/bin/openssl" ]]; then
        echo "OpenSSL: $("$LOCAL_PREFIX/bin/openssl" version | grep -oP '\d+\.\d+\.\d+')"
    else
        echo "OpenSSL: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/lib/libncurses.so" ]]; then
        echo "ncurses: $(strings "$LOCAL_PREFIX/lib/libncurses.so" | grep -E '^[0-9]+\.[0-9]+$' | head -1 || echo "Version detection failed")"
    else
        echo "ncurses: NOT INSTALLED"
    fi
    
    if [[ -f "$LOCAL_PREFIX/lib/libreadline.so" ]]; then
        echo "readline: $(strings "$LOCAL_PREFIX/lib/libreadline.so" | grep -E '^[0-9]+\.[0-9]+$' | head -1 || echo "Version detection failed")"
    else
        echo "readline: NOT INSTALLED"
    fi
    
    echo ""
    echo "=== ENVIRONMENT SETUP ==="
    echo "PATH includes: $LOCAL_PREFIX/bin"
    echo "LD_LIBRARY_PATH includes: $LOCAL_PREFIX/lib"
    echo "PKG_CONFIG_PATH includes: $LOCAL_PREFIX/lib/pkgconfig"
    echo ""
    echo "=== USAGE ==="
    echo "To use this toolchain, run:"
    echo "  source ~/.profile"
    echo "  # or start a new shell session"
    echo ""
} > "$INSTALLED_LOG"

log "📊 Build Summary:"
if [[ -f "$DOWNLOADS_DIR/.build_results" ]]; then
    while IFS=: read -r status name extra; do
        case $status in
            "SUCCESS") log "  ✅ $name" ;;
            "SKIPPED") log "  ⏭️  $name (already installed)" ;;
            "FAILED") 
                if [[ "$extra" == "missing_source" ]]; then
                    log "  ❌ $name (missing source)"
                else
                    log "  ❌ $name (build failed)"
                fi
                ;;
        esac
    done < "$DOWNLOADS_DIR/.build_results"
fi

log "📋 Detailed logs available:"
log "  📁 All logs: $LOGS_DIR/"
log "  📝 Main build log: $LOG_FILE"
log "  📊 Versions manifest: $VERSIONS_LOG"
log "  ✅ Installed versions: $INSTALLED_LOG"
log "  📥 Individual download logs: $LOGS_DIR/download_*.log"
log "  📦 Individual extraction logs: $LOGS_DIR/extract_*.log"
log "  🔨 Individual build logs: $LOGS_DIR/build_*.log"

# Final TUI refresh to show completed state
refresh_tui

# Wait a moment for user to see final state before restoring terminal
if [[ "$TUI_ENABLED" == "true" ]]; then
    echo ""
    echo "🎉 Build process complete! Press Enter to continue..."
    read -r
fi

# Function to update .profile with toolchain environment variables
update_profile() {
    local profile_file="$HOME/.profile"
    local marker_start="# --- Custom Toolchain Environment (AUTO-GENERATED) ---"
    local marker_end="# --- End Custom Toolchain Environment ---"

    # Create .profile if it doesn't exist
    if [[ ! -f "$profile_file" ]]; then
        echo "Creating .profile..."
        cat > "$profile_file" << 'EOF'
# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.

# if running bash
if [ -n "$BASH_VERSION" ]; then
    # include .bashrc if it exists
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/bin" ] ; then
    PATH="$HOME/bin:$PATH"
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi
EOF
    fi

    # Read current .profile content
    local profile_content
    profile_content=$(cat "$profile_file")

    # Remove existing toolchain section if it exists
    if echo "$profile_content" | grep -q "$marker_start"; then
        echo "Updating existing toolchain environment in .profile..."
        # Remove the old section
        profile_content=$(echo "$profile_content" | sed "/$marker_start/,/$marker_end/d")
    else
        echo "Adding toolchain environment to .profile..."
    fi

    # Write updated content with new toolchain environment
    cat > "$profile_file" << EOF
$profile_content

$marker_start
# Custom toolchain built from source
export LOCAL_PREFIX="$LOCAL_PREFIX"
export PATH="$LOCAL_PREFIX/bin:\$PATH"
export LD_LIBRARY_PATH="$LOCAL_PREFIX/lib:\$LD_LIBRARY_PATH"
export PKG_CONFIG_PATH="$LOCAL_PREFIX/lib/pkgconfig:\$PKG_CONFIG_PATH"
export CPPFLAGS="-I$LOCAL_PREFIX/include \$CPPFLAGS"
export LDFLAGS="-L$LOCAL_PREFIX/lib \$LDFLAGS"
export MANPATH="$LOCAL_PREFIX/share/man:\$MANPATH"
$marker_end
EOF

    log "✓ Updated .profile with toolchain environment variables"
    log "✓ Run 'source ~/.profile' or start a new shell to use the new toolchain"
}

# Final summary function
print_summary() {
    log "=== Build Summary ==="
    log "Installation directory: $LOCAL_PREFIX"
    log "Log file: $LOG_FILE"
    
    if [[ ${#FAILED_ITEMS[@]} -eq 0 ]]; then
        log "🎉 All components built successfully!"
    else
        log "⚠️  Some components failed to build:"
        for item in "${FAILED_ITEMS[@]}"; do
            log "   - $item"
        done
        log ""
        log "💡 You can:"
        log "   1. Check the log file for detailed error messages: $LOG_FILE"
        log "   2. Fix the issues and re-run the script (it will skip successful builds)"
        log "   3. Continue using the successfully built components"
    fi
    
    log ""
    log "🔧 To use the toolchain:"
    log "   source ~/.profile"
    log "   # or start a new shell session"
}

log "=== Toolchain build process complete! ==="

# Update .profile with environment variables
update_profile

# Print final summary
print_summary
