#!/bin/bash
set -euo pipefail

START=$(date +%s)

DEFCONFIG=arch/arm64/configs/surya_defconfig
OUT_DIR=out

# Warna
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
NC='\033[0m'

# Pastikan make tersedia
command -v make >/dev/null || { echo -e "${RED}❌ 'make' not found!${NC}"; exit 1; }

# Hapus semua backup defconfig lama
echo -e "${YEL}🧹 Cleaning old .bak files...${NC}"
find arch/arm64/configs -name "*.bak.*" -type f -delete

# Bersihkan direktori out/
echo -e "${YEL}🧹 Cleaning $OUT_DIR/...${NC}"
rm -rf "$OUT_DIR"

# Buat .config dari defconfig
echo -e "${YEL}📁 Generating .config from $DEFCONFIG...${NC}"
make -s O="$OUT_DIR" ARCH=arm64 "$(basename "$DEFCONFIG")"

# Jalankan olddefconfig untuk sync
echo -e "${YEL}🔄 Running olddefconfig...${NC}"
make -s O="$OUT_DIR" ARCH=arm64 olddefconfig

# Bandingkan dan tampilkan diff
echo -e "${YEL}🔍 Diff between old and new defconfig:${NC}"
if diff -u "$DEFCONFIG" "$OUT_DIR/.config"; then
  echo -e "${GRN}✅ No changes detected in defconfig.${NC}"
else
  BACKUP="$DEFCONFIG.bak.$(date +%s)"
  cp "$DEFCONFIG" "$BACKUP"
  echo -e "${YEL}🛡️  Backup saved: $BACKUP${NC}"

  cp "$OUT_DIR/.config" "$DEFCONFIG"
  echo -e "${GRN}✅ Defconfig replaced with new .config${NC}"
fi

# Tambahkan out/ ke .gitignore jika belum ada
if [[ ! -f .gitignore ]] || ! grep -Fxq "$OUT_DIR/" .gitignore; then
  echo "$OUT_DIR/" >> .gitignore
  echo -e "${GRN}📌 '$OUT_DIR/' added to .gitignore${NC}"
fi

# Hapus direktori out/
echo -e "${YEL}🧽 Cleaning $OUT_DIR/...${NC}"
rm -rf "$OUT_DIR"

END=$(date +%s)
echo -e "${GRN}⏱️ Finished in $((END - START))s.${NC}"
