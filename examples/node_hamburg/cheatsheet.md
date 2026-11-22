# 🔧 AnchorPoint — Installer Card

## HAMBURG · Hamburg (DE)

| | |
|---|---|
| **Router hostname** | `mesh-hamburg` |
| **Overlay IP** | `10.0.80.1` |
| **This site's DDNS** | `anchorpoint-hamburg.duckdns.org` |
| **Admin / Wi-Fi password** | in the SOPS bundle (`hamburg_admin_password`, `hamburg_wifi_passphrase`) |

---

### 🔌 Cable & Wi-Fi map — plug clients in here
| Port(s) | Wi-Fi SSID | You appear in | Subnet |
|---|---|---|---|
| **ether1** | — | *(WAN uplink to the ISP modem)* | — |
| **ether2** | `AnchorPoint-BCN` | **Barcelona** — via BARCELONA (tunnel) | `192.168.11.0/24` |
| **ether3/ether4/ether5** | `AnchorPoint-HAM` | **Hamburg** (local ISP) | `192.168.10.0/24` |

> **Roaming test clients:** iphone + macbook connect over WireGuard to this site (`wg-clients` · UDP 51821 · `10.0.91.0/24`) — full tunnel, so they exit in **Hamburg**.

---

### 📡 Port-forward on THIS site's ISP router → the router's WAN IP
- **UDP 51820** — WireGuard tunnel hamburg ↔ barcelona (Barcelona)
- **UDP 51821** — roaming test clients (iphone, macbook)
> All ports are UDP. Tunnel ports are forwarded on **both** ends of each tunnel.
> **DDNS:** `anchorpoint-hamburg.duckdns.org` is kept current by DuckDNS (a scheduler on the router updates it every 5 min, outbound) — **no port-forward** needed for it.

---

### 🚀 Install steps
1. **Factory-reset** the MikroTik hAP ax2. Plug the ISP uplink into **ether1**.
2. Decrypt & paste this node's config (WinBox → *New Terminal*):
   `sops -d --input-type binary --output-type binary deployments/node_hamburg/bootstrap.sensitive.rsc`
3. Add the **UDP port-forward(s)** above on the site's ISP router.
4. Verify: `/interface wireguard peers print` → **1** tunnel peer(s) with a recent handshake; `/tool netwatch print` → watchdog(s) **up**.
5. Test each exit: connect to a port/SSID above and confirm your public IP is that country's.
6. Test from your phone/laptop: import `deployments/node_hamburg/clients/<device>.sensitive.conf` into the WireGuard app (iphone, macbook) → `ifconfig.me` shows **Hamburg**.

*AnchorPoint: anchorpoint · 2 sites · overlay 10.0.80.0/24 · generated — do not hand-edit.*
