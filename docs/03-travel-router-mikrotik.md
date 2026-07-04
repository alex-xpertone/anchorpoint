# 03 — Travel router: MikroTik hAP ax2

This is the device you carry. It:

- broadcasts the **`AnchorPoint Home Network`** SSID for your laptop / phone,
- pushes **all** their traffic through the WireGuard tunnel to home,
- and reaches the internet through whichever uplink is available (covered in
  [doc 04](04-uplink-failover.md)).

Configure it with **WinBox → New Terminal** (or WebFig → Terminal, or SSH).
Paste the blocks below in order. Anything in `<ANGLE_BRACKETS>` is a value **you**
supply.

> ⚠️ **Do the WireGuard + LAN part while connected by cable to the hAP's
> `ether2`–`ether5` or its default Wi-Fi.** You will be moving `ether2` onto a new
> bridge, so don't rely on `ether2` for your management link during setup.

---

## Step 1 — Time & timezone (WireGuard needs correct time)

A WireGuard handshake fails if the clock is wrong. Sync it first.

```rsc
/system/ntp/client/set enabled=yes
/system/ntp/client/servers/add address=pool.ntp.org
/system/clock/set time-zone-name=Europe/Berlin
```

---

## Step 2 — Type in the WireGuard client config

This is the config you exported from home in
[doc 02](02-home-wireguard-server-fritzbox.md). RouterOS can import the **exact
same text** the WireGuard app uses, via `wg-import`. Paste it, substituting your
real values:

```rsc
/interface/wireguard/wg-import config-string="
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address    = 10.0.80.3/24
DNS        = 10.0.80.1

[Peer]
PublicKey           = <SERVER_PUBLIC_KEY>
Endpoint            = home.example.myfritz.net:443
AllowedIPs          = 0.0.0.0/0,::/0
PersistentKeepalive = 25
"
```

- The import creates a WireGuard interface (referred to as **`wg1`** in the rest
  of this guide — check the exact name with `/interface/wireguard/print` and
  adjust if RouterOS named it differently).
- `Endpoint … :443` is the **UDP/443** trick — the router dials **out** to home
  on the HTTPS port so venue firewalls allow it.
- `AllowedIPs = 0.0.0.0/0,::/0` = **full tunnel** → home is the exit point.

---

## Step 3 — Build the travel LAN (`192.168.20.0/24`) and route it through the tunnel

Your devices sit on `192.168.20.0/24`. A dedicated routing table forces that
whole subnet out through `wg1`, and NAT masquerades it onto the tunnel.

```rsc
# Move ether2 onto a dedicated VPN bridge
/interface bridge port remove [find interface=ether2]
/interface bridge add name=bridge-vpn
/interface bridge port add bridge=bridge-vpn interface=ether2
/ip address add address=192.168.20.1/24 interface=bridge-vpn

# Policy route: everything from the travel LAN exits via the tunnel
/routing table add name=to-vpn fib
/ip route add dst-address=0.0.0.0/0 gateway=wg1 routing-table=to-vpn
/routing rule add src-address=192.168.20.0/24 action=lookup-only-in-table table=to-vpn

# NAT the travel LAN onto the tunnel
/ip firewall nat add action=masquerade chain=srcnat out-interface=wg1

# DHCP for your devices, DNS pointed at home (10.0.80.1) so DNS doesn't leak
/ip pool add name=vpn-pool ranges=192.168.20.10-192.168.20.100
/ip dhcp-server add address-pool=vpn-pool interface=bridge-vpn name=dhcp-vpn
/ip dhcp-server network add address=192.168.20.0/24 dns-server=10.0.80.1 gateway=192.168.20.1
```

---

## Step 4 — Fix MTU / MSS (prevents "connects but nothing loads")

WireGuard adds overhead; without this, large packets are silently dropped and
pages hang. This is the single most common AnchorPoint gotcha.

```rsc
/interface wireguard set wg1 mtu=1412
/ip firewall mangle add action=change-mss chain=forward comment="Clamp MSS out" new-mss=1280 out-interface=wg1 protocol=tcp tcp-flags=syn tcp-mss=1281-65535
/ip firewall mangle add action=change-mss chain=forward comment="Clamp MSS in"  new-mss=1280 in-interface=wg1  protocol=tcp tcp-flags=syn tcp-mss=1281-65535
```

---

## Step 5 — Broadcast the `AnchorPoint Home Network` SSID

This is the SSID your devices join. Both radios (5 GHz + 2.4 GHz) advertise it
and are bridged onto `bridge-vpn`, so anything that connects is on the tunnel.

Type in **your** home-network password where shown:

```rsc
/interface/wifi/add name=wifi-vpn-5ghz master-interface=wifi1 \
    configuration.ssid="AnchorPoint Home Network" \
    security.passphrase="<HOME_NETWORK_PASSWORD>" \
    security.authentication-types=wpa2-psk,wpa3-psk disabled=no
/interface/wifi/add name=wifi-vpn-2ghz master-interface=wifi2 \
    configuration.ssid="AnchorPoint Home Network" \
    security.passphrase="<HOME_NETWORK_PASSWORD>" \
    security.authentication-types=wpa2-psk,wpa3-psk disabled=no
/interface/bridge/port add bridge=bridge-vpn interface=wifi-vpn-5ghz
/interface/bridge/port add bridge=bridge-vpn interface=wifi-vpn-2ghz
```

> **Note on radios:** if you plan to use **Wi-Fi as an uplink** (venue Wi-Fi or
> phone hotspot, [doc 04](04-uplink-failover.md)), the `wifi2` (2.4 GHz) radio is
> needed as the **station/uplink** radio. In that setup, broadcast
> `AnchorPoint Home Network` on **`wifi1` (5 GHz) only** and reserve `wifi2` for
> the uplink. Use both radios only when your uplink is the wired `ether1` port.

---

## Step 6 — Keep the tunnel healthy + reachable

```rsc
# Let tunnel-side and admin traffic be treated as LAN
/interface list member add interface=bridge-vpn list=LAN
/interface list member add interface=wg1 list=LAN
/ip firewall filter add chain=input action=accept src-address=192.168.20.0/24 \
    comment="Allow WireGuard Admin Access" \
    place-before=[find comment="defconf: drop all not coming from LAN"]

# Watchdog: if home stops answering, bounce the tunnel
/tool netwatch add host=10.0.80.1 interval=1m type=simple up-script="" \
    down-script="/interface wireguard disable wg1; :delay 2s; /interface wireguard enable wg1"

# Hygiene
/ip firewall filter set [find comment="defconf: fasttrack"] src-address=!192.168.20.0/24
/ipv6/settings/set disable-ipv6=yes
/ip service disable ftp,telnet
/interface wifi set [find] security.ft=no .ft-over-ds=no
```

> IPv6 is disabled on purpose: it prevents traffic from bypassing the IPv4
> tunnel and leaking your real location.

---

## Step 7 — Verify

Connect a device to `AnchorPoint Home Network`, then:

- Visit `https://ifconfig.me` → must show your **home** IP.
- Visit `https://dnsleaktest.com` → DNS servers must be your **home** resolver,
  not the venue's.
- On the router: `/interface/wireguard/print` and `/ping 10.0.80.1` → the
  handshake is recent and home replies.

A complete, paste-in-one-go version of Steps 1–6 is in
[`config/mikrotik-travel-base.rsc`](../config/mikrotik-travel-base.rsc).

Next: [04 — Uplink failover (LAN → Wi-Fi → Hotspot)](04-uplink-failover.md)
