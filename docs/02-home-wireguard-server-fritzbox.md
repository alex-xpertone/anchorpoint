# 02 — Home: WireGuard server (FRITZ!Box)

The **home network is the exit point.** Everything the travel router sends
through the tunnel comes out here, onto your home internet line, with your home
IP address. This document builds that server.

You need three things at home:

1. A **WireGuard server** listening for the travel router.
2. **Port forwarding** so the outside world can reach it — on **`UDP/443`**.
3. A **DDNS hostname** so the travel router can always find home, even when your
   ISP changes your IP.

---

## Path A — FRITZ!Box built-in WireGuard (recommended)

FRITZ!OS 7.50 and later ship WireGuard natively. This is the least-effort home
end: no extra hardware, no Linux.

### A1. Create the WireGuard connection

1. Open `http://fritz.box` and log in.
2. Go to **Internet → Permit Access → VPN (WireGuard)**.
3. Click **Add connection**.
4. Choose **"Configure connection for a specific application / device"** (the
   *custom* option — not the guided "MyFRITZ! app" one). This lets you export a
   raw config for the MikroTik.
5. Give it a name, e.g. `anchorpoint-travel-router`.
6. FRITZ!OS generates a **key pair and a client config**. **Download / copy** the
   shown configuration — you will paste it into the MikroTik verbatim in
   [doc 03](03-travel-router-mikrotik.md).

The exported client config looks like this (yours will have real keys):

```ini
[Interface]
PrivateKey = <CLIENT_PRIVATE_KEY>
Address    = 10.0.80.3/24
DNS        = 10.0.80.1

[Peer]
PublicKey           = <SERVER_PUBLIC_KEY>
Endpoint            = home.example.myfritz.net:443
AllowedIPs          = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```

Key points to verify / adjust:

- **`Address = 10.0.80.3/24`** — this travel router's tunnel IP. The FRITZ!Box
  WireGuard server is `10.0.80.1`.
- **`DNS = 10.0.80.1`** — clients resolve names through home, so DNS does not
  leak to the local venue.
- **`AllowedIPs = 0.0.0.0/0, ::/0`** — **full tunnel**. This is what makes home
  the exit point: *all* traffic goes through the tunnel. (If you only want to
  reach home resources and keep local browsing on the venue link, narrow this to
  your home subnets instead — but the AnchorPoint default is full tunnel.)
- **`Endpoint`** — must be your **DDNS hostname on port 443** (see A3).
- **`PersistentKeepalive = 25`** — keeps the tunnel alive through NAT while you
  roam.

### A2. Put the listener on UDP 443

We use **`UDP/443`** because it is indistinguishable from HTTPS to a firewall,
so hotel / airport / corporate networks that block port `51820` still let the
tunnel out.

- When you create the WireGuard connection, set (or note) the **listen port** and
  make the **public-facing port `443/UDP`**.
- On a FRITZ!Box acting as your edge router, the port it listens on *is* the
  public port, so simply ensure the connection uses **`443`** and that the
  Endpoint in the client config ends in **`:443`**.
- If your FRITZ!Box is **behind another modem/router** (bridge mode elsewhere),
  add a port forward on that upstream device: `UDP 443 → FRITZ!Box`.

### A3. DDNS so the tunnel always finds home

Your home IP changes. DDNS maps a **stable hostname** to whatever IP you
currently have.

- **Easiest — MyFRITZ!:** **Internet → MyFRITZ!-Account**. Register / sign in.
  The box gets a free `xxxx.myfritz.net` hostname that always points at your
  current IP. Use that as the `Endpoint` host.
- **Custom DDNS:** **Internet → Permit Access → DynDNS**. Enter your provider's
  update URL, domain, username and password. Then use *your* domain as the
  `Endpoint` host.

Whichever you pick, the client `Endpoint` becomes
`home.example.myfritz.net:443`.

---

## Path B — Linux WireGuard server behind a router

If you prefer a Raspberry Pi / mini-PC / VPS instead of the FRITZ!Box radio:

1. Install WireGuard and generate keys:
   ```bash
   sudo apt install wireguard
   wg genkey | tee server_private.key | wg pubkey > server_public.key
   ```
2. Create `/etc/wireguard/wg0.conf` on the server:
   ```ini
   [Interface]
   Address    = 10.0.80.1/24
   ListenPort = 443
   PrivateKey = <SERVER_PRIVATE_KEY>
   # Route travel-router traffic out to the internet (home exit point):
   PostUp   = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; sysctl -w net.ipv4.ip_forward=1
   PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

   [Peer]
   # The MikroTik travel router
   PublicKey  = <CLIENT_PUBLIC_KEY>
   AllowedIPs = 10.0.80.3/32
   ```
3. Enable it: `sudo systemctl enable --now wg-quick@wg0`.
4. On the **router in front of the server**, forward **`UDP 443 → server:443`**.
5. Set up **DDNS** on that router (or with `ddclient` on the server) so the
   travel router can reach `home.example.myfritz.net:443`.

A sanitized version of both ends lives in
[`config/wireguard-client.conf.example`](../config/wireguard-client.conf.example).

---

## Verify the server before you leave home

From a phone on mobile data (not on your home Wi-Fi), import the client config
into the official **WireGuard app** and connect. Then open
`https://ifconfig.me` — it must show your **home** IP. If it does, the exit point
works and you can move on to the travel router.

Next: [03 — Travel router: MikroTik hAP ax2](03-travel-router-mikrotik.md)
