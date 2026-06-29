# High Availability DNS

Two Raspberry Pi nodes serving DNS behind a single floating virtual IP, with automatic failover. If the primary node or its DNS service goes down, the virtual IP moves to the backup node within a couple of seconds and clients keep resolving names without noticing. Configuration is replicated from the primary to the backup so the backup is a true mirror, not just a bare resolver.

This builds on the single-node [DNS filtering](../dns-filtering) project and turns it into a redundant pair.

## What this demonstrates

- A floating virtual IP (VIP) shared between two hosts using VRRP (keepalived)
- A service-aware health check, so the VIP moves not just when a node dies, but when the local DNS service stops answering
- Tested failover in both directions: failover to the backup, and automatic failback to the primary
- Automated configuration replication between nodes

## Architecture

```
Clients  ->  DNS VIP 192.168.86.40  (floats between nodes via keepalived)
                     |
        +------------+------------+
        v                         v
  Pi #1  192.168.86.34        Pi #2  192.168.86.35
  MASTER, priority 100        BACKUP, priority 90
  AdGuard Home + Unbound      AdGuard Home + Unbound
        ^                         ^
        +-- AdGuardHome-sync ------+
            (Pi #1 = source of truth, replicated to Pi #2)
```

| Node | Hostname | Address | keepalived role | Priority |
|---|---|---|---|---|
| Pi #1 | raspberrypi5 | 192.168.86.34 | MASTER | 100 |
| Pi #2 | hl-node-02 | 192.168.86.35 | BACKUP | 90 |
| VIP | n/a | 192.168.86.40 | floating | n/a |

Both nodes run on a wired gigabit backbone (Pi -> TP-Link switch -> Google Wifi).

## How the failover works

keepalived runs on both nodes and speaks VRRP. Both advertise themselves on the LAN; the one with the higher priority holds the VIP. Pi #1 starts at priority 100 and normally owns `192.168.86.40`. Pi #2 sits at priority 90 as backup.

A health-check script (`check_dns.sh`) runs every 2 seconds on each node. It asks the local AdGuard to resolve a name and only succeeds if AdGuard actually responds. If the check fails twice in a row, keepalived subtracts 20 from that node's priority. On Pi #1 that drops it from 100 to 80, below Pi #2's 90, so the VIP moves to Pi #2. When Pi #1's DNS recovers, the check passes again, its priority returns to 100, and the VIP fails back.

The health check is the important part. Without it, keepalived would only fail over if the whole node went offline. With it, the VIP also moves when the node is up but its DNS has stopped, which is the more common real-world failure.

## Components

| File | Runs on | Purpose |
|---|---|---|
| `keepalived/node01-master.conf` | Pi #1 | keepalived config, MASTER |
| `keepalived/node02-backup.conf` | Pi #2 | keepalived config, BACKUP |
| `keepalived/check_dns.sh` | both | health check, installed at `/etc/keepalived/check_dns.sh` |
| `adguardhome-sync/docker-compose.yml` | Pi #1 | runs the sync service |
| `adguardhome-sync/adguardhome-sync.example.yaml` | Pi #1 | sanitized config template |

On the nodes, the keepalived files live at `/etc/keepalived/keepalived.conf` and `/etc/keepalived/check_dns.sh`. They are copied here under `keepalived/` for reference.

## Build summary

Each node already ran AdGuard Home (filtering) forwarding to a local Unbound recursive resolver on `127.0.0.1:5335`, installed bare-metal, matching the single-node DNS project. On top of that:

1. Installed keepalived on both nodes.
2. Added the health-check script and made it executable on both nodes.
3. Wrote the MASTER config on Pi #1 and the BACKUP config on Pi #2. They are identical except for `state`, `priority`, and they share `virtual_router_id 51` and an auth pass, which is what pairs them.
4. Enabled and started keepalived on both. Pi #1 took the VIP as MASTER, Pi #2 came up as BACKUP.
5. Confirmed the VIP `192.168.86.40` bound to Pi #1 and that clients could resolve against it.
6. Ran AdGuardHome-sync in Docker on Pi #1 to replicate its config to Pi #2.

## Failover test

With the VIP held by Pi #1, AdGuard was stopped on Pi #1 to simulate a DNS failure:

```bash
# On Pi #1
sudo systemctl stop AdGuardHome
```

Within a few seconds the VIP moved to Pi #2, confirmed by the VIP appearing on Pi #2's interface:

```
# On Pi #2
inet 192.168.86.35/24 ... eth0
inet 192.168.86.40/24 scope global secondary ... eth0
```

A query against the VIP kept working throughout, now answered by Pi #2:

```bash
dig @192.168.86.40 google.com   # still NOERROR
```

Restarting AdGuard on Pi #1 caused the VIP to fail back to Pi #1 automatically, since its recovered priority of 100 beats Pi #2's 90. No manual intervention was needed in either direction.

See `screenshots/` for the VIP binding, the working query, and the before/after of the failover.

## Configuration sync

The two AdGuard instances start out independent: Pi #1 holds the real blocklists and settings, Pi #2 is a fresh install. AdGuardHome-sync runs on Pi #1, reads its config through the AdGuard API, and writes it to Pi #2 on a 10-minute schedule (and once on startup). This keeps the backup filtering identically to the primary, so a failover does not silently drop ad and tracker blocking.

Credentials are kept out of this repo. The real `adguardhome-sync.yaml` holds the AdGuard admin login and is gitignored. Only the sanitized `adguardhome-sync.example.yaml` with placeholders is committed. To use it, copy the example to `adguardhome-sync.yaml` and fill in the real values on the node.

## Notes and honest limitations

- The VRRP `auth_pass` is a LAN-local pairing value to keep unrelated VRRP instances from interfering. It is not a sensitive credential and is not real authentication; anything on the LAN can speak VRRP. This is acceptable for a home network.
- Clients still need to be pointed at the VIP (`192.168.86.40`) to benefit from failover. Because this network's router (Google Wifi) is not under my control, DNS is set per device rather than handed out network-wide by DHCP.
- Static addresses are set as host statics, not DHCP reservations, for the same reason. There is a small risk the router could hand one of these addresses to another device until the DHCP pool is narrowed.
- Sync currently replicates Pi #1's AdGuard upstream setting as-is. At the time of writing, that upstream is a public DoH resolver rather than the local Unbound on `127.0.0.1:5335`. Both Unbound instances are installed and healthy; pointing AdGuard back at local Unbound on Pi #1 (which sync then propagates) is a follow-up to fully match the recursive-resolver design from the DNS project.

## What I would do next

- Point AdGuard back at local Unbound and let sync propagate it, so the pair uses recursive resolution end to end.
- Narrow the router's DHCP pool so the static range cannot collide.
- Add the VIP and both nodes to the monitoring stack so failover events are visible in Grafana.
