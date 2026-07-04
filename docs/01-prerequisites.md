# 01 — Prerequisites

Before you configure anything, make sure the following are in place. AnchorPoint
assumes you already control **both ends** of the tunnel: your home network and
your travel router.

## Hardware

- **Travel router:** MikroTik **hAP ax2** (`C52iG-5HaxD2HaxD`), running
  **RouterOS 7.x** (the Wi-Fi commands in this guide use the RouterOS 7
  `/interface/wifi` stack, not the legacy `/interface/wireless` one).
- **Home gateway:** a **FRITZ!Box** with **FRITZ!OS ≥ 7.50** (native WireGuard),
  **or** any always-on Linux host (Raspberry Pi, mini-PC, VPS) that can run
  `wireguard`.

## Home internet connection

- A **publicly reachable IPv4 address**, or a way to reach one. If your ISP puts
  you behind **CGNAT / DS-Lite** (common on German cable/fibre), plain port
  forwarding will not work — use MyFRITZ! + IPv6, a port-mapping tunnel, or a
  cheap VPS relay. A normal dual-stack DSL/fibre line with a public IPv4 is the
  easy path.
- The ability to **forward `UDP/443` inbound** to your WireGuard server, and to
  set a **DDNS** hostname (see [doc 02](02-home-wireguard-server-fritzbox.md)).

## Skills & tools

- **WinBox** (or WebFig / SSH) to configure the MikroTik.
- Basic comfort pasting a block of commands into the MikroTik **Terminal**.
- Access to your FRITZ!Box web UI at `http://fritz.box`.

## The prerequisite you must not skip: a working WireGuard server

**AnchorPoint does not create the WireGuard server for you** — it consumes one.
You must have a WireGuard **server** running at home before the travel router has
anything to dial into. The two supported paths:

1. **FRITZ!Box built-in WireGuard** (recommended, zero extra hardware) — covered
   step-by-step in [doc 02](02-home-wireguard-server-fritzbox.md).
2. **Linux WireGuard server** behind your router — also covered in doc 02, with
   the `UDP/443` port-forward and DDNS notes.

Once the server exists, it will hand you a **client configuration** (private key,
tunnel address, DNS, peer public key, endpoint, allowed IPs). That client config
is what you type into the MikroTik in [doc 03](03-travel-router-mikrotik.md).

## Naming used throughout these docs

| Placeholder | Meaning | Example value in the docs |
|---|---|---|
| `AnchorPoint Home Network` | SSID the **travel router broadcasts** to your devices | `AnchorPoint Home Network` |
| `<HOME_NETWORK_PASSWORD>` | Wi-Fi password for that SSID | — |
| `<VENUE_WIFI_SSID>` / `<VENUE_WIFI_PASSWORD>` | The **hotel / café Wi-Fi** you use as an uplink | — |
| `<PHONE_HOTSPOT_SSID>` / `<PHONE_HOTSPOT_PASSWORD>` | Your **phone's hotspot** used as a fallback uplink | — |
| `home.example.myfritz.net` | Your home **DDNS hostname** | `xxxx.myfritz.net` |
| `10.0.80.0/24` | WireGuard tunnel subnet; server is `10.0.80.1` | server `.1`, this client `.3` |
| `192.168.20.0/24` | Travel LAN handed out to your devices | gateway `192.168.20.1` |

Next: [02 — Home: WireGuard server (FRITZ!Box)](02-home-wireguard-server-fritzbox.md)
