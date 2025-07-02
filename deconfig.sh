#!/bin/bash

set -euo pipefail

DEFCONFIG=arch/arm64/configs/surya_defconfig
BACKUP=${DEFCONFIG}.bak.$(date +%s)

# Warna
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
NC='\033[0m'

# Step 0: Bersihkan out/
echo -e "${YEL}🧹 Cleaning out/ directory...${NC}"
rm -rf out/

# Step 1: Generate .config dari defconfig
echo -e "${YEL}📁 Generating .config from $DEFCONFIG...${NC}"
make -s O=out ARCH=arm64 surya_defconfig

# Step 2: Update config terhadap Kconfig baru
echo -e "${YEL}🔄 Running olddefconfig to refresh with latest Kconfig...${NC}"
make -s O=out ARCH=arm64 olddefconfig

# Step 3: Backup lama
cp "$DEFCONFIG" "$BACKUP"
echo -e "${YEL}🛡️  Backup created: $BACKUP${NC}"

# Step 4: Salin hasil final ke defconfig
cp out/.config "$DEFCONFIG"
echo -e "${GRN}✅ $DEFCONFIG updated from .config.${NC}"

# Step 5: Tambahkan out/ ke .gitignore jika belum ada
if [[ ! -f .gitignore ]] || ! grep -Fxq "out/" .gitignore; then
  echo "out/" >> .gitignore
  echo -e "${GRN}📌 out/ added to .gitignore${NC}"
fi

# Step 6: Bersihkan out/ setelah selesai
echo -e "${YEL}🧽 Cleaning up out/ directory...${NC}"
rm -rf out/
