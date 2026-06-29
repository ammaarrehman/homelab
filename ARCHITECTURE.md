# Homelab Architecture

This document is the design of record for the homelab: what runs where, how it is addressed, the decisions behind it, and where it is going. It separates what is running today from what is designed but not yet built, so the diagram never claims more than the lab actually does.

## Status legend

- **Live**: built, running, and documented
- **In progress**: partially built
- **Planned**: designed here, not yet built

## Goals and principles

- Treat the machines as a small fleet of nodes whose configuration lives in version control, not in my memory
- Keep the primary infrastructure node lean and stable; put graphical and experimental things elsewhere
- Prefer the production-correct pattern over the quick one, and document the tradeoff when I take a shortcut
- Accuracy over resume padding: this doc marks planned work as planned

## Hardware

| Device | Role | Status |
|---|---|---|
| Raspberry Pi 5 (8GB) | Primary infrastructure node, runs all services | Live |
| Raspberry Pi 5 (2GB) | Free, planned secondary node: backup DNS + touchscreen kiosk | Planned |
| DeskPi RackMate T1 + 7" touchscreen | Rack and NOC display | Live (rack), In progress (kiosk) |
| TP-Link 8-port 2.5GbE switch | Wired backbone | Live |
| Google Wifi / Nest | Home network and gateway (not admin-controlled) | Live |
| Lenovo Tiny | Future Proxmox virtualization host | Planned |
| MacBook | Administration workstation | Live |
| Ryzen 7 desktop | Windows Server / Active Directory lab host | Planned |

The primary node is currently the 8GB Pi 5. The stack was migrated to it from the original 2GB Pi by cloning the SD card (see Migration and recovery below). The 2GB Pi is now free and is the intended secondary node.

## Node roles

The 8GB Pi 5 is the primary infrastructure node, running the load-bearing services. The hostname is currently `raspberrypi5`; the `hl-node-01` / `hl-node-02` naming scheme below is being adopted as the fleet grows, so that roles can change without renaming hosts.

The 2GB Pi 5 will become the secondary node: a backup DNS resolver and the driver for the rack touchscreen as a kiosk. Pairing backup DNS with the kiosk on one node is a deliberate compromise of a two-node setup; DNS ideally lives on a lean headless node, but the kiosk needs a graphical one, and there are only two Pis. AdGuard and Unbound are light enough that this is acceptable until a third node exists.

## Current architecture (live today)

```
Devices (MacBook, phone)
      |  DNS set per device (no router admin access)
      v
Primary Pi (8GB, 192.168.86.34)
  AdGuard Home (filtering)  ->  Unbound (recursive, DNSSEC)  ->  root servers
  Prometheus + Grafana + node-exporter + cAdvisor (metrics)
  Uptime Kuma (availability)
  Homepage (dashboard, displayed on the rack touchscreen)
  Tailscale (remote access)
```

Everything currently runs on this single node. DNS is pointed per device because the router is not under my control, so there is no network-wide DNS or DHCP reservation. This is the honest current state: capable, but single-node, with no failover yet.

## Target architecture (with the HA pair, planned)

```
Devices  ->  DNS VIP 192.168.86.40  (keepalived, floats between nodes)
                     |
        +------------+------------+
        v                         v
hl-node-01 (.34) MASTER     hl-node-02 (.35) BACKUP
  AdGuard + Unbound           AdGuard + Unbound
  monitoring stack            touchscreen kiosk (Homepage)
  Homepage, Tailscale         Tailscale
        ^                         ^
        +-- AdGuardHome-sync ------+   (primary config replicated to backup)
```

In the target design, devices point only at the DNS VIP. keepalived presents that single address and moves it to whichever node is healthy, so a node failure is invisible to clients. This is the next project to build, and it depends on flashing the 2GB Pi as the second node.

## IP plan

Addresses are set as host statics (NetworkManager) because there is no router access for DHCP reservations.

| Range | Use |
|---|---|
| .30 - .39 | Infrastructure hosts (node-01 = .34, node-02 = .35, future Lenovo = .30) |
| .40 - .49 | Service VIPs (DNS VIP = .40) |
| .50 - .69 | Future Proxmox VMs |

Tailscale addresses (100.x) are assigned by Tailscale and are separate from this LAN plan.

**Current limitation:** without control of the Google Wifi DHCP pool, there is a small risk the router hands one of these addresses to another device. The fix is a one-time request to narrow the DHCP pool so this range is reserved.

## Service placement

| Service | Node | Containerized | Status |
|---|---|---|---|
| AdGuard Home | both | yes | Live on primary, planned on secondary |
| Unbound | both | yes | Live on primary, planned on secondary |
| keepalived | both | host | Planned |
| AdGuardHome-sync | primary | yes | Planned |
| Prometheus | primary | yes | Live |
| Grafana | primary | yes | Live |
| node-exporter | all nodes | yes | Live on primary |
| cAdvisor | all nodes | yes | Live on primary |
| Uptime Kuma | primary | yes | Live |
| Homepage | primary (served and currently displayed) | yes | Live |
| Tailscale | both | host | Live on primary |

## Docker strategy

Services run in Docker via Compose wherever it makes sense, with the Compose files kept in the repo, named volumes for persistence, and `restart: unless-stopped` so they survive reboots. This was proven during the migration: after cloning to new hardware and rebooting, every container came back on its own. The deliberate exceptions run on the host because they need host-level access: Tailscale, the kiosk browser, and (planned) keepalived.

## Migration and recovery notes

The stack was moved from the original 2GB Pi to the 8GB Pi 5 by cloning the SD card: a `dd` image of the 32GB card was written to a 64GB card and the filesystem expanded.

Two real problems came up and were resolved:

**Boot order.** The 8GB Pi had previously booted from NVMe, so its bootloader tried NVMe first and hung on a solid green LED with no NVMe present. It eventually fell through to the SD card after a delay. A permanent fix is to set the bootloader to prefer SD.

**Broken NetworkManager.** After the swap, NetworkManager crash-looped with `libssh2.so.1: cannot open shared object file`. The package `libssh2-1t64` was marked installed but its shared library was missing, the result of an interrupted apt upgrade. With NetworkManager down there was no network to download the fix. Recovery was to bring `wlan0` up by hand (wpa_supplicant for association, dhcpcd for the DHCP lease) to get online, reinstall the missing library, then restart NetworkManager, which came up clean and took over Wi-Fi again. The static IP was re-pinned afterward.

Lesson: an interrupted apt upgrade can leave a package marked installed while its files are missing, and any service linking against it fails to start with a shared-library error. When networking itself is down, the recovery path is to bring the interface up manually with wpa_supplicant and a DHCP client, repair the package, then hand control back to NetworkManager.

## Rack layout (DeskPi RackMate T1)

- Touchscreen front-mounted at viewing height, currently driven by the primary Pi (will move to the secondary node)
- Pi(s) on a tray in the middle bay on active coolers, airflow kept clear of cabling
- Switch low, as the cabling hub, with short patch cables
- Power routed up one side, Ethernet down the other
- Google Wifi kept off or on top of the rack, not enclosed in metal

## Design decisions and tradeoffs

**Floating VIP for DNS instead of client-side primary/secondary.** Operating systems handle secondary DNS entries inconsistently, so two DNS entries on clients give unreliable failover. A keepalived VIP gives clients one address and fails over in about a second, which is the production pattern and is genuinely testable.

**Backup DNS shares the kiosk node.** A compromise forced by having two Pis. Acceptable because DNS is lightweight; revisited when a third node exists.

**DNS stays on the Pis permanently.** When the Lenovo arrives, heavy compute moves there, but DNS stays on the dedicated Pis so that rebooting the hypervisor during VM work does not take down the whole network's name resolution.

**No VLAN segmentation yet.** The managed switch supports VLANs, but Google Wifi cannot route between them or serve VLAN-aware DHCP, so real segmentation needs a proper L3 router or firewall. Planned for when that hardware exists.

**Per-device DNS, not network-wide.** A constraint of not controlling the router, not a design choice. Documented honestly rather than described as network-wide.

## Current limitations

- Single node today; the HA pair and failover are designed but not built
- The primary node currently runs the full desktop (it drives the touchscreen); the intended end-state is a lean headless primary with the screen on the secondary node
- DNS is per-device because the router is not admin-controlled
- Static IPs are not DHCP-reserved, so address collisions are possible until the pool is narrowed
- Configuration is managed by hand and per-node Compose files; fleet automation (Ansible) is planned

## Roadmap

| Item | Type | Status |
|---|---|---|
| High availability DNS (keepalived VIP + AdGuardHome-sync) | Project | Next |
| Fleet configuration with Ansible | Project | Planned |
| Touchscreen kiosk on the secondary node | Infrastructure | In progress |
| Lenovo Tiny on Proxmox | Project | Planned |
| Windows Server + Active Directory | Project | Planned |
| Microsoft Entra ID / Zero Trust lab | Project | Planned |
| SIEM and threat hunting | Project | Planned |

## How this maps to the repo

Standalone project folders document a distinct system end to end: DNS filtering, uptime monitoring, remote access, the monitoring stack, the Terraform site, Homepage, and the upcoming HA DNS and Ansible work. Supporting pieces that describe how the lab is wired rather than a standalone build (the kiosk, Tailscale, the IP plan, the rack, the migration) are captured in this document.
