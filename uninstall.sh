#!/bin/bash
# UFW Manager — Удаление

OPT_DIR="/opt/ufw-manager"
INSTALL_BIN="/usr/local/bin/ufw"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
NC='\033[0m'

if [[ $EUID -ne 0 ]]; then
    echo -e "${R}❌ Ошибка: запустите от имени root: sudo bash uninstall.sh${NC}" >&2
    exit 1
fi

echo -e "${Y}🗑️  Удаляю UFW Manager...${NC}\n"

if [[ -L "$INSTALL_BIN" || -f "$INSTALL_BIN" ]]; then
    rm -f "$INSTALL_BIN"
    echo -e "  ${G}✅${NC} Удалён: $INSTALL_BIN"
else
    echo -e "  ${Y}⚠️ ${NC} $INSTALL_BIN не найден, пропускаю"
fi

echo ""
read -rp "  Удалить директорию $OPT_DIR (файлы менеджера)? [y/N]: " confirm
if [[ "${confirm,,}" == "y" ]]; then
    rm -rf "$OPT_DIR"
    echo -e "  ${G}✅${NC} Удалена директория: $OPT_DIR"
fi

echo -e "\n${G}✅ UFW Manager успешно удалён.${NC}"
echo -e "Правила UFW остались нетронутыми.\n"
