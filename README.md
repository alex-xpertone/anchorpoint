# AnchorPoint

> **A WireGuard link between two of your locations, where each site is both a local
> gateway and an internet exit for the other.** Plug into a port (or join a Wi-Fi
> SSID) at site A and browse as if you were at site B. Config-driven: you edit one
> small YAML file and the tool generates the complete, reproducible RouterOS config
> for both sides — secrets encrypted, never committed.

Built for MikroTik RouterOS v7 (hAP ax2 and similar). Validated on RouterOS CHR
7.20.8 (handshake, both-way exit, leak-proof fail-closed).

Each site has a short **identifier** (a city, a code — any short label), used for its
interface names, routing table, device identity and secret keys.

![AnchorPoint — two-site architecture: local (wired + Wi-Fi) vs tunneled exit, the WireGuard tunnel, leak-proof fail-closed, and the netwatch self-heal](docs/architecture.svg)

---

## How it works

```
your small config          generate secrets                 render
inventory/example.yaml ─►  secrets/<name>.sops.yaml    ─►  deployments/<site>/bootstrap.sensitive.rsc
(the two sites, port,       (per-site WG keypair + admin       (the RouterOS config for BOTH sides;
 SSIDs, endpoints)           + wifi pw — random, ENCRYPTED)     all addressing derived)
        gen-mesh-secrets.py   (writes public keys back)   render-mesh.py
```

- **You hand-write** only the small inventory: each site's `id`/name, its DuckDNS name
  (`duckdns_subdomain`), a Wi-Fi `ssid_suffix`; and for the link, the `wg_port`,
  `wifi_ssid_prefix` and your DuckDNS account `duckdns_token`.
- **Generated for you** (never typed, never committed): the two WireGuard keypairs, the
  admin password and the Wi-Fi passphrase — random, stored only in the SOPS-encrypted bundle.
- Public keys are derived and written back into the inventory (non-secret). Each site's
  public endpoint (`ddns`) is derived from its `duckdns_subdomain`, and the `duckdns_token`
  is moved into the encrypted bundle (see [Dynamic DNS](#dynamic-dns-duckdns)).

## Port map per site (hAP ax2, 5 ports)

| Port | Role |
|------|------|
| `ether1` | WAN / uplink (your local ISP) — optional [Wi-Fi backup](#wi-fi-wan-failover-optional) on `wifi2` |
| `ether2` | **Exit** via the other site |
| `ether3` / `ether4` / `ether5` | **Local** network (normal local internet) |
| Wi-Fi | `wifi1` (5 GHz): own SSID = local · the other site's SSID = exit via that site |

So the port you plug into — or the SSID you join — decides which country you browse from.

## Addressing (two sites: A = index 1, B = index 2 — all derived)

| Thing | Site A | Site B |
|-------|--------|--------|
| Overlay id (tunnel source + watchdog target) | `10.0.80.1/32` | `10.0.80.2/32` |
| Local LAN (SSID `<prefix>-<suffix>`) | `192.168.10.0/24` | `192.168.20.0/24` |
| Exit subnet (traffic out via the other site) | `192.168.11.0/24` | `192.168.21.0/24` |
| Tunnel | `UDP <wg_port>` — both ends | ← same |
| Roaming clients (`wg-clients`, `UDP <wg_client_port>`) | `10.0.91.0/24` (iPhone `.2`, MacBook `.3`) | `10.0.92.0/24` |

**Leak-proof:** the exit subnet is policy-routed into the tunnel with
`action=lookup-only-in-table` — if the tunnel drops, exit traffic is **dropped, not
leaked** to the local ISP. FastTrack is disabled (it bypasses policy routing + MSS clamp).

---

## Prerequisites

```bash
brew install sops age d2                 # the CLIs (macOS; or your package manager)
source scripts/env.sh                    # venv + deps + age key + env vars (idempotent)
```

**`scripts/env.sh` is sourced, not run.** On first use it creates the Python venv and
installs the deps (`jinja2 pyyaml cryptography ruamel.yaml`), generates your age keypair
at `~/.age/keys.txt` if you don't have one, then activates the venv and exports
`SOPS_AGE_KEY_FILE` + `AGE_RECIPIENT`. Source it again in each new shell — it only does
the one-time work once. (Works in zsh and bash. Back up `~/.age/keys.txt` — it's the only
thing that can decrypt your secrets.)

## Quickstart

```bash
# 1. Describe your two sites (copy the example; set each site's duckdns_subdomain +
#    ssid_suffix, and the link's wg_port + your duckdns_token). my-link.yaml is gitignored.
cp inventory/example.yaml inventory/my-link.yaml

# 2. Generate keys + passwords (encrypted bundle; public keys written back)
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml

# 3. Render the config for both sides
scripts/render-mesh.py --inventory inventory/my-link.yaml --out deployments

# 4. (optional) diagram
scripts/render-diagrams.sh deployments/architecture.d2
```

Each site gets `deployments/<site>/bootstrap.sensitive.rsc` (encrypted),
`bootstrap.rsc` (redacted, safe to read), and `cheatsheet.md` (a printable install card).
Decrypt a site's config to a scratch file **outside the repo**, paste it into that
router over a console/WinBox terminal, then shred the scratch file.

Each site also gets `deployments/<site>/clients/<device>.sensitive.conf` — a ready
WireGuard config per **test device** (iPhone, MacBook) to import on your phone/laptop
(see [Test clients](#test-clients-iphone--macbook)).

Full runbook — DDNS/CGNAT collection, port-forwarding, flashing, verification,
day-2 ops — in **[docs/ONBOARDING.md](docs/ONBOARDING.md)**.

## Config knobs (inventory)

| Field | Where | Meaning |
|-------|-------|---------|
| `id`, `color`, `location`, `country` | per site | identity / labels (`color` = the site's short identifier) |
| `duckdns_subdomain` | per site | DuckDNS name for this site; its endpoint `<sub>.duckdns.org` is derived from it |
| `ddns` | per site | *(optional)* a static endpoint (DDNS name / public IP) — only for a site with **no** `duckdns_subdomain` |
| `ssid_suffix` | per site | Wi-Fi SSID = `wifi_ssid_prefix` + `-` + suffix |
| `wan_wifi_backup` | per site | *(optional)* `{ssid, password}` of your local router's Wi-Fi → a **WAN failover** uplink (see below). `password` is **(secret)** — `gen` encrypts it into the bundle |
| `wifi_ssid_prefix` | link | base SSID name |
| `wifi_ap_iface` / `wifi_wan_iface` | link | radios for the AnchorPoint SSIDs / the Wi-Fi WAN backup (default `wifi1`=5 GHz, `wifi2`=2.4 GHz on hAP ax2; **swap on ax3**) |
| `wg_port` | link | the WireGuard UDP port (both ends) |
| `duckdns_token` | link | **(secret)** your DuckDNS account token; `gen-mesh-secrets.py` encrypts it into the bundle and clears it here |
| `wg_client_port` | link | UDP port each site serves its roaming test clients on (default 51823) |
| `clients` | link | roaming test devices per site, e.g. `[iphone, macbook]` — each gets its own config |

(A site may instead carry a full `ssid` for back-compat; `ssid_suffix` wins when present.)

> The `mesh:` block and the `mesh-*` script/template names are just the internal
> tooling names — this builds a **two-site link**.

## Test clients (iPhone + MacBook)

Each site also serves a couple of **roaming WireGuard clients** on a dedicated
`wg-clients` interface (`UDP <wg_client_port>`), so you can dial into a site from your own
devices and verify it end-to-end. Each client is **full-tunnel**: once connected you browse
from that site (its own WAN is your exit).

- Which devices per site is `mesh.clients` (default `[iphone, macbook]`); `gen-mesh-secrets.py`
  makes a keypair for each and `render-mesh.py` writes a ready config to
  `deployments/<site>/clients/<device>.sensitive.conf` (SOPS-encrypted).
- Import one into the WireGuard app:
  ```bash
  sops -d deployments/node_hamburg/clients/iphone.sensitive.conf > /tmp/iphone.conf
  # macOS: WireGuard app → Import tunnel(s) from file → /tmp/iphone.conf
  # iPhone: scan a QR, then shred:  qrencode -t ansiutf8 < /tmp/iphone.conf ; shred -u /tmp/iphone.conf
  ```
- Connect, then open `ifconfig.me` — it should show **that site's** WAN IP. Each site's ISP
  router must forward `UDP <wg_client_port>` to the box (alongside the tunnel port).

## Dynamic DNS (DuckDNS)

Most home/office WANs have a **changing public IP**, so each site advertises itself with a
free [DuckDNS](https://www.duckdns.org) name instead of a fixed IP. The other site and your
roaming clients always dial `anchorpoint-<city>.duckdns.org`; the router keeps that name
pointed at its current IP.

- **You set** two things in the inventory: a `duckdns_subdomain` **per site** (the name you
  registered at duckdns.org, without the `.duckdns.org`), and **one** `duckdns_token` for the
  link (your DuckDNS account token — covers all your subdomains).
- The token is a **secret**: `gen-mesh-secrets.py` moves it from the inventory into the
  SOPS-encrypted bundle and blanks it in the inventory, so no plaintext token is ever
  committed. (To change it later: `sops set secrets/<name>.sops.yaml '["duckdns_token"]' '"<token>"'`.)
- Each site's endpoint (`ddns`) is **derived** as `<duckdns_subdomain>.duckdns.org` — you
  don't set it by hand. (A site with a truly static IP can skip DuckDNS and set `ddns` directly.)
- The generated config installs a `/system script` + `/system scheduler` that re-publishes
  the current IP **every 5 minutes** (and at boot) — outbound, so **no port-forward** is
  needed for DuckDNS itself.

> **TLS note:** the update uses `check-certificate=no` because RouterOS ships no CA bundle by
> default (the request still travels over TLS). To validate strictly, import the DuckDNS CA
> and flip it to `=yes` in the generated `duckdns-update` script.

## Wi-Fi WAN failover (optional)

Each site's internet uplink is the **wired `ether1`** (to your ISP box). You can add a
**Wi-Fi backup uplink** so a site stays online — and the site-to-site tunnel stays up — if
that cable/port fails:

```yaml
    wan_wifi_backup:           # per node
      ssid: MyHomeRouter       # your local router's Wi-Fi (join it as a station)
      password: <its Wi-Fi password>   # secret -> gen encrypts it into the bundle
```

- The hAP ax2 has **two radios**: the AnchorPoint SSIDs stay on **`wifi1` (5 GHz)**; the backup
  joins your router on **`wifi2` (2.4 GHz)** in station mode. Separate radios, so your local/exit
  Wi-Fi and the roaming clients are unaffected. (On an **ax3** the radios are swapped — set
  `wifi_ap_iface`/`wifi_wan_iface`; verify with `/interface wifi print`.)
- **Failover** is by default-route distance: `ether1` = 1 (primary), Wi-Fi = 2 (backup). If the
  `ether1` link drops, traffic moves to Wi-Fi and back automatically. The WireGuard tunnel roams
  to the new path and DuckDNS re-publishes the IP within 5 min.
- **No port-forward** for the backup — it's an outbound station + DHCP client. Best paired with a
  backup that reaches the **same upstream router** as the cable (seamless, same public IP).
- The upstream Wi-Fi password is **(secret)** — `gen-mesh-secrets.py` lifts it from the inventory
  into the encrypted bundle and blanks it, exactly like the DuckDNS token. Omit the whole
  `wan_wifi_backup` block for a wired-only site.

> ⚠ The Wi-Fi **station** syntax (like all the Wi-Fi config) needs validating on your RouterOS
> build — CHR has no radios, so it can't be tested there.

## What's in git (and what's never)

| Kind | In git? |
|------|---------|
| Scripts, templates, example inventory, example secrets file | ✅ |
| Your real inventory `inventory/my-link.yaml` (endpoints, public keys, pre-gen token) | ❌ gitignored |
| Your real secrets bundle `secrets/*.sops.yaml` | ❌ gitignored |
| Generated `deployments/` (rendered configs, even encrypted) | ❌ gitignored |
| age private key `~/.age/keys.txt`, `.venv/` | ❌ gitignored / outside repo |

Secrets are unique per operator — you generate your own; nothing sensitive is shared via this repo.

## Validation

Validated on RouterOS CHR 7.20.8: WireGuard handshake both ways, per-tunnel `netwatch`
watchdog up, both-way internet exit (traffic egresses at the other site's WAN),
local-LAN via own WAN, and fail-closed (tunnel down → exit dropped, no leak). Re-test
Wi-Fi VAPs + physical bridge-port moves on your exact hardware/build before production.
