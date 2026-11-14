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
brew install sops age d2
python3 -m venv .venv && . .venv/bin/activate
pip install jinja2 pyyaml cryptography ruamel.yaml
age-keygen -o ~/.age/keys.txt                     # if you don't have one; prints "Public key: age1..."
export SOPS_AGE_KEY_FILE=$HOME/.age/keys.txt      # your age PRIVATE key (decrypt / render)
export AGE_RECIPIENT=age1...                       # your age PUBLIC key   (encrypt)
```

---

## Phase 0 — collect each site's endpoint (⚠ you need both before rendering)
Each site's config points at the **other** site's endpoint, so both must exist first.
Both sites are servers, so both must be reachable from the internet.

For **each** of the two sites:
1. Factory-reset the hAP ax2, give it internet on `ether1`.
2. Enable DDNS and read the name:
   ```
   /ip cloud set ddns-enabled=yes
   /ip cloud print          # dns-name -> this site's ddns
   ```
3. Note the serial: `/system routerboard print` (field `serial-number`).
4. **CGNAT check** — a site behind carrier NAT can't accept inbound tunnels:
   ```
   /ip cloud print          # compare public-address to the WAN interface address
   ```
   If `public-address` is in `100.64.0.0/10` or is private → that site is behind CGNAT.
   Two CGNAT'd sites cannot connect to each other — make sure at least one has a public IP
   (the other can initiate and keepalive holds the tunnel).

Put each site's DDNS into `ddns:` in your inventory. (Serials aren't in the config; keep them in your asset record.)

---

## Phase 1 — inventory
```bash
cp inventory/example.yaml inventory/my-link.yaml
```
Edit the two node blocks:
- Set each `ddns:` (from Phase 0) and `ssid_suffix:` (its Wi-Fi name = `wifi_ssid_prefix`-`suffix`).
- Set `wg_port:` (the UDP port both ends use).
- Leave `wg_public_key:` as `REPLACE_...` — the generator fills it.

Everything else (subnets, port layout, routes) is **derived** — don't hand-edit.

---

## Phase 2 — generate secrets
```bash
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml           # idempotent
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml --list    # inspect
```
Generates each site's keypair (offline X25519), writes **private** keys +
admin/wifi passwords into `secrets/<name>.sops.yaml` (SOPS-encrypted, gitignored) and
the **public** keys into the inventory. Re-runs never overwrite; `--rotate <name>`
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
2. Decrypt its config to a scratch file **outside the repo**, paste it in
   (WinBox → New Terminal), then shred it:
   ```bash
   sops -d --input-type binary --output-type binary \
     deployments/node_hamburg/bootstrap.sensitive.rsc > /tmp/hamburg.rsc
   # paste /tmp/hamburg.rsc into the router, then:
   shred -u /tmp/hamburg.rsc
   ```
3. **Port-forward on this site's ISP router:** forward the WireGuard UDP port (`wg_port`,
   printed at the bottom of this site's `bootstrap.rsc`) to the router's WAN IP. Both sites
   forward the same port.

| Site | Forward (UDP) |
|------|----------------|
| Hamburg   | `wg_port` (↔ Barcelona) |
| Barcelona | `wg_port` (↔ Hamburg)   |

---

## Phase 6 — verify the live link
- On each site: `/interface wireguard peers print` — the peer shows a recent handshake;
  the watchdog (`/tool netwatch print`) shows UP.
- From each exit port/SSID, confirm the public IP = the other site's node.
- Confirm leak-proof again on real hardware (drop the tunnel; the exit port goes dark, local stays up).

---

## Day-2 operations
| Task | How |
|------|-----|
| Inspect keys | `scripts/gen-mesh-secrets.py --inventory <inv> --list` |
| Rotate a site's key | `gen-mesh-secrets.py --rotate <name>` → re-render → re-flash **both** sites (each holds the other's public key) |
| Change a DDNS | edit inventory `ddns:` → re-render → re-flash both sites |
| Edit any secret | `sops secrets/<name>.sops.yaml` |

---

## What lives where
| Kind | Location | In git? |
|------|----------|---------|
| Sites, DDNS, SSIDs, PUBLIC keys, subnets (derived) | `inventory/*.yaml` | ✅ plaintext |
| Example secrets file (placeholders only) | `secrets/*.sops.yaml.example` | ✅ |
| PRIVATE keys, admin/wifi passwords (your real values) | `secrets/*.sops.yaml` | ❌ gitignored |
| Rendered configs (redacted + encrypted) | `deployments/<site>/…` | ❌ gitignored |
| age private key | `~/.age/keys.txt` | ❌ never |
