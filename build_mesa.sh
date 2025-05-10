#!/bin/bash
set -euo pipefail

#===============================================================================
# Require root
#===============================================================================
if [ "$EUID" -ne 0 ]; then
  echo "Please run this script as root (e.g. sudo ./build_mesa.sh)"
  exit 1
fi

#===============================================================================
# Variables
#===============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/mesa-build"
REPO_URL="https://github.com/DvaMishkiLapa/mesa-turnip-kgsl-build.git"
REPO_DIR="${BUILD_DIR}/mesa-turnip-kgsl-build"
MESA_ARCHIVE="${BUILD_DIR}/mesa-main.tar.gz"
MESA_SRC="${BUILD_DIR}/mesa-main"
. /etc/os-release
CODENAME="$UBUNTU_CODENAME"

#===============================================================================
# 1) Prepare apt sources and multi-arch
#===============================================================================
prepare_sources() {
  if [ -f /etc/apt/sources.list.d/ubuntu.sources ]; then
    mv /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources.bak
  fi
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
  dpkg --add-architecture arm64
  apt update && apt upgrade -y
}

#===============================================================================
# 2) Install build dependencies
#===============================================================================
install_deps() {
  apt build-dep -y mesa
  apt install -y --no-install-recommends \
    pkg-config make cmake git wget vulkan-tools mesa-utils rsync \
    g++-arm-linux-gnueabihf g++-aarch64-linux-gnu \
    zlib1g-dev:armhf     zlib1g-dev:arm64 \
    libdrm-dev:armhf     libdrm-dev:arm64 \
    libx11-dev:armhf     libx11-dev:arm64 \
    libxcb1-dev:armhf    libxcb1-dev:arm64 \
    libxcb-randr0-dev:armhf libxcb-randr0-dev:arm64 \
    libxext-dev:armhf    libxext-dev:arm64 \
    libxfixes-dev:armhf  libxfixes-dev:arm64 \
    libxrender-dev:armhf libxrender-dev:arm64 \
    libv4l-dev:armhf     libv4l-dev:arm64 \
    x11proto-dev:armhf   libxdamage-dev:arm64 \
    libxcb-glx0-dev:armhf    libxcb-glx0-dev:arm64 \
    libxcb-shm0-dev:armhf    libxcb-shm0-dev:arm64 \
    libx11-xcb-dev:armhf     libx11-xcb-dev:arm64 \
    libxcb-keysyms1-dev:armhf libxcb-keysyms1-dev:arm64 \
    libxcb-dri2-0-dev:armhf   libxcb-dri2-0-dev:arm64 \
    libxcb-dri3-dev:armhf     libxcb-dri3-dev:arm64 \
    libxcb-present-dev:armhf  libxcb-present-dev:arm64 \
    libxshmfence-dev:armhf    libxshmfence-dev:arm64 \
    libxxf86vm-dev:armhf      libxxf86vm-dev:arm64 \
    libxrandr-dev:armhf       libxrandr-dev:arm64
  # workaround for missing headers
  cp /usr/include/libdrm/drm.h /usr/include/libdrm/drm_mode.h /usr/include/ || true
}

#===============================================================================
# 3) Clone or update patches repository
#===============================================================================
fetch_patches_repo() {
  if [ -d "${REPO_DIR}" ]; then
    git -C "${REPO_DIR}" pull --ff-only
  else
    git clone --depth 1 "${REPO_URL}" "${REPO_DIR}"
  fi
}

#===============================================================================
# 4) Download and unpack Mesa
#===============================================================================
download_unpack() {
  mkdir -p "${BUILD_DIR}"
  [ -f "${MESA_ARCHIVE}" ] || wget -qO "${MESA_ARCHIVE}" \
    https://gitlab.freedesktop.org/mesa/mesa/-/archive/main/mesa-main.tar.gz
  [ -d "${MESA_SRC}" ] || tar xf "${MESA_ARCHIVE}" -C "${BUILD_DIR}"
}

#===============================================================================
# 5) Apply patches idempotently
#===============================================================================
apply_patches() {
  pushd "${MESA_SRC}" >/dev/null
  for p in "${REPO_DIR}"/turnip-patches/*.patch; do
    echo ">> Applying patch: $(basename "$p")"
    if patch -p1 --dry-run < "$p" >/dev/null 2>&1; then
      patch -p1 < "$p"
    else
      echo "   Skipping already applied: $(basename "$p")"
    fi
  done
  popd >/dev/null
}

#===============================================================================
# 6) Generate Meson cross files
#===============================================================================
generate_cross() {
  mkdir -p "${BUILD_DIR}"
  # aarch64
  cat > "${BUILD_DIR}/cross_aarch64.txt" <<EOF
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
pkg-config = 'pkg-config'
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
  # armhf
  cat > "${BUILD_DIR}/cross_armhf.txt" <<EOF
[binaries]
c = 'arm-linux-gnueabihf-gcc'
cpp = 'arm-linux-gnueabihf-g++'
pkg-config = 'pkg-config'
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
# 7) Build for an architecture
#===============================================================================
build_arch() {
  local ARCH="$1" CFG="$2"
  rm -rf "${BUILD_DIR}/build_${ARCH}"
  mkdir -p "${BUILD_DIR}/build_${ARCH}"

  if [ "$ARCH" = armhf ]; then
    export PKG_CONFIG_LIBDIR="/usr/lib/arm-linux-gnueabihf/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"
  else
    unset PKG_CONFIG_LIBDIR
  fi

  meson setup "${BUILD_DIR}/build_${ARCH}" "${MESA_SRC}" \
    --cross-file "${CFG}" \
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

  ninja -C "${BUILD_DIR}/build_${ARCH}" -j"$(nproc)"
}

#===============================================================================
# 8) Install built libraries from staging
#===============================================================================
install_flow() {
  echo ">> Installing staged artifacts..."
  for ARCH in aarch64 armhf; do
    STG="${BUILD_DIR}/stage_${ARCH}"
    if [ ! -d "${STG}" ]; then
      echo "Error: staging for $ARCH not found. Run './build_mesa.sh' first to build." >&2
      exit 1
    fi
    INST="${STG}/usr"

    # libraries
    rsync -a "${INST}/lib/${ARCH}-linux-gnu"/ "/usr/lib/${ARCH}-linux-gnu/"

    # Vulkan ICDs
    if [ -d "${INST}/share/vulkan/icd.d" ]; then
      mkdir -p /usr/share/vulkan/icd.d
      rsync -a "${INST}/share/vulkan/icd.d"/ /usr/share/vulkan/icd.d/
    fi

    # drirc configs
    if [ -d "${INST}/share/drirc.d" ]; then
      mkdir -p /usr/share/drirc.d
      rsync -a "${INST}/share/drirc.d"/ /usr/share/drirc.d/
    fi
  done

  # environment vars
  grep -qxF 'VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json:/usr/share/vulkan/icd.d/freedreno_icd.armhf.json"' /etc/environment \
    || echo 'VK_ICD_FILENAMES="/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json:/usr/share/vulkan/icd.d/freedreno_icd.armhf.json"' >> /etc/environment
  grep -qxF 'TU_DEBUG="noconform"' /etc/environment \
    || echo 'TU_DEBUG="noconform"' >> /etc/environment

  ldconfig
  echo ">> Installation complete."
}

#===============================================================================
# Main
#===============================================================================
main() {
  echo ">> Preparing apt sources..."
  prepare_sources

  echo ">> Installing build dependencies..."
  install_deps

  if [ "${1:-}" != "install" ]; then
    echo ">> Cleaning previous build directory..."
    rm -rf "${BUILD_DIR}"
  fi

  echo ">> Fetching patch repository..."
  fetch_patches_repo

  echo ">> Downloading Mesa..."
  download_unpack

  echo ">> Applying patches to Mesa..."
  apply_patches

  echo ">> Generating Meson cross files..."
  generate_cross

  if [ "${1:-}" = "install" ]; then
    install_flow
  else
    echo ">> Building aarch64..."
    build_arch aarch64 "${BUILD_DIR}/cross_aarch64.txt"
    echo ">> Building armhf..."
    build_arch armhf "${BUILD_DIR}/cross_armhf.txt"

    echo ">> Staging artifacts..."
    for ARCH in aarch64 armhf; do
      BDIR="${BUILD_DIR}/build_${ARCH}"
      STG="${BUILD_DIR}/stage_${ARCH}"
      rm -rf "${STG}"
      mkdir -p "${STG}"
      echo "   Staging $ARCH..."
      DESTDIR="${STG}" ninja -C "${BDIR}" install
    done
    echo ">> Build and staging complete; staging dirs under ${BUILD_DIR}/stage_*"
  fi
}

main "$@"
