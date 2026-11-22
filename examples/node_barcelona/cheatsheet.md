# 🔧 AnchorPoint — Installer Card

## BARCELONA · Barcelona (ES)

| | |
|---|---|
| **Router hostname** | `mesh-barcelona` |
| **Overlay IP** | `10.0.80.2` |
| **This site's DDNS** | `barcelona.example.net` |
| **Admin / Wi-Fi password** | in the SOPS bundle (`barcelona_admin_password`, `barcelona_wifi_passphrase`) |

---

### 🔌 Cable & Wi-Fi map — plug clients in here
| Port(s) | Wi-Fi SSID | You appear in | Subnet |
|---|---|---|---|
| **ether1** | — | *(WAN uplink to the ISP modem)* | — |
| **ether2** | `AnchorPoint-HAM` | **Hamburg** — via HAMBURG (tunnel) | `192.168.21.0/24` |
| **ether3/ether4/ether5** | `AnchorPoint-BCN` | **Barcelona** (local ISP) | `192.168.20.0/24` |

> **Roaming test clients:** iphone + macbook connect over WireGuard to this site (`wg-clients` · UDP 51821 · `10.0.92.0/24`) — full tunnel, so they exit in **Barcelona**.

---

### 📡 Port-forward on THIS site's ISP router → the router's WAN IP
- **UDP 51820** — WireGuard tunnel barcelona ↔ hamburg (Hamburg)
- **UDP 51821** — roaming test clients (iphone, macbook)
> All ports are UDP. Tunnel ports are forwarded on **both** ends of each tunnel.

---

### 🚀 Install steps
1. **Factory-reset** the MikroTik hAP ax2. Plug the ISP uplink into **ether1**.
2. Decrypt & paste this node's config (WinBox → *New Terminal*):
   `sops -d --input-type binary --output-type binary deployments/node_barcelona/bootstrap.sensitive.rsc`
3. Add the **UDP port-forward(s)** above on the site's ISP router.
4. Verify: `/interface wireguard peers print` → **1** tunnel peer(s) with a recent handshake; `/tool netwatch print` → watchdog(s) **up**.
5. Test each exit: connect to a port/SSID above and confirm your public IP is that country's.
6. Test from your phone/laptop: import `deployments/node_barcelona/clients/<device>.sensitive.conf` into the WireGuard app (iphone, macbook) → `ifconfig.me` shows **Barcelona**.

*AnchorPoint: anchorpoint · 2 sites · overlay 10.0.80.0/24 · generated — do not hand-edit.*
