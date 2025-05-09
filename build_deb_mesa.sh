#!/bin/bash
set -euo pipefail

#===============================================================================
# Variables
#===============================================================================
BUILD_DIR="/root/mesa-build"
REPO_URL="https://github.com/DvaMishkiLapa/mesa-turnip-kgsl-build.git"
REPO_DIR="$BUILD_DIR/mesa-turnip-kgsl-build"
MESA_ARCHIVE="$BUILD_DIR/mesa-main.tar.gz"
MESA_SRC="$BUILD_DIR/mesa-main"
. /etc/os-release
CODENAME="$UBUNTU_CODENAME"
DATE="$(date +%Y%m%d)"
MESA_VER=""

#===============================================================================
# 1) Prepare /etc/apt for ubuntu-ports and enable armhf multiarch
#===============================================================================
prepare_sources() {
  cat > /etc/apt/sources.list <<EOF
# Ubuntu-ports ${CODENAME}
deb http://ports.ubuntu.com/ubuntu-ports ${CODENAME} main restricted universe multiverse
deb-src http://ports.ubuntu.com/ubuntu-ports ${CODENAME} main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports ${CODENAME}-updates main restricted universe multiverse
deb-src http://ports.ubuntu.com/ubuntu-ports ${CODENAME}-updates main restricted universe multiverse

deb http://ports.ubuntu.com/ubuntu-ports ${CODENAME}-security main restricted universe multiverse
deb-src http://ports.ubuntu.com/ubuntu-ports ${CODENAME}-security main restricted universe multiverse
EOF
  dpkg --add-architecture armhf
  apt update && apt upgrade -y
}

#===============================================================================
# 2) Install build-deps (including cross-arch)
#===============================================================================
install_deps() {
  apt build-dep -y mesa
  apt install -y --no-install-recommends \
    pkg-config make cmake git wget vulkan-tools mesa-utils \
    g++-arm-linux-gnueabihf g++-aarch64-linux-gnu \
    zlib1g-dev:armhf libdrm-dev:armhf libx11-dev:armhf \
    libxcb1-dev:armhf libxext-dev:armhf libxfixes-dev:armhf \
    libxrender-dev:armhf x11proto-dev:armhf libv4l-dev:armhf \
    zlib1g-dev:arm64 libdrm-dev:arm64 libx11-dev:arm64 \
    libxcb1-dev:arm64 libxext-dev:arm64 libxfixes-dev:arm64 \
    libxrender-dev:arm64 libxdamage-dev:arm64 libv4l-dev:arm64
  # fix missing drm_mode.h
  cp /usr/include/libdrm/drm.h /usr/include/libdrm/drm_mode.h /usr/include/
}

#===============================================================================
# 3) Clone or update the repository with patches
#===============================================================================
fetch_patches_repo() {
  if [ -d "$REPO_DIR" ]; then
    git -C "$REPO_DIR" pull --ff-only
  else
    git clone --depth 1 "$REPO_URL" "$REPO_DIR"
  fi
}

#===============================================================================
# 4) Download and unzip Mesa
#===============================================================================
download_unpack() {
  mkdir -p "$BUILD_DIR"
  [ -f "$MESA_ARCHIVE" ] || \
    wget -qO "$MESA_ARCHIVE" https://gitlab.freedesktop.org/mesa/mesa/-/archive/main/mesa-main.tar.gz
  [ -d "$MESA_SRC" ] || tar xf "$MESA_ARCHIVE" -C "$BUILD_DIR"
}

#===============================================================================
# 5) Apply all your patches
#===============================================================================
apply_patches() {
  pushd "$MESA_SRC" >/dev/null
    for p in "$REPO_DIR"/turnip-patches/*.patch; do
      echo ">> Applying patch: $(basename "$p")"
      patch -p1 < "$p"
    done
  popd >/dev/null
}

#===============================================================================
# 6) Generate Meson cross files
#===============================================================================
generate_cross() {
  mkdir -p "$BUILD_DIR"

  # --- aarch64 ---
  cat > "$BUILD_DIR/cross_aarch64.txt" <<EOF
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
pkgconfig = 'pkg-config'
strip = 'aarch64-linux-gnu-strip'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'

[built-in options]
c_args = ['-O3','-mcpu=cortex-a76','-mtune=cortex-a76','-fomit-frame-pointer','-ffunction-sections','-fdata-sections']
cpp_args = c_args
c_link_args = ['-Wl,--as-needed','-Wl,--gc-sections']
EOF

  # --- armhf ---
  cat > "$BUILD_DIR/cross_armhf.txt" <<EOF
[binaries]
c = 'arm-linux-gnueabihf-gcc'
cpp = 'arm-linux-gnueabihf-g++'
pkgconfig = 'pkg-config'
strip = 'arm-linux-gnueabihf-strip'

[host_machine]
system = 'linux'
cpu_family = 'arm'
cpu = 'armv7l'
endian = 'little'

[built-in options]
c_args = ['-O3','-march=armv7-a+simd','-mtune=cortex-a55','-mfpu=neon','-fomit-frame-pointer','-ffunction-sections','-fdata-sections']
cpp_args = c_args
c_link_args = ['-Wl,--as-needed','-Wl,--gc-sections']
EOF
}

#===============================================================================
# 7) Assembly + packaging for a given ARCH
#===============================================================================
build_and_package() {
  ARCH="$1"; CFG="$2"; DEST="$3"
  case "$ARCH" in
    aarch64) DEB_ARCH="arm64" ;;
    armhf)   DEB_ARCH="armhf" ;;
    *)       DEB_ARCH="$ARCH" ;;
  esac

  # for armhf - substitute PKG_CONFIG_LIBDIR so that pkg-config finds .pc of the target architecture.
  if [ "$ARCH" = "armhf" ]; then
    export PKG_CONFIG_LIBDIR="/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
  else
    unset PKG_CONFIG_LIBDIR
  fi

  rm -rf "$BUILD_DIR/build_$ARCH"
  mkdir -p "$BUILD_DIR/build_$ARCH"

  MESON_LOG_LEVEL=info meson setup "$BUILD_DIR/build_$ARCH" "$MESA_SRC" \
    --cross-file "$CFG" \
    --prefix=/usr \
    --libdir="lib/${ARCH}-linux-gnu" \
    --wrap-mode=nofallback \
    -D vulkan-drivers=freedreno \
    -D freedreno-kmds=kgsl \
    -D gallium-drivers=freedreno \
    -D glx=dri \
    -D egl=enabled \
    -D gles1=enabled \
    -D gles2=enabled \
    -D platforms=x11 \
    -D gbm=enabled \
    -D buildtype=release \
    -D b_lto=true

  ninja -C "$BUILD_DIR/build_$ARCH" -j"$(nproc)"
  DESTDIR="$DEST" ninja -C "$BUILD_DIR/build_$ARCH" install

  # create .deb package
  apt remove -y mesa-vulkan-drivers:"$DEB_ARCH" || true
  apt download mesa-vulkan-drivers:"$DEB_ARCH"
  dpkg-deb -x mesa-vulkan-drivers_*_"$DEB_ARCH".deb "$DEST/usr"
  dpkg-deb -e mesa-vulkan-drivers_*_"$DEB_ARCH".deb "$DEST/DEBIAN"
  sed -i "s/^Version:.*/Version: $MESA_VER-$DATE/" "$DEST/DEBIAN/control"
  dpkg-deb --build "$DEST"
  rm -f mesa-vulkan-drivers_*_"$DEB_ARCH".deb
}

#===============================================================================
# Main
#===============================================================================
main() {
  echo ">> Preparing apt sources..."
  prepare_sources

  echo ">> Installing dependencies..."
  install_deps

  echo ">> Fetching patch repository..."
  fetch_patches_repo

  echo ">> Downloading Mesa source..."
  download_unpack

  echo ">> Applying patches to Mesa..."
  apply_patches

  echo ">> Generating Meson cross files..."
  generate_cross

  MESA_VER="$(<"$MESA_SRC/VERSION")"

  echo ">> Building for aarch64..."
  build_and_package aarch64 "$BUILD_DIR/cross_aarch64.txt" \
    "$BUILD_DIR/mesa-vk-kgsl_${MESA_VER}-${DATE}-${CODENAME}_arm64"

  echo ">> Building for armhf..."
  build_and_package armhf "$BUILD_DIR/cross_armhf.txt" \
    "$BUILD_DIR/mesa-vk-kgsl_${MESA_VER}-${DATE}-${CODENAME}_armhf"

  echo ">> Build complete. Packages in $BUILD_DIR"
}

main "$@"
