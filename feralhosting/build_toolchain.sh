#!/bin/bash
set -e

cd "$HOME/downloads"

# GNU mirrors
GNU_MIRROR="https://ftp.gnu.org/gnu"
KERNEL_MIRROR="https://www.kernel.org/pub"

# Function to check if package is already installed
check_installed() {
    local package=$1
    local check_command=$2
    
    if eval "$check_command" &>/dev/null; then
        echo "✓ $package already installed, skipping..."
        return 0
    else
        echo "✗ $package not found, will build..."
        return 1
    fi
}

# Function to download if not exists
download_if_missing() {
    local url=$1
    local filename=$(basename "$url")
    
    if [[ -f "$filename" ]]; then
        echo "✓ $filename already downloaded"
    else
        echo "Downloading $filename..."
        wget -c "$url"
    fi
}

echo "=== Downloading Sources ==="

# Binutils
download_if_missing "$GNU_MIRROR/binutils/binutils-2.41.tar.xz"
[[ -d "binutils-2.41" ]] || tar -xf binutils-2.41.tar.xz

# GCC (with prerequisites)
download_if_missing "$GNU_MIRROR/gcc/gcc-13.2.0/gcc-13.2.0.tar.xz"
if [[ ! -d "gcc-13.2.0" ]]; then
    tar -xf gcc-13.2.0.tar.xz
    cd gcc-13.2.0
    ./contrib/download_prerequisites
    cd ..
fi

# Glibc
download_if_missing "$GNU_MIRROR/glibc/glibc-2.38.tar.xz"
[[ -d "glibc-2.38" ]] || tar -xf glibc-2.38.tar.xz

# Make
download_if_missing "$GNU_MIRROR/make/make-4.4.1.tar.gz"
[[ -d "make-4.4.1" ]] || tar -xf make-4.4.1.tar.gz

# Autotools
download_if_missing "$GNU_MIRROR/autoconf/autoconf-2.71.tar.xz"
download_if_missing "$GNU_MIRROR/automake/automake-1.16.5.tar.xz"
download_if_missing "$GNU_MIRROR/libtool/libtool-2.4.7.tar.xz"
[[ -d "autoconf-2.71" ]] || tar -xf autoconf-2.71.tar.xz
[[ -d "automake-1.16.5" ]] || tar -xf automake-1.16.5.tar.xz
[[ -d "libtool-2.4.7" ]] || tar -xf libtool-2.4.7.tar.xz

# pkg-config
download_if_missing "https://pkgconfig.freedesktop.org/releases/pkg-config-0.29.2.tar.gz"
[[ -d "pkg-config-0.29.2" ]] || tar -xf pkg-config-0.29.2.tar.gz

# Essential libraries
download_if_missing "https://zlib.net/zlib-1.3.tar.gz"
[[ -d "zlib-1.3" ]] || tar -xf zlib-1.3.tar.gz

download_if_missing "https://www.sqlite.org/2024/sqlite-autoconf-3440200.tar.gz"
[[ -d "sqlite-autoconf-3440200" ]] || tar -xf sqlite-autoconf-3440200.tar.gz

download_if_missing "https://www.openssl.org/source/openssl-3.1.4.tar.gz"
[[ -d "openssl-3.1.4" ]] || tar -xf openssl-3.1.4.tar.gz

download_if_missing "$GNU_MIRROR/ncurses/ncurses-6.4.tar.gz"
[[ -d "ncurses-6.4" ]] || tar -xf ncurses-6.4.tar.gz

download_if_missing "$GNU_MIRROR/readline/readline-8.2.tar.gz"
[[ -d "readline-8.2" ]] || tar -xf readline-8.2.tar.gz

echo "=== Building Toolchain ==="

# 1. Binutils
if check_installed "binutils" "test -f '$LOCAL_PREFIX/bin/ld' && '$LOCAL_PREFIX/bin/ld' --version"; then
    echo "Skipping binutils build"
else
    echo "Building binutils..."
    cd binutils-2.41
    ./configure --prefix="$LOCAL_PREFIX" --disable-werror
    make -j$(nproc)
    make install
    cd ..
fi

# 2. GCC (stage 1 - C only)
if check_installed "GCC stage 1" "test -f '$LOCAL_PREFIX/bin/gcc' && '$LOCAL_PREFIX/bin/gcc' --version"; then
    echo "Skipping GCC stage 1 build"
else
    echo "Building GCC stage 1..."
    mkdir -p gcc-build-stage1
    cd gcc-build-stage1
    ../gcc-13.2.0/configure --prefix="$LOCAL_PREFIX" \
        --enable-languages=c \
        --disable-multilib \
        --disable-bootstrap \
        --disable-libsanitizer
    make -j$(nproc)
    make install
    cd ..
fi

# 3. Glibc
if check_installed "glibc" "test -f '$LOCAL_PREFIX/lib/libc.so'"; then
    echo "Skipping glibc build"
else
    echo "Building glibc..."
    mkdir -p glibc-build
    cd glibc-build
    ../glibc-2.38/configure --prefix="$LOCAL_PREFIX" \
        --disable-werror \
        --enable-shared
    make -j$(nproc)
    make install
    cd ..
fi

# 4. GCC (stage 2 - full)
if check_installed "GCC C++" "test -f '$LOCAL_PREFIX/bin/g++' && '$LOCAL_PREFIX/bin/g++' --version"; then
    echo "Skipping GCC stage 2 build"
else
    echo "Building GCC stage 2..."
    mkdir -p gcc-build-stage2
    cd gcc-build-stage2
    ../gcc-13.2.0/configure --prefix="$LOCAL_PREFIX" \
        --enable-languages=c,c++ \
        --disable-multilib \
        --disable-bootstrap
    make -j$(nproc)
    make install
    cd ..
fi

echo "=== Building Build Tools ==="

# Make
if check_installed "make" "'$LOCAL_PREFIX/bin/make' --version"; then
    echo "Skipping make build"
else
    echo "Building make..."
    cd make-4.4.1
    ./configure --prefix="$LOCAL_PREFIX"
    make -j$(nproc)
    make install
    cd ..
fi

# pkg-config
if check_installed "pkg-config" "'$LOCAL_PREFIX/bin/pkg-config' --version"; then
    echo "Skipping pkg-config build"
else
    echo "Building pkg-config..."
    cd pkg-config-0.29.2
    ./configure --prefix="$LOCAL_PREFIX" --with-internal-glib
    make -j$(nproc)
    make install
    cd ..
fi

# Autotools
if check_installed "autoconf" "'$LOCAL_PREFIX/bin/autoconf' --version"; then
    echo "Skipping autoconf build"
else
    echo "Building autoconf..."
    cd autoconf-2.71
    ./configure --prefix="$LOCAL_PREFIX"
    make -j$(nproc)
    make install
    cd ..
fi

if check_installed "automake" "'$LOCAL_PREFIX/bin/automake' --version"; then
    echo "Skipping automake build"
else
    echo "Building automake..
