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

# Function to get latest version from GNU FTP
get_gnu_latest_version() {
    local package=$1
    local pattern=${2:-""}
    local cache_key="gnu_${package}"
    
    if [[ -n "${VERSION_CACHE[$cache_key]:-}" ]]; then
        echo "${VERSION_CACHE[$cache_key]}"
        return 0
    fi
    
    log "🔍 Fetching latest version for $package..." >&2
    
    local url="$GNU_MIRROR/$package/"
    local version
    
    # Try to get directory listing and extract latest version
    if version=$(curl -s "$url" | grep -oP "${package}-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.tar)" | sort -V | tail -1); then
        if [[ -n "$version" ]]; then
            VERSION_CACHE[$cache_key]="$version"
            log "✓ Found $package version: $version" >&2
            echo "$version"
            return 0
        fi
    fi
    
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
    
    log "🔍 Fetching latest version for $name..." >&2
    
    local version
    if version=$(curl -s "$base_url" | grep -oP "$pattern" | sort -V | tail -1); then
        if [[ -n "$version" ]]; then
            VERSION_CACHE[$cache_key]="$version"
            log "✓ Found $name version: $version" >&2
            echo "$version"
            return 0
        fi
    fi
    
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
    
    log "🔍 Fetching latest SQLite version..." >&2
    
    # SQLite uses a special naming convention
    local version_info
    if version_info=$(curl -s "https://www.sqlite.org/download.html" | grep -oP 'sqlite-autoconf-\K[0-9]+(?=\.tar\.gz)' | head -1); then
        if [[ -n "$version_info" ]]; then
            VERSION_CACHE[$cache_key]="$version_info"
            log "✓ Found SQLite version: $version_info" >&2
            echo "$version_info"
            return 0
        fi
    fi
    
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
BINUTILS_VER=$(get_gnu_latest_version "binutils" || echo "${FALLBACK_VERSIONS[binutils]}")
GCC_VER=$(get_gnu_latest_version "gcc" || echo "${FALLBACK_VERSIONS[gcc]}")
GLIBC_VER=$(get_gnu_latest_version "glibc" || echo "${FALLBACK_VERSIONS[glibc]}") 
MAKE_VER=$(get_gnu_latest_version "make" || echo "${FALLBACK_VERSIONS[make]}")
AUTOCONF_VER=$(get_gnu_latest_version "autoconf" || echo "${FALLBACK_VERSIONS[autoconf]}")
AUTOMAKE_VER=$(get_gnu_latest_version "automake" || echo "${FALLBACK_VERSIONS[automake]}")
LIBTOOL_VER=$(get_gnu_latest_version "libtool" || echo "${FALLBACK_VERSIONS[libtool]}")
NCURSES_VER=$(get_gnu_latest_version "ncurses" || echo "${FALLBACK_VERSIONS[ncurses]}")
READLINE_VER=$(get_gnu_latest_version "readline" || echo "${FALLBACK_VERSIONS[readline]}")

# Special version detections with fallbacks
PKGCONFIG_VER=$(get_latest_version "pkg-config" "https://pkgconfig.freedesktop.org/releases/" "pkg-config-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.tar)" || echo "${FALLBACK_VERSIONS[pkg-config]}")
ZLIB_VER=$(get_latest_version "zlib" "https://zlib.net/" "zlib-\K[0-9]+\.[0-9]+(\.[0-9]+)?(?=\.tar)" || echo "${FALLBACK_VERSIONS[zlib]}")
SQLITE_VER=$(get_sqlite_latest_version || echo "${FALLBACK_VERSIONS[sqlite]}")
OPENSSL_VER=$(get_latest_version "openssl" "https://openssl-library.org/source/" "openssl-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar)" || echo "${FALLBACK_VERSIONS[openssl]}")

# Log which versions we'll be using
log "Detected versions:"
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

log "=== Downloading Sources ==="

# Binutils
if [[ -n "$BINUTILS_VER" ]]; then
    BINUTILS_FILE="binutils-${BINUTILS_VER}.tar.xz"
    BINUTILS_DIR="binutils-${BINUTILS_VER}"
    if download_if_missing "$GNU_MIRROR/binutils/$BINUTILS_FILE"; then
        safe_extract "$BINUTILS_FILE" "$BINUTILS_DIR"
    fi
fi

# GCC (with prerequisites)
if [[ -n "$GCC_VER" ]]; then
    GCC_FILE="gcc-${GCC_VER}.tar.xz"
    GCC_DIR="gcc-${GCC_VER}"
    if download_if_missing "$GNU_MIRROR/gcc/gcc-${GCC_VER}/$GCC_FILE"; then
        if safe_extract "$GCC_FILE" "$GCC_DIR"; then
            log "📥 Downloading GCC prerequisites..."
            cd "$GCC_DIR" && ./contrib/download_prerequisites && cd "$DOWNLOADS_DIR" || {
                handle_error "GCC prerequisites" "download"
            }
        fi
    fi
fi

# Glibc
if [[ -n "$GLIBC_VER" ]]; then
    GLIBC_FILE="glibc-${GLIBC_VER}.tar.xz"
    GLIBC_DIR="glibc-${GLIBC_VER}"
    if download_if_missing "$GNU_MIRROR/glibc/$GLIBC_FILE"; then
        safe_extract "$GLIBC_FILE" "$GLIBC_DIR"
    fi
fi

# Make
if [[ -n "$MAKE_VER" ]]; then
    MAKE_FILE="make-${MAKE_VER}.tar.gz"
    MAKE_DIR="make-${MAKE_VER}"
    if download_if_missing "$GNU_MIRROR/make/$MAKE_FILE"; then
        safe_extract "$MAKE_FILE" "$MAKE_DIR"
    fi
fi

# Autotools
if [[ -n "$AUTOCONF_VER" ]]; then
    AUTOCONF_FILE="autoconf-${AUTOCONF_VER}.tar.xz"
    AUTOCONF_DIR="autoconf-${AUTOCONF_VER}"
    if download_if_missing "$GNU_MIRROR/autoconf/$AUTOCONF_FILE"; then
        safe_extract "$AUTOCONF_FILE" "$AUTOCONF_DIR"
    fi
fi

if [[ -n "$AUTOMAKE_VER" ]]; then
    AUTOMAKE_FILE="automake-${AUTOMAKE_VER}.tar.xz"
    AUTOMAKE_DIR="automake-${AUTOMAKE_VER}"
    if download_if_missing "$GNU_MIRROR/automake/$AUTOMAKE_FILE"; then
        safe_extract "$AUTOMAKE_FILE" "$AUTOMAKE_DIR"
    fi
fi

if [[ -n "$LIBTOOL_VER" ]]; then
    LIBTOOL_FILE="libtool-${LIBTOOL_VER}.tar.xz"
    LIBTOOL_DIR="libtool-${LIBTOOL_VER}"
    if download_if_missing "$GNU_MIRROR/libtool/$LIBTOOL_FILE"; then
        safe_extract "$LIBTOOL_FILE" "$LIBTOOL_DIR"
    fi
fi

# pkg-config
if [[ -n "$PKGCONFIG_VER" ]]; then
    PKGCONFIG_FILE="pkg-config-${PKGCONFIG_VER}.tar.gz"
    PKGCONFIG_DIR="pkg-config-${PKGCONFIG_VER}"
    if download_if_missing "https://pkgconfig.freedesktop.org/releases/$PKGCONFIG_FILE"; then
        safe_extract "$PKGCONFIG_FILE" "$PKGCONFIG_DIR"
    fi
fi

# Essential libraries
if [[ -n "$ZLIB_VER" ]]; then
    ZLIB_FILE="zlib-${ZLIB_VER}.tar.gz"
    ZLIB_DIR="zlib-${ZLIB_VER}"
    if download_if_missing "https://zlib.net/$ZLIB_FILE"; then
        safe_extract "$ZLIB_FILE" "$ZLIB_DIR"
    fi
fi

if [[ -n "$SQLITE_VER" ]]; then
    SQLITE_FILE="sqlite-autoconf-${SQLITE_VER}.tar.gz"
    SQLITE_DIR="sqlite-autoconf-${SQLITE_VER}"
    # SQLite uses year-based URLs, try current year first
    SQLITE_YEAR=$(date +%Y)
    if ! download_if_missing "https://www.sqlite.org/${SQLITE_YEAR}/$SQLITE_FILE"; then
        # Try previous year if current year fails
        PREV_YEAR=$((SQLITE_YEAR - 1))
        download_if_missing "https://www.sqlite.org/${PREV_YEAR}/$SQLITE_FILE"
    fi
    if [[ -f "$SQLITE_FILE" ]]; then
        safe_extract "$SQLITE_FILE" "$SQLITE_DIR"
    fi
fi

if [[ -n "$OPENSSL_VER" ]]; then
    OPENSSL_FILE="openssl-${OPENSSL_VER}.tar.gz"
    OPENSSL_DIR="openssl-${OPENSSL_VER}"
    if download_if_missing "https://openssl-library.org/source/$OPENSSL_FILE"; then
        safe_extract "$OPENSSL_FILE" "$OPENSSL_DIR"
    fi
fi

if [[ -n "$NCURSES_VER" ]]; then
    NCURSES_FILE="ncurses-${NCURSES_VER}.tar.gz"
    NCURSES_DIR="ncurses-${NCURSES_VER}"
    if download_if_missing "$GNU_MIRROR/ncurses/$NCURSES_FILE"; then
        safe_extract "$NCURSES_FILE" "$NCURSES_DIR"
    fi
fi

if [[ -n "$READLINE_VER" ]]; then
    READLINE_FILE="readline-${READLINE_VER}.tar.gz"
    READLINE_DIR="readline-${READLINE_VER}"
    if download_if_missing "$GNU_MIRROR/readline/$READLINE_FILE"; then
        safe_extract "$READLINE_FILE" "$READLINE_DIR"
    fi
fi

log "=== Building Toolchain ==="

# 1. Binutils
if check_installed "binutils" "test -f '$LOCAL_PREFIX/bin/ld' && '$LOCAL_PREFIX/bin/ld' --version"; then
    log "Skipping binutils build"
else
    if [[ -n "$BINUTILS_VER" && -d "$BINUTILS_DIR" ]]; then
        safe_build "binutils" "$BINUTILS_DIR" "./configure --prefix='$LOCAL_PREFIX' --disable-werror"
    else
        handle_error "binutils" "source directory not found or version detection failed"
    fi
fi

# 2. GCC (stage 1 - C only)
if check_installed "GCC stage 1" "test -f '$LOCAL_PREFIX/bin/gcc' && '$LOCAL_PREFIX/bin/gcc' --version"; then
    log "Skipping GCC stage 1 build"
else
    if [[ -n "$GCC_VER" && -d "$GCC_DIR" ]]; then
        safe_build "GCC stage 1" "gcc-build-stage1" "../$GCC_DIR/configure --prefix='$LOCAL_PREFIX' --enable-languages=c --disable-multilib --disable-bootstrap --disable-libsanitizer"
    else
        handle_error "GCC stage 1" "source directory not found or version detection failed"
    fi
fi

# 3. Glibc
if check_installed "glibc" "test -f '$LOCAL_PREFIX/lib/libc.so'"; then
    log "Skipping glibc build"
else
    if [[ -n "$GLIBC_VER" && -d "$GLIBC_DIR" ]]; then
        safe_build "glibc" "glibc-build" "../$GLIBC_DIR/configure --prefix='$LOCAL_PREFIX' --disable-werror --enable-shared"
    else
        handle_error "glibc" "source directory not found or version detection failed"
    fi
fi

# 4. GCC (stage 2 - full)
if check_installed "GCC C++" "test -f '$LOCAL_PREFIX/bin/g++' && '$LOCAL_PREFIX/bin/g++' --version"; then
    log "Skipping GCC stage 2 build"
else
    if [[ -n "$GCC_VER" && -d "$GCC_DIR" ]]; then
        safe_build "GCC stage 2" "gcc-build-stage2" "../$GCC_DIR/configure --prefix='$LOCAL_PREFIX' --enable-languages=c,c++ --disable-multilib --disable-bootstrap"
    else
        handle_error "GCC stage 2" "source directory not found or version detection failed"
    fi
fi

log "=== Building Build Tools ==="

# Make
if check_installed "make" "'$LOCAL_PREFIX/bin/make' --version"; then
    log "Skipping make build"
else
    if [[ -n "$MAKE_VER" && -d "$MAKE_DIR" ]]; then
        safe_build "make" "$MAKE_DIR" "./configure --prefix='$LOCAL_PREFIX'"
    else
        handle_error "make" "source directory not found or version detection failed"
    fi
fi

# pkg-config
if check_installed "pkg-config" "'$LOCAL_PREFIX/bin/pkg-config' --version"; then
    log "Skipping pkg-config build"
else
    if [[ -n "$PKGCONFIG_VER" && -d "$PKGCONFIG_DIR" ]]; then
        safe_build "pkg-config" "$PKGCONFIG_DIR" "./configure --prefix='$LOCAL_PREFIX' --with-internal-glib"
    else
        handle_error "pkg-config" "source directory not found or version detection failed"
    fi
fi

# Autotools
if check_installed "autoconf" "'$LOCAL_PREFIX/bin/autoconf' --version"; then
    log "Skipping autoconf build"
else
    if [[ -n "$AUTOCONF_VER" && -d "$AUTOCONF_DIR" ]]; then
        safe_build "autoconf" "$AUTOCONF_DIR" "./configure --prefix='$LOCAL_PREFIX'"
    else
        handle_error "autoconf" "source directory not found or version detection failed"
    fi
fi

if check_installed "automake" "'$LOCAL_PREFIX/bin/automake' --version"; then
    log "Skipping automake build"
else
    if [[ -n "$AUTOMAKE_VER" && -d "$AUTOMAKE_DIR" ]]; then
        safe_build "automake" "$AUTOMAKE_DIR" "./configure --prefix='$LOCAL_PREFIX'"
    else
        handle_error "automake" "source directory not found or version detection failed"
    fi
fi

if check_installed "libtool" "'$LOCAL_PREFIX/bin/libtool' --version"; then
    log "Skipping libtool build"
else
    if [[ -n "$LIBTOOL_VER" && -d "$LIBTOOL_DIR" ]]; then
        safe_build "libtool" "$LIBTOOL_DIR" "./configure --prefix='$LOCAL_PREFIX'"
    else
        handle_error "libtool" "source directory not found or version detection failed"
    fi
fi

log "=== Building Libraries ==="

# zlib
if check_installed "zlib" "test -f '$LOCAL_PREFIX/lib/libz.so'"; then
    log "Skipping zlib build"
else
    if [[ -n "$ZLIB_VER" && -d "$ZLIB_DIR" ]]; then
        safe_build "zlib" "$ZLIB_DIR" "./configure --prefix='$LOCAL_PREFIX'"
    else
        handle_error "zlib" "source directory not found or version detection failed"
    fi
fi

# SQLite
if check_installed "SQLite" "test -f '$LOCAL_PREFIX/lib/libsqlite3.so'"; then
    log "Skipping SQLite build"
else
    if [[ -n "$SQLITE_VER" && -d "$SQLITE_DIR" ]]; then
        safe_build "SQLite" "$SQLITE_DIR" "./configure --prefix='$LOCAL_PREFIX'"
    else
        handle_error "SQLite" "source directory not found or version detection failed"
    fi
fi

# OpenSSL
if check_installed "OpenSSL" "test -f '$LOCAL_PREFIX/lib/libssl.so'"; then
    log "Skipping OpenSSL build"
else
    if [[ -n "$OPENSSL_VER" && -d "$OPENSSL_DIR" ]]; then
        safe_build "OpenSSL" "$OPENSSL_DIR" "./config --prefix='$LOCAL_PREFIX' --openssldir='$LOCAL_PREFIX/ssl'"
    else
        handle_error "OpenSSL" "source directory not found or version detection failed"
    fi
fi

# ncurses
if check_installed "ncurses" "test -f '$LOCAL_PREFIX/lib/libncurses.so'"; then
    log "Skipping ncurses build"
else
    if [[ -n "$NCURSES_VER" && -d "$NCURSES_DIR" ]]; then
        safe_build "ncurses" "$NCURSES_DIR" "./configure --prefix='$LOCAL_PREFIX' --with-shared --enable-widec"
    else
        handle_error "ncurses" "source directory not found or version detection failed"
    fi
fi

# readline
if check_installed "readline" "test -f '$LOCAL_PREFIX/lib/libreadline.so'"; then
    log "Skipping readline build"
else
    if [[ -n "$READLINE_VER" && -d "$READLINE_DIR" ]]; then
        safe_build "readline" "$READLINE_DIR" "./configure --prefix='$LOCAL_PREFIX'"
    else
        handle_error "readline" "source directory not found or version detection failed"
    fi
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
