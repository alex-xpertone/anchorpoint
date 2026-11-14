# AnchorPoint

> **WireGuard between 2–4 of your own locations, where every site is both a local
> gateway and an internet exit for the others.** Plug into a port (or join a Wi-Fi
> SSID) at site A and browse as if you were at site B. Config-driven: you edit one
> small YAML file and the tool generates the complete, reproducible RouterOS config
> for every side — secrets encrypted, never committed.

Built for MikroTik RouterOS v7 (hAP ax2 and similar). Validated on RouterOS CHR
7.20.8 (handshake, both-way exit, leak-proof fail-closed).

Each node has a short **identifier** (a city, a code — any short label), used for
its interface names, routing tables, device identity and secret keys.

---

## How it works

```
your small config            generate secrets                 render
inventory/example.yaml ─►  secrets/<name>.sops.yaml     ─►  deployments/<node>/bootstrap.sensitive.rsc
(locations, ports,         (per-node WG keypair + admin       (the RouterOS config for BOTH sides;
 SSIDs, endpoints)          + wifi pw — random, ENCRYPTED)     all addressing/ports DERIVED)
         gen-mesh-secrets.py  (writes public keys back)   render-mesh.py
```

- **You hand-write** only the small inventory: each location's `id`/name, its public
  endpoint (`ddns`), a Wi-Fi `ssid_suffix`; and per link the `wg_port` and `wifi_ssid_prefix`.
- **Generated for you** (never typed, never committed): the WireGuard keypairs, the
  admin password and the Wi-Fi passphrase — all random, stored only in the SOPS-encrypted bundle.
- Public keys are derived and written back into the inventory (non-secret).

## Port map per node (hAP ax2, 5 ports)

| Port | Role |
|------|------|
| `ether1` | WAN / uplink (your local ISP) |
| `ether2` | **Exit** via the other site (one exit port per peer for a bigger mesh) |
| `ether3` / `ether4` / `ether5` | **Local** network (normal local internet) |
| Wi-Fi | own SSID = local · the other site's SSID = exit via that site |

So the port you plug into — or the SSID you join — decides which country you browse from.

## Addressing (all derived from each node's `index`, i = 1..N)

| Thing | Value |
|-------|-------|
| Overlay id (tunnel source + watchdog target) | `10.0.80.<i>/32` |
| Local LAN (SSID `<prefix>-<suffix>`) | `192.168.<i·10>.0/24` |
| Exit net per peer | `192.168.<i·10 + k>.0/24`, k = 1..N−1 |
| Tunnel UDP port | `wg_port` (explicit, 2-node link) or `wg_port_base + min(i,j)·10 + max(i,j)` |
| Per-exit interface / table | `wg-<peer>` / `to-<peer>` |

**Leak-proof:** each exit subnet is policy-routed into its tunnel with
`action=lookup-only-in-table` — if the tunnel drops, exit traffic is **dropped, not
leaked** to the local ISP. FastTrack is disabled (it bypasses policy routing + MSS clamp).

---

## Prerequisites

```bash
brew install sops age d2                 # macOS (or your package manager)
python3 -m venv .venv && . .venv/bin/activate
pip install jinja2 pyyaml cryptography ruamel.yaml

# One age keypair per operator. Keep the PRIVATE key safe and OUT of the repo.
age-keygen -o ~/.age/keys.txt            # prints "Public key: age1..."
export SOPS_AGE_KEY_FILE=$HOME/.age/keys.txt    # to decrypt / render
export AGE_RECIPIENT=age1...                     # your PUBLIC key, to encrypt
```

## Quickstart (2-site link)

```bash
# 1. Describe your sites (copy the example and edit ddns + ssid_suffix + wg_port)
cp inventory/example.yaml inventory/my-link.yaml

# 2. Generate keys + passwords (encrypted bundle; public keys written back)
scripts/gen-mesh-secrets.py --inventory inventory/my-link.yaml

# 3. Render the per-side RouterOS configs
scripts/render-mesh.py --inventory inventory/my-link.yaml --out deployments

# 4. (optional) diagram
scripts/render-diagrams.sh deployments/architecture.d2
```

Each node gets `deployments/<node>/bootstrap.sensitive.rsc` (encrypted),
`bootstrap.rsc` (redacted, safe to read), and `cheatsheet.md` (a printable install card).
Decrypt a node's config to a scratch file **outside the repo**, paste it into that
router over a console/WinBox terminal, then shred the scratch file.

Full runbook — DDNS/CGNAT collection, port-forwarding, flashing, verification,
day-2 ops — in **[docs/ONBOARDING-MESH.md](docs/ONBOARDING-MESH.md)**.

## Config knobs (inventory)

| Field | Where | Meaning |
|-------|-------|---------|
| `id`, `color`, `location`, `country` | per node | identity / labels (`color` = the node's short identifier) |
| `ddns` | per node | the site's public endpoint (DDNS name or public IP) |
| `ssid_suffix` | per node | Wi-Fi SSID = `wifi_ssid_prefix` + `-` + suffix |
| `wifi_ssid_prefix` | mesh | base SSID name |
| `wg_port` | mesh | explicit UDP port for a 2-node link (both ends) |
| `wg_port_base` | mesh | fallback for deriving per-pair ports in a 3–4 node mesh |

(A node may instead carry a full `ssid` for back-compat; `ssid_suffix` wins when present.)

## What's in git (and what's never)

| Kind | In git? |
|------|---------|
| Scripts, templates, example inventory, example secrets file | ✅ |
| Your real secrets bundle `secrets/*.sops.yaml` | ❌ gitignored |
| Generated `deployments/` (rendered configs, even encrypted) | ❌ gitignored |
| age private key `~/.age/keys.txt`, `.venv/` | ❌ gitignored / outside repo |

Secrets are unique per operator — you generate your own; nothing sensitive is shared via this repo.

## Validation

Validated on RouterOS CHR 7.20.8 for a 2-site link: WireGuard handshake both ways,
per-tunnel `netwatch` watchdog up, both-way internet exit (traffic egresses at the
peer's WAN), local-LAN via own WAN, and fail-closed (tunnel down → exit dropped, no
leak). Re-test Wi-Fi VAPs + physical bridge-port moves on your exact hardware/build
before production.
