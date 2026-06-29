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
| Raspberry Pi 5 (8GB) | Primary node (`raspberrypi5`, .34): full service stack, DNS MASTER | Live |
| Raspberry Pi 5 (2GB) | Secondary node (`hl-node-02`, .35): backup DNS, DNS BACKUP | Live |
| DeskPi RackMate T1 + 7" touchscreen | Rack and NOC display | Live (rack), In progress (kiosk) |
| TP-Link 8-port 2.5GbE switch | Wired backbone | Live |
| Google Wifi / Nest | Home network and gateway (not admin-controlled) | Live |
| Mini PC | On the switch, unprovisioned | Planned use |
| Lenovo Tiny | Future Proxmox virtualization host | Planned |
| MacBook | Administration workstation | Live |
| Ryzen 7 desktop | Windows Server / Active Directory lab host | Planned |

Both Pis are now live and wired. The 8GB Pi is the primary; the stack was migrated to it from the original 2GB Pi by cloning the SD card (see Migration and recovery). The 2GB Pi was then reflashed clean and brought up as the secondary DNS node.

## Node roles

The 8GB Pi 5 (`raspberrypi5`, 192.168.86.34) is the primary infrastructure node, running the full service stack and acting as the DNS MASTER. The 2GB Pi 5 (`hl-node-02`, 192.168.86.35) is the secondary node, currently running a backup AdGuard + Unbound resolver as the DNS BACKUP. The `hl-node-01` / `hl-node-02` naming scheme is being adopted as the fleet grows; the 8GB Pi still reports the hostname `raspberrypi5` and will be renamed when convenient.

The secondary node is also the intended home for the rack touchscreen kiosk. That move has not happened yet: the touchscreen is currently driven by the primary node, which is why the primary still runs a full desktop. Pairing backup DNS with the kiosk on one node is a deliberate compromise of a two-Pi setup; DNS ideally lives on a lean headless node, but the kiosk needs a graphical one, and there are only two Pis. AdGuard and Unbound are light enough that this is acceptable until a third node exists.

## Current architecture (live today)

```
Clients (per-device DNS, no router admin access)
      |
      v
DNS VIP 192.168.86.40  (keepalived, floats between nodes)
      |
  +---+-----------------------+
  v                           v
Primary Pi (8GB, .34)     Secondary Pi (2GB, .35)
MASTER, priority 100      BACKUP, priority 90
  AdGuard -> Unbound        AdGuard -> Unbound
  Prometheus + Grafana
  node-exporter + cAdvisor
  Uptime Kuma
  Homepage (on touchscreen)
  Tailscale                 Tailscale
  +-- AdGuardHome-sync ------+
      (primary replicated to secondary)
```

The DNS layer is now a high-availability pair: two nodes behind a floating virtual IP with automatic failover, and config replicated from primary to secondary. The monitoring stack, dashboard, and remote access still run on the primary only. This is the honest current state: DNS is redundant; the rest is single-node.

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
| AdGuard Home | both | bare-metal | Live |
| Unbound | both | bare-metal | Live |
| keepalived (DNS VIP) | both | host | Live |
| AdGuardHome-sync | primary | yes | Live |
| Prometheus | primary | yes | Live |
| Grafana | primary | yes | Live |
| node-exporter | primary (secondary planned) | yes | Live on primary |
| cAdvisor | primary | yes | Live |
| Uptime Kuma | primary | yes | Live |
| Homepage | primary (served and currently displayed) | yes | Live |
| Tailscale | both | host | Live |

AdGuard and Unbound are bare-metal on both nodes (install script + apt), matching across the pair so the config sync and health checks behave identically. Docker is installed on both nodes; on the secondary it currently hosts nothing but is in place for node-exporter and future services.

## How the DNS failover works

keepalived runs on both nodes and speaks VRRP. Both advertise on the LAN; the higher-priority node holds the VIP `192.168.86.40`. The primary starts at priority 100 and normally owns it; the secondary sits at 90.

A health-check script runs every 2 seconds on each node, querying the local AdGuard. If AdGuard stops answering, the check fails and keepalived subtracts 20 from that node's priority, dropping the primary to 80, below the secondary's 90, so the VIP moves. When the primary's DNS recovers, its priority returns to 100 and the VIP fails back. This means failover happens not only when a node dies, but when its DNS service stops, which is the more common real failure. Tested in both directions. Details in `ha-dns/`.

## Docker strategy

Services run in Docker via Compose where it makes sense, with Compose files in the repo, named volumes for persistence, and `restart: unless-stopped` so they survive reboots. This was proven during the migration: after cloning to new hardware and rebooting, every container came back on its own. The deliberate exceptions run on the host because they need host-level access: Tailscale, the kiosk browser, and keepalived. AdGuard and Unbound are bare-metal by choice to keep the DNS pair symmetric and simple.

## Migration and recovery notes

The stack was moved from the original 2GB Pi to the 8GB Pi 5 by cloning the SD card: a `dd` image of the 32GB card written to a 64GB card, then expanded.

Two real problems came up and were resolved:

**Boot order.** The 8GB Pi had previously booted from NVMe, so its bootloader tried NVMe first and hung on a solid green LED with no NVMe present. It eventually fell through to the SD card after a delay. A permanent fix is to set the bootloader to prefer SD.

**Broken NetworkManager.** After the swap, NetworkManager crash-looped with `libssh2.so.1: cannot open shared object file`. The package `libssh2-1t64` was marked installed but its shared library was missing, the result of an interrupted apt upgrade. With NetworkManager down there was no network to download the fix. Recovery was to bring `wlan0` up by hand (wpa_supplicant for association, dhcpcd for the lease) to get online, reinstall the missing library, then restart NetworkManager, which came up clean. The static IP was re-pinned afterward.

Lesson: an interrupted apt upgrade can leave a package marked installed while its files are missing, and any service linking against it fails to start with a shared-library error. When networking itself is down, the recovery path is to bring the interface up manually with wpa_supplicant and a DHCP client, repair the package, then hand control back to NetworkManager.

A smaller version recurred when bringing up the secondary node: it was briefly dual-homed (Wi-Fi and Ethernet both active on the same subnet), which caused heavy packet loss from asymmetric routing. Fixed by taking Wi-Fi down and disabling its autoconnect so the node commits to the wire.

## Rack layout (DeskPi RackMate T1)

- Touchscreen front-mounted at viewing height, currently driven by the primary Pi (intended to move to the secondary node)
- Pis on a tray on active coolers, airflow kept clear of cabling
- Switch low, as the cabling hub, with short patch cables
- Power routed up one side, Ethernet down the other
- Google Wifi kept off or on top of the rack, not enclosed in metal

## Design decisions and tradeoffs

**Floating VIP for DNS instead of client-side primary/secondary.** Operating systems handle secondary DNS entries inconsistently, so two DNS entries on clients give unreliable failover. A keepalived VIP gives clients one address and fails over in about a second, which is the production pattern and is genuinely testable. Now live.

**AdGuard and Unbound bare-metal, not containerized.** Kept symmetric across both nodes so the config sync and the keepalived health check behave identically. Containerizing both consistently is a possible future cleanup, not worth disrupting a working pair now.

**Both Pis run the desktop OS.** Not the lean-headless ideal for the primary. The 8GB primary runs a desktop because it currently drives the touchscreen, and the desktop proved its worth during the NetworkManager recovery, when a local screen was the only way back in. The overhead is negligible on these Pis. The textbook split (headless primary, graphical secondary) is a later cleanup once the screen moves to the secondary node.

**Backup DNS shares the kiosk node.** A compromise forced by having two Pis. Acceptable because DNS is lightweight; revisited when a third node exists.

**DNS stays on the Pis permanently.** When the Lenovo arrives, heavy compute moves there, but DNS stays on the dedicated Pis so that rebooting the hypervisor during VM work does not take down the whole network's name resolution.

**No VLAN segmentation yet.** The managed switch supports VLANs, but Google Wifi cannot route between them or serve VLAN-aware DHCP, so real segmentation needs a proper L3 router or firewall. Planned for when that hardware exists.

**Per-device DNS, not network-wide.** A constraint of not controlling the router, not a design choice. Documented honestly rather than described as network-wide.

## Current limitations

- DNS is highly available; the monitoring stack, dashboard, and remote access still run on the primary only
- Clients must be pointed at the VIP (.40) to benefit from failover; because the router is not admin-controlled, DNS is set per device, not network-wide
- AdGuard's upstream currently points at a public DoH resolver rather than the local Unbound on `127.0.0.1:5335`, despite Unbound being installed and healthy on both nodes; pointing AdGuard back at local Unbound (which sync then propagates) is a pending follow-up to match the recursive-resolver design
- Both Pis run the desktop OS; the primary is not yet the intended lean headless node, and the touchscreen has not yet moved to the secondary
- Static IPs are not DHCP-reserved, so address collisions are possible until the pool is narrowed
- The secondary node is not yet in the monitoring stack (no node-exporter on it yet)
- Configuration is still managed by hand per node; fleet automation (Ansible) is the next project

## Roadmap

| Item | Type | Status |
|---|---|---|
| High availability DNS (keepalived VIP + AdGuardHome-sync) | Project | Live |
| Fleet configuration with Ansible | Project | Next |
| Point AdGuard back at local Unbound across the pair | Cleanup | Planned |
| Add secondary node to the monitoring stack | Infrastructure | Planned |
| Move the touchscreen kiosk to the secondary node | Infrastructure | Planned |
| Lenovo Tiny on Proxmox | Project | Planned |
| Windows Server + Active Directory | Project | Planned |
| Microsoft Entra ID / Zero Trust lab | Project | Planned |
| SIEM and threat hunting | Project | Planned |

## How this maps to the repo

Standalone project folders document a distinct system end to end: DNS filtering, uptime monitoring, remote access, the monitoring stack, the Terraform site, Homepage, and the high availability DNS project. Supporting pieces that describe how the lab is wired rather than a standalone build (the kiosk, Tailscale, the IP plan, the rack, the migration) are captured in this document.
