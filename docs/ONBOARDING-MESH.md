# AnchorPoint — Deployment Runbook

Provision 2–4 locations into a WireGuard link/mesh where every node is both a local
gateway and an internet exit for the others. Examples use two sites, **Hamburg** and
**Barcelona** — swap in your own. Run from the repo root. Nothing is skipped.

> ✓ Validated on RouterOS CHR 7.20.8 (2-site link: handshake, both-way exit,
> leak-proof fail-closed). Still run the **CHR validation pass (Phase 4)** on your
> exact hardware/build (Wi-Fi VAPs, physical bridge-port moves) before production.

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

## Phase 0 — collect DDNS + serials (⚠ you need ALL sites before rendering)
Every node's config references **every other node's endpoint**, so you cannot render
until all sites' DDNS names exist. And every node is a *server*, so every site must be reachable.

For **each** site:
1. Factory-reset the hAP ax2, give it internet on `ether1`.
2. Enable DDNS and read the name:
   ```
   /ip cloud set ddns-enabled=yes
   /ip cloud print          # dns-name -> this site's ddns
   ```
3. Note the serial: `/system routerboard print` (field `serial-number`).
4. **CGNAT check** — a node behind carrier NAT can't accept inbound tunnels:
   ```
   /ip cloud print          # compare public-address to the WAN interface address
   ```
   If `public-address` is in `100.64.0.0/10` or is private → that site is behind CGNAT.
   It can still *initiate* to public peers (keepalive holds the tunnel), but **two
   CGNAT'd sites cannot connect to each other.** Ensure at least the sites that must
   accept inbound have a public IP.

Put each site's DDNS into `ddns:` in your inventory. (Serials aren't in the config; keep them in your asset record.)

---

## Phase 1 — inventory
Copy and edit the example:
```bash
cp inventory/example.yaml inventory/my-link.yaml
```
- Keep **2, 3, or 4** node blocks. Indices must be contiguous 1..N.
- Set each `ddns:` (from Phase 0) and `ssid_suffix:` (its Wi-Fi name = `wifi_ssid_prefix`-`suffix`).
- Set `wg_port` for a 2-site link (drop it for a 3–4 site mesh so per-pair ports derive).
- Leave `wg_public_key:` as `REPLACE_...` — the generator fills it.

Everything else (subnets, ports, interfaces, routes) is **derived** — don't hand-edit.

---

## Phase 2 — generate secrets
```bash
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml           # idempotent
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml --list    # inspect
```
Generates each node's keypair (offline X25519), writes **private** keys +
admin/wifi passwords into `secrets/<name>.sops.yaml` (SOPS-encrypted, gitignored)
and the **public** keys into the inventory. Re-runs never overwrite; `--rotate <name>`
regenerates one node.

---

## Phase 3 — render
```bash
scripts/render-mesh.py --inventory inventory/my-link.yaml --out deployments
scripts/render-diagrams.sh deployments/architecture.d2
```
Per node you get `bootstrap.rsc` (redacted), `bootstrap.sensitive.rsc` (SOPS-encrypted),
and **`cheatsheet.md`** — a standalone printable installer card (port→country→SSID→subnet
map, the exact UDP ports to forward, install steps). Hand `cheatsheet.md` to whoever racks the box.

---

## Phase 4 — VALIDATE on CHR (do this before touching real hardware)
1. `render-mesh.py --no-secrets` renders with no Jinja errors.
2. Flash the two sites (Hamburg + Barcelona) on two RouterOS CHR VMs (or spare hAP ax2).
3. Confirm the tunnel comes up (`/interface wireguard peers print`, handshake recent).
4. From Hamburg's **exit-via-Barcelona** port/SSID, confirm traffic exits at **Barcelona's**
   WAN IP, and DNS resolves. Then the reverse (Barcelona exiting via Hamburg).
5. Drop the tunnel (disable the peer's WAN) → confirm the exit port has **no fallback**
   to the local ISP (leak-proof `lookup-only-in-table` holds), while local ports stay online.
6. Verify the Wi-Fi VAPs broadcast and land clients on the right bridge/subnet.
7. Only then scale to 3/4 sites and re-test each exit independently.

Watch for: default-config leftovers (`192.168.88.x`, the default bridge), Wi-Fi VAP
syntax on your exact ROS build, and the per-tunnel `src-nat` return path.

---

## Phase 5 — provision each node
Per site:
1. Factory-reset; internet on `ether1`.
2. Decrypt its config to a scratch file **outside the repo**, paste it in
   (WinBox → New Terminal), then shred it:
   ```bash
   sops -d --input-type binary --output-type binary \
     deployments/node_hamburg/bootstrap.sensitive.rsc > /tmp/hamburg.rsc
   # paste /tmp/hamburg.rsc into the router, then:
   shred -u /tmp/hamburg.rsc
   ```
3. **Port-forward on this site's ISP router:** forward the **N−1 UDP port(s)** listed
   at the bottom of this node's `bootstrap.rsc` to the router's WAN IP. (Pair port =
   `wg_port`, or `wg_port_base + min(i,j)*10 + max(i,j)`; both ends of a tunnel forward the same port.)

### Port-forward (2-site example)
| Site | Forward these UDP ports |
|------|-------------------------|
| Hamburg   | 51820 (↔ Barcelona) |
| Barcelona | 51820 (↔ Hamburg)   |

(For a 3–4 site mesh each site forwards N−1 ports — one per tunnel; the exact list is printed in each node's `bootstrap.rsc`.)

---

## Phase 6 — verify the live link
- On each node: `/interface wireguard peers print` — each peer shows a recent handshake;
  the per-tunnel watchdogs (`/tool netwatch print`) show UP.
- From each exit port/SSID, confirm the public IP = the target site's node.
- Confirm leak-proof again on real hardware (drop a tunnel; the exit port should go dark, local stays up).

---

## Day-2 operations
| Task | How |
|------|-----|
| Inspect keys | `scripts/gen-mesh-secrets.py --inventory <inv> --list` |
| Rotate one node's key | `gen-mesh-secrets.py --rotate <name>` → re-render → **re-flash ALL nodes** (they all hold its public key) |
| **Add a site** | add a node block → `gen-mesh-secrets.py` → `render-mesh.py` → **re-flash every node** (each gains a peer) + forward the new ports |
| Change a DDNS | edit inventory `ddns:` → re-render → re-flash the affected peers |
| Edit any secret | `sops secrets/<name>.sops.yaml` |

**Key rule:** any topology change (add/remove node, rotate a key) touches **all** nodes,
because every node peers with every other. Plan a maintenance window.

---

## What lives where
| Kind | Location | In git? |
|------|----------|---------|
| Nodes, DDNS, SSIDs, PUBLIC keys, subnets (derived) | `inventory/*.yaml` | ✅ plaintext |
| Example secrets file (placeholders only) | `secrets/*.sops.yaml.example` | ✅ |
| PRIVATE keys, admin/wifi passwords (your real values) | `secrets/*.sops.yaml` | ❌ gitignored |
| Rendered node configs (redacted + encrypted) | `deployments/<node>/…` | ❌ gitignored |
| age private key | `~/.age/keys.txt` | ❌ never |
