#!/usr/bin/env bash
set -euo pipefail
shopt -s nocasematch

#Ngenggg

# Fix for Arch Linux python issue
if [[ "$(python --version 2>/dev/null)" == *"Python 3"* ]]; then
    alias python3=python
fi

# KERNEL TIMESTAMP (WIB)
get_kernel_timestamp() {
    date '+%a %b %d %H:%M:%S %Z %Y'
}

CLANG_VER="${CLANG_VER:-r547379}"
CLANG_URL_PRIMARY="${CLANG_URL_PRIMARY:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-${CLANG_VER}.tar.gz}"
CLANG_URL_FALLBACK="${CLANG_URL_FALLBACK:-https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+/refs/heads/main/clang-${CLANG_VER}?format=tar.gz}"

MKDTBOIMG_URL="https://android.googlesource.com/platform/system/libufdt/+/refs/heads/main/utils/src/mkdtboimg.py?format=TEXT"

KERNEL_NAME="${KERNEL_NAME:-MIUI-A10}"
DEFCONFIG="${DEFCONFIG:-surya_defconfig}"
OUTDIR="${OUTDIR:-out}"
ARCH="${ARCH:-arm64}"
SUBARCH="${SUBARCH:-arm64}"
BUILD_USER="${BUILD_USER:-fannndi}"
BUILD_HOST="${BUILD_HOST:-local}"
TUNE="${CPU_TUNE:-${TUNE:-cortex-a76}}" #cortex-a55 #cortex-a76 #default
CACHE_DIR="${CACHE_DIR:-$(pwd)/toolchains}"
CCACHE="${CCACHE:-1}"
USE_CCACHE=${USE_CCACHE:-$CCACHE}
ZIPNAME="${ZIPNAME:-${KERNEL_NAME}-Surya-${TUNE}-$(date '+%d%m%Y-%H%M').zip}"
BUILD_START=$(date +%s)
MAKE_PROCS="${MAKE_PROCS:-$(nproc)}"

# Colors & icons
CSI="\e["
CLR_RST="${CSI}0m"
CLR_RED="${CSI}31m"
CLR_GREEN="${CSI}32m"
CLR_YEL="${CSI}33m"
CLR_BLU="${CSI}34m"
CLR_MAG="${CSI}35m"
CLR_CYAN="${CSI}36m"
ICON_INFO="ℹ"
ICON_WARN="⚠"
ICON_ERR="❌"
ICON_OK="✅"
ICON_DEBUG="🔧"
LOGFILE="build-artifacts/log.txt"

# Derived
CLANG_DIR="${CACHE_DIR}/clang-${CLANG_VER}"
CLANG_TAR="${CACHE_DIR}/clang-${CLANG_VER}.tar.gz"
MKDTBOIMG_SCRIPT="${CACHE_DIR}/mkdtboimg.py"

# -------------------------
# Logging helpers
# -------------------------
_log() { local c="$1"; shift; echo -e "${c}$*${CLR_RST}"; }
info()  { _log "${CSI}1m${CLR_BLU}" "[$ICON_INFO] $*"; }
ok()    { _log "${CSI}1m${CLR_GREEN}" "[$ICON_OK] $*"; }
warn()  { _log "${CSI}1m${CLR_YEL}" "[$ICON_WARN] $*"; }
warning() { warn "$@"; }
err()   { _log "${CSI}1m${CLR_RED}" "[$ICON_ERR] $*"; }
error() { err "$@"; }
debug() { _log "${CSI}1m${CLR_CYAN}" "[$ICON_DEBUG] $*"; }

# Trap errors & exit
trap 'err "Build failed. Lihat ${LOGFILE} untuk detail."; exit 1' ERR
mkdir -p build-artifacts
rm -f "$LOGFILE"
exec > >(tee -i "$LOGFILE") 2>&1

info "Environment: Local (Arch Linux)"
info "Using Clang: ${CLANG_VER}"
info "Tune target: ${TUNE}"
info "Out dir: ${OUTDIR}"
info "Make procs: ${MAKE_PROCS}"
info "Toolchain: FULL LLVM (Modern)"
if (( USE_CCACHE )); then info "ccache: enabled"; else warn "ccache: disabled"; fi

# -------------------------
# Debug Toolchain Information
# -------------------------
debug_toolchain() {
    debug "=== TOOLCHAIN DEBUG INFORMATION ==="
    
    # CLANG/LLVM Information
    debug "--- LLVM Toolchain ---"
    if command -v clang >/dev/null 2>&1; then
        debug "Clang path: $(which clang)"
        debug "Clang version: $(clang --version | head -n1)"
        debug "Clang target: $(clang -dumpmachine 2>/dev/null || echo "N/A")"
        
        # Get detailed LLVM version
        local clang_full=$(clang --version)
        if echo "$clang_full" | grep -q "clang version"; then
            local llvm_version=$(echo "$clang_full" | grep -o "clang version [0-9\.]*" | cut -d' ' -f3)
            debug "LLVM version: ${llvm_version:-N/A}"
        fi
    else
        warn "Clang not found in PATH"
    fi
    
    if command -v ld.lld >/dev/null 2>&1; then
        debug "LLD path: $(which ld.lld)"
        debug "LLD version: $(ld.lld --version 2>&1 | head -n1)"
    else
        warn "LLD not found in PATH"
    fi
    
    # LLVM tools check
    debug "LLVM tools availability:"
    local llvm_tools=("llvm-ar" "llvm-nm" "llvm-objcopy" "llvm-strip" "llvm-objdump" "llvm-readelf" "llvm-size")
    for tool in "${llvm_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            debug "  ✓ $tool: $(which $tool)"
        else
            warn "  ✗ $tool: Not found"
        fi
    done
    
    # GNU Toolchain Information
    debug "--- GNU Toolchain ---"
    if command -v aarch64-linux-android-as >/dev/null 2>&1; then
        debug "GNU Assembler path: $(which aarch64-linux-android-as)"
        debug "GNU Assembler version: $(aarch64-linux-android-as --version 2>&1 | head -n1)"
    else
        warn "GNU Assembler not found"
    fi
    
    if command -v aarch64-linux-gnu-as >/dev/null 2>&1; then
        debug "System GNU Assembler: $(aarch64-linux-gnu-as --version 2>&1 | head -n1)"
    fi
    
    # ARM32 toolchain
    debug "--- ARM32 Toolchain ---"
    if command -v arm-linux-androideabi-as >/dev/null 2>&1; then
        debug "ARM32 Assembler: $(arm-linux-androideabi-as --version 2>&1 | head -n1)"
    else
        debug "ARM32 Assembler: Not configured"
    fi
    
    # System Compilers
    debug "--- System Compilers ---"
    if command -v gcc >/dev/null 2>&1; then
        debug "System GCC: $(gcc --version 2>&1 | head -n1)"
        debug "GCC target: $(gcc -dumpmachine 2>&1 || echo "N/A")"
    fi
    
    if command -v g++ >/dev/null 2>&1; then
        debug "System G++: $(g++ --version 2>&1 | head -n1)"
    fi
    
    # Python Information
    debug "--- Python Environment ---"
    if command -v python3 >/dev/null 2>&1; then
        debug "Python3: $(python3 --version 2>&1) at $(which python3)"
    fi
    
    if command -v python >/dev/null 2>&1; then
        debug "Python: $(python --version 2>&1) at $(which python)"
    fi
    
    # Build Tools
    debug "--- Build Tools ---"
    local build_tools=("make" "bash" "perl" "flex" "bison" "dtc" "lz4" "zstd")
    for tool in "${build_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            debug "  ✓ $tool: $(which $tool)"
        else
            warn "  ✗ $tool: Not found"
        fi
    done
    
    # PATH Analysis
    debug "--- PATH Analysis ---"
    debug "PATH components:"
    echo "$PATH" | tr ':' '\n' | while IFS= read -r path_item; do
        if [[ -n "$path_item" ]]; then
            debug "  $path_item"
        fi
    done
    
    # Toolchain Symlinks Check
    debug "--- Toolchain Symlinks ---"
    local gnu_dir="$CACHE_DIR/gnu-tools"
    if [[ -d "$gnu_dir" ]]; then
        debug "GNU tools directory: $gnu_dir"
        local symlinks=($(find "$gnu_dir" -type l 2>/dev/null))
        if (( ${#symlinks[@]} > 0 )); then
            debug "Symlinks found: ${#symlinks[@]}"
            for symlink in "${symlinks[@]:0:5}"; do
                debug "  $(basename "$symlink") -> $(readlink "$symlink")"
            done
            if (( ${#symlinks[@]} > 5 )); then
                debug "  ... and $(( ${#symlinks[@]} - 5 )) more"
            fi
        fi
    fi
    
    # Clang Directory Contents
    if [[ -d "$CLANG_DIR/bin" ]]; then
        debug "--- Clang Directory Contents ---"
        debug "Clang dir: $CLANG_DIR/bin"
        local clang_tools=($(ls "$CLANG_DIR/bin" 2>/dev/null))
        if (( ${#clang_tools[@]} > 0 )); then
            debug "Tools count: ${#clang_tools[@]}"
        fi
    fi
    
    # Memory and CPU Info
    debug "--- System Information ---"
    if command -v free >/dev/null 2>&1; then
        debug "Memory: $(free -h | awk '/^Mem:/ {print $2}') total"
    fi
    
    debug "CPU cores: $(nproc)"
    debug "System: $(uname -a)"
    
    debug "=== END TOOLCHAIN DEBUG ==="
}

# -------------------------
# Download mkdtboimg.py from Google
# -------------------------
download_mkdtboimg() {
    info "Setting up mkdtboimg.py..."
    
    if [[ ! -f "$MKDTBOIMG_SCRIPT" ]]; then
        info "Downloading mkdtboimg.py from Google AOSP..."
        
        local temp_script="${MKDTBOIMG_SCRIPT}.tmp"
        
        if curl -L --connect-timeout 30 --retry 3 "$MKDTBOIMG_URL" 2>/dev/null | \
           base64 -d > "$temp_script" 2>/dev/null; then
            
            if head -n 5 "$temp_script" | grep -q "python\|import\|def\|class"; then
                mv "$temp_script" "$MKDTBOIMG_SCRIPT"
                chmod +x "$MKDTBOIMG_SCRIPT"
                ok "mkdtboimg.py downloaded and made executable"
            else
                rm -f "$temp_script"
                warn "Downloaded file doesn't look like a Python script"
                return 1
            fi
        else
            rm -f "$temp_script"
            warn "Failed to download mkdtboimg.py"
            return 1
        fi
    else
        ok "mkdtboimg.py already exists"
    fi
    
    return 0
}

# -------------------------
# Utility: retry downloader
# -------------------------
_retry_wget() {
    local url=$1 out=$2 max=3 i=0 rc
    while (( i < max )); do
        info "Downloading (attempt $((i+1))/$max): $url"
        if command -v wget >/dev/null 2>&1; then
            wget -c -q -O "$out" "$url" && rc=0 || rc=$?
        else
            rc=1
        fi
        
        if [[ $rc -ne 0 ]]; then 
            info "wget failed or not available, trying curl (attempt $((i+1))/$max): $url"
            curl -L -o "$out" -C - --fail --silent --retry 3 --max-time 30 "$url" && rc=0 || rc=$?
        fi

        if [[ $rc -eq 0 && -s "$out" ]]; then
            ok "Downloaded: $out"
            return 0
        fi
        ((i++))
        sleep 2
    done
    return 1
}

# -------------------------
# Check & install light deps (DIPERBAIKI untuk Arch Linux)
# -------------------------
require_tools() {
    # Peta nama paket: [nama_alat]="nama_paket_arch"
    declare -A tool_map=(
        ["git"]="git" ["wget"]="wget" ["tar"]="tar" ["unzip"]="unzip"
        ["python3"]="python" ["zip"]="zip" ["make"]="make"
        ["lz4"]="lz4" ["zstd"]="zstd" ["cpio"]="cpio" ["bc"]="bc"
        ["curl"]="curl" ["ccache"]="ccache" ["dtc"]="dtc"
        ["flex"]="flex" ["bison"]="bison" ["openssl"]="openssl"
        ["perl"]="perl" ["rsync"]="rsync" ["patch"]="patch"
        ["file"]="file" ["gzip"]="gzip" ["xz"]="xz"
        # Toolchain GNU untuk ARM64
        ["aarch64-linux-gnu-as"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-ld"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-objcopy"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-objdump"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-strip"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-nm"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-ar"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-readelf"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-strings"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-size"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-addr2line"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-elfedit"]="aarch64-linux-gnu-binutils"
        ["aarch64-linux-gnu-gcc"]="aarch64-linux-gnu-gcc"
        # Toolchain GNU untuk ARM32
        ["arm-none-eabi-as"]="arm-none-eabi-binutils"
        ["arm-none-eabi-ld"]="arm-none-eabi-binutils"
        ["arm-none-eabi-objcopy"]="arm-none-eabi-binutils"
        ["arm-none-eabi-objdump"]="arm-none-eabi-binutils"
        ["arm-none-eabi-strip"]="arm-none-eabi-binutils"
        ["arm-none-eabi-nm"]="arm-none-eabi-binutils"
        ["arm-none-eabi-ar"]="arm-none-eabi-binutils"
        ["arm-none-eabi-readelf"]="arm-none-eabi-binutils"
        ["arm-none-eabi-gcc"]="arm-none-eabi-gcc"
        # Clang/LLVM (jika ingin pakai sistem)
        ["clang"]="clang" ["lld"]="lld" ["llvm"]="llvm"
    )
    
    local pkgs_to_install=()
    for t in "${!tool_map[@]}"; do
        if ! command -v "$t" >/dev/null 2>&1; then
            pkgs_to_install+=("${tool_map[$t]}")
        fi
    done

    if (( ${#pkgs_to_install[@]} )); then
        warn "Missing tools: ${pkgs_to_install[*]}"
        if command -v pacman >/dev/null 2>&1; then
            info "Arch Linux detected. Installing missing packages via pacman..."
            
            # Cek apakah base-devel sudah terinstall
            if ! pacman -Qg base-devel >/dev/null 2>&1; then
                warn "base-devel group not installed. Installing base-devel..."
                sudo pacman -S --noconfirm base-devel
            fi
            
            # Perbarui sistem sebelum menginstal
            sudo pacman -Sy --noconfirm
            
            # Instal paket yang hilang (hilang duplikat)
            unique_pkgs=($(printf "%s\n" "${pkgs_to_install[@]}" | sort -u))
            info "Installing packages: ${unique_pkgs[*]}"
            sudo pacman -S --needed --noconfirm "${unique_pkgs[@]}"
            
            # Python3 alias
            if [[ " ${unique_pkgs[@]} " =~ " python " ]]; then
                alias python3=python
            fi
        else
            err "pacman not found. Install manually: ${unique_pkgs[*]}"
            exit 1
        fi
    fi
    
    # Pastikan python3 ada (baik sebagai python3 atau python)
    if ! command -v python3 >/dev/null 2>&1; then
        if command -v python >/dev/null 2>&1 && [[ "$(python --version 2>&1)" == *"Python 3"* ]]; then
            alias python3=python
            info "Using 'python' as python3"
        else
            err "python3 not found. Please install python3"
            exit 1
        fi
    fi
    
    # Verifikasi toolchain penting
    info "Verifying essential toolchain..."
    local essential_tools=(
        "aarch64-linux-gnu-as"
        "aarch64-linux-gnu-ld"
        "arm-none-eabi-as"
        "clang"
        "ld.lld"
    )
    
    for tool in "${essential_tools[@]}"; do
        if command -v "$tool" >/dev/null 2>&1; then
            ok "Found: $tool ($(which $tool))"
        else
            warn "Missing essential tool: $tool"
        fi
    done
}

# -------------------------
# Prepare clang (cached) - DIPERBAIKI: HAPUS symlink as ke llvm-as
# -------------------------
prepare_clang() {
    info "Preparing Clang ${CLANG_VER}..."
    mkdir -p "$CACHE_DIR"
    
    if [[ -f "$CLANG_DIR/bin/clang" ]] && [[ -f "$CLANG_DIR/clang.version" ]] && \
       [[ "$(cat "$CLANG_DIR/clang.version" 2>/dev/null)" == "$CLANG_VER" ]]; then
        ok "Found valid clang installation in cache"
        return 0
    fi

    if [[ ! -f "$CLANG_TAR" ]] || [[ ! -s "$CLANG_TAR" ]]; then
        info "Downloading clang tarball..."
        if ! _retry_wget "$CLANG_URL_PRIMARY" "$CLANG_TAR"; then
            warn "Primary failed, trying fallback..."
            if ! _retry_wget "$CLANG_URL_FALLBACK" "$CLANG_TAR"; then
                err "Failed to download clang tarball"
                exit 1
            fi
        fi
    fi

    info "Verifying tarball integrity..."
    if ! tar -tzf "$CLANG_TAR" >/dev/null 2>&1; then
        warn "Tarball is corrupt or invalid, re-downloading..."
        rm -f "$CLANG_TAR"
        if ! _retry_wget "$CLANG_URL_PRIMARY" "$CLANG_TAR"; then
            err "Failed to download valid clang tarball"
            exit 1
        fi
    fi

    rm -rf "${CLANG_DIR}.tmp" "$CLANG_DIR"
    mkdir -p "${CLANG_DIR}.tmp"
    
    info "Extracting clang (this may take a while)..."
    
    if ! tar -xzf "$CLANG_TAR" -C "${CLANG_DIR}.tmp"; then
        err "Failed to extract clang tarball"
        exit 1
    fi

    if [[ -f "${CLANG_DIR}.tmp/bin/clang" ]]; then
        info "Found clang in standard bin/ location"
        mv "${CLANG_DIR}.tmp" "$CLANG_DIR"
    else
        local found_bin=$(find "${CLANG_DIR}.tmp" -type d -name "bin" | head -1)
        if [[ -n "$found_bin" ]] && [[ -f "$found_bin/clang" ]]; then
            info "Found bin directory at: $found_bin"
            mv "${CLANG_DIR}.tmp" "$CLANG_DIR"
        else
            err "No clang binary found in extracted structure"
            exit 1
        fi
    fi

    if ! "$CLANG_DIR/bin/clang" --version >/dev/null 2>&1; then
        err "Clang binary verification failed"
        exit 1
    fi

    info "Setting up essential symlinks and checking tools..."

    # HAPUS 'as' dari daftar symlink - kernel butuh GNU as, bukan llvm-as
    declare -A SYMLINKS=(
        ["ld"]="ld.lld"
        ["nm"]="llvm-nm"
        ["objcopy"]="llvm-objcopy"
        ["strip"]="llvm-strip"
        ["objdump"]="llvm-objdump"
        ["ar"]="llvm-ar"
        ["readelf"]="llvm-readelf"
        ["size"]="llvm-size"
        ["strings"]="llvm-strings"
        ["addr2line"]="llvm-addr2line"
    )

    # Hapus symlink as yang salah jika ada
    if [[ -L "$CLANG_DIR/bin/as" ]] && [[ "$(readlink "$CLANG_DIR/bin/as")" == "llvm-as" ]]; then
        rm -f "$CLANG_DIR/bin/as"
        warn "Removed incorrect 'as' symlink to llvm-as"
    fi

    # Buat symlink
    for short in "${!SYMLINKS[@]}"; do
        long="${SYMLINKS[$short]}"
        if [[ -f "$CLANG_DIR/bin/$long" ]] && [[ ! -f "$CLANG_DIR/bin/$short" ]]; then
            ln -sfn "$long" "$CLANG_DIR/bin/$short"
            [[ -f "$CLANG_DIR/bin/$short" ]] && chmod +x "$CLANG_DIR/bin/$short" 2>/dev/null || true
        fi
    done

    # Cek tool esensial
    local essential_tools=(clang clang++ ld.lld llvm-ar)
    local missing_tools=()
    
    for tool in "${essential_tools[@]}"; do
        if [[ ! -x "$CLANG_DIR/bin/$tool" ]]; then
            missing_tools+=("$tool")
        fi
    done
    
    if (( ${#missing_tools[@]} )); then
        warn "Missing essential tools: ${missing_tools[*]}"
        for tool in "${missing_tools[@]}"; do
            if command -v "$tool" >/dev/null 2>&1; then
                info "Found $tool in system PATH"
            fi
        done
    fi

    echo "$CLANG_VER" > "$CLANG_DIR/clang.version"
    
    local version_info=$("$CLANG_DIR/bin/clang" --version | head -n1)
    ok "Clang prepared at: $CLANG_DIR"
    info "Version: $version_info"
}

# -------------------------
# Setup GNU toolchain from Arch Linux (DIPERBAIKI)
# -------------------------
setup_gnu_toolchain() {
    info "Setting up GNU toolchain from Arch Linux packages..."
    
    local gnu_dir="$CACHE_DIR/gnu-tools"
    mkdir -p "$gnu_dir"
    
    # Cek toolchain ARM64
    if ! command -v aarch64-linux-gnu-as >/dev/null 2>&1; then
        err "aarch64-linux-gnu-as not found. Please run: sudo pacman -S aarch64-linux-gnu-binutils aarch64-linux-gnu-gcc"
        return 1
    fi
    
    # Buat symlink untuk aarch64 (64-bit)
    local aarch64_tools=("as" "ld" "objcopy" "objdump" "strip" "nm" "ar" "readelf" "strings" "size" "addr2line" "elfedit")
    
    for tool in "${aarch64_tools[@]}"; do
        local gnu_tool="aarch64-linux-gnu-$tool"
        local android_tool="aarch64-linux-android-$tool"
        
        if command -v "$gnu_tool" >/dev/null 2>&1; then
            ln -sf "$(command -v "$gnu_tool")" "$gnu_dir/$android_tool"
            chmod +x "$gnu_dir/$android_tool" 2>/dev/null || true
        else
            warn "Tool $gnu_tool not found, skipping"
        fi
    done
    
    # Buat symlink generic (tanpa prefix) untuk assembler
    ln -sf "$(command -v aarch64-linux-gnu-as)" "$gnu_dir/as" 2>/dev/null || true
    
    # Cek toolchain ARM (32-bit) - gunakan arm-none-eabi-*
    if command -v arm-none-eabi-as >/dev/null 2>&1; then
        ln -sf "$(command -v arm-none-eabi-as)" "$gnu_dir/arm-linux-androideabi-as"
        ln -sf "$(command -v arm-none-eabi-ld)" "$gnu_dir/arm-linux-androideabi-ld"
        ln -sf "$(command -v arm-none-eabi-objcopy)" "$gnu_dir/arm-linux-androideabi-objcopy"
        ln -sf "$(command -v arm-none-eabi-strip)" "$gnu_dir/arm-linux-androideabi-strip"
        ln -sf "$(command -v arm-none-eabi-ar)" "$gnu_dir/arm-linux-androideabi-ar"
        ln -sf "$(command -v arm-none-eabi-nm)" "$gnu_dir/arm-linux-androideabi-nm"
        ln -sf "$(command -v arm-none-eabi-readelf)" "$gnu_dir/arm-linux-androideabi-readelf"
    else
        warn "ARM 32-bit toolchain not found. If needed, install: sudo pacman -S arm-none-eabi-binutils arm-none-eabi-gcc"
    fi
    
    # Tambah ke PATH
    export PATH="$gnu_dir:$PATH"
    
    ok "GNU toolchain setup complete at $gnu_dir"
    return 0
}

# -------------------------
# Setup PATH, ccache
# -------------------------
prepare_toolchains() {
    info "Setting up toolchains & environment..."
    mkdir -p "$CACHE_DIR"
    
    download_mkdtboimg || warn "mkdtboimg.py setup failed, will use fallback for dtbo"
    
    [[ -f "$CLANG_DIR/clang.version" ]] || prepare_clang
    
    # Setup GNU toolchain dari Arch Linux
    setup_gnu_toolchain || exit 1

    # Tambahkan clang ke PATH
    export PATH="$CLANG_DIR/bin:$PATH"

    if (( USE_CCACHE )); then
        if ! command -v ccache >/dev/null 2>&1; then
            warn "ccache not found; install to enable caching"
        else
            export CCACHE_DIR="${CACHE_DIR}/ccache"
            mkdir -p "$CCACHE_DIR"
            
            export CCACHE_SLOPPINESS="time_macros,include_file_mtime,include_file_ctime,file_stat_matches"
            export CCACHE_COMPRESS=1
            export CCACHE_COMPRESSLEVEL=6
            export CCACHE_MAXSIZE=10G
            
            export CC="ccache clang"
            export HOSTCC="ccache clang"
            export HOSTCXX="ccache clang++"
            
            info "ccache enabled at $CCACHE_DIR"
            ccache -M 5G >/dev/null 2>&1 || true
        fi
    else
        export CC="clang"
        export HOSTCC="clang"
        export HOSTCXX="clang++"
    fi

    info "Toolchain summary:"
    command -v clang >/dev/null 2>&1 && clang --version | head -n 1 || warn "clang not on PATH"
    command -v aarch64-linux-android-as >/dev/null 2>&1 && info "GNU assembler: $(aarch64-linux-android-as --version | head -1)" || warn "GNU assembler not found"
}

# -------------------------
# Check toolchain versions
# -------------------------
check_toolchain_versions() {
    info "Checking toolchain versions..."

    if ! command -v clang >/dev/null 2>&1; then
        err "clang not found in PATH"
        return 1
    fi
    info "clang version: $(clang --version | head -n1)"

    if ! command -v aarch64-linux-android-as >/dev/null 2>&1; then
        warn "aarch64-linux-android-as not found"
    else
        info "GNU assembler: $(aarch64-linux-android-as --version | head -1)"
    fi

    if ! command -v ld.lld >/dev/null 2>&1; then
        warn "ld.lld not found; build may fail"
    else
        info "ld.lld version: $(ld.lld --version 2>&1 | head -n1)"
    fi

    return 0
}

# -------------------------
# Clean source safe
# -------------------------
ensure_clean_source() {
    info "Running make mrproper to reset source tree..."
    make mrproper 2>/dev/null || true
}

# -------------------------
# Clean outdir safely
# -------------------------
clean_output() {
    info "Cleaning old build outputs (safe)..."
    if [[ -d "$OUTDIR" ]]; then
        make O="$OUTDIR" clean 2>/dev/null || true
        rm -rf "$OUTDIR"/{*.img,.config,arch/arm64/boot/*.gz*} 2>/dev/null || true
    fi
}

# -------------------------
# Apply defconfig
# -------------------------
make_defconfig() {
    info "Applying defconfig: $DEFCONFIG"
    make O="$OUTDIR" ARCH=$ARCH "$DEFCONFIG" \
        CC="$CC" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
        CROSS_COMPILE=aarch64-linux-android- \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        AS=aarch64-linux-android-as LD=ld.lld LLVM=1 LLVM_IAS=1 2>&1 | tee -a "$LOGFILE"
    ok "Defconfig applied"
}

# -------------------------
# Compile kernel - AOSP CLANG r547379 (LLVM 20) OPTIMIZED
# -------------------------
compile_kernel() {
    # FIX untuk Arch Linux compatibility
    export CONFIG_SHELL="/bin/bash"
    export SHELL="/bin/bash"
    
    info "Compiling kernel for Poco X3 NFC (Snapdragon 732G) - AOSP CLANG r547379 (LLVM 20) OPTIMIZED"

    
    local KCFLAGS=""
    local KBUILD_LDFLAGS=""
    
    # ARM architecture configuration - TUNED FOR SNAPDRAGON 732G
    local ARM_ARCH_BASE="armv8.2-a"
    local ARM_EXTENSIONS="lse+crypto+dotprod+crc+fp16+rcpc+ssbs+ras+predres"
    local ARM_ARCH_FULL="${ARM_ARCH_BASE}+${ARM_EXTENSIONS}"
    
    info "ARM Architecture: ${ARM_ARCH_FULL}"
    info "ARM Extensions: ${ARM_EXTENSIONS}"
    info "CPU: Snapdragon 732G (Kryo 470 = Cortex-A76 + Cortex-A55)"
    
    # BASE MLLVM FLAGS - REVISED FOR LLVM 20
    local BASE_MLLVM_FLAGS=""
    BASE_MLLVM_FLAGS+=" -mllvm --enable-gvn-hoist"
    BASE_MLLVM_FLAGS+=" -mllvm --enable-loopinterchange"
    BASE_MLLVM_FLAGS+=" -mllvm --aggressive-ext-opt"
    BASE_MLLVM_FLAGS+=" -mllvm --enable-misched"

    # ====================== CPU TUNING CONFIGURATION ======================
    case "$TUNE" in
        cortex-a55)
            info "Tuning for Cortex-A55 LITTLE cores (battery efficiency)..."
            KCFLAGS+=" -pipe -march=${ARM_ARCH_FULL} -mcpu=$TUNE -mtune=$TUNE"
            KCFLAGS+=" -O2 -falign-functions=16 -falign-loops=8"
            KCFLAGS+=" -ftrivial-auto-var-init=zero -fno-plt -fno-pie"
            KCFLAGS+=" -fno-math-errno -fno-trapping-math"
            KCFLAGS+=" -fno-tree-vectorize"

            KCFLAGS+="${BASE_MLLVM_FLAGS}"
            
            KBUILD_LDFLAGS="-fuse-ld=lld"
            KBUILD_LDFLAGS+=" -Wl,--hash-style=gnu"
            KBUILD_LDFLAGS+=" -Wl,--build-id=sha1"
            ;;
            
        cortex-a76)
            info "Tuning for Cortex-A76 big cores (performance focus)..."
            KCFLAGS+=" -pipe -march=${ARM_ARCH_FULL} -mcpu=$TUNE -mtune=$TUNE"
            KCFLAGS+=" -O2 -falign-functions=64 -falign-loops=32"
            KCFLAGS+=" -fomit-frame-pointer -fno-plt -fno-pie"
            KCFLAGS+=" -fno-math-errno -fno-trapping-math"
            KCFLAGS+=" -ftree-vectorize"
            
            KCFLAGS+="${BASE_MLLVM_FLAGS}"

            KBUILD_LDFLAGS="-fuse-ld=lld"
            KBUILD_LDFLAGS+=" -Wl,--hash-style=both"
            KBUILD_LDFLAGS+=" -Wl,--build-id=sha1"
            ;;
            
        default)
            info "Tuning for default CPU (balanced across big.LITTLE)..."
            KCFLAGS+=" -pipe -march=${ARM_ARCH_FULL}"
            KCFLAGS+=" -O2 -falign-functions=32 -falign-loops=16"
            KCFLAGS+=" -ftrivial-auto-var-init=zero"
            KCFLAGS+=" -ftree-vectorize"
            
            KCFLAGS+="${BASE_MLLVM_FLAGS}"

            KBUILD_LDFLAGS="-fuse-ld=lld"
            KBUILD_LDFLAGS+=" -Wl,--hash-style=gnu"
            KBUILD_LDFLAGS+=" -Wl,--build-id=sha1"
            ;;
    esac

    # ====================== COMMON OPTIMIZATION FLAGS ======================
    
    # Basic compiler flags
    KCFLAGS+=" -fintegrated-as"
    KCFLAGS+=" -fno-strict-aliasing"
    KCFLAGS+=" -fno-common"
    KCFLAGS+=" -fno-pic"
    
    # Performance optimizations
    KCFLAGS+=" -ffunction-sections"
    KCFLAGS+=" -fdata-sections"
    KCFLAGS+=" -moutline-atomics" 
    KCFLAGS+=" -g0"
    
    # AOSP Clang r547379 (LLVM 20) specific optimizations
    KCFLAGS+=" -fno-semantic-interposition"
    KCFLAGS+=" -fmerge-all-constants"
    KCFLAGS+=" -foptimize-sibling-calls"
    
    # Runtime library
    KCFLAGS+=" -rtlib=compiler-rt"
    
    # File prefix for reproducible builds
    KCFLAGS+=" -ffile-prefix-map=$(pwd)=."
    
    # ====================== WARNING SUPPRESSIONS ======================
    
    # Error downgrades (harmless)
    KCFLAGS+=" -Wno-error=unused-command-line-argument"
    KCFLAGS+=" -Wno-error=unused-but-set-variable"
    KCFLAGS+=" -Wno-error=unused-const-variable"
    KCFLAGS+=" -Wno-error=ignored-optimization-argument"
    
    # Warning suppressions (non-critical tapi harmless)
    KCFLAGS+=" -Wno-unused-but-set-variable"
    KCFLAGS+=" -Wno-unused-variable"
    KCFLAGS+=" -Wno-unused-function"
    KCFLAGS+=" -Wno-unused-parameter"
    KCFLAGS+=" -Wno-implicit-fallthrough"
    KCFLAGS+=" -Wno-missing-field-initializers"
    KCFLAGS+=" -Wno-type-limits"
    KCFLAGS+=" -Wno-sign-compare"
    KCFLAGS+=" -Wno-format-overflow"
    KCFLAGS+=" -Wno-format-truncation"
    KCFLAGS+=" -Wno-misleading-indentation"
    KCFLAGS+=" -Wno-address-of-packed-member"
    KCFLAGS+=" -Wno-int-in-bool-context"
    KCFLAGS+=" -Wno-tautological-constant-out-of-range-compare"
    KCFLAGS+=" -Wno-tautological-compare"
    KCFLAGS+=" -Wno-deprecated-declarations"
    KCFLAGS+=" -Wno-enum-conversion"
    KCFLAGS+=" -Wno-bool-operation"
    
    # ====================== LINKER OPTIMIZATIONS ======================
    
    # Common linker flags for all profiles
    KBUILD_LDFLAGS+=" -Wl,--no-undefined"
    KBUILD_LDFLAGS+=" -Wl,--sort-common"
    KBUILD_LDFLAGS+=" -Wl,--compress-debug-sections=zlib"
    KBUILD_LDFLAGS+=" -Wl,--strip-debug"
    KBUILD_LDFLAGS+=" -Wl,--gc-sections"
    KBUILD_LDFLAGS+=" -Wl,--icf=safe"
    KBUILD_LDFLAGS+=" -Wl,--pack-dyn-relocs=relr"
    KBUILD_LDFLAGS+=" -Wl,-z,noexecstack"
    KBUILD_LDFLAGS+=" -Wl,--warn-common"
    KBUILD_LDFLAGS+=" -Wl,--no-undefined-version"
    KBUILD_LDFLAGS+=" -Wl,--orphan-handling=warn"
    
    # Page size optimizations
    KBUILD_LDFLAGS+=" -z max-page-size=4096"
    KBUILD_LDFLAGS+=" -z common-page-size=4096"
    
    # Additional optimizations
    KBUILD_LDFLAGS+=" -Wl,-O2"
    KBUILD_LDFLAGS+=" -Wl,--as-needed"
    KBUILD_LDFLAGS+=" -Wl,--sort-section=alignment"
    KBUILD_LDFLAGS+=" -Wl,-z,nodlopen"
    
    # CRITICAL: Link compiler-rt untuk runtime functions support
    KBUILD_LDFLAGS+=" -lcompiler_rt"

    KBUILD_LDFLAGS+=" -z separate-code"
    KBUILD_LDFLAGS+=" -z relro -z now"
    
    export KCFLAGS
    export KBUILD_LDFLAGS

    # ====================== BUILD ENVIRONMENT ======================
    
    # Export environment variables
    export ARCH="$ARCH"
    export SUBARCH="$SUBARCH"
    export KBUILD_BUILD_USER="$BUILD_USER"
    export KBUILD_BUILD_HOST="$BUILD_HOST"
    export KBUILD_BUILD_TIMESTAMP="$(get_kernel_timestamp)"

    # Toolchain configuration - AOSP Clang r547379
    export CROSS_COMPILE=aarch64-linux-android-
    export CROSS_COMPILE_ARM32=arm-linux-androideabi-
    export CLANG_TRIPLE=aarch64-linux-gnu-
    export LD=ld.lld
    export AS=aarch64-linux-android-as  # FIX: GUNAKAN GNU as, BUKAN llvm-as
    export NM=llvm-nm
    export OBJCOPY=llvm-objcopy
    export STRIP=llvm-strip
    export OBJDUMP=llvm-objdump
    export LLVM=1
    export LLVM_IAS=1
    
    # Additional LLVM tools
    export READELF=llvm-readelf
    export OBJSIZE=llvm-size
    
    # CC already set in prepare_toolchains (with or without ccache)
    export CC="${CC:-clang}"
    export HOSTCC="${HOSTCC:-clang}"
    export HOSTCXX="${HOSTCXX:-clang++}"

    # LLVM 20 specific environment untuk AOSP Clang r547379
    export LLVM_AR=llvm-ar
    export LLVM_DIS=llvm-dis
    export LLVM_NM=llvm-nm
    export LLVM_OBJCOPY=llvm-objcopy
    export LLVM_OBJDUMP=llvm-objdump
    export LLVM_STRIP=llvm-strip
    export LLVM_READELF=llvm-readelf
    export LLVM_SIZE=llvm-size

    # Parallel build configuration
    if [ -z "${MAKE_PROCS}" ]; then
        MAKE_PROCS=$(nproc)
        MAKE_PROCS=$((MAKE_PROCS * 4 / 5))
        [ $MAKE_PROCS -lt 2 ] && MAKE_PROCS=2
        [ $MAKE_PROCS -gt 12 ] && MAKE_PROCS=12
        info "Auto-set MAKE_PROCS to ${MAKE_PROCS}"
    fi

    export MAKEFLAGS="-j${MAKE_PROCS} --output-sync=target"
    
    info "CPU Tuning: $TUNE"
    info "Parallel jobs: ${MAKE_PROCS}"
    info "Toolchain: AOSP Clang r547379 (LLVM 20.0.0) - Android 16/Mainline"
    
    # Build environment
    export KBUILD_CHECKSRC=0
    export KBUILD_VERBOSE=0
    export KCONFIG_CONFIG=".config"
    export HOSTLDFLAGS=""
    export HOST_LOADLIBES=""
    export MAKE="make"
    export AWK="awk"
    export GENKSYMS="scripts/genksyms/genksyms"
    export INSTALLKERNEL="installkernel"
    export DEPMOD="/sbin/depmod"
    export PERL="perl"
    export PYTHON="python3"
    export CHECK="sparse"
    export CHECKFLAGS="-D__linux__ -Dlinux -D__STDC__ -Dunix -D__unix__ -Wbitwise -Wno-return-void"
    
    # Get clang include path
    local clang_include_path
    if command -v clang >/dev/null 2>&1; then
        clang_include_path=$(clang -print-file-name=include 2>/dev/null || echo '/usr/include')
    else
        clang_include_path='/usr/include'
    fi
    export NOSTDINC_FLAGS="-nostdinc -isystem $clang_include_path"

    # Explicitly set compiler string for AOSP Clang r547379
    export KBUILD_COMPILER_STRING="AOSP Clang r547379 (LLVM 20.0.0)"
    
    info "Compiler: $KBUILD_COMPILER_STRING"
    info "Architecture: ${ARCH} (${SUBARCH})"
    info "Note: This toolchain is used for Android 16 and Mainline kernel builds"
    
    # Show ccache stats before build if active
    if (( USE_CCACHE )) && command -v ccache >/dev/null 2>&1; then
        info "ccache stats before build:"
        local ccache_stats_before
        ccache_stats_before=$(ccache -s 2>/dev/null | grep -E "cache hit|cache miss|files in cache" || true)
        if [[ -n "$ccache_stats_before" ]]; then
            echo "$ccache_stats_before"
        else
            info "No ccache stats available"
        fi
    fi

    # ====================== BUILD EXECUTION ======================
    local build_start=$(date +%s)
    local log_file="${OUTDIR}/build_${TUNE}_$(date +%Y%m%d_%H%M%S).log"
    
    mkdir -p "$OUTDIR"

    info "Building vmlinux..."
    
    # Debug: Tampilkan info tentang optimisasi yang digunakan
    info "Using optimization profile: $TUNE"
    if [ "$TUNE" = "cortex-a55" ] || [ "$TUNE" = "cortex-a76" ]; then
        info "Optimization strategy: BASE MLLVM (default) + EXTRA for $TUNE"
    else
        info "Optimization strategy: BASE MLLVM only (proven stable)"
    fi

    # Test compiler dulu
    info "Testing compiler..."
    if ! ${CC} --version >/dev/null 2>&1; then
        error "Compiler ${CC} not found or not executable!"
        return 1
    fi

    # Run Make for vmlinux - TANGANI ERROR DENGAN BAIK
    if ! time make O="$OUTDIR" \
        CC="$CC" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
        LD="$LD" AS="$AS" NM="$NM" OBJCOPY="$OBJCOPY" STRIP="$STRIP" \
        KCFLAGS="$KCFLAGS" \
        KBUILD_LDFLAGS="$KBUILD_LDFLAGS" \
        vmlinux 2>&1 | tee "$log_file"
    then
        error "vmlinux compilation failed!"
        
        # Analisis error lebih detail
        if grep -q "correlated-propagation" "$log_file"; then
            warning "Compiler crash di pass 'correlated-propagation'"
            warning "Mungkin ada flag mllvm yang bermasalah"
        fi
        if grep -q "Exit code 139" "$log_file"; then
            warning "Segmentation fault (139) - compiler crash"
        fi
        
        # Tampilkan error terakhir
        tail -20 "$log_file" | grep -A5 -B5 -i "error\|fatal\|crash"
        
        return 1
    fi

    local compile_time=$(($(date +%s) - build_start))
    ok "vmlinux built in ${compile_time}s"
    
    # Show ccache stats after vmlinux if active
    if (( USE_CCACHE )) && command -v ccache >/dev/null 2>&1; then
        info "ccache stats after vmlinux:"
        local ccache_stats_mid
        ccache_stats_mid=$(ccache -s 2>/dev/null | grep -E "cache hit|cache miss" || true)
        if [[ -n "$ccache_stats_mid" ]]; then
            echo "$ccache_stats_mid"
        fi
    fi

    # Build modules if enabled
    local kernel_config="$OUTDIR/.config"
    if [ -f "$kernel_config" ] && grep -q "CONFIG_MODULES=y" "$kernel_config"; then
        info "Building kernel modules..."
        if ! make O="$OUTDIR" \
            CC="$CC" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
            KCFLAGS="$KCFLAGS" KBUILD_LDFLAGS="$KBUILD_LDFLAGS" \
            modules 2>&1 | tee -a "$log_file"
        then
            error "Module compilation failed!"
            tail -10 "$log_file"
            return 1
        fi
        ok "Modules built successfully"
    fi

    # Generate compressed kernel image
    info "Generating Image.gz-dtb..."
    local image_start=$(date +%s)

    if ! make O="$OUTDIR" ARCH="$ARCH" \
          CC="$CC" HOSTCC="$HOSTCC" HOSTCXX="$HOSTCXX" \
          KCFLAGS="$KCFLAGS" KBUILD_LDFLAGS="$KBUILD_LDFLAGS" \
          Image.gz-dtb 2>&1 | tee -a "$log_file"
    then
        error "Image.gz-dtb generation failed!"
        return 1
    fi

    local image_time=$(($(date +%s) - image_start))
    ok "Image.gz-dtb generated in ${image_time}s"

    # ====================== BUILD SUMMARY ======================
    local total_time=$(($(date +%s) - build_start))
    local image_path="$OUTDIR/arch/arm64/boot/Image.gz-dtb"
    local vmlinux_path="$OUTDIR/vmlinux"

    if [[ -f "$image_path" ]] && [[ -f "$vmlinux_path" ]]; then
        local image_size=$(stat -c%s "$image_path" 2>/dev/null || echo 0)
        local vmlinux_size=$(stat -c%s "$vmlinux_path" 2>/dev/null || echo 0)

        format_size() {
            local size=$1
            if command -v numfmt >/dev/null 2>&1; then
                numfmt --to=iec-i --suffix=B $size
            else
                echo "$size bytes"
            fi
        }
        
        info "=== Build Summary ==="
        info "Build time: ${total_time}s"
        info "Compiler: $KBUILD_COMPILER_STRING"
        info "Toolchain: AOSP Clang r547379 (LLVM 20.0.0)"
        info "CPU Tuning: $TUNE"
        info "Optimization: BASE MLLVM"$( [ "$TUNE" != "default" ] && echo " + EXTRA for $TUNE" )
        info "Output: $image_path"
        info "Image size: $(format_size $image_size)"
        info "vmlinux size: $(format_size $vmlinux_size)"

        if [ $image_size -gt 0 ] && [ $vmlinux_size -gt 0 ]; then
            local compression_ratio=$((image_size * 100 / vmlinux_size))
            info "Compression ratio: ${compression_ratio}%"

            if [ $compression_ratio -lt 30 ]; then
                warning "Very high compression ratio - check for debug symbols"
            fi
        fi
        
        local warning_count=$(grep -c "warning:" "$log_file" 2>/dev/null || echo 0)
        local error_count=$(grep -c "error:" "$log_file" 2>/dev/null || echo 0)
        
        info "Build log: $log_file"
        info "Warnings: $warning_count | Errors: $error_count"
        
        # Show critical warning categories
        if [ $warning_count -gt 0 ]; then
            info "=== Critical Warning Categories ==="
            grep "warning:" "$log_file" | grep -i -E "overflow|bounds|uninitialized|leak" | head -5 | while read line; do
                warning "⚠ $line"
            done
        fi
        
        # Show final ccache stats if active
        if (( USE_CCACHE )) && command -v ccache >/dev/null 2>&1; then
            info "=== CCache Stats ==="
            ccache -s 2>/dev/null | tail -10 || info "Could not get ccache stats"
        fi

        ok "Kernel build successful! (AOSP Clang r547379 LLVM 20 Optimized)"
        info "This toolchain is production-ready for Android 16 and Mainline kernels"
        return 0  # KEMBALIKAN 0 untuk sukses
    else
        error "Build completed but Image.gz-dtb not found!"
        return 1
    fi
}

# -------------------------
# Build DTB & DTBO - DIPERBAIKI
# -------------------------
build_dtb_dtbo() {
    info "Building DTB & DTBO images..."
    
    # Cari file DTB di lokasi yang umum
    local dtb_outdir="$OUTDIR/arch/arm64/boot/dts/qcom"
    
    if [ -d "$dtb_outdir" ]; then
        info "Looking for DTB files in: $dtb_outdir"
        shopt -s nullglob
        local dtb_list=("$dtb_outdir"/*.dtb)
        
        if [ ${#dtb_list[@]} -gt 0 ] && [ -f "${dtb_list[0]}" ]; then
            info "Found ${#dtb_list[@]} DTB files"
            cat "${dtb_list[@]}" > "$OUTDIR/dtb.img" 2>/dev/null
            local dtb_size=$(stat -c%s "$OUTDIR/dtb.img" 2>/dev/null || echo 0)
            ok "Created dtb.img (${dtb_size} bytes)"
        else
            warn "No .dtb files found in $dtb_outdir"
            : > "$OUTDIR/dtb.img"
        fi
        shopt -u nullglob
    else
        warn "DTB directory not found: $dtb_outdir"
        : > "$OUTDIR/dtb.img"
    fi
    
    # Cari file DTBO
    info "Looking for DTBO files..."
    shopt -s nullglob
    local dtbo_list=("$dtb_outdir"/*.dtbo)
    if [ ${#dtbo_list[@]} -gt 0 ] && [ -f "${dtbo_list[0]}" ]; then
        info "Found ${#dtbo_list[@]} DTBO files"
        
        if [[ -f "$MKDTBOIMG_SCRIPT" ]] && command -v python3 >/dev/null 2>&1; then
            info "Creating dtbo.img using Google's mkdtboimg.py..."
            if python3 "$MKDTBOIMG_SCRIPT" create "$OUTDIR/dtbo.img" "${dtbo_list[@]}" 2>/dev/null; then
                local dtbo_size=$(stat -c%s "$OUTDIR/dtbo.img" 2>/dev/null || echo 0)
                ok "Created dtbo.img using mkdtboimg.py (${dtbo_size} bytes)"
            else
                warn "mkdtboimg.py failed; using fallback method"
                cat "${dtbo_list[@]}" > "$OUTDIR/dtbo.img" 2>/dev/null || : > "$OUTDIR/dtbo.img"
            fi
        else
            warn "mkdtboimg.py not found; using fallback method"
            cat "${dtbo_list[@]}" > "$OUTDIR/dtbo.img" 2>/dev/null || : > "$OUTDIR/dtbo.img"
        fi
    else
        warn "No .dtbo files found"
        : > "$OUTDIR/dtbo.img"
    fi
    shopt -u nullglob
}

# -------------------------
# Save .config snapshot
# -------------------------
save_config_snapshot() {
    if [[ -f "$OUTDIR/.config" ]]; then
        cp "$OUTDIR/.config" "build-artifacts/${DEFCONFIG}.snapshot"
        ok "Saved .config snapshot"
    fi
}

# -------------------------
# Package AnyKernel3 (SIMPLE VERSION)
# -------------------------
package_anykernel() {
    info "Packaging AnyKernel3..."
    local akdir="AnyKernel3"
    
    # Coba clone branch Farewell, jika gagal, coba main/master
    if [[ ! -d "$akdir" ]]; then
        info "Cloning AnyKernel3 repository..."
        if ! git clone --depth=1 https://github.com/fannndi/Kernel_Zip -b Farewell "$akdir" 2>/dev/null; then
            warn "Failed to clone from branch Farewell, trying default branch..."
            if ! git clone --depth=1 https://github.com/fannndi/Kernel_Zip "$akdir" 2>/dev/null; then
                err "Failed to clone AnyKernel3 repository. Please check your network connection or the repository URL."
                return 1
            fi
        fi
        ok "AnyKernel3 repository cloned successfully"
    else
        info "Using existing AnyKernel3 directory"
    fi

    # Salin kernel images ke AnyKernel3 directory
    if [[ -f "$OUTDIR/arch/arm64/boot/Image.gz-dtb" ]]; then
        cp "$OUTDIR/arch/arm64/boot/Image.gz-dtb" "$akdir/"
        ok "Copied Image.gz-dtb to AnyKernel3"
    else
        warn "Image.gz-dtb not found; trying alternative kernel images"
        local found_kernel=false
        
        if [[ -f "$OUTDIR/arch/arm64/boot/Image" ]]; then
            cp "$OUTDIR/arch/arm64/boot/Image" "$akdir/"
            info "Copied Image to AnyKernel3"
            found_kernel=true
        fi
        
        if [[ -f "$OUTDIR/arch/arm64/boot/zImage" ]]; then
            cp "$OUTDIR/arch/arm64/boot/zImage" "$akdir/"
            info "Copied zImage to AnyKernel3"
            found_kernel=true
        fi
        
        if [[ "$found_kernel" == false ]]; then
            err "No kernel image found in $OUTDIR/arch/arm64/boot/"
            return 1
        fi
    fi

    # Salin dtb.img dan dtbo.img jika ada
    if [[ -f "$OUTDIR/dtb.img" ]]; then
        cp "$OUTDIR/dtb.img" "$akdir/"
        info "Copied dtb.img to AnyKernel3"
    else
        warn "dtb.img not found"
    fi
    
    if [[ -f "$OUTDIR/dtbo.img" ]]; then
        cp "$OUTDIR/dtbo.img" "$akdir/"
        info "Copied dtbo.img to AnyKernel3"
    else
        warn "dtbo.img not found"
    fi

    # Buat zip file
    info "Creating zip package: $ZIPNAME"
    
    # DEBUG: Tampilkan direktori saat ini
    debug "Current directory: $(pwd)"
    debug "AnyKernel3 directory: $akdir"
    debug "Zip target: $ZIPNAME"
    
    # Masuk ke direktori AnyKernel3
    cd "$akdir"
    
    # Buat zip
    zip -r9 "../$ZIPNAME" ./* -x ".git/*" "*.git*" 2>&1 | while read line; do
        debug "zip: $line"
    done
    
    local zip_result=$?
    
    # Kembali ke direktori root
    cd ..
    
    # DEBUG: Cek file yang dibuat
    debug "Files in current directory after zip:"
    ls -la *.zip 2>/dev/null || debug "No zip files found"
    
    # Perbaiki pengecekan - gunakan nama file langsung (bukan ../)
    if [[ $zip_result -eq 0 ]] && [[ -f "$ZIPNAME" ]]; then
        local zip_size=$(stat -c%s "$ZIPNAME" 2>/dev/null || echo 0)
        if command -v numfmt >/dev/null 2>&1; then
            zip_size_fmt=$(numfmt --to=iec-i --suffix=B $zip_size)
        else
            zip_size_fmt="${zip_size} bytes"
        fi
        ok "Packaged kernel zip: $ZIPNAME (${zip_size_fmt})"
        debug "Zip path: $(pwd)/$ZIPNAME"
        return 0
    else
        # Coba cari zip dengan pattern
        local found_zip=$(find . -maxdepth 1 -name "*.zip" -type f 2>/dev/null | head -1)
        if [[ -n "$found_zip" ]]; then
            warn "Found zip but with different name: $found_zip"
            if [[ "$found_zip" != "$ZIPNAME" ]]; then
                mv "$found_zip" "$ZIPNAME" && ok "Renamed to $ZIPNAME"
                return 0
            fi
        fi
        err "Failed to create zip package (exit code: $zip_result)"
        return 1
    fi
}

# -------------------------
# Main build flow with debug - DIPERBAIKI
# -------------------------
main() {
    require_tools
    prepare_toolchains
    
    # Debug toolchain information
    debug_toolchain
    
    # Check toolchain versions
    if ! check_toolchain_versions; then
        err "Toolchain check failed!"
        exit 1
    fi
    
    ensure_clean_source
    clean_output
    make_defconfig
    
    # Gunakan subshell untuk compile_kernel agar tidak exit script
    (
        set +e  # Nonaktifkan exit on error dalam subshell
        compile_kernel
        local kernel_result=$?
        set -e  # Aktifkan kembali
        return $kernel_result
    )
    local kernel_result=$?
    
    if [ $kernel_result -eq 0 ]; then
        info "Kernel compilation successful, proceeding to DTB/DTBO..."
        build_dtb_dtbo
        save_config_snapshot
        package_anykernel
        local duration=$(( $(date +%s) - BUILD_START ))
        ok "Build completed in $(($duration / 60)) min $(( $duration % 60 )) sec"
    else
        err "Kernel compilation failed, skipping DTB/DTBO and packaging"
        exit 1
    fi
}

main "$@"
