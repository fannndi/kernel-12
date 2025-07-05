#!/usr/bin/env bash

# 📦 Kernel Build Dependencies Installer (v2.6)
# Cocok untuk Gitpod, VPS, atau WSL
# By Fannndi & ChatGPT

set -euo pipefail

# Warna untuk output terminal
GREEN='\033[1;32m'
RED='\033[1;31m'
BLUE='\033[1;34m'
NC='\033[0m'

# =============== DETEKSI SISTEM ===============
echo -e "${BLUE}🔍 Mendeteksi sistem build...${NC}"
ARCH=$(uname -m)
DISTRO=$(lsb_release -ds 2>/dev/null || grep -oP '(?<=^NAME=).+' /etc/os-release | tr -d '"')
echo -e "${BLUE}🖥️  Arsitektur: ${GREEN}${ARCH}${NC}"
echo -e "${BLUE}🧩 Distro: ${GREEN}${DISTRO}${NC}"

# =============== CEK AKSES SUDO ===============
if ! command -v sudo >/dev/null 2>&1; then
  echo -e "${RED}❌ 'sudo' tidak tersedia. Harap jalankan skrip sebagai root atau install sudo.${NC}"
  exit 1
fi

# =============== UPDATE & INSTALL ===============
echo -e "${BLUE}🔄 Memperbarui indeks paket...${NC}"
sudo apt-get update -y

echo -e "${BLUE}🔧 Menginstal build-essential...${NC}"
sudo apt-get install -y build-essential

echo -e "${BLUE}📦 Menginstal semua dependencies...${NC}"
DEPS=(
  # Core build tools
  bc bison flex libssl-dev libelf-dev libncurses5-dev libncursesw5-dev
  libzstd-dev device-tree-compiler curl wget git zip unzip rsync lz4 jq

  # Python & scripting
  python3 python3-pip python-is-python3 python2

  # Compression & packaging
  nano pigz cpio zstd xz-utils liblz4-tool

  # Compiler toolchain
  clang llvm gcc-aarch64-linux-gnu gcc-arm-linux-gnueabi

  # Dev & dtbo
  libudev-dev libfdt-dev

  # Optional tools
  ccache kmod ninja-build patchutils binutils

  # Others
  lsb-release openssl
)

if ! sudo apt-get install -y "${DEPS[@]}"; then
  echo -e "${RED}❌ Gagal menginstal satu atau lebih paket. Periksa koneksi atau sumber APT.${NC}"
  exit 1
fi

# =============== VERIFIKASI TOOLS ===============
echo -e "${BLUE}🔍 Memverifikasi tools penting...${NC}"
REQUIRED_TOOLS=(bc make curl git zip python3 clang lz4 zstd)

for tool in "${REQUIRED_TOOLS[@]}"; do
  if ! command -v "$tool" &>/dev/null; then
    echo -e "${RED}❌ Tool '${tool}' tidak ditemukan setelah instalasi.${NC}"
    exit 1
  fi
done

# =============== CLEANUP ===============
echo -e "${BLUE}🧹 Membersihkan cache APT...${NC}"
sudo apt-get autoremove -y
sudo apt-get clean

echo -e "${GREEN}✅ Semua dependencies berhasil diinstal dan diverifikasi!${NC}"
