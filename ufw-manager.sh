#!/bin/bash
# UFW Manager — Interactive firewall management tool
# https://github.com/latham5656/ufw-manager

set -euo pipefail

UFW_BIN="/usr/sbin/ufw"
DATA_DIR="/etc/ufw-manager"
DESC_FILE="$DATA_DIR/descriptions.conf"
VERSION="1.0.0"

# ── Colors ────────────────────────────────────────────────────────────────────
R='\033[0;31m'   # Red
G='\033[0;32m'   # Green
Y='\033[1;33m'   # Yellow
B='\033[0;34m'   # Blue
C='\033[0;36m'   # Cyan
W='\033[1;37m'   # White
D='\033[2m'      # Dim
NC='\033[0m'     # Reset

# ── Helpers ───────────────────────────────────────────────────────────────────
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${R}Error: this script must be run as root (sudo ufw)${NC}" >&2
        exit 1
    fi
}

check_ufw_installed() {
    if [[ ! -x "$UFW_BIN" ]]; then
        echo -e "${R}Error: ufw not found at $UFW_BIN${NC}" >&2
        echo -e "Install it with: ${W}apt install ufw${NC}" >&2
        exit 1
    fi
}

init_data_dir() {
    mkdir -p "$DATA_DIR"
    touch "$DESC_FILE"
}

pause() {
    echo ""
    read -rp "  Press Enter to continue..."
}

# ── Descriptions ──────────────────────────────────────────────────────────────
# Format in file:  PORT/PROTO:IP:DESCRIPTION
# IP field is "any" when no IP binding

_desc_key() { echo "${1}/${2}"; }

save_desc() {
    local port=$1 proto=$2 ip=${3:-any} desc=$4
    local key; key=$(_desc_key "$port" "$proto")
    sed -i "/^${key}:/d" "$DESC_FILE" 2>/dev/null || true
    echo "${key}:${ip}:${desc}" >> "$DESC_FILE"
}

get_desc() {
    local port=$1 proto=$2
    local key; key=$(_desc_key "$port" "$proto")
    grep "^${key}:" "$DESC_FILE" 2>/dev/null | cut -d':' -f3- | head -1
}

get_ip_binding() {
    local port=$1 proto=$2
    local key; key=$(_desc_key "$port" "$proto")
    grep "^${key}:" "$DESC_FILE" 2>/dev/null | cut -d':' -f2 | head -1
}

remove_desc() {
    local port=$1 proto=${2:-}
    if [[ -n "$proto" ]]; then
        sed -i "/^${port}\/${proto}:/d" "$DESC_FILE" 2>/dev/null || true
    else
        sed -i "/^${port}\//d" "$DESC_FILE" 2>/dev/null || true
    fi
}

# ── UFW wrappers ──────────────────────────────────────────────────────────────
ufw_status_line() {
    $UFW_BIN status 2>/dev/null | head -1
}

is_active() {
    ufw_status_line | grep -q "active"
}

# ── Screens ───────────────────────────────────────────────────────────────────
header() {
    clear
    echo -e "${C}"
    echo "  ╔══════════════════════════════════════╗"
    echo "  ║         UFW Manager  v${VERSION}         ║"
    echo "  ╚══════════════════════════════════════╝"
    echo -e "${NC}"
    if is_active; then
        echo -e "  Firewall: ${G}● Active${NC}"
    else
        echo -e "  Firewall: ${R}○ Inactive${NC}"
    fi
    echo ""
}

screen_status() {
    header
    echo -e "  ${W}=== UFW Verbose Status ===${NC}\n"
    $UFW_BIN status verbose 2>&1 | sed 's/^/  /'
    pause
}

screen_rules() {
    header
    echo -e "  ${W}=== Rules with Descriptions ===${NC}\n"

    local numbered
    numbered=$($UFW_BIN status numbered 2>&1)

    if echo "$numbered" | grep -q "Status: inactive"; then
        echo -e "  ${Y}UFW is inactive — no rules to show.${NC}"
        pause
        return
    fi

    while IFS= read -r line; do
        if [[ $line =~ ^\[([[:space:]]*[0-9]+)\] ]]; then
            echo -e "  ${W}${line}${NC}"

            # Try to extract port from rule line
            local port proto desc ip_binding
            port=$(echo "$line" | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' | head -1)
            proto=$(echo "$line" | grep -oP '(?<=\d/)(tcp|udp)' | head -1)
            [[ -z "$proto" ]] && proto="any"

            if [[ -n "$port" ]]; then
                desc=$(get_desc "$port" "$proto")
                ip_binding=$(get_ip_binding "$port" "$proto")
                [[ -n "$desc" ]]       && echo -e "  ${D}    ↳ desc:${NC} ${Y}${desc}${NC}"
                [[ -n "$ip_binding" && "$ip_binding" != "any" ]] \
                                       && echo -e "  ${D}    ↳ ip  :${NC} ${B}${ip_binding}${NC}"
            fi
        else
            echo "  $line"
        fi
    done <<< "$numbered"

    pause
}

screen_enable() {
    header
    echo -e "  ${Y}Enabling UFW...${NC}\n"
    echo "y" | $UFW_BIN enable 2>&1 | sed 's/^/  /'
    echo -e "\n  ${G}Done.${NC}"
    pause
}

screen_disable() {
    header
    echo -e "  ${Y}Are you sure you want to disable the firewall? [y/N]${NC} "
    read -rp "  " confirm
    if [[ "${confirm,,}" == "y" ]]; then
        $UFW_BIN disable 2>&1 | sed 's/^/  /'
        echo -e "\n  ${G}UFW disabled.${NC}"
    else
        echo -e "\n  ${D}Cancelled.${NC}"
    fi
    pause
}

screen_add_port() {
    header
    echo -e "  ${W}=== Add Port Rule ===${NC}\n"

    # ── Port ──
    read -rp "  Port number (or range, e.g. 8000:9000): " port
    if [[ -z "$port" ]]; then
        echo -e "\n  ${R}Port cannot be empty.${NC}"
        pause; return
    fi

    # ── Protocol ──
    echo ""
    echo -e "  Protocol:"
    echo -e "    ${W}1)${NC} TCP"
    echo -e "    ${W}2)${NC} UDP"
    echo -e "    ${W}3)${NC} Both TCP + UDP ${D}(default)${NC}"
    read -rp "  Choice [1-3]: " proto_choice
    case "$proto_choice" in
        1) proto="tcp" ;;
        2) proto="udp" ;;
        *) proto="any" ;;
    esac

    # ── IP binding ──
    echo ""
    read -rp "  Bind to specific IP address? (leave blank for any): " bind_ip
    bind_ip="${bind_ip:-any}"

    # ── Description ──
    echo ""
    read -rp "  Description (e.g. 'Nginx HTTPS'): " description

    echo ""
    echo -e "  ${Y}Applying rule...${NC}"

    local exit_code=0
    if [[ "$bind_ip" != "any" ]]; then
        if [[ "$proto" == "any" ]]; then
            $UFW_BIN allow from "$bind_ip" to any port "$port" || exit_code=$?
        else
            $UFW_BIN allow from "$bind_ip" to any port "$port" proto "$proto" || exit_code=$?
        fi
    else
        if [[ "$proto" == "any" ]]; then
            $UFW_BIN allow "$port" || exit_code=$?
        else
            $UFW_BIN allow "${port}/${proto}" || exit_code=$?
        fi
    fi

    if [[ $exit_code -eq 0 ]]; then
        save_desc "$port" "$proto" "$bind_ip" "${description:-No description}"
        echo -e "\n  ${G}✓ Rule added:${NC}"
        echo -e "    Port       : ${W}${port}${NC} (${proto})"
        [[ "$bind_ip" != "any" ]] && echo -e "    IP binding : ${B}${bind_ip}${NC}"
        echo -e "    Description: ${Y}${description:-No description}${NC}"
    else
        echo -e "\n  ${R}✗ Failed to add rule. Check the values and try again.${NC}"
    fi

    pause
}

screen_remove_port() {
    header
    echo -e "  ${W}=== Remove Port Rule ===${NC}\n"

    $UFW_BIN status numbered 2>&1 | sed 's/^/  /'
    echo ""

    read -rp "  Rule number to delete (or 'q' to cancel): " rule_num
    if [[ "${rule_num,,}" == "q" || -z "$rule_num" ]]; then
        return
    fi

    if [[ ! "$rule_num" =~ ^[0-9]+$ ]]; then
        echo -e "\n  ${R}Invalid number.${NC}"
        pause; return
    fi

    # Grab port/proto before deletion for description cleanup
    local rule_line port proto
    rule_line=$($UFW_BIN status numbered 2>/dev/null | grep -P "^\[ *${rule_num}\]")
    port=$(echo "$rule_line" | grep -oP '\b\d{1,5}(?=/(?:tcp|udp))' | head -1)
    proto=$(echo "$rule_line" | grep -oP '(?<=\d/)(tcp|udp)' | head -1)

    echo "y" | $UFW_BIN delete "$rule_num" 2>&1 | sed 's/^/  /'

    if [[ $? -eq 0 ]]; then
        [[ -n "$port" ]] && remove_desc "$port" "$proto"
        echo -e "\n  ${G}✓ Rule #${rule_num} removed.${NC}"
    else
        echo -e "\n  ${R}✗ Failed to remove rule.${NC}"
    fi

    pause
}

screen_reload() {
    header
    echo -e "  ${Y}Reloading UFW...${NC}\n"
    $UFW_BIN reload 2>&1 | sed 's/^/  /'
    echo -e "\n  ${G}Done.${NC}"
    pause
}

screen_reset() {
    header
    echo -e "  ${R}WARNING: This will reset ALL UFW rules to defaults!${NC}"
    echo -e "  Type ${W}RESET${NC} to confirm, or anything else to cancel:\n"
    read -rp "  " confirm
    if [[ "$confirm" == "RESET" ]]; then
        echo "y" | $UFW_BIN reset 2>&1 | sed 's/^/  /'
        > "$DESC_FILE"
        echo -e "\n  ${G}UFW has been reset.${NC}"
    else
        echo -e "\n  ${D}Cancelled.${NC}"
    fi
    pause
}

# ── Main menu ─────────────────────────────────────────────────────────────────
main_menu() {
    while true; do
        header
        echo -e "  ${W}1)${NC} Show status"
        echo -e "  ${W}2)${NC} Show rules (with descriptions)"
        echo -e "  ${W}3)${NC} Enable UFW"
        echo -e "  ${W}4)${NC} Disable UFW"
        echo -e "  ───────────────────────────────────"
        echo -e "  ${W}5)${NC} Add port rule"
        echo -e "  ${W}6)${NC} Remove port rule"
        echo -e "  ${W}7)${NC} Reload UFW"
        echo -e "  ───────────────────────────────────"
        echo -e "  ${W}8)${NC} ${R}Reset all rules${NC}"
        echo -e "  ${W}0)${NC} Exit"
        echo ""
        read -rp "  Choose option: " choice

        case "$choice" in
            1) screen_status ;;
            2) screen_rules ;;
            3) screen_enable ;;
            4) screen_disable ;;
            5) screen_add_port ;;
            6) screen_remove_port ;;
            7) screen_reload ;;
            8) screen_reset ;;
            0)
                echo -e "\n  ${G}Goodbye!${NC}\n"
                exit 0
                ;;
            *)
                echo -e "\n  ${R}Invalid option.${NC}"
                sleep 0.8
                ;;
        esac
    done
}

# ── Entry point ───────────────────────────────────────────────────────────────
# If arguments are passed, forward them to real ufw (non-interactive use)
if [[ $# -gt 0 ]]; then
    exec "$UFW_BIN" "$@"
fi

check_root
check_ufw_installed
init_data_dir
main_menu
