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
    echo -e "${R}❌ Ошибка: запустите от имени root: sudo bash uninstall.sh${NC}" >&2
    exit 1
fi

echo -e "${Y}🗑️  Удаляю UFW Manager...${NC}\n"

if [[ -f "$INSTALL_PATH" ]]; then
    rm -f "$INSTALL_PATH"
    echo -e "  ${G}✅${NC} Удалён файл $INSTALL_PATH"
else
    echo -e "  ${Y}⚠️ ${NC} $INSTALL_PATH не найден, пропускаю"
fi

echo ""
read -rp "  Удалить сохранённые описания ($DATA_DIR)? [y/N]: " confirm
if [[ "${confirm,,}" == "y" ]]; then
    rm -rf "$DATA_DIR"
    echo -e "  ${G}✅${NC} Удалена директория $DATA_DIR"
fi

echo -e "\n${G}✅ UFW Manager успешно удалён.${NC}\n"
