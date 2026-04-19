# UFW Manager

Interactive terminal menu for managing UFW (Uncomplicated Firewall) on Linux VPS servers.

## Features

- Enable / disable UFW
- Add port rules (TCP, UDP, or both) with a description
- Bind a port rule to a specific IP address
- Remove rules by number
- View all rules with saved descriptions and IP bindings
- Full status view
- Reset all rules
- Passthrough mode — `sudo ufw status` still works normally

## Requirements

- Linux (Ubuntu / Debian recommended)
- `ufw` installed (`apt install ufw`)
- Bash 4+
- Root / sudo access

## Installation

```bash
git clone https://github.com/latham5656/ufw-manager.git
cd ufw-manager
sudo bash install.sh
```

The installer copies `ufw-manager.sh` to `/usr/local/bin/ufw`, which takes precedence over the system `ufw` in `PATH`. The real `ufw` binary at `/usr/sbin/ufw` is called internally, so all existing `ufw` commands continue to work.

## Usage

Open the interactive menu:

```bash
sudo ufw
```

All standard ufw commands still work via passthrough:

```bash
sudo ufw status
sudo ufw allow 22/tcp
sudo ufw disable
```

## Menu options

| Option | Description |
|--------|-------------|
| 1 | Show verbose UFW status |
| 2 | List all rules with descriptions and IP bindings |
| 3 | Enable UFW |
| 4 | Disable UFW |
| 5 | Add a port rule (with description and optional IP binding) |
| 6 | Remove a port rule by number |
| 7 | Reload UFW |
| 8 | Reset all rules to defaults |

## Adding a port

When you choose option **5**, you will be prompted for:

1. **Port** — single port or range (e.g. `443` or `8000:9000`)
2. **Protocol** — TCP, UDP, or both
3. **IP binding** — restrict the rule to a specific source IP (optional)
4. **Description** — a short label like `Nginx HTTPS` or `Wireguard VPN`

Descriptions and IP bindings are stored in `/etc/ufw-manager/descriptions.conf` and shown in the rules list (option 2).

## Uninstall

```bash
sudo bash uninstall.sh
```

## License

MIT
