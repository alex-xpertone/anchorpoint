# 05 — Ports & networks reference

AnchorPoint has **two separate networks**. This page lists exactly which ports
each side uses, so you can open the right things and close everything else.

---

## Home network (the exit point — WireGuard **server**)

Subnet on the tunnel: **`10.0.80.0/24`** · server address **`10.0.80.1`**.

| Port | Proto | Direction | Purpose | Must open? |
|---|---|---|---|---|
| **443** | **UDP** | **Inbound** (internet → server) | **WireGuard listener.** Port-forward `UDP 443` from your home router to the WireGuard server. Chosen to look like HTTPS so client-side firewalls allow it. | **Yes — the only inbound port.** |
| 53 | UDP/TCP | Internal only | DNS resolver (`10.0.80.1`) that tunnel clients use. Stays on the LAN. | No inbound rule |
| 123 | UDP | Outbound | NTP time sync. | No |

- **DDNS** (no fixed port): a hostname like `home.example.myfritz.net` tracks your
  changing home IP so the travel router can always find the endpoint.
- Nothing else needs to be reachable from the internet. **Only `UDP/443` is
  exposed.**

---

## Travel network (the entry point — WireGuard **client**, MikroTik hAP ax2)

Subnet handed to your devices: **`192.168.20.0/24`** · gateway **`192.168.20.1`**.

| Port | Proto | Direction | Purpose |
|---|---|---|---|
| **443** | **UDP** | **Outbound** (router → home) | The **only** port the tunnel needs. The router dials `home.example.myfritz.net:443`. Because it's UDP/443, venue and corporate firewalls that only permit web traffic still let it out. |
| 67 / 68 | UDP | Both | **DHCP.** *Client* on the uplinks (`ether1`, `wifi2`) to get a venue IP; *server* on `bridge-vpn` to hand `192.168.20.x` to your devices. |
| 53 | UDP/TCP | Internal → tunnel | DNS requests from your devices, forwarded to home's resolver (`10.0.80.1`). Does **not** leak to the venue. |
| 123 | UDP | Outbound | **NTP.** Correct time is mandatory — a wrong clock breaks the WireGuard handshake. |

- **No inbound ports** are opened on the travel router from the venue side.
- The travel router needs **only outbound `UDP/443`** to work. Everything else
  (DHCP, DNS, NTP) is standard local-network plumbing.

---

## Tunnel sizing

| Setting | Value | Why |
|---|---|---|
| WireGuard MTU (`wg1`) | **1412** | Leaves room for WireGuard's encapsulation overhead. |
| TCP MSS clamp | **1280** | Prevents oversized TCP segments from being dropped inside the tunnel (the "connects but nothing loads" failure). |
| `PersistentKeepalive` | **25 s** | Keeps the NAT mapping open while roaming. |

---

## One-glance summary

- **Home exposes exactly one port to the world: `UDP/443` inbound.**
- **Travel needs exactly one port to the world: `UDP/443` outbound.**
- Both `10.0.80.0/24` (tunnel) and `192.168.20.0/24` (travel LAN) are private and
  never reachable from the venue.
