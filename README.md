# Build script mesa-turnip-kgsl for Qualcomm Adreno GPU

This script will “attempt” to build mesa-turnip-kgsl. Suitable for Ubuntu. Ubuntu 24 or higher is preferred.

- [Build script mesa-turnip-kgsl for Qualcomm Adreno GPU](#build-script-mesa-turnip-kgsl-for-qualcomm-adreno-gpu)
- [Build and install](#build-and-install)
- [Tested environment](#tested-environment)
- [Latest tested Mesa Config](#latest-tested-mesa-config)
- [Optimization](#optimization)
- [Thanks](#thanks)

# Build and install

For convenience, run from the root account. The build will take place in `/root/mesa-build`.

```sh
apt install git
git clone https://github.com/DvaMishkiLapa/mesa-turnip-kgsl-build.git
cd mesa-turnip-kgsl-build
./build_mesa
```

If you want to build and install in a system, then:
```sh
./build_mesa install
```

The process may take about 20-30 minutes, will take about 300 mb of internal memory.

# Tested environment

- [Samsung Galaxy Tab A9+ 5G (SM6375)](https://www.devicespecifications.com/en/model/3e1d5e00)
  - Chroot Ubuntu 24.04 via [chroot-distro](https://github.com/Magisk-Modules-Alt-Repo/chroot-distro) on Android 14 OneUI6.1 + Root with [Apatch](https://github.com/bmax121/APatch).

# Latest tested Mesa Config

```sh
mesa 25.2.0-devel

  Directories
    prefix           : /usr
    libdir           : lib/aarch64-linux-gnu
    includedir       : include

  Common C and C++ arguments
    c_cpp_args       : -mtls-dialect=desc

  OpenGL
    OpenGL           : YES
    ES1              : YES
    ES2              : YES
    GLVND            : YES

  DRI
    Platform         : drm
    Driver dir       : /usr/lib/aarch64-linux-gnu/dri

  GLX
    Enabled          : YES
    Provider         : dri

  EGL
    Enabled          : YES
    Drivers          : builtin:egl_dri2 builtin:egl_dri3
    Platforms        : x11 surfaceless drm xcb

  GBM
    Enabled          : YES
    External libgbm  : NO
    Backends path    : /usr/lib/aarch64-linux-gnu/gbm

  Vulkan
    Drivers          : freedreno
    Platforms        : x11 surfaceless drm xcb
    ICD dir          : share/vulkan/icd.d
    Intel Ray tracing: NO

  Video
    Codecs           : all_free av1dec av1enc vp9dec
    APIs             : vulkan xa

  LLVM
    Enabled          : NO

  Gallium
    Enabled          : YES
    Drivers          : freedreno
    Platforms        : x11 surfaceless drm xcb
    Frontends        : mesa xa
    HUD lm-sensors   : YES

  Perfetto
    Enabled          : NO

  Teflon (TensorFlow Lite delegate)
    Enabled          : NO

  User defined options
    Cross files      : /root/mesa-build/cross_aarch64.txt
    buildtype        : release
    libdir           : lib/aarch64-linux-gnu
    prefix           : /usr
    wrap_mode        : nofallback
    b_lto            : true
    egl              : enabled
    freedreno-kmds   : kgsl
    gallium-drivers  : freedreno
    gbm              : enabled
    gles1            : enabled
    gles2            : enabled
    glx              : dri
    platforms        : x11
    vulkan-drivers   : freedreno
```

# Optimization

You can put together a package with optimizations for your SoC if you're not lazy. Example for SM6375:

```txt
# cross_aarch64.txt
c_args = ['-O3',
          '-mcpu=cortex-a78',
          '-mtune=cortex-a78',
          '-fomit-frame-pointer',
          '-ffunction-sections',
          '-fdata-sections']
```

```txt
# cross_armhf.txt
c_args = ['-O3',
          '-mcpu=cortex-a55',
          '-mfpu=neon',
          '-fomit-frame-pointer',
          '-ffunction-sections',
          '-fdata-sections']
```

Universal options (for any arch):
```txt
c_args = ['-O3',
          '-fomit-frame-pointer',
          '-ffunction-sections',
          '-fdata-sections']
```

# Thanks

- [xDoge26](https://github.com/xDoge26/mesa-turnip) xDoge26 for the idea;
- [MastaG](https://github.com/MastaG/mesa-turnip-ppa) for recommendations on ENV customization and source patches.
