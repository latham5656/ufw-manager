#!/bin/bash
# UFW Manager — Интерактивное управление брандмауэром
# https://github.com/latham5656/ufw-manager

UFW_BIN="/usr/sbin/ufw"
INSTALL_BIN="/usr/local/bin/ufw"
OPT_DIR="/opt/ufw-manager"
DESC_FILE="$OPT_DIR/descriptions.conf"
VERSION="1.0.0"

# ── Цвета ─────────────────────────────────────────────────────────────────────
R='\033[0;31m'
G='\033[0;32m'
Y='\033[1;33m'
B='\033[0;34m'
C='\033[0;36m'
W='\033[1;37m'
D='\033[2m'
NC='\033[0m'

# ── Проверки ──────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${R}❌ Ошибка: запустите от имени root (sudo ufw)${NC}" >&2
        exit 1
    fi
}

check_ufw_installed() {
    if [[ ! -x "$UFW_BIN" ]]; then
        echo -e "${R}❌ Ошибка: ufw не найден по пути $UFW_BIN${NC}" >&2
        echo -e "Установите командой: ${W}apt install ufw${NC}" >&2
        exit 1
    fi
}

init_opt_dir() {
    mkdir -p "$OPT_DIR"
    touch "$DESC_FILE"
}

pause() {
    echo ""
    read -rp "  Нажмите Enter для продолжения..."
}

# ── IP-привязки (хранятся отдельно, т.к. в ufw нет нативного поля) ────────────
# Формат: PORT/PROTO:IP

save_ip_binding() {
    local port=$1 proto=$2 ip=$3
    local key="${port}/${proto}"
    sed -i "\|^${key}:|d" "$DESC_FILE" 2>/dev/null
    echo "${key}:${ip}" >> "$DESC_FILE"
}

get_ip_binding() {
    local port=$1 proto=$2
    local key="${port}/${proto}"
    grep "^${key}:" "$DESC_FILE" 2>/dev/null | cut -d':' -f2 | head -1
    return 0
}

remove_ip_binding() {
    local port=$1 proto=${2:-}
    if [[ -n "$proto" ]]; then
        sed -i "\|^${port}/${proto}:|d" "$DESC_FILE" 2>/dev/null
    else
        sed -i "\|^${port}/|d" "$DESC_FILE" 2>/dev/null
    fi
    return 0
}

# ── UFW обёртки ───────────────────────────────────────────────────────────────
ufw_status_line() {
    "$UFW_BIN" status 2>/dev/null | head -1
}

is_active() {
    ufw_status_line | grep -q "active"
}

# ── Экраны ────────────────────────────────────────────────────────────────────
header() {
    clear
    echo -e "${C}"
    echo "  ╔══════════════════════════════════════════╗"
    echo "  ║   🔥  UFW Manager  v${VERSION}  🔥           ║"
    echo "  ║      Управление брандмауэром VPS         ║"
    echo "  ╚══════════════════════════════════════════╝"
    echo -e "${NC}"
    if is_active; then
        echo -e "  Брандмауэр: ${G}🟢 Активен${NC}"
    else
        echo -e "  Брандмауэр: ${R}🔴 Отключён${NC}"
    fi
    echo ""
}

screen_status() {
    header
    echo -e "  ${W}📊 Подробный статус UFW${NC}\n"
    "$UFW_BIN" status verbose 2>&1 | sed 's/^/  /'
    pause
}

screen_rules() {
    header
    echo -e "  ${W}📋 Список правил с описаниями${NC}\n"

    local numbered
    numbered=$("$UFW_BIN" status numbered 2>&1)

    if echo "$numbered" | grep -q "Status: inactive"; then
        echo -e "  ${Y}⚠️  UFW отключён — правила недоступны.${NC}"
        pause
        return
    fi

    while IFS= read -r line; do
        # Пропускаем IPv6-правила
        if [[ $line == *"(v6)"* ]]; then
            continue
        fi

        if [[ $line =~ ^\[([[:space:]]*[0-9]+)\] ]]; then
            # Разбиваем строку на часть до # и сам комментарий
            local main_part comment_part
            if [[ $line == *'#'* ]]; then
                main_part="${line%%#*}"
                comment_part="${line#*#}"
                echo -e "  ${W}${main_part}${NC}${Y}#${comment_part}${NC}"
            else
                echo -e "  ${W}${line}${NC}"
            fi

            # Показываем IP-привязку из нашего файла (если есть)
            local port proto ip_binding
            port=$(echo "$line" | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' 2>/dev/null | head -1) || port=""
            proto=$(echo "$line" | grep -oP '(?<=\d/)(tcp|udp)' 2>/dev/null | head -1) || proto=""
            [[ -z "$proto" ]] && proto="any"

            if [[ -n "$port" ]]; then
                ip_binding=$(get_ip_binding "$port" "$proto")
                if [[ -n "$ip_binding" && "$ip_binding" != "any" ]]; then
                    echo -e "  ${D}    🔒 только с IP:${NC} ${B}${ip_binding}${NC}"
                fi
            fi
        else
            echo "  $line"
        fi
    done <<< "$numbered"

    pause
}

screen_enable() {
    header
    echo -e "  ${Y}⚡ Включаю UFW...${NC}\n"
    echo "y" | "$UFW_BIN" enable 2>&1 | sed 's/^/  /'
    echo -e "\n  ${G}✅ UFW успешно включён.${NC}"
    pause
}

screen_disable() {
    header
    echo -e "  ${Y}⚠️  Вы уверены, что хотите отключить брандмауэр? [y/N]${NC} "
    read -rp "  " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        "$UFW_BIN" disable 2>&1 | sed 's/^/  /'
        echo -e "\n  ${G}✅ UFW отключён.${NC}"
    else
        echo -e "\n  ${D}Отменено.${NC}"
    fi
    pause
}

screen_add_port() {
    header
    echo -e "  ${W}➕ Добавить правило для порта${NC}\n"

    # ── Порт ──
    local port
    read -rp "  Номер порта (или диапазон, напр. 8000:9000): " port
    if [[ -z "$port" ]]; then
        echo -e "\n  ${R}❌ Порт не может быть пустым.${NC}"
        pause; return
    fi

    # ── Протокол ──
    echo ""
    echo -e "  Протокол:"
    echo -e "    ${W}1)${NC} TCP"
    echo -e "    ${W}2)${NC} UDP"
    echo -e "    ${W}3)${NC} TCP + UDP ${D}(по умолчанию)${NC}"
    local proto_choice proto
    read -rp "  Выбор [1-3]: " proto_choice
    case "$proto_choice" in
        1) proto="tcp" ;;
        2) proto="udp" ;;
        *) proto="any" ;;
    esac

    # ── Привязка к IP ──
    echo ""
    local bind_ip
    read -rp "  Привязать к IP-адресу? (оставьте пустым — для всех): " bind_ip
    bind_ip="${bind_ip:-any}"

    # ── Описание ──
    echo ""
    local description
    read -rp "  Описание (напр. 'Nginx HTTPS'): " description
    description="${description:-Без описания}"

    echo ""
    echo -e "  ${Y}⏳ Применяю правило...${NC}"

    local ufw_out ufw_exit
    ufw_exit=0

    # Только IPv4-правила (from 0.0.0.0/0 исключает создание v6-правил)
    # Описание передаётся как нативный комментарий UFW — виден в ufw status
    if [[ "$bind_ip" != "any" ]]; then
        if [[ "$proto" == "any" ]]; then
            ufw_out=$("$UFW_BIN" allow from "$bind_ip" to any port "$port" comment "$description" 2>&1) || ufw_exit=$?
        else
            ufw_out=$("$UFW_BIN" allow from "$bind_ip" to any port "$port" proto "$proto" comment "$description" 2>&1) || ufw_exit=$?
        fi
    else
        if [[ "$proto" == "any" ]]; then
            ufw_out=$("$UFW_BIN" allow from 0.0.0.0/0 to any port "$port" comment "$description" 2>&1) || ufw_exit=$?
        else
            ufw_out=$("$UFW_BIN" allow from 0.0.0.0/0 to any port "$port" proto "$proto" comment "$description" 2>&1) || ufw_exit=$?
        fi
    fi

    echo "$ufw_out" | sed 's/^/  /'

    if [[ $ufw_exit -eq 0 ]]; then
        # IP-привязку сохраняем отдельно (UFW не хранит её в виде метаданных)
        if [[ "$bind_ip" != "any" ]]; then
            save_ip_binding "$port" "$proto" "$bind_ip"
        fi
        echo -e "\n  ${G}✅ Правило добавлено:${NC}"
        echo -e "    Порт      : ${W}${port}${NC} (${proto})"
        if [[ "$bind_ip" != "any" ]]; then
            echo -e "    IP-привязка: ${B}${bind_ip}${NC}"
        fi
        echo -e "    Описание  : ${Y}${description}${NC}"
        echo -e "\n  ${D}Описание сохранено в UFW и видно в: sudo ufw status numbered${NC}"
    else
        echo -e "\n  ${R}❌ Не удалось добавить правило. Проверьте введённые данные.${NC}"
    fi

    pause
}

screen_remove_port() {
    header
    echo -e "  ${W}🗑️  Удалить правило${NC}\n"

    "$UFW_BIN" status numbered 2>&1 | grep -v "(v6)" | sed 's/^/  /'
    echo ""

    local rule_num
    read -rp "  Номер правила для удаления (или 'q' для отмены): " rule_num
    if [[ "${rule_num,,}" == "q" || -z "$rule_num" ]]; then
        return
    fi

    if [[ ! "$rule_num" =~ ^[0-9]+$ ]]; then
        echo -e "\n  ${R}❌ Неверный номер.${NC}"
        pause; return
    fi

    # Сохраняем порт и протокол до удаления — для очистки IP-привязки
    local rule_line port proto
    rule_line=$("$UFW_BIN" status numbered 2>/dev/null | grep -P "^\[ *${rule_num}\]") || rule_line=""
    port=$(echo "$rule_line" | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' 2>/dev/null | head -1) || port=""
    proto=$(echo "$rule_line" | grep -oP '(?<=\d/)(tcp|udp)' 2>/dev/null | head -1) || proto=""

    local del_out del_exit
    del_exit=0
    del_out=$(echo "y" | "$UFW_BIN" delete "$rule_num" 2>&1) || del_exit=$?
    echo "$del_out" | sed 's/^/  /'

    if [[ $del_exit -eq 0 ]]; then
        if [[ -n "$port" ]]; then
            remove_ip_binding "$port" "$proto"
        fi
        echo -e "\n  ${G}✅ Правило #${rule_num} удалено.${NC}"
    else
        echo -e "\n  ${R}❌ Не удалось удалить правило.${NC}"
    fi

    pause
}

screen_reload() {
    header
    echo -e "  ${Y}🔄 Перезагружаю UFW...${NC}\n"
    "$UFW_BIN" reload 2>&1 | sed 's/^/  /'
    echo -e "\n  ${G}✅ Готово.${NC}"
    pause
}

screen_reset() {
    header
    echo -e "  ${R}⚠️  ВНИМАНИЕ: Все правила UFW будут сброшены до заводских!${NC}"
    echo -e "  Введите ${W}СБРОС${NC} для подтверждения, или что-угодно для отмены:\n"
    local confirm
    read -rp "  " confirm
    if [[ "$confirm" == "СБРОС" ]]; then
        echo "y" | "$UFW_BIN" reset 2>&1 | sed 's/^/  /'
        > "$DESC_FILE"
        echo -e "\n  ${G}✅ UFW сброшен до настроек по умолчанию.${NC}"
    else
        echo -e "\n  ${D}Отменено.${NC}"
    fi
    pause
}

screen_uninstall() {
    header
    echo -e "  ${R}⚠️  Удалить UFW Manager из системы?${NC}\n"
    echo -e "  Будет удалено:"
    echo -e "    ${D}•${NC} $INSTALL_BIN  (команда меню)"
    echo -e "    ${D}•${NC} $OPT_DIR      (файлы менеджера)\n"
    echo -e "  Правила UFW и сам брандмауэр останутся нетронутыми.\n"
    echo -e "  Введите ${W}УДАЛИТЬ${NC} для подтверждения:\n"
    local confirm
    read -rp "  " confirm
    if [[ "$confirm" == "УДАЛИТЬ" ]]; then
        rm -f "$INSTALL_BIN"
        rm -rf "$OPT_DIR"
        echo -e "\n  ${G}✅ UFW Manager удалён.${NC}"
        echo -e "  ${D}Используйте /usr/sbin/ufw для работы с брандмауэром напрямую.${NC}\n"
        exit 0
    else
        echo -e "\n  ${D}Отменено.${NC}"
        pause
    fi
}

# ── Главное меню ──────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        header
        echo -e "  ${W}1)${NC} 📊 Статус брандмауэра"
        echo -e "  ${W}2)${NC} 📋 Список правил с описаниями"
        echo -e "  ${W}3)${NC} ✅ Включить UFW"
        echo -e "  ${W}4)${NC} ⛔ Отключить UFW"
        echo -e "  ─────────────────────────────────────"
        echo -e "  ${W}5)${NC} ➕ Добавить правило (порт + описание + IP)"
        echo -e "  ${W}6)${NC} 🗑️  Удалить правило"
        echo -e "  ${W}7)${NC} 🔄 Перезагрузить UFW"
        echo -e "  ─────────────────────────────────────"
        echo -e "  ${W}8)${NC} ${R}💣 Сбросить все правила${NC}"
        echo -e "  ${W}9)${NC} ${R}🗑️  Удалить UFW Manager${NC}"
        echo -e "  ${W}0)${NC} 🚪 Выход"
        echo ""
        read -rp "  Выберите пункт: " choice

        case "$choice" in
            1) screen_status ;;
            2) screen_rules ;;
            3) screen_enable ;;
            4) screen_disable ;;
            5) screen_add_port ;;
            6) screen_remove_port ;;
            7) screen_reload ;;
            8) screen_reset ;;
            9) screen_uninstall ;;
            0)
                echo -e "\n  ${G}👋 До свидания!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "\n  ${R}❌ Неверный пункт меню.${NC}"
                sleep 0.8
                ;;
        esac
    done
}

# ── Точка входа ───────────────────────────────────────────────────────────────
# Если переданы аргументы — пробрасываем в системный ufw без каких-либо проверок
if [[ $# -gt 0 ]]; then
    if [[ ! -x "$UFW_BIN" ]]; then
        echo "ufw: command not found at $UFW_BIN" >&2
        exit 1
    fi
    exec "$UFW_BIN" "$@"
fi

check_root
check_ufw_installed
init_opt_dir
main_menu
