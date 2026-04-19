#!/bin/bash
# UFW Manager — Интерактивное управление брандмауэром
# https://github.com/latham5656/ufw-manager

UFW_BIN="/usr/sbin/ufw"
INSTALL_BIN="/usr/local/bin/ufw"
OPT_DIR="/opt/ufw-manager"
DESC_FILE="$OPT_DIR/descriptions.conf"
BLOCKED_FILE="$OPT_DIR/blocked_ips.conf"
PROFILES_DIR="$OPT_DIR/profiles"
EXPORTS_DIR="$OPT_DIR/exports"
UPDATE_CACHE="$OPT_DIR/.update_check"
SCRIPT_REPO_URL="https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master/ufw-manager.sh"
VERSION="3.3.0"

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
    mkdir -p "$OPT_DIR" "$PROFILES_DIR" "$EXPORTS_DIR"
    touch "$DESC_FILE" "$BLOCKED_FILE"
}

pause() {
    echo ""
    read -rp "  Нажмите Enter для продолжения..."
}

# Возвращает 1 если пользователь ввёл 0 (выход), иначе 0 (продолжить)
nav_prompt() {
    local msg="${1:-  [Enter] — повторить  [0] — главное меню: }"
    echo ""
    read -rp "$msg" _nav
    [[ "$_nav" == "0" ]] && return 1
    return 0
}

# ── Валидация ─────────────────────────────────────────────────────────────────
validate_ip() {
    local ip=$1
    [[ -z "$ip" ]] && return 1
    local addr="${ip%%/*}"
    local cidr="${ip##*/}"

    if [[ ! "$addr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then return 1; fi

    local IFS='.'
    local -a octets
    read -ra octets <<< "$addr"
    for oct in "${octets[@]}"; do
        [[ "$oct" -gt 255 ]] && return 1
    done

    if [[ "$ip" == */* ]]; then
        [[ ! "$cidr" =~ ^[0-9]+$ || "$cidr" -gt 32 ]] && return 1
    fi
    return 0
}

validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+:[0-9]+$ ]]; then
        local p1="${port%%:*}" p2="${port##*:}"
        [[ "$p1" -lt 1 || "$p1" -gt 65535 || "$p2" -lt 1 || "$p2" -gt 65535 || "$p1" -ge "$p2" ]] && return 1
        return 0
    fi
    if [[ "$port" =~ ^[0-9]+$ ]]; then
        [[ "$port" -lt 1 || "$port" -gt 65535 ]] && return 1
        return 0
    fi
    return 1
}

# ── IP-привязки ───────────────────────────────────────────────────────────────
save_ip_binding() {
    local port=$1 proto=$2 ip=$3
    local key="${port}/${proto}"
    sed -i "\|^${key}:|d" "$DESC_FILE" 2>/dev/null
    echo "${key}:${ip}" >> "$DESC_FILE"
}

get_ip_binding() {
    local port=$1 proto=$2
    grep "^${port}/${proto}:" "$DESC_FILE" 2>/dev/null | cut -d':' -f2 | head -1
}

remove_ip_binding() {
    local port=$1 proto=${2:-}
    if [[ -n "$proto" ]]; then
        sed -i "\|^${port}/${proto}:|d" "$DESC_FILE" 2>/dev/null
    else
        sed -i "\|^${port}/|d" "$DESC_FILE" 2>/dev/null
    fi
}

# ── Заблокированные IP ────────────────────────────────────────────────────────
save_blocked_ip() {
    local ip=$1 reason=$2
    sed -i "\|^${ip}|d" "$BLOCKED_FILE" 2>/dev/null
    echo "${ip}|${reason}|$(date '+%Y-%m-%d %H:%M')" >> "$BLOCKED_FILE"
}

remove_blocked_ip() {
    sed -i "\|^${1}|d" "$BLOCKED_FILE" 2>/dev/null
}

# ── Сравнение версий (возвращает 0 если $1 строго новее $2) ──────────────────
is_newer_version() {
    local a=$1 b=$2
    [[ "$a" == "$b" ]] && return 1
    local newest
    newest=$(printf '%s\n%s\n' "$a" "$b" | sort -V | tail -1)
    [[ "$newest" == "$a" ]]
}

# ── Авто-проверка обновлений (кеш 24ч, фоновый запрос) ───────────────────────
UPDATE_NOTIFY=""

check_for_updates() {
    # Читаем кеш и показываем уведомление только если remote НОВЕЕ current
    if [[ -f "$UPDATE_CACHE" ]]; then
        local cached_ver
        cached_ver=$(tail -1 "$UPDATE_CACHE" 2>/dev/null)
        is_newer_version "$cached_ver" "$VERSION" && UPDATE_NOTIFY="$cached_ver"
    fi
    # Фоновое обновление кеша раз в 24ч
    (
        command -v curl &>/dev/null || exit 0
        local now last=0
        now=$(date +%s)
        [[ -f "$UPDATE_CACHE" ]] && last=$(head -1 "$UPDATE_CACHE" 2>/dev/null)
        (( now - last < 86400 )) && exit 0
        local ver
        ver=$(curl -fsSL --max-time 4 "$SCRIPT_REPO_URL" 2>/dev/null \
            | head -n 20 | grep -m1 "^VERSION=" | cut -d'"' -f2)
        [[ -n "$ver" ]] && printf '%s\n%s\n' "$now" "$ver" > "$UPDATE_CACHE"
    ) &>/dev/null &
}

# ── UFW обёртки ───────────────────────────────────────────────────────────────
ufw_status_line() {
    "$UFW_BIN" status 2>/dev/null | head -1
}

is_active() {
    ufw_status_line | grep -q "^Status: active$"
}

# ── Шапка ─────────────────────────────────────────────────────────────────────
header() {
    clear
    local inner=44
    local title="UFW Manager  v${VERSION}"
    local subtitle="Управление брандмауэром VPS"
    local border
    border=$(printf '═%.0s' $(seq 1 $inner))

    local tl=$(( (inner - ${#title}) / 2 ))
    local tr=$(( inner - ${#title} - tl ))
    local sl=$(( (inner - ${#subtitle}) / 2 ))
    local sr=$(( inner - ${#subtitle} - sl ))

    echo -e "${C}"
    echo  "  ╔${border}╗"
    printf "  ║%${tl}s%s%${tr}s║\n" "" "$title" ""
    printf "  ║%${sl}s%s%${sr}s║\n" "" "$subtitle" ""
    echo  "  ╚${border}╝"
    echo -e "${NC}"

    if is_active; then
        echo -e "  Брандмауэр: ${G}🟢 Активен${NC}"
    else
        echo -e "  Брандмауэр: ${R}🔴 Отключён${NC}"
    fi

    [[ -n "$UPDATE_NOTIFY" ]] && \
        echo -e "  ${Y}⬆️  Доступна новая версия v${UPDATE_NOTIFY}${NC}  ${D}curl ... | sudo bash${NC}"

    echo ""
}

# ── Статус ────────────────────────────────────────────────────────────────────
screen_status() {
    while true; do
        header
        echo -e "  ${W}📊 Подробный статус UFW${NC}\n"
        "$UFW_BIN" status verbose 2>&1 | sed 's/^/  /'
        nav_prompt "  [Enter] — обновить  [0] — главное меню: " || return
    done
}

# ── Список правил с поиском и подсветкой ─────────────────────────────────────
screen_rules() {
    while true; do
        header
        echo -e "  ${W}📋 Список правил с описаниями${NC}\n"

        local numbered
        numbered=$("$UFW_BIN" status numbered 2>&1)

        if echo "$numbered" | grep -q "Status: inactive"; then
            echo -e "  ${Y}⚠️  UFW отключён — правила недоступны.${NC}"
            nav_prompt "  [Enter] — повторить  [0] — главное меню: " || return
            continue
        fi

        local filter=""
        read -rp "  Фильтр по порту/IP/описанию (Enter — все, 0 — назад): " filter
        [[ "$filter" == "0" ]] && return
        echo ""

        local found=0
        while IFS= read -r line; do
            [[ $line == *"(v6)"* ]] && continue

            if [[ $line =~ ^\[([[:space:]]*[0-9]+)\] ]]; then
                if [[ -n "$filter" ]] && ! echo "$line" | grep -qi "$filter"; then
                    continue
                fi
                found=1

                if [[ $line == *'#'* ]]; then
                    local main_part="${line%%#*}"
                    local comment_part="${line#*#}"
                    echo -e "  ${W}${main_part}${NC}${Y}#${comment_part}${NC}"
                elif [[ $line == *"DENY"* || $line == *"REJECT"* ]]; then
                    echo -e "  ${R}${line}${NC}"
                elif [[ $line == *"ALLOW"* ]]; then
                    echo -e "  ${G}${line}${NC}"
                else
                    echo -e "  ${W}${line}${NC}"
                fi

                local port proto
                port=$(echo "$line" | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' 2>/dev/null | head -1) || port=""
                proto=$(echo "$line" | grep -oP '(?<=\d/)(tcp|udp)' 2>/dev/null | head -1) || proto="any"
                [[ -z "$proto" ]] && proto="any"

                if [[ -n "$port" ]]; then
                    local ip_binding
                    ip_binding=$(get_ip_binding "$port" "$proto")
                    [[ -n "$ip_binding" && "$ip_binding" != "any" ]] && \
                        echo -e "  ${D}    🔒 только с IP:${NC} ${B}${ip_binding}${NC}"
                fi
            else
                [[ -z "$filter" ]] && echo "  $line"
            fi
        done <<< "$numbered"

        [[ $found -eq 0 && -n "$filter" ]] && \
            echo -e "  ${Y}Ничего не найдено по запросу «${filter}»${NC}"

        nav_prompt "  [Enter] — новый поиск  [0] — главное меню: " || return
    done
}

# ── Включить ──────────────────────────────────────────────────────────────────
screen_enable() {
    while true; do
        header
        echo -e "  ${Y}⚡ Включаю UFW...${NC}\n"
        echo "y" | "$UFW_BIN" enable 2>&1 | sed 's/^/  /'
        echo -e "\n  ${G}✅ UFW успешно включён.${NC}"
        nav_prompt "  [Enter] — повторить  [0] — главное меню: " || return
    done
}

# ── Отключить ─────────────────────────────────────────────────────────────────
screen_disable() {
    while true; do
        header
        echo -e "  ${Y}⚠️  Вы уверены, что хотите отключить брандмауэр? [y/N/0]${NC} "
        read -rp "  " confirm
        [[ "$confirm" == "0" ]] && return
        if [[ "${confirm,,}" == "y" ]]; then
            "$UFW_BIN" disable 2>&1 | sed 's/^/  /'
            echo -e "\n  ${G}✅ UFW отключён.${NC}"
        else
            echo -e "\n  ${D}Отменено.${NC}"
        fi
        nav_prompt "  [Enter] — повторить  [0] — главное меню: " || return
    done
}

# ── Добавить правило ──────────────────────────────────────────────────────────
screen_add_port() {
    while true; do
        header
        echo -e "  ${W}➕ Добавить правило для порта${NC}\n"

        local port
        read -rp "  Номер порта (0 — назад, или диапазон 8000:9000): " port
        [[ "$port" == "0" || -z "$port" ]] && return
        if ! validate_port "$port"; then
            echo -e "\n  ${R}❌ Некорректный порт «${port}». Укажите 1-65535 или диапазон 8000:9000.${NC}"
            sleep 1; continue
        fi

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

        echo ""
        local bind_ip
        read -rp "  Привязать к IP-адресу? (оставьте пустым — для всех): " bind_ip
        if [[ -n "$bind_ip" ]] && ! validate_ip "$bind_ip"; then
            echo -e "\n  ${R}❌ Некорректный IP-адрес «${bind_ip}»${NC}"; sleep 1; continue
        fi
        bind_ip="${bind_ip:-any}"

        echo ""
        local description
        read -rp "  Описание (напр. 'Nginx HTTPS'): " description
        description="${description:-Без описания}"

        echo ""
        echo -e "  ${Y}⏳ Применяю правило...${NC}"

        local ufw_out ufw_exit=0

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
            [[ "$bind_ip" != "any" ]] && save_ip_binding "$port" "$proto" "$bind_ip"
            echo -e "\n  ${G}✅ Правило добавлено:${NC}"
            echo -e "    Порт      : ${W}${port}${NC} (${proto})"
            [[ "$bind_ip" != "any" ]] && echo -e "    IP-привязка: ${B}${bind_ip}${NC}"
            echo -e "    Описание  : ${Y}${description}${NC}"
        else
            echo -e "\n  ${R}❌ Не удалось добавить правило. Проверьте введённые данные.${NC}"
        fi

        nav_prompt "  [Enter] — добавить ещё  [0] — главное меню: " || return
    done
}

# ── Блокировка IP ─────────────────────────────────────────────────────────────
screen_block_ip() {
    while true; do
        header
        echo -e "  ${W}🚫 Блокировка IP-адресов${NC}\n"

        if [[ -s "$BLOCKED_FILE" ]]; then
            echo -e "  ${D}Активные блокировки:${NC}"
            while IFS='|' read -r ip reason ts; do
                echo -e "    ${R}🔴 ${W}${ip}${NC}  ${D}— ${reason} (${ts})${NC}"
            done < "$BLOCKED_FILE"
            echo ""
        else
            echo -e "  ${D}Активных блокировок нет.${NC}\n"
        fi

        echo -e "  ${W}1)${NC} Заблокировать IP"
        echo -e "  ${W}2)${NC} Разблокировать IP"
        echo -e "  ${W}0)${NC} Назад"
        echo ""
        read -rp "  Выбор: " action

        case "$action" in
            1)
                echo ""
                local ip
                read -rp "  IP для блокировки (напр. 1.2.3.4 или 1.2.3.0/24): " ip
                if [[ -z "$ip" ]]; then
                    echo -e "  ${R}❌ IP не может быть пустым.${NC}"; sleep 1; continue
                fi
                if ! validate_ip "$ip"; then
                    echo -e "  ${R}❌ Некорректный IP «${ip}»${NC}"; sleep 1; continue
                fi
                echo ""
                local reason
                read -rp "  Причина блокировки: " reason
                reason="${reason:-Без причины}"

                local out exit_code=0
                out=$("$UFW_BIN" insert 1 deny from "$ip" to any 2>&1) || exit_code=$?
                echo "$out" | sed 's/^/  /'

                if [[ $exit_code -eq 0 ]]; then
                    save_blocked_ip "$ip" "$reason"
                    echo -e "\n  ${G}✅ IP ${ip} заблокирован.${NC}"
                else
                    echo -e "\n  ${R}❌ Не удалось заблокировать IP.${NC}"
                fi
                sleep 1
                ;;
            2)
                echo ""
                if [[ ! -s "$BLOCKED_FILE" ]]; then
                    echo -e "  ${Y}Нет заблокированных IP.${NC}"; sleep 1; continue
                fi
                local ip
                read -rp "  IP для разблокировки: " ip
                if [[ -z "$ip" ]]; then sleep 1; continue; fi
                if ! validate_ip "$ip"; then
                    echo -e "  ${R}❌ Некорректный IP «${ip}»${NC}"; sleep 1; continue
                fi

                local out exit_code=0
                out=$(echo "y" | "$UFW_BIN" delete deny from "$ip" to any 2>&1) || exit_code=$?
                echo "$out" | sed 's/^/  /'

                if [[ $exit_code -eq 0 ]]; then
                    remove_blocked_ip "$ip"
                    echo -e "\n  ${G}✅ IP ${ip} разблокирован.${NC}"
                else
                    echo -e "\n  ${R}❌ Не удалось разблокировать. Возможно, правило не найдено.${NC}"
                fi
                sleep 1
                ;;
            0|"") return ;;
            *) echo -e "\n  ${R}❌ Неверный выбор.${NC}"; sleep 0.5 ;;
        esac
    done
}

# ── Удалить правила ───────────────────────────────────────────────────────────
screen_remove_port() {
    while true; do
        header
        echo -e "  ${W}🗑️  Удалить правило${NC}\n"

        "$UFW_BIN" status numbered 2>&1 | sed 's/^/  /'
        echo ""

        local input
        read -rp "  Номера правил через пробел или запятую (0 — назад): " input
        [[ "$input" == "0" || -z "$input" ]] && return

        local raw_nums
        IFS=', ' read -ra raw_nums <<< "$input"

        local nums=()
        for n in "${raw_nums[@]}"; do
            [[ -z "$n" ]] && continue
            if [[ ! "$n" =~ ^[0-9]+$ ]]; then
                echo -e "  ${R}❌ «${n}» — не число, пропускаю.${NC}"; continue
            fi
            nums+=("$n")
        done

        if [[ ${#nums[@]} -eq 0 ]]; then
            echo -e "\n  ${R}❌ Не указано ни одного корректного номера.${NC}"; sleep 1; continue
        fi

        IFS=$'\n' nums=($(printf '%s\n' "${nums[@]}" | sort -rnu))
        unset IFS

        echo ""
        local ok=0 fail=0

        for rule_num in "${nums[@]}"; do
            local rule_line
            rule_line=$("$UFW_BIN" status numbered 2>/dev/null | grep -P "^\[ *${rule_num}\]") || rule_line=""
            local port proto
            port=$(echo "$rule_line" | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' 2>/dev/null | head -1) || port=""
            proto=$(echo "$rule_line" | grep -oP '(?<=\d/)(tcp|udp)' 2>/dev/null | head -1) || proto=""

            local del_exit=0
            echo "y" | "$UFW_BIN" delete "$rule_num" &>/dev/null || del_exit=$?

            if [[ $del_exit -eq 0 ]]; then
                [[ -n "$port" ]] && remove_ip_binding "$port" "$proto"
                echo -e "  ${G}✅ Правило #${rule_num} удалено.${NC}"
                (( ok++ ))
            else
                echo -e "  ${R}❌ Правило #${rule_num}: не удалось удалить.${NC}"
                (( fail++ ))
            fi
        done

        echo ""
        if [[ $ok -gt 0 && $fail -eq 0 ]]; then
            echo -e "  ${G}Итого удалено: ${ok}.${NC}"
        elif [[ $ok -gt 0 ]]; then
            echo -e "  ${Y}Удалено: ${ok}, ошибок: ${fail}.${NC}"
        else
            echo -e "  ${R}Не удалось удалить ни одного правила.${NC}"
        fi
        # После удаления петля возвращается вверх — показывает обновлённый список
    done
}

# ── Редактировать правило ─────────────────────────────────────────────────────
screen_edit_rule() {
    while true; do
        header
        echo -e "  ${W}✏️  Редактировать правило${NC}\n"

        local numbered
        numbered=$("$UFW_BIN" status numbered 2>&1)

        if echo "$numbered" | grep -q "Status: inactive"; then
            echo -e "  ${Y}⚠️  UFW отключён — правила недоступны.${NC}"
            nav_prompt || return; continue
        fi

        # Показываем только IPv4 правила
        local has_rules=0
        while IFS= read -r line; do
            [[ $line == *"(v6)"* ]] && continue
            if [[ $line =~ ^\[([[:space:]]*[0-9]+)\] ]]; then
                has_rules=1
                if [[ $line == *'#'* ]]; then
                    echo -e "  ${W}${line%%#*}${NC}${Y}#${line#*#}${NC}"
                elif [[ $line == *"DENY"* || $line == *"REJECT"* ]]; then
                    echo -e "  ${R}${line}${NC}"
                elif [[ $line == *"ALLOW"* ]]; then
                    echo -e "  ${G}${line}${NC}"
                else
                    echo -e "  ${W}${line}${NC}"
                fi
            else
                echo "  $line"
            fi
        done <<< "$numbered"

        if [[ $has_rules -eq 0 ]]; then
            echo -e "  ${D}Правил нет.${NC}"
            nav_prompt || return; continue
        fi

        echo ""
        local rule_num
        read -rp "  Номер правила для редактирования (0 — назад): " rule_num
        [[ "$rule_num" == "0" || -z "$rule_num" ]] && return
        if [[ ! "$rule_num" =~ ^[0-9]+$ ]]; then
            echo -e "  ${R}❌ Введите число.${NC}"; sleep 1; continue
        fi

        local rule_line
        rule_line=$(echo "$numbered" | grep -P "^\[ *${rule_num}\]")
        if [[ -z "$rule_line" ]]; then
            echo -e "  ${R}❌ Правило #${rule_num} не найдено.${NC}"; sleep 1; continue
        fi
        if [[ "$rule_line" == *"(v6)"* ]]; then
            echo -e "  ${Y}IPv6-правила редактируются автоматически вместе с IPv4.${NC}"; sleep 1; continue
        fi

        # Парсим поля правила
        local port proto from_ip comment action_type

        port=$(echo "$rule_line"    | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' | head -1)
        proto=$(echo "$rule_line"   | grep -oP '(?<=\d/)(tcp|udp)' | head -1)
        comment=$(echo "$rule_line" | grep -oP '(?<=#)\s*.+' | sed 's/^\s*//')

        # "From" IP — первое слово после ALLOW IN / DENY IN
        from_ip=$(echo "$rule_line" \
            | sed 's/.*\(ALLOW\|DENY\|REJECT\) \(IN\|FWD\|OUT\)\s*//' \
            | awk '{print $1}')
        [[ "$from_ip" == "Anywhere" || "$from_ip" == "0.0.0.0/0" || -z "$from_ip" ]] && from_ip="any"

        [[ $rule_line == *"DENY"* || $rule_line == *"REJECT"* ]] \
            && action_type="deny" || action_type="allow"

        if [[ -z "$port" ]]; then
            echo -e "  ${Y}⚠️  Это правило блокировки IP — управляйте через пункт 7.${NC}"
            sleep 2; continue
        fi

        # Внутренний цикл редактирования
        local new_proto="${proto:-any}" new_ip="$from_ip" new_comment="$comment"

        while true; do
            header
            echo -e "  ${W}✏️  Редактирование правила #${rule_num}${NC}\n"
            echo -e "  ${D}──────────────────────────────────${NC}"
            echo -e "    Порт       : ${W}${port}${NC}"
            echo -e "    Протокол   : ${W}${new_proto}${NC}"
            echo -e "    IP-источник: ${W}${new_ip}${NC}  ${D}(any = все адреса)${NC}"
            echo -e "    Комментарий: ${Y}${new_comment:-—}${NC}"
            echo -e "  ${D}──────────────────────────────────${NC}\n"
            echo -e "  ${W}1)${NC} Изменить протокол    ${D}(сейчас: ${new_proto})${NC}"
            echo -e "  ${W}2)${NC} Изменить IP-источник ${D}(сейчас: ${new_ip})${NC}"
            echo -e "  ${W}3)${NC} Изменить комментарий ${D}(сейчас: ${new_comment:-—})${NC}"
            echo -e "  ${W}4)${NC} ${G}✅ Применить изменения${NC}"
            echo -e "  ${W}0)${NC} Отмена"
            echo ""
            read -rp "  Выбор: " edit_choice

            case "$edit_choice" in
                1)
                    echo ""
                    echo -e "  Протокол:"
                    echo -e "    ${W}1)${NC} TCP"
                    echo -e "    ${W}2)${NC} UDP"
                    echo -e "    ${W}3)${NC} TCP + UDP"
                    read -rp "  Выбор [1-3]: " pc
                    case "$pc" in
                        1) new_proto="tcp" ;;
                        2) new_proto="udp" ;;
                        3) new_proto="any" ;;
                        *) echo -e "  ${D}Без изменений.${NC}"; sleep 0.5 ;;
                    esac
                    ;;
                2)
                    echo ""
                    read -rp "  Новый IP-источник (пусто = для всех): " inp
                    if [[ -z "$inp" ]]; then
                        new_ip="any"
                    elif validate_ip "$inp"; then
                        new_ip="$inp"
                    else
                        echo -e "  ${R}❌ Некорректный IP «${inp}»${NC}"; sleep 1
                    fi
                    ;;
                3)
                    echo ""
                    read -rp "  Новый комментарий (пусто = удалить): " new_comment
                    ;;
                4)
                    echo ""
                    echo -e "  ${Y}⏳ Применяю изменения...${NC}\n"

                    # Паттерн для поиска v6-дублёра
                    local v6_pattern
                    [[ "$proto" == "any" ]] \
                        && v6_pattern="${port}.*\(v6\)" \
                        || v6_pattern="${port}/${proto}.*\(v6\)"

                    # Удаляем v4
                    echo "y" | "$UFW_BIN" delete "$rule_num" &>/dev/null

                    # После удаления v4 ищем v6 по содержимому (номер мог сдвинуться)
                    local v6_num
                    v6_num=$("$UFW_BIN" status numbered 2>/dev/null \
                        | grep -P "^\[.*\] ${v6_pattern}" \
                        | grep -oP '(?<=\[)\s*\d+' | tr -d ' ' | head -1)
                    [[ -n "$v6_num" ]] && echo "y" | "$UFW_BIN" delete "$v6_num" &>/dev/null

                    # Убираем старую IP-привязку из нашего файла
                    remove_ip_binding "$port" "$proto"

                    # Добавляем с новыми параметрами
                    local desc="${new_comment:-Без описания}"
                    local ufw_out ufw_exit=0

                    if [[ "$new_ip" != "any" ]]; then
                        if [[ "$new_proto" == "any" ]]; then
                            ufw_out=$("$UFW_BIN" allow from "$new_ip" to any port "$port" comment "$desc" 2>&1) || ufw_exit=$?
                        else
                            ufw_out=$("$UFW_BIN" allow from "$new_ip" to any port "$port" proto "$new_proto" comment "$desc" 2>&1) || ufw_exit=$?
                        fi
                    else
                        if [[ "$new_proto" == "any" ]]; then
                            ufw_out=$("$UFW_BIN" allow from 0.0.0.0/0 to any port "$port" comment "$desc" 2>&1) || ufw_exit=$?
                        else
                            ufw_out=$("$UFW_BIN" allow from 0.0.0.0/0 to any port "$port" proto "$new_proto" comment "$desc" 2>&1) || ufw_exit=$?
                        fi
                    fi

                    echo "$ufw_out" | sed 's/^/  /'

                    if [[ $ufw_exit -eq 0 ]]; then
                        [[ "$new_ip" != "any" ]] && save_ip_binding "$port" "$new_proto" "$new_ip"
                        echo -e "\n  ${G}✅ Правило успешно изменено.${NC}"
                    else
                        echo -e "\n  ${R}❌ Не удалось применить изменения.${NC}"
                    fi
                    sleep 1
                    break  # Выходим из редактора, возвращаемся к выбору правила
                    ;;
                0|"") break ;;
                *) sleep 0.4 ;;
            esac
        done
    done
}

# ── Перезагрузить ─────────────────────────────────────────────────────────────
screen_reload() {
    while true; do
        header
        echo -e "  ${Y}🔄 Перезагружаю UFW...${NC}\n"
        "$UFW_BIN" reload 2>&1 | sed 's/^/  /'
        echo -e "\n  ${G}✅ Готово.${NC}"
        nav_prompt "  [Enter] — перезагрузить ещё раз  [0] — главное меню: " || return
    done
}

# ── Профили правил ────────────────────────────────────────────────────────────
screen_profiles() {
    while true; do
        header
        echo -e "  ${W}📁 Профили правил${NC}\n"

        local profiles=()
        while IFS= read -r f; do
            profiles+=("$f")
        done < <(find "$PROFILES_DIR" -maxdepth 1 -name "*.meta" 2>/dev/null | sort)

        if [[ ${#profiles[@]} -gt 0 ]]; then
            echo -e "  ${D}Сохранённые профили:${NC}"
            for f in "${profiles[@]}"; do
                local name
                name=$(basename "$f" .meta)
                local desc ts
                desc=$(grep "^desc=" "$f" | cut -d'=' -f2-)
                ts=$(grep "^date=" "$f" | cut -d'=' -f2-)
                echo -e "    ${W}• ${name}${NC}  ${D}— ${desc} (${ts})${NC}"
            done
            echo ""
        else
            echo -e "  ${D}Профилей нет.${NC}\n"
        fi

        echo -e "  ${W}1)${NC} Сохранить текущие правила как профиль"
        [[ ${#profiles[@]} -gt 0 ]] && echo -e "  ${W}2)${NC} Загрузить профиль"
        [[ ${#profiles[@]} -gt 0 ]] && echo -e "  ${W}3)${NC} Удалить профиль"
        echo -e "  ${W}0)${NC} Назад"
        echo ""
        read -rp "  Выбор: " action

        case "$action" in
            1)
                echo ""
                local name
                read -rp "  Имя профиля (без пробелов): " name
                name="${name// /_}"
                if [[ -z "$name" || ! "$name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    echo -e "  ${R}❌ Некорректное имя. Используйте буквы, цифры, _ и -.${NC}"
                    sleep 1; continue
                fi
                local desc
                read -rp "  Описание профиля: " desc
                desc="${desc:-Без описания}"

                if [[ ! -f /etc/ufw/user.rules ]]; then
                    echo -e "  ${R}❌ Файл /etc/ufw/user.rules не найден.${NC}"; sleep 1; continue
                fi

                cp /etc/ufw/user.rules  "$PROFILES_DIR/${name}.rules"  2>/dev/null
                cp /etc/ufw/user6.rules "$PROFILES_DIR/${name}.rules6" 2>/dev/null
                cp "$DESC_FILE"         "$PROFILES_DIR/${name}.desc"   2>/dev/null
                {
                    echo "desc=${desc}"
                    echo "date=$(date '+%Y-%m-%d %H:%M')"
                } > "$PROFILES_DIR/${name}.meta"

                echo -e "\n  ${G}✅ Профиль «${name}» сохранён.${NC}"
                sleep 1
                ;;
            2)
                [[ ${#profiles[@]} -eq 0 ]] && continue
                echo ""
                local name
                read -rp "  Имя профиля для загрузки: " name
                if [[ ! -f "$PROFILES_DIR/${name}.meta" ]]; then
                    echo -e "  ${R}❌ Профиль «${name}» не найден.${NC}"; sleep 1; continue
                fi
                echo -e "  ${Y}⚠️  Текущие правила будут заменены. Введите ${W}ДА${Y}:${NC} "
                local confirm
                read -rp "  " confirm
                if [[ "$confirm" == "ДА" ]]; then
                    cp "$PROFILES_DIR/${name}.rules"  /etc/ufw/user.rules  2>/dev/null
                    cp "$PROFILES_DIR/${name}.rules6" /etc/ufw/user6.rules 2>/dev/null
                    cp "$PROFILES_DIR/${name}.desc"   "$DESC_FILE"         2>/dev/null
                    "$UFW_BIN" reload 2>&1 | sed 's/^/  /'
                    echo -e "  ${G}✅ Профиль «${name}» загружен.${NC}"
                else
                    echo -e "  ${D}Отменено.${NC}"
                fi
                sleep 1
                ;;
            3)
                [[ ${#profiles[@]} -eq 0 ]] && continue
                echo ""
                local name
                read -rp "  Имя профиля для удаления: " name
                if [[ -f "$PROFILES_DIR/${name}.meta" ]]; then
                    rm -f "$PROFILES_DIR/${name}".{rules,rules6,desc,meta}
                    echo -e "  ${G}✅ Профиль «${name}» удалён.${NC}"
                else
                    echo -e "  ${R}❌ Профиль «${name}» не найден.${NC}"
                fi
                sleep 1
                ;;
            0|"") return ;;
            *) sleep 0.4 ;;
        esac
    done
}

# ── Экспорт / Импорт ──────────────────────────────────────────────────────────
screen_export_import() {
    while true; do
        header
        echo -e "  ${W}💾 Экспорт / Импорт правил${NC}\n"

        echo -e "  ${W}1)${NC} Экспортировать правила в .sh файл ${D}(для переноса на другой сервер)${NC}"
        echo -e "  ${W}2)${NC} Импортировать из .sh файла"
        echo -e "  ${W}0)${NC} Назад"
        echo ""
        read -rp "  Выбор: " action

        case "$action" in
            1)
                local filename="${EXPORTS_DIR}/ufw-export-$(date +%Y%m%d-%H%M%S).sh"
                {
                    echo "#!/bin/bash"
                    echo "# UFW Manager — экспорт правил"
                    echo "# Дата: $(date '+%Y-%m-%d %H:%M:%S')"
                    echo "# Экспортировано с: $(hostname 2>/dev/null || echo unknown)"
                    echo "# Версия UFW Manager: ${VERSION}"
                    echo ""
                    echo "UFW=/usr/sbin/ufw"
                    echo ""
                    echo "# Применить правила (запустите от root: sudo bash <файл>)"
                    "$UFW_BIN" status numbered 2>/dev/null \
                        | grep -P "^\[" | grep -v "(v6)" \
                        | while IFS= read -r line; do
                            local port proto comment action_word
                            port=$(echo "$line"    | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' | head -1)
                            proto=$(echo "$line"   | grep -oP '(?<=\d/)(tcp|udp)' | head -1)
                            comment=$(echo "$line" | grep -oP '(?<=#).+' | sed 's/^ *//')

                            if [[ $line == *"DENY"* || $line == *"REJECT"* ]]; then
                                action_word="deny"
                            else
                                action_word="allow"
                            fi

                            if [[ -n "$port" && -n "$proto" ]]; then
                                if [[ -n "$comment" ]]; then
                                    echo "\$UFW $action_word from 0.0.0.0/0 to any port $port proto $proto comment \"$comment\""
                                else
                                    echo "\$UFW $action_word $port/$proto"
                                fi
                            elif [[ $line == *"DENY"* ]]; then
                                local from_ip
                                from_ip=$(echo "$line" | grep -oP '\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}(/\d+)?' | head -1)
                                [[ -n "$from_ip" ]] && echo "\$UFW deny from $from_ip to any"
                            fi
                        done
                } > "$filename"
                chmod +x "$filename"

                echo -e "\n  ${G}✅ Экспорт сохранён:${NC}"
                echo -e "  ${W}${filename}${NC}\n"
                echo -e "  ${D}Перенос на другой сервер:${NC}"
                echo -e "  ${W}scp ${filename} user@server:/tmp/ && ssh user@server sudo bash /tmp/$(basename "$filename")${NC}"
                pause
                ;;
            2)
                echo ""
                local files=()
                while IFS= read -r f; do files+=("$f"); done \
                    < <(find "$EXPORTS_DIR" -maxdepth 1 -name "*.sh" 2>/dev/null | sort -r)

                if [[ ${#files[@]} -gt 0 ]]; then
                    echo -e "  ${D}Файлы в ${EXPORTS_DIR}/:${NC}"
                    for f in "${files[@]}"; do
                        echo -e "    ${W}•${NC} $(basename "$f")"
                    done
                    echo ""
                fi

                local fname
                read -rp "  Имя файла или полный путь: " fname
                [[ "$fname" != /* ]] && fname="$EXPORTS_DIR/$fname"

                if [[ ! -f "$fname" ]]; then
                    echo -e "  ${R}❌ Файл не найден: ${fname}${NC}"; pause; continue
                fi

                if ! head -1 "$fname" | grep -q '^#!.*bash'; then
                    echo -e "  ${R}❌ Файл не является bash-скриптом.${NC}"; pause; continue
                fi

                echo -e "  ${Y}⚠️  Правила из файла будут добавлены к текущим. Введите ${W}ДА${Y}:${NC} "
                local confirm
                read -rp "  " confirm
                if [[ "$confirm" == "ДА" ]]; then
                    bash "$fname" 2>&1 | sed 's/^/  /'
                    echo -e "\n  ${G}✅ Импорт завершён.${NC}"
                else
                    echo -e "  ${D}Отменено.${NC}"
                fi
                pause
                ;;
            0|"") return ;;
            *) sleep 0.4 ;;
        esac
    done
}

# ── Лог брандмауэра ───────────────────────────────────────────────────────────
screen_log() {
    local log_file="/var/log/ufw.log"

    colorize_log() {
        while IFS= read -r line; do
            if [[ $line == *"BLOCK"* ]]; then
                echo -e "  ${R}${line}${NC}"
            elif [[ $line == *"ALLOW"* ]]; then
                echo -e "  ${G}${line}${NC}"
            else
                echo -e "  ${D}${line}${NC}"
            fi
        done
    }

    while true; do
        header
        echo -e "  ${W}📜 Лог брандмауэра${NC}\n"

        if [[ ! -f "$log_file" ]]; then
            echo -e "  ${Y}⚠️  Файл лога не найден: ${log_file}${NC}"
            echo -e "  ${D}Включите логирование: sudo ufw logging on${NC}"
            nav_prompt "  [Enter] — повторить  [0] — главное меню: " || return
            continue
        fi

        echo -e "  ${W}1)${NC} Последние 50 записей"
        echo -e "  ${W}2)${NC} Только заблокированные ${D}(BLOCK)${NC}"
        echo -e "  ${W}3)${NC} Поиск по IP"
        echo -e "  ${W}4)${NC} Живой режим ${D}(Ctrl+C для выхода)${NC}"
        echo -e "  ${W}0)${NC} Главное меню"
        echo ""
        read -rp "  Выбор: " log_choice

        echo ""
        case "$log_choice" in
            1) tail -50 "$log_file" | colorize_log ;;
            2) grep "BLOCK" "$log_file" | tail -50 | colorize_log ;;
            3)
                local search_ip
                read -rp "  IP для поиска: " search_ip
                echo ""
                grep "$search_ip" "$log_file" | tail -50 | colorize_log
                ;;
            4)
                echo -e "  ${D}Нажмите Ctrl+C для выхода...${NC}\n"
                trap 'echo ""' INT
                tail -f "$log_file" | colorize_log
                trap - INT
                continue
                ;;
            0|"") return ;;
            *) echo -e "  ${R}❌ Неверный выбор.${NC}"; sleep 0.5; continue ;;
        esac

        nav_prompt "  [Enter] — снова  [0] — главное меню: " || return
    done
}

# ── Обновление ────────────────────────────────────────────────────────────────
screen_update() {
    local INSTALL_URL="https://raw.githubusercontent.com/latham5656/ufw-manager/refs/heads/master/install.sh"

    while true; do
        header
        echo -e "  ${W}⬆️  Обновление UFW Manager${NC}\n"
        echo -e "  Установленная версия: ${W}v${VERSION}${NC}"

        if [[ -n "$UPDATE_NOTIFY" ]]; then
            echo -e "  Доступная версия:     ${G}v${UPDATE_NOTIFY}${NC}\n"
            echo -e "  ${W}1)${NC} Обновить до v${UPDATE_NOTIFY}"
        else
            echo -e "  ${G}✅ Установлена актуальная версия.${NC}\n"
            echo -e "  ${W}1)${NC} Проверить наличие обновлений"
        fi
        echo -e "  ${W}0)${NC} Назад"
        echo ""
        read -rp "  Выбор: " action

        case "$action" in
            1)
                echo ""
                if [[ -n "$UPDATE_NOTIFY" ]]; then
                    echo -e "  ${Y}⏳ Запускаю установщик...${NC}\n"
                    local tmp_install
                    tmp_install=$(mktemp /tmp/ufw-install-XXXXXX.sh)
                    if curl -fsSL --max-time 15 "$INSTALL_URL" -o "$tmp_install" 2>/dev/null \
                        && head -1 "$tmp_install" | grep -q '^#!.*bash'; then
                        bash "$tmp_install"
                        rm -f "$tmp_install"
                        rm -f "$UPDATE_CACHE"
                        echo -e "\n  ${G}✅ Обновление завершено. Перезапускаю меню...${NC}\n"
                        sleep 1
                        exec "$INSTALL_BIN"
                    else
                        rm -f "$tmp_install"
                        echo -e "  ${R}❌ Не удалось скачать установщик. Проверьте подключение.${NC}"
                        nav_prompt || return
                    fi
                else
                    # Принудительная проверка — сбрасываем кеш и проверяем синхронно
                    echo -e "  ${Y}⏳ Проверяю GitHub...${NC}"
                    rm -f "$UPDATE_CACHE"
                    local ver
                    ver=$(curl -fsSL --max-time 8 "$SCRIPT_REPO_URL" 2>/dev/null \
                        | head -n 20 | grep -m1 "^VERSION=" | cut -d'"' -f2)
                    if [[ -n "$ver" ]]; then
                        printf '%s\n%s\n' "$(date +%s)" "$ver" > "$UPDATE_CACHE"
                        if is_newer_version "$ver" "$VERSION"; then
                            UPDATE_NOTIFY="$ver"
                            echo -e "  ${Y}Доступна новая версия: v${ver}${NC}"
                        else
                            UPDATE_NOTIFY=""
                            echo -e "  ${G}✅ Установлена актуальная версия v${VERSION}.${NC}"
                        fi
                    else
                        echo -e "  ${R}❌ Не удалось проверить обновления.${NC}"
                    fi
                    nav_prompt || return
                fi
                ;;
            0|"") return ;;
            *) sleep 0.4 ;;
        esac
    done
}

# ── Сброс ─────────────────────────────────────────────────────────────────────
screen_reset() {
    while true; do
        header
        echo -e "  ${R}⚠️  ВНИМАНИЕ: Все правила UFW будут сброшены до заводских!${NC}"
        echo -e "  Введите ${W}СБРОС${NC} для подтверждения, ${W}0${NC} — отмена:\n"
        local confirm
        read -rp "  " confirm
        [[ "$confirm" == "0" ]] && return
        if [[ "$confirm" == "СБРОС" ]]; then
            echo "y" | "$UFW_BIN" reset 2>&1 | sed 's/^/  /'
            > "$DESC_FILE"
            > "$BLOCKED_FILE"
            echo -e "\n  ${G}✅ UFW сброшен до настроек по умолчанию.${NC}"
            nav_prompt "  [Enter] — сбросить ещё раз  [0] — главное меню: " || return
        else
            echo -e "\n  ${D}Отменено.${NC}"
            nav_prompt "  [Enter] — повторить  [0] — главное меню: " || return
        fi
    done
}

# ── Удалить менеджер ──────────────────────────────────────────────────────────
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
        echo -e "  ${W}1)${NC}  📊 Статус брандмауэра"
        echo -e "  ${W}2)${NC}  📋 Список правил с описаниями"
        echo -e "  ${W}3)${NC}  ✅ Включить UFW"
        echo -e "  ${W}4)${NC}  ⛔ Отключить UFW"
        echo -e "  ─────────────────────────────────────"
        echo -e "  ${W}5)${NC}  ➕ Добавить правило ${D}(порт + IP + описание)${NC}"
        echo -e "  ${W}6)${NC}  ✏️  Редактировать правило ${D}(протокол, IP, комментарий)${NC}"
        echo -e "  ${W}7)${NC}  🚫 Заблокировать / разблокировать IP"
        echo -e "  ${W}8)${NC}  🗑️  Удалить правила ${D}(один или несколько)${NC}"
        echo -e "  ${W}9)${NC}  🔄 Перезагрузить UFW"
        echo -e "  ─────────────────────────────────────"
        echo -e "  ${W}10)${NC} 📁 Профили правил"
        echo -e "  ${W}11)${NC} 💾 Экспорт / Импорт правил"
        echo -e "  ${W}12)${NC} 📜 Лог брандмауэра"
        echo -e "  ─────────────────────────────────────"
        echo -e "  ${W}13)${NC} ${R}💣 Сбросить все правила${NC}"
        echo -e "  ${W}14)${NC} ${R}🗑️  Удалить UFW Manager${NC}"
        if [[ -n "$UPDATE_NOTIFY" ]]; then
            echo -e "  ${W}15)${NC} ${Y}⬆️  Обновить до v${UPDATE_NOTIFY}${NC}"
        else
            echo -e "  ${W}15)${NC} ⬆️  Обновления"
        fi
        echo -e "  ${W}0)${NC}  🚪 Выход"
        echo ""
        read -rp "  Выберите пункт: " choice

        case "$choice" in
            1)  screen_status ;;
            2)  screen_rules ;;
            3)  screen_enable ;;
            4)  screen_disable ;;
            5)  screen_add_port ;;
            6)  screen_edit_rule ;;
            7)  screen_block_ip ;;
            8)  screen_remove_port ;;
            9)  screen_reload ;;
            10) screen_profiles ;;
            11) screen_export_import ;;
            12) screen_log ;;
            13) screen_reset ;;
            14) screen_uninstall ;;
            15) screen_update ;;
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
check_for_updates
main_menu
