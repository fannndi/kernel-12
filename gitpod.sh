#!/usr/bin/env bash

set -o pipefail
SECONDS=0

# =============== CONFIG ===============
KERNEL_DIR=$(pwd)
DEFCONFIG="surya_defconfig"
DEVICE="Surya"
KERNEL_NAME="MIUI-A12-NOS"
BUILD_TIME=$(date '+%d%m%Y-%H%M')
ZIPNAME="${KERNEL_NAME}-${DEVICE}-${BUILD_TIME}.zip"
LOGS="${KERNEL_DIR}/build.log"
CLANG_DIR="${KERNEL_DIR}/clang"
GCC64_DIR="/usr/bin/aarch64-linux-gnu"
GCC32_DIR="/usr/bin/arm-linux-gnueabi"
MKDTBOIMG="${KERNEL_DIR}/tools/mkdtboimg.py"
DTBO_OUT="dtbo.img"

export ARCH=arm64
export SUBARCH=arm64
export KBUILD_BUILD_USER="fannndi"
export KBUILD_BUILD_HOST="gitpod"
export KBUILD_BUILD_VERSION="1"
export KBUILD_LDFLAGS="-Wl,--no-keep-memory"

# =============== EXPERIMENTAL CONFIGS ===============
EXPERIMENTAL_FEATURES_ENABLED=""
EXPERIMENTAL_FEATURES_DISABLED=""
EXPERIMENTAL_CONFIGS=()
EXPERIMENTAL_DISABLE_CONFIGS=()

# =============== TELEGRAM ===============
CHATID="-1002354747626"
TELEGRAM_TOKEN=""
TG="${HOME}/telegram/telegram"

if [ ! -f "$TG" ]; then
    git clone https://github.com/fabianonline/telegram.sh "${HOME}/telegram"
    chmod +x "$TG"
fi

tg_cast() {
    "$TG" -t "$TELEGRAM_TOKEN" -c "$CHATID" -M "$*"
}

tg_ship() {
    "$TG" -f "$1" -t "$TELEGRAM_TOKEN" -c "$CHATID" -M "$2"
}

tg_fail() {
    tg_cast "❌ Build failed in $(($SECONDS / 60))m $(($SECONDS % 60))s"
    [ -f "$LOGS" ] && tg_ship "$LOGS" "🧾 Build log:"
    exit 1
}

# =============== TOOLCHAIN ===============
prepare_toolchain() {
    if ! command -v "${CLANG_DIR}/bin/clang" &>/dev/null; then
        echo "🔧 Clang tidak ditemukan, mendownload..."
        mkdir -p "$CLANG_DIR" && cd "$CLANG_DIR" || exit 1
        wget -q https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r536225.tar.gz -O - | tar -xz
        cd "$KERNEL_DIR" || exit 1
    else
        echo "✅ Clang sudah tersedia, skip download."
    fi
    export PATH="${CLANG_DIR}/bin:$PATH"
}

# =============== PATCH DEFCONFIG ===============
patch_defconfig() {
    if [ -f "out/.config" ]; then
        cp out/.config arch/arm64/configs/${DEFCONFIG}
    fi
    cp arch/arm64/configs/${DEFCONFIG} arch/arm64/configs/${DEFCONFIG}.bak
    sed -i -e '/^CONFIG_LOCALVERSION=/d' -e '/^CONFIG_LOCALVERSION_AUTO=/d' arch/arm64/configs/${DEFCONFIG}
    echo 'CONFIG_LOCALVERSION="-TEST"' >> arch/arm64/configs/${DEFCONFIG}
    echo 'CONFIG_LOCALVERSION_AUTO=y' >> arch/arm64/configs/${DEFCONFIG}
}

# =============== EXPERIMENTAL CONFIG SETUP ===============
enable_experimental_configs() {
    [ ! -x scripts/config ] && make O=out scripts

    for conf in "${EXPERIMENTAL_CONFIGS[@]}"; do
        if ! grep -q "^$conf=y" out/.config; then
            EXPERIMENTAL_FEATURES_ENABLED+="$conf\n"
            scripts/config --file out/.config -e "$conf"
        fi
    done

    for conf in "${EXPERIMENTAL_DISABLE_CONFIGS[@]}"; do
        if grep -q "^$conf=y" out/.config; then
            EXPERIMENTAL_FEATURES_DISABLED+="$conf\n"
            scripts/config --file out/.config -d "$conf"
        fi
    done

    make O=out olddefconfig
}

# =============== ENV INFO ===============
print_env() {
    echo "🧠 Build Info:"
    echo "• Kernel: $(make kernelversion)"
    echo "• CPU: $(nproc)-core $(lscpu | awk -F: '/Model name/ {print $2}' | sed 's/^ *//')"
    echo "• RAM: $(free -h | awk '/Mem:/ {print $2}')"
    echo "• Swap: $(free -h | awk '/Swap:/ {print $2}')"
    echo "• Disk: $(df -h . | awk 'NR==2 {print $4}') free"
    echo "• Uptime: $(uptime -p)"
    echo "• Date: $(date)"
}

# =============== BUILD ===============
build_kernel() {
    rm -rf out && mkdir out

    echo "🧹 Cleaning source..."
    make O=out clean
    make O=out mrproper

    echo "⚙️  Applying defconfig..."
    make O=out "$DEFCONFIG" || tg_fail

    patch_defconfig
    enable_experimental_configs

    nice -n10 make -j$(nproc) O=out \
        ARCH=arm64 \
        CC=clang \
        LD=ld.lld \
        AR=llvm-ar NM=llvm-nm \
        OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump STRIP=llvm-strip \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=${GCC64_DIR}- \
        CROSS_COMPILE_COMPAT=${GCC32_DIR}- \
        LLVM=1 LLVM_IAS=1 \
        LLVM_AR=llvm-ar LLVM_NM=llvm-nm \
        KBUILD_USE_RESPONSE_FILE=1 \
        KBUILD_BUILD_USER=$KBUILD_BUILD_USER \
        KBUILD_BUILD_HOST=$KBUILD_BUILD_HOST \
        Image.gz dtbs 2>&1 | tee "$LOGS"

    [ ! -f out/arch/arm64/boot/Image.gz ] && tg_fail

    echo "📦 Menggabungkan Image.gz-dtb..."

    DTB_PATH=$(find out/arch/arm64/boot/ -type f -name '*.dtb' | head -n1 | xargs dirname)
    if [ -z "$DTB_PATH" ]; then
        echo "❌ Tidak ditemukan file .dtb!"
        tg_fail
    fi

    find "$DTB_PATH" -name '*.dtb' | sort | xargs cat > dtb.img || tg_fail
    { cat out/arch/arm64/boot/Image.gz; find "$DTB_PATH" -name '*.dtb' | sort | xargs cat; } > Image.gz-dtb || tg_fail

    if [ -f "$MKDTBOIMG" ]; then
        mkdir -p overlay
        find "$DTB_PATH" -name '*.dtbo' -exec cp {} overlay/ \;
        if ls overlay/*.dtbo 1> /dev/null 2>&1; then
            python3 "$MKDTBOIMG" create "$DTBO_OUT" --page_size=4096 --id=0 overlay/*.dtbo || tg_fail
        fi
        rm -rf overlay
    fi

    cp out/.config out/experimental_defconfig_snapshot
    make O=out savedefconfig
    cp out/defconfig arch/arm64/configs/${DEFCONFIG}
}

# =============== PACKAGE ===============
package_kernel() {
    rm -rf AnyKernel3
    git clone --depth=1 https://github.com/rinnsakaguchi/AnyKernel3 -b FSociety || tg_fail

    cp Image.gz-dtb dtb.img "$DTBO_OUT" AnyKernel3/ 2>/dev/null || true
    cd AnyKernel3 || tg_fail
    zip -r9 "../$ZIPNAME" ./* -x '*.git*' README.md *placeholder
    cd ..

    [ ! -f "$ZIPNAME" ] && tg_fail

    SIZE=$(du -h "$ZIPNAME" | cut -f1)
    SHA1=$(sha1sum "$ZIPNAME" | cut -d' ' -f1)

    CHANGELOG=""
    if [ -n "$EXPERIMENTAL_FEATURES_ENABLED" ]; then
        CHANGELOG+="\n🧪 *Enabled Features:*\n\`\`\`\n$(printf "$EXPERIMENTAL_FEATURES_ENABLED")\`\`\`"
    fi
    if [ -n "$EXPERIMENTAL_FEATURES_DISABLED" ]; then
        CHANGELOG+="\n🚫 *Disabled Features:*\n\`\`\`\n$(printf "$EXPERIMENTAL_FEATURES_DISABLED")\`\`\`"
    fi

    tg_ship "$ZIPNAME" "✅ Build succeeded for *$DEVICE* in *$(($SECONDS / 60))m $(($SECONDS % 60))s*$CHANGELOG"
    tg_cast "📦 *File Info:*\n• Name: \`$ZIPNAME\`\n• Size: *$SIZE*\n• SHA1: \`$SHA1\`"
    tg_ship "out/experimental_defconfig_snapshot" "📄 Experimental Defconfig Snapshot"

    rm -f Image.gz-dtb dtb.img "$DTBO_OUT" "$ZIPNAME" "$LOGS"
    rm -rf AnyKernel3 out overlay 2>/dev/null
}

# =============== MAIN ===============
NOW=$(date +%d/%m/%Y-%H:%M)
KERNEL_VER=$(make kernelversion)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_COMMIT=$(git rev-parse --short HEAD)

tg_cast "*🚀 Build Started!*%0A*Device:* $DEVICE%0A*Compiler:* Google Clang A15%0A*Kernel:* $KERNEL_VER%0A*Branch:* $GIT_BRANCH%0A*Commit:* \`$GIT_COMMIT\`%0A*Started:* $NOW"

prepare_toolchain
print_env
build_kernel
package_kernel