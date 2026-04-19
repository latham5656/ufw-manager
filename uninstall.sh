#!/bin/bash
# UFW Manager — Uninstaller

set -euo pipefail

INSTALL_PATH="/usr/local/bin/ufw"
DATA_DIR="/etc/ufw-manager"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${R}Error: run as root: sudo bash uninstall.sh${NC}" >&2
    exit 1
fi

echo -e "${Y}Uninstalling UFW Manager...${NC}\n"

if [[ -f "$INSTALL_PATH" ]]; then
    rm -f "$INSTALL_PATH"
    echo -e "  ${G}✓${NC} Removed $INSTALL_PATH"
else
    echo -e "  ${Y}!${NC} $INSTALL_PATH not found, skipping"
fi

echo ""
read -rp "  Remove descriptions data ($DATA_DIR)? [y/N]: " confirm
if [[ "${confirm,,}" == "y" ]]; then
    rm -rf "$DATA_DIR"
    echo -e "  ${G}✓${NC} Removed $DATA_DIR"
fi

echo -e "\n${G}Uninstalled successfully.${NC}\n"
