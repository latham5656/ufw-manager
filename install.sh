#!/bin/bash
# UFW Manager — Installer

set -euo pipefail

INSTALL_PATH="/usr/local/bin/ufw"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_SRC="$SCRIPT_DIR/ufw-manager.sh"
DATA_DIR="/etc/ufw-manager"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
W='\033[1;37m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${R}Error: run as root: sudo bash install.sh${NC}" >&2
    exit 1
fi

if [[ ! -f "$SCRIPT_SRC" ]]; then
    echo -e "${R}Error: ufw-manager.sh not found in $SCRIPT_DIR${NC}" >&2
    exit 1
fi

echo -e "${Y}Installing UFW Manager...${NC}\n"

# Create data directory
mkdir -p "$DATA_DIR"
echo -e "  ${G}✓${NC} Created data directory: $DATA_DIR"

# Install script
cp "$SCRIPT_SRC" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo -e "  ${G}✓${NC} Installed to: $INSTALL_PATH"

echo -e "\n${G}Installation complete!${NC}"
echo -e "Run ${W}sudo ufw${NC} to open the interactive menu."
echo -e "Run ${W}sudo ufw status${NC} etc. to use ufw normally (passthrough).\n"
