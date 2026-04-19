#!/bin/bash
# UFW Manager — Установщик / Обновлятор
# Режимы:
#   curl -fsSL https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master/install.sh | sudo bash
#   sudo bash install.sh

SCRIPT_REPO_URL="https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master/ufw-manager.sh"
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

step_ok()   { echo -e "  ${G}[  OK  ]${NC}  $1"; }
step_skip() { echo -e "  ${D}[ SKIP ]${NC}  $1"; }
step_info() { echo -e "  ${C}[ INFO ]${NC}  $1"; }
step_err()  { echo -e "  ${R}[ ERR  ]${NC}  $1"; }

# ── Шапка ─────────────────────────────────────────────────────────────────────
clear
echo -e "${C}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║                                              ║"
echo "  ║          UFW Manager  —  Installer           ║"
echo "  ║                                              ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ── Проверка root ─────────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    step_err "Запустите от имени root:"
    echo -e "\n    curl ... | ${W}sudo${NC} bash\n"
    exit 1
fi

# ── Проверка curl ─────────────────────────────────────────────────────────────
if ! command -v curl &>/dev/null; then
    step_err "curl не найден. Установите: apt install curl"
    exit 1
fi

# ── Определяем источник скрипта ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || SCRIPT_DIR=""
LOCAL_SRC="$SCRIPT_DIR/ufw-manager.sh"

if [[ -f "$LOCAL_SRC" ]]; then
    # Локальный режим (git clone + bash install.sh)
    MODE="local"
    SRC_FILE="$LOCAL_SRC"
    REMOTE_VER=$(grep -m 1 "^VERSION=" "$SRC_FILE" | cut -d'"' -f2)

    if [[ -f "$INSTALLED_SCRIPT" ]]; then
        INSTALLED_VER=$(grep -m 1 "^VERSION=" "$INSTALLED_SCRIPT" | cut -d'"' -f2)
    else
        INSTALLED_VER=""
    fi
else
    # Remote режим — скачиваем первые 100 строк чтобы узнать версию
    MODE="remote"

    step_info "Получаю версию с GitHub..."
    TEMP_VER=$(mktemp)
    if ! curl -fsSL "$SCRIPT_REPO_URL" 2>/dev/null | head -n 100 > "$TEMP_VER"; then
        step_err "Нет соединения с GitHub"
        rm -f "$TEMP_VER"
        exit 1
    fi

    REMOTE_VER=$(grep -m 1 "^VERSION=" "$TEMP_VER" | cut -d'"' -f2)
    rm -f "$TEMP_VER"

    if [[ -z "$REMOTE_VER" ]]; then
        step_err "Не удалось получить версию из скрипта"
        exit 1
    fi

    if [[ -f "$INSTALLED_SCRIPT" ]]; then
        INSTALLED_VER=$(grep -m 1 "^VERSION=" "$INSTALLED_SCRIPT" | cut -d'"' -f2)
    else
        INSTALLED_VER=""
    fi

    # Если версии совпадают — выходим
    if [[ -n "$INSTALLED_VER" && "$INSTALLED_VER" == "$REMOTE_VER" ]]; then
        echo -e "  ${G}Установлена актуальная версия ${W}v${REMOTE_VER}${G}.${NC}\n"
        step_info "Для принудительной переустановки удалите $INSTALLED_SCRIPT и запустите снова."
        echo ""
        exit 0
    fi

    # Скачиваем полный скрипт
    if [[ -n "$INSTALLED_VER" ]]; then
        step_info "Скачиваю v${REMOTE_VER} (обновление с ${INSTALLED_VER})..."
    else
        step_info "Скачиваю v${REMOTE_VER}..."
    fi

    SRC_FILE=$(mktemp /tmp/ufw-manager-XXXXXX.sh)
    if ! curl -fsSL "$SCRIPT_REPO_URL" -o "$SRC_FILE" || [[ ! -s "$SRC_FILE" ]]; then
        step_err "Не удалось скачать ufw-manager.sh"
        rm -f "$SRC_FILE"
        exit 1
    fi

    # Валидация — проверяем что это bash-скрипт
    if ! head -n 1 "$SRC_FILE" | grep -q '^#!.*bash'; then
        step_err "Скачанный файл повреждён"
        rm -f "$SRC_FILE"
        exit 1
    fi
fi

# ── Показываем режим ──────────────────────────────────────────────────────────
if [[ -n "$INSTALLED_VER" && "$INSTALLED_VER" != "$REMOTE_VER" ]]; then
    echo -e "  ${Y}Режим: обновление${NC}  ${D}v${INSTALLED_VER}${NC} ${W}→${NC} ${G}v${REMOTE_VER}${NC}"
elif [[ -z "$INSTALLED_VER" ]]; then
    echo -e "  ${C}Режим: новая установка${NC}  ${W}v${REMOTE_VER}${NC}"
fi

[[ "$MODE" == "local" ]] && step_info "Источник: локальный файл" || step_info "Источник: GitHub"

echo ""
echo -e "  ${D}────────────────────────────────────────────────${NC}"
echo ""

# ── Резервная копия при обновлении ────────────────────────────────────────────
if [[ -n "$INSTALLED_VER" && "$INSTALLED_VER" != "$REMOTE_VER" && -f "$INSTALLED_SCRIPT" ]]; then
    BAK="${INSTALLED_SCRIPT}.bak.$(date +%s)"
    # Удаляем старые бэкапы, оставляем только последний
    find "$OPT_DIR" -maxdepth 1 -name "ufw-manager.sh.bak.*" -type f -delete 2>/dev/null
    cp "$INSTALLED_SCRIPT" "$BAK"
    step_ok "Резервная копия:   $BAK"
fi

# ── Установка ─────────────────────────────────────────────────────────────────
mkdir -p "$OPT_DIR"
step_ok "Директория:        $OPT_DIR"

if cp "$SRC_FILE" "$INSTALLED_SCRIPT" && chmod +x "$INSTALLED_SCRIPT"; then
    if [[ -n "$INSTALLED_VER" && "$INSTALLED_VER" != "$REMOTE_VER" ]]; then
        step_ok "Скрипт обновлён:   $INSTALLED_SCRIPT"
    else
        step_ok "Скрипт установлен: $INSTALLED_SCRIPT"
    fi
else
    step_err "Не удалось записать $INSTALLED_SCRIPT"
    [[ "$MODE" == "remote" ]] && rm -f "$SRC_FILE"
    exit 1
fi

[[ "$MODE" == "remote" ]] && rm -f "$SRC_FILE"

if [[ ! -f "$OPT_DIR/descriptions.conf" ]]; then
    touch "$OPT_DIR/descriptions.conf"
    step_ok "Файл метаданных:  $OPT_DIR/descriptions.conf"
else
    step_skip "Файл метаданных уже существует — не трогаем"
fi

ln -sf "$INSTALLED_SCRIPT" "$INSTALL_BIN"
step_ok "Команда:           $INSTALL_BIN → $INSTALLED_SCRIPT"

# ── Итог ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "  ${D}────────────────────────────────────────────────${NC}"
echo ""

if [[ -n "$INSTALLED_VER" && "$INSTALLED_VER" != "$REMOTE_VER" ]]; then
    echo -e "  ${G}Обновление до v${REMOTE_VER} завершено!${NC}"
else
    echo -e "  ${G}Установка v${REMOTE_VER} завершена!${NC}"
fi

echo ""
echo -e "  Открыть меню : ${W}sudo ufw${NC}"
echo -e "  Обычные cmd  : ${W}sudo ufw status${NC}${D}, sudo ufw allow 22/tcp${NC}"
echo ""
