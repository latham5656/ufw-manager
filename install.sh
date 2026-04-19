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
    echo -e "${R}❌ Ошибка: запустите от имени root: sudo bash install.sh${NC}" >&2
    exit 1
fi

if [[ ! -f "$SCRIPT_SRC" ]]; then
    echo -e "${R}❌ Ошибка: файл ufw-manager.sh не найден в $SCRIPT_DIR${NC}" >&2
    exit 1
fi

echo -e "${Y}⚙️  Устанавливаю UFW Manager...${NC}\n"

# Создать директорию данных
mkdir -p "$DATA_DIR"
echo -e "  ${G}✅${NC} Создана директория: $DATA_DIR"

# Установить скрипт
cp "$SCRIPT_SRC" "$INSTALL_PATH"
chmod +x "$INSTALL_PATH"
echo -e "  ${G}✅${NC} Скрипт установлен в: $INSTALL_PATH"

echo -e "\n${G}🎉 Установка завершена!${NC}"
echo -e "Откройте меню командой: ${W}sudo ufw${NC}"
echo -e "Стандартные команды (${W}sudo ufw status${NC} и др.) работают как прежде.\n"
