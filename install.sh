#!/bin/bash
# UFW Manager — Установщик / Обновлятор
# Режимы запуска:
#   curl -fsSL https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master/install.sh | sudo bash
#   sudo bash install.sh

BASE_URL="https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master"
CACHE_BUST="?t=$(date +%s)"
OPT_DIR="/opt/ufw-manager"
INSTALL_BIN="/usr/local/bin/ufw"
INSTALLED_SCRIPT="$OPT_DIR/ufw-manager.sh"

# ── Цвета ─────────────────────────────────────────────────────────────────────
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
W='\033[1;37m'
D='\033[2m'
NC='\033[0m'

# ── Шаги ──────────────────────────────────────────────────────────────────────
step_ok()   { echo -e "  ${G}[  OK  ]${NC}  $1"; }
step_skip() { echo -e "  ${D}[ SKIP ]${NC}  $1"; }
step_info() { echo -e "  ${C}[ INFO ]${NC}  $1"; }
step_err()  { echo -e "  ${R}[ ERR  ]${NC}  $1"; }

# ── Шапка ─────────────────────────────────────────────────────────────────────
print_header() {
    clear
    echo -e "${C}"
    echo "  ╔══════════════════════════════════════════════╗"
    echo "  ║                                              ║"
    echo "  ║        🔥  UFW Manager  Installer  🔥        ║"
    echo "  ║                                              ║"
    echo "  ╚══════════════════════════════════════════════╝"
    echo -e "${NC}"
}

# ── Загрузчик ─────────────────────────────────────────────────────────────────
download_file() {
    local url=$1 dest=$2
    if command -v curl &>/dev/null; then
        curl -fsSL "$url" -o "$dest" 2>/dev/null
    elif command -v wget &>/dev/null; then
        wget -qO "$dest" "$url" 2>/dev/null
    else
        return 1
    fi
}

# ── Получить версию из файла скрипта ──────────────────────────────────────────
get_version() {
    grep -oP '(?<=^VERSION=")[^"]+' "$1" 2>/dev/null || echo "0.0.0"
}

# ═══════════════════════════════════════════════════════════════════════════════

print_header

# ── Проверка root ──────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    step_err "Запустите от имени root:"
    echo -e "\n    curl ... | ${W}sudo${NC} bash\n"
    exit 1
fi

# ── Проверка curl/wget ────────────────────────────────────────────────────────
if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    step_err "Не найдены curl или wget. Установите: apt install curl"
    exit 1
fi

# ── Определяем источник: локальный файл или GitHub ────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_SRC="$SCRIPT_DIR/ufw-manager.sh"
TMP_SCRIPT=""

if [[ -f "$LOCAL_SRC" ]]; then
    MODE="local"
    SRC_FILE="$LOCAL_SRC"
else
    MODE="remote"
    TMP_SCRIPT=$(mktemp /tmp/ufw-manager-XXXXXX.sh)
    if ! download_file "$BASE_URL/ufw-manager.sh$CACHE_BUST" "$TMP_SCRIPT" || [[ ! -s "$TMP_SCRIPT" ]]; then
        step_err "Не удалось скачать ufw-manager.sh с GitHub"
        rm -f "$TMP_SCRIPT"
        exit 1
    fi
    SRC_FILE="$TMP_SCRIPT"
fi

# ── Определяем версии ─────────────────────────────────────────────────────────
REMOTE_VER=$(get_version "$SRC_FILE")
INSTALLED_VER=""
IS_UPDATE=false

if [[ -f "$INSTALLED_SCRIPT" ]]; then
    INSTALLED_VER=$(get_version "$INSTALLED_SCRIPT")
    if [[ "$INSTALLED_VER" == "$REMOTE_VER" ]]; then
        IS_UPDATE=false
        ALREADY_UPTODATE=true
    else
        IS_UPDATE=true
        ALREADY_UPTODATE=false
    fi
fi

# ── Шапка режима ──────────────────────────────────────────────────────────────
if [[ "$IS_UPDATE" == true ]]; then
    echo -e "  ${Y}Режим: обновление${NC}  ${D}${INSTALLED_VER}${NC} ${W}→${NC} ${G}${REMOTE_VER}${NC}"
elif [[ -n "$INSTALLED_VER" && "$ALREADY_UPTODATE" == true ]]; then
    echo -e "  ${G}Установлена актуальная версия ${REMOTE_VER} — уже обновлено.${NC}"
    echo ""
    step_info "Для переустановки удалите $INSTALLED_SCRIPT и запустите снова."
    echo ""
    [[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"
    exit 0
else
    echo -e "  ${C}Режим: новая установка${NC}  ${W}v${REMOTE_VER}${NC}"
fi

if [[ "$MODE" == "local" ]]; then
    step_info "Источник: локальный файл"
else
    step_info "Источник: GitHub"
fi

echo ""
echo -e "  ${D}────────────────────────────────────────────────${NC}"
echo ""

# ── Установка / Обновление ────────────────────────────────────────────────────

# Директория
if mkdir -p "$OPT_DIR" 2>/dev/null; then
    step_ok "Директория: $OPT_DIR"
else
    step_err "Не удалось создать $OPT_DIR"
    [[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"
    exit 1
fi

# Скрипт
if cp "$SRC_FILE" "$INSTALLED_SCRIPT" && chmod +x "$INSTALLED_SCRIPT"; then
    if [[ "$IS_UPDATE" == true ]]; then
        step_ok "Скрипт обновлён:  $INSTALLED_SCRIPT"
    else
        step_ok "Скрипт установлен: $INSTALLED_SCRIPT"
    fi
else
    step_err "Не удалось записать $INSTALLED_SCRIPT"
    [[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"
    exit 1
fi

# Файл метаданных (только при новой установке)
if [[ ! -f "$OPT_DIR/descriptions.conf" ]]; then
    touch "$OPT_DIR/descriptions.conf"
    step_ok "Файл метаданных:  $OPT_DIR/descriptions.conf"
else
    step_skip "Файл метаданных уже существует — не трогаем"
fi

# Символическая ссылка
if ln -sf "$INSTALLED_SCRIPT" "$INSTALL_BIN"; then
    step_ok "Команда:          $INSTALL_BIN → $INSTALLED_SCRIPT"
else
    step_err "Не удалось создать ссылку $INSTALL_BIN"
    [[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"
    exit 1
fi

[[ -n "$TMP_SCRIPT" ]] && rm -f "$TMP_SCRIPT"

# ── Итог ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${D}────────────────────────────────────────────────${NC}"
echo ""

if [[ "$IS_UPDATE" == true ]]; then
    echo -e "  ${G}Обновление до v${REMOTE_VER} завершено!${NC}"
else
    echo -e "  ${G}Установка v${REMOTE_VER} завершена!${NC}"
fi

echo ""
echo -e "  Открыть меню : ${W}sudo ufw${NC}"
echo -e "  Обычные cmd  : ${W}sudo ufw status${NC}${D}, sudo ufw allow 22/tcp${NC}"
echo ""
