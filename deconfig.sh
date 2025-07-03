#!/bin/bash
set -euo pipefail

START=$(date +%s)

DEFCONFIG=arch/arm64/configs/surya_defconfig
BACKUP=${DEFCONFIG}.bak.$(date +%s)
OUT_DIR=out
DRY_RUN=0
KEEP_OUT=0
LOG_FILE=config_changes.log

# Warna
RED='\033[0;31m'
GRN='\033[0;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
NC='\033[0m'

# Argument parsing
for arg in "$@"; do
  case $arg in
    --dry-run) DRY_RUN=1 ;;
    --keep-out) KEEP_OUT=1 ;;
    --help)
      echo -e "${YEL}Usage: $0 [--dry-run] [--keep-out]${NC}"
      exit 0
      ;;
    *) echo -e "${RED}❌ Unknown option: $arg${NC}"; exit 1 ;;
  esac
done

[[ -f "$DEFCONFIG" ]] || { echo -e "${RED}❌ Defconfig not found: $DEFCONFIG${NC}"; exit 1; }

command -v make >/dev/null || { echo -e "${RED}❌ 'make' not found!${NC}"; exit 1; }

echo -e "${YEL}🧹 Cleaning $OUT_DIR/ directory...${NC}"
rm -rf "$OUT_DIR"

echo -e "${YEL}📁 Generating .config from $DEFCONFIG...${NC}"
make -s O="$OUT_DIR" ARCH=arm64 "$(basename "$DEFCONFIG")"

echo -e "${YEL}🔄 Running olddefconfig to refresh config...${NC}"
make -s O="$OUT_DIR" ARCH=arm64 olddefconfig

echo -e "${YEL}🛡️  Backup: $BACKUP${NC}"
cp "$DEFCONFIG" "$BACKUP"

echo -e "${BLU}🔍 Analyzing configuration changes...${NC}"
diff -u "$DEFCONFIG" "$OUT_DIR/.config" | grep -E '^\+CONFIG|^-CONFIG' > "$LOG_FILE" || true

if [[ -s $LOG_FILE ]]; then
  echo -e "${YEL}📋 Config changes detected:${NC}"
  while IFS= read -r line; do
    if [[ $line == +CONFIG* ]]; then
      echo -e "${GRN}${line}${NC}"
    elif [[ $line == -CONFIG* ]]; then
      echo -e "${RED}${line}${NC}"
    fi
  done < "$LOG_FILE"
else
  echo -e "${GRN}✅ No changes in config.${NC}"
fi

echo -e "${YEL}📄 Updating $DEFCONFIG...${NC}"
if [[ $DRY_RUN -eq 1 ]]; then
  echo -e "${YEL}💡 Dry run enabled. Changes not saved.${NC}"
else
  cp "$OUT_DIR/.config" "$DEFCONFIG"
  echo -e "${GRN}✅ Defconfig updated.${NC}"
fi

# Tambahkan out/ ke .gitignore
if [[ ! -f .gitignore ]] || ! grep -Fxq "$OUT_DIR/" .gitignore; then
  echo "$OUT_DIR/" >> .gitignore
  echo -e "${GRN}📌 $OUT_DIR/ added to .gitignore${NC}"
fi

# Cleanup jika tidak pakai --keep-out
if [[ $KEEP_OUT -eq 0 ]]; then
  echo -e "${YEL}🧽 Cleaning $OUT_DIR/...${NC}"
  rm -rf "$OUT_DIR"
else
  echo -e "${YEL}📦 Keeping $OUT_DIR/ as requested.${NC}"
fi

END=$(date +%s)
echo -e "${GRN}⏱️ Finished in $((END - START))s.${NC}"
echo -e "${BLU}📄 Log saved to ${LOG_FILE}${NC}"
