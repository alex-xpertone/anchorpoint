# 🔧 AnchorPoint Mesh — Installer Card

## HAMBURG · Hamburg (DE)

| | |
|---|---|
| **Router hostname** | `mesh-hamburg` |
| **Overlay IP** | `10.0.80.1` |
| **This node's DDNS** | `hamburg.example.net` |
| **Admin password / Wi-Fi password** | in the SOPS bundle (`hamburg_admin_password`, `hamburg_wifi_passphrase`) |

---

### 🔌 Cable & Wi-Fi map — plug clients in here
| Port | Wi-Fi SSID | You appear in | Client subnet |
|:----:|-----------|---------------|---------------|
| **1** | — | *(WAN uplink to the ISP modem)* | — |
| **2** | `AnchorPoint-HAM` | **Hamburg** (local ISP) | `192.168.10.0/24` |
| **2** | `AnchorPoint-BCN` | **Barcelona** (via BARCELONA) | `192.168.11.0/24` |

---

### 📡 Port-forward on THIS site's ISP router → the router's WAN IP
- **UDP 51820**  — WireGuard tunnel hamburg ↔ barcelona (Barcelona)
> All ports are UDP. Each is forwarded on **both** ends of its tunnel.

---

### 🚀 Install steps
1. **Factory-reset** the MikroTik hAP ax2. Plug the ISP uplink into **Port 1**.
2. Decrypt & paste this node's config (WinBox → *New Terminal*):
   `sops -d --input-type binary --output-type binary deployments/mesh/node_hamburg/bootstrap.sensitive.rsc`
3. Add the **UDP port-forward(s)** above on the site's ISP router.
4. Verify: `/interface wireguard peers print` → **1** peer(s) with a recent handshake;
   `/tool netwatch print` → all watchdogs **up**.
5. Test each exit: connect to a port/SSID above and confirm your public IP is that country's.

*Mesh: anchorpoint · 2 nodes · overlay 10.0.80.0/24 · generated — do not hand-edit.*
