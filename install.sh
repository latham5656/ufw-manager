#!/bin/bash
# UFW Manager — Установщик
# Поддерживает два режима:
#   1) curl -fsSL https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master/install.sh | sudo bash
#   2) sudo bash install.sh  (из клонированного репозитория)

BASE_URL="https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master"
OPT_DIR="/opt/ufw-manager"
INSTALL_BIN="/usr/local/bin/ufw"

R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
W='\033[1;37m'
D='\033[2m'
NC='\033[0m'

# ── Проверки ──────────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${R}❌ Ошибка: запустите от имени root.${NC}" >&2
    echo -e "  curl ... | ${W}sudo${NC} bash" >&2
    exit 1
fi

# ── Определяем режим: локальный или remote ─────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_SRC="$SCRIPT_DIR/ufw-manager.sh"

echo -e "${Y}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   🔥  UFW Manager — Установка  🔥        ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"

# ── Получить ufw-manager.sh ───────────────────────────────────────────────────
TMP_SCRIPT=""

if [[ -f "$LOCAL_SRC" ]]; then
    echo -e "  ${D}Режим: локальная установка${NC}"
    SRC_FILE="$LOCAL_SRC"
else
    echo -e "  ${D}Режим: загрузка с GitHub...${NC}"

    # Проверяем наличие curl или wget
    if command -v curl &>/dev/null; then
        DOWNLOADER="curl"
    elif command -v wget &>/dev/null; then
        DOWNLOADER="wget"
    else
        echo -e "\n  ${R}❌ Ошибка: не найдены curl или wget.${NC}" >&2
        echo -e "  Установите: ${W}apt install curl${NC}" >&2
        exit 1
    fi

    TMP_SCRIPT=$(mktemp /tmp/ufw-manager-XXXXXX.sh)

    echo -e "  Скачиваю ufw-manager.sh..."
    if [[ "$DOWNLOADER" == "curl" ]]; then
        curl -fsSL "$BASE_URL/ufw-manager.sh" -o "$TMP_SCRIPT" 2>&1
    else
        wget -qO "$TMP_SCRIPT" "$BASE_URL/ufw-manager.sh" 2>&1
    fi

    if [[ $? -ne 0 || ! -s "$TMP_SCRIPT" ]]; then
        echo -e "\n  ${R}❌ Не удалось скачать ufw-manager.sh${NC}" >&2
        rm -f "$TMP_SCRIPT"
        exit 1
    fi

    SRC_FILE="$TMP_SCRIPT"
fi

echo ""

# ── Установка ─────────────────────────────────────────────────────────────────
mkdir -p "$OPT_DIR"
echo -e "  ${G}✅${NC} Создана директория       : $OPT_DIR"

cp "$SRC_FILE" "$OPT_DIR/ufw-manager.sh"
chmod +x "$OPT_DIR/ufw-manager.sh"
echo -e "  ${G}✅${NC} Скрипт установлен в      : $OPT_DIR/ufw-manager.sh"

touch "$OPT_DIR/descriptions.conf"
echo -e "  ${G}✅${NC} Создан файл метаданных   : $OPT_DIR/descriptions.conf"

ln -sf "$OPT_DIR/ufw-manager.sh" "$INSTALL_BIN"
echo -e "  ${G}✅${NC} Символическая ссылка     : $INSTALL_BIN"

# ── Очистка временного файла ──────────────────────────────────────────────────
[[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"

# ── Готово ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${G}🎉 Установка завершена!${NC}"
echo ""
echo -e "  Открыть меню    : ${W}sudo ufw${NC}"
echo -e "  Стандартные cmd : ${W}sudo ufw status${NC}${D} (работают как прежде)${NC}"
echo ""
