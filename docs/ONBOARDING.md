# AnchorPoint — Deployment Runbook (two sites)

Set up a WireGuard link between **two** locations, where each site is both a local
gateway and an internet exit for the other. Examples use **Hamburg** and **Barcelona**
— swap in your own. Run from the repo root. Nothing is skipped.

> ✓ Validated on RouterOS CHR 7.20.8 (handshake, both-way exit, leak-proof fail-closed).
> Still run the **CHR validation pass (Phase 4)** on your exact hardware/build (Wi-Fi
> VAPs, physical bridge-port moves) before production.

---

## 0. One-time operator setup
```bash
brew install sops age d2          # the CLIs (Homebrew; can't be scripted away)
source scripts/env.sh             # venv + Python deps + age key + env vars (idempotent)
```
`scripts/env.sh` is **sourced, not run**: it builds the venv + installs deps on first use,
generates your age key at `~/.age/keys.txt` if missing, activates the venv, and exports
`SOPS_AGE_KEY_FILE` + `AGE_RECIPIENT`. Re-source it in each new shell (the one-time work
runs once). Keep `~/.age/keys.txt` safe and backed up — it's the only key that decrypts
your secrets.

---

## Phase 0 — register DuckDNS + check for CGNAT (⚠ do this before rendering)
Each site advertises itself with a free **DuckDNS** name (home/office public IPs change),
and each site's config points at the **other** site's name — so both must exist first. Both
sites are servers, so both must be reachable from the internet.

1. At [duckdns.org](https://www.duckdns.org), sign in and **register one subdomain per site**
   (e.g. `anchorpoint-hamburg`, `anchorpoint-barcelona`). Copy your account **token** (one
   token covers all your subdomains) — you set it in the inventory once.

For **each** of the two sites:

2. Factory-reset the hAP ax2, give it internet on `ether1`.
3. Note the serial: `/system routerboard print` (field `serial-number`).
4. **CGNAT check** — a site behind carrier NAT can't accept inbound tunnels:
   ```
   /ip cloud set ddns-enabled=yes
   /ip cloud print          # compare public-address to the WAN interface address
   ```
   If `public-address` is in `100.64.0.0/10` or is private → that site is behind CGNAT.
   Two CGNAT'd sites cannot connect to each other — make sure at least one has a public IP
   (the other can initiate and keepalive holds the tunnel).

Put each site's subdomain into `duckdns_subdomain:` and your token into `duckdns_token:`
(next phase). The generated config keeps each name pointed at its live IP automatically.
(Serials aren't in the config; keep them in your asset record.)

---

## Phase 1 — inventory
```bash
cp inventory/example.yaml inventory/my-link.yaml          # my-link.yaml is gitignored
```
Edit the two node blocks:
- Set each `duckdns_subdomain:` (from Phase 0) and `ssid_suffix:` (its Wi-Fi name =
  `wifi_ssid_prefix`-`suffix`). The endpoint `ddns:` is **derived** from the subdomain — leave it.
- Set `wg_port:` (the UDP port both ends use) and `duckdns_token:` (your DuckDNS account token).
- *(optional)* **WAN failover:** set each node's `wan_wifi_backup:` to your local router's Wi-Fi
  (`ssid` + `password`) so the site fails over from the `ether1` cable to a 2.4 GHz Wi-Fi uplink
  (`wifi2`) and back. The password is lifted into the bundle like the token. Remove the block for
  wired-only. See [Wi-Fi WAN failover](../README.md#wi-fi-wan-failover-optional).
- Leave `wg_public_key:` and the `clients:` keys as `REPLACE_...` — the generator fills them.

Everything else (subnets, port layout, routes) is **derived** — don't hand-edit.

> Your real `my-link.yaml` holds the token (until the next phase moves it) plus endpoints and
> public keys, so it's gitignored — only `inventory/example.yaml` is committed.

---

## Phase 2 — generate secrets
```bash
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml           # idempotent
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml --list    # inspect
```
Generates each site's keypair (offline X25519), writes **private** keys +
admin/wifi passwords into `secrets/<name>.sops.yaml` (SOPS-encrypted, gitignored) and
the **public** keys into the inventory. It also **moves your `duckdns_token` and any
`wan_wifi_backup` password** from the inventory into the encrypted bundle and blanks them
there (no plaintext secret is left behind). Re-runs never overwrite; `--rotate <name>`
regenerates one site.

---

## Phase 3 — render
```bash
scripts/render-mesh.py --inventory inventory/my-link.yaml --out deployments
scripts/render-diagrams.sh deployments/architecture.d2
```
Per site you get `bootstrap.rsc` (redacted), `bootstrap.sensitive.rsc` (SOPS-encrypted),
and **`cheatsheet.md`** — a printable installer card (port→country→SSID→subnet map, the
UDP port to forward, install steps). Hand `cheatsheet.md` to whoever racks the box.

---

## Phase 4 — VALIDATE on CHR (before touching real hardware)
1. `render-mesh.py --no-secrets` renders with no Jinja errors.
2. Flash both sites (Hamburg + Barcelona) on two RouterOS CHR VMs (or spare hAP ax2).
3. Confirm the tunnel comes up (`/interface wireguard peers print`, handshake recent).
4. From Hamburg's **exit-via-Barcelona** port/SSID, confirm traffic exits at **Barcelona's**
   WAN IP, and DNS resolves. Then the reverse (Barcelona exiting via Hamburg).
5. Drop the tunnel (disable the peer's WAN) → confirm the exit port has **no fallback**
   to the local ISP (leak-proof `lookup-only-in-table` holds), while local ports stay online.
6. Verify the Wi-Fi VAPs broadcast and land clients on the right bridge/subnet.

Watch for: default-config leftovers (`192.168.88.x`, the default bridge), Wi-Fi VAP
syntax on your exact ROS build, and the per-tunnel `src-nat` return path.

---

## Phase 5 — provision each site
For each of the two sites:
1. Factory-reset; internet on `ether1`.
2. Decrypt its config to a scratch file **outside the repo**:
   ```bash
   sops -d --input-type binary --output-type binary \
     deployments/node_hamburg/bootstrap.sensitive.rsc > "$TMPDIR/hamburg.rsc"
   ```
   The bootstrap is a one-shot script that **adds** config, so you apply it to a
   **clean** router (don't paste it over an existing config — you'd get duplicate-object
   errors). Apply it one of two ways, then remove the scratch file
   (`rm -P "$TMPDIR/hamburg.rsc"` — macOS has no `shred`):
   - **Paste** `hamburg.rsc` into a fresh router (WinBox → New Terminal), **or**
   - **Replace in one shot** (also how you re-flash an already-configured box): upload the
     file (WinBox → Files, or `scp`), then on the router wipe-and-apply — keep defaults, the
     config expects defconf:
     ```
     /system reset-configuration run-after-reset=hamburg.rsc skip-backup=yes
     ```
     The router resets to factory defaults, reboots, and runs the config automatically.
     ⚠ A reset drops your connection — do it **on-site** (or with a tested config), never
     blindly on a remote router.
3. **Port-forward on this site's ISP router:** forward the WireGuard UDP ports (both are
   printed at the bottom of this site's `bootstrap.rsc`) to the router's WAN IP — the tunnel
   port (`wg_port`) and the roaming-clients port (`wg_client_port`).

| Site | Forward (UDP) |
|------|----------------|
| Hamburg   | `wg_port` (↔ Barcelona) · `wg_client_port` (iPhone/MacBook) |
| Barcelona | `wg_port` (↔ Hamburg) · `wg_client_port` (iPhone/MacBook) |

> DuckDNS updates run **outbound** from the router (a 5-min `/system scheduler`) — **no
> port-forward** is needed for the `*.duckdns.org` names.

---

## Phase 6 — verify the live link
- On each site: `/interface wireguard peers print` — the peer shows a recent handshake;
  the watchdog (`/tool netwatch print`) shows UP.
- From each exit port/SSID, confirm the public IP = the other site's node.
- Confirm leak-proof again on real hardware (drop the tunnel; the exit port goes dark, local stays up).

---

## Phase 7 — test clients (iPhone + MacBook)
Each site serves two roaming WireGuard clients on `wg-clients` (`UDP wg_client_port`) so you
can test a site from your own devices — full tunnel, so you exit at that site.

1. Make sure the site's ISP router forwards `UDP wg_client_port` (Phase 5).
2. Import a device config (one per device, per site). Install the QR tool once:
   `brew install qrencode`.
   ```bash
   # iPhone — decrypt straight into a QR in the terminal (nothing hits disk), then
   # scan it in the WireGuard app:  ＋ → Create from QR code
   sops -d --input-type binary --output-type binary \
     deployments/node_hamburg/clients/iphone.sensitive.conf | qrencode -t ansiutf8

   # MacBook — decrypt to a scratch file, import it (WireGuard → Import tunnel(s)
   # from file), then remove it (macOS has no `shred`; rm -P overwrites):
   sops -d --input-type binary --output-type binary \
     deployments/node_hamburg/clients/macbook.sensitive.conf > "$TMPDIR/mb.conf"
   rm -P "$TMPDIR/mb.conf"
   ```
   (QR too dense to scan? Shrink the terminal font / widen the window, or use `-t utf8`.)
3. Connect the device, open `ifconfig.me` — it must show **that site's** WAN IP. Switch to the
   other site's config to confirm it exits there instead.

---

## Day-2 operations
| Task | How |
|------|-----|
| Inspect keys | `scripts/gen-mesh-secrets.py --inventory <inv> --list` |
| Re-apply / replace a site's config | decrypt the new `bootstrap.sensitive.rsc`, upload it, then on the router: `/system reset-configuration run-after-reset=<file> skip-backup=yes` (keeps defaults → resets + applies cleanly). **On-site only** — a reset drops the link. |
| Rotate a site's key | `gen-mesh-secrets.py --rotate <name>` → re-render → re-flash **both** sites (each holds the other's public key) |
| Change a site's DuckDNS name | edit its `duckdns_subdomain:` → re-render → re-flash both sites |
| Change the DuckDNS token | `sops set secrets/<name>.sops.yaml '["duckdns_token"]' '"<token>"'` → re-render |
| Edit any secret | `sops secrets/<name>.sops.yaml` |
| Add / rotate a test device | edit `mesh.clients` (or `--rotate <site>`) → re-render → re-import the new `clients/<device>.sensitive.conf` |

---

## What lives where
| Kind | Location | In git? |
|------|----------|---------|
| Example inventory (placeholders) | `inventory/example.yaml` | ✅ plaintext |
| Your real inventory: subdomains, SSIDs, PUBLIC keys, subnets (+ token until Phase 2) | `inventory/my-link.yaml` | ❌ gitignored |
| Example secrets file (placeholders only) | `secrets/*.sops.yaml.example` | ✅ |
| PRIVATE keys, admin/wifi passwords, **DuckDNS token**, **Wi-Fi backup password** (real values) | `secrets/*.sops.yaml` | ❌ gitignored |
| Rendered configs (redacted + encrypted) | `deployments/<site>/…` | ❌ gitignored |
| Per-device client configs (encrypted) | `deployments/<site>/clients/*.sensitive.conf` | ❌ gitignored |
| age private key | `~/.age/keys.txt` | ❌ never |
