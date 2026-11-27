#!/usr/bin/env python3
"""
AnchorPoint Mesh — config generator.

Reads the inventory (2–4 nodes), DERIVES all addressing/ports from
each node's `index`, merges the decrypted SOPS bundle, and renders per node:

    deployments/mesh/<node_id>/bootstrap.rsc            (redacted, git-safe)
    deployments/mesh/<node_id>/bootstrap.sensitive.rsc  (full, SOPS-encrypted)

Also renders the whole-mesh diagram to deployments/mesh/architecture.d2.

Derivation (node index i, remotes = the other nodes in index order):
    wg_ip        = 10.0.80.<i>
    local subnet = 192.168.<i*10>.0/24                 -> ether3..5 + local SSID
    exit k       = 192.168.<i*10 + k>.0/24  (k=1..)    -> ether<1+k> + remote SSID
    pair port    = wg_port_base + min(i,j)*10 + max(i,j)   (both ends forward it)
    exit iface   = wg-<remote.color>   table = to-<remote.color>
    client net   = 10.0.<90+i>.0/24    (wg-clients: iphone .2, macbook .3; full tunnel)

Usage:
    scripts/render-mesh.py                      # full (needs sops + the bundle)
    scripts/render-mesh.py --no-secrets         # redacted only
Requires: pip install jinja2 pyyaml ; sops on PATH (unless --no-secrets)
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

try:
    import yaml
    from jinja2 import Environment, FileSystemLoader, StrictUndefined
except ImportError:
    sys.exit("Missing deps. Run:  pip install jinja2 pyyaml")

REPO = Path(__file__).resolve().parent.parent
TEMPLATES = REPO / "templates"
OUT = REPO / "deployments" / "mesh"
# Your age PUBLIC key (recipient). Set it in the environment — never hardcode a
# personal key in a shared repo. See README (age-keygen).
AGE_RECIPIENT = os.environ.get("AGE_RECIPIENT", "").strip()


def rel(p: Path) -> str:
    try:
        return str(p.relative_to(REPO))
    except ValueError:
        return str(p)


class RedactingDict(dict):
    def __init__(self, *a, redact=False, **k):
        super().__init__(*a, **k)
        self._redact = redact

    def __getitem__(self, key):
        if self._redact:
            return f"<REDACTED:{key}>"
        if key not in self:
            raise KeyError(f"secret '{key}' missing from the bundle")
        return super().__getitem__(key)


def load_secrets(bundle: Path) -> dict:
    env = os.environ.copy()
    if "SOPS_AGE_KEY_FILE" not in env and "SOPS_AGE_KEY" not in env:
        for c in (Path.home() / ".age" / "keys.txt",
                  Path.home() / ".config" / "sops" / "age" / "keys.txt"):
            if c.exists():
                env["SOPS_AGE_KEY_FILE"] = str(c)
                break
    if not bundle.exists():
        sys.exit(f"secrets bundle not found: {bundle}\n  run scripts/gen-mesh-secrets.py first")
    out = subprocess.run(["sops", "--decrypt", str(bundle)],
                         check=True, capture_output=True, text=True, env=env).stdout
    return yaml.safe_load(out) or {}


def enrich(mesh: dict, nodes: list[dict]) -> list[dict]:
    """Attach derived addressing/exit topology to each node.

    Port layout (hAP ax2, 5 ports): ether1 = WAN; exits take ether2, ether3, …
    (one per remote); the LOCAL network gets the remaining ports up to ether5.
    So a 2-node link is ether1=WAN, ether2=exit, ether3..5=local.

    Optional inventory knobs (all have safe fallbacks):
      mesh.wg_port          explicit UDP port for a 2-node link (both ends); if
                            omitted the per-pair port derives from wg_port_base.
      mesh.wifi_ssid_prefix base SSID; combined with each node's ssid_suffix ->
                            "<prefix>-<suffix>". A node may instead give a full
                            `ssid` (back-compat); ssid_suffix wins when present.
    """
    base = mesh.get("wg_port_base", 51823)
    prefix = mesh.get("wifi_ssid_prefix")
    explicit_port = mesh.get("wg_port")
    client_names = mesh.get("clients") or []          # roaming test clients per node (e.g. iphone, macbook)
    client_port = mesh.get("wg_client_port", 51823)   # UDP port each node serves its clients on
    nodes = sorted(nodes, key=lambda n: n["index"])
    by_index = {n["index"]: n for n in nodes}
    # resolve each node's SSID: prefix + per-node suffix, else a full `ssid`;
    # and derive the public endpoint from DuckDNS when a subdomain is given.
    for n in nodes:
        suffix = n.get("ssid_suffix")
        if suffix is not None:
            n["ssid"] = f"{prefix}-{suffix}" if prefix else str(suffix)
        elif "ssid" not in n:
            sys.exit(f"node {n.get('id', n.get('index'))}: give ssid_suffix "
                     f"(with mesh.wifi_ssid_prefix) or a full ssid")
        # DDNS: the site endpoint IS its DuckDNS name (<subdomain>.duckdns.org).
        sub = n.get("duckdns_subdomain")
        if sub:
            n["ddns"] = f"{sub}.duckdns.org"
        elif "ddns" not in n:
            sys.exit(f"node {n.get('id', n.get('index'))}: give duckdns_subdomain "
                     f"or a static ddns endpoint")
    if explicit_port is not None and len(nodes) != 2:
        sys.exit("mesh.wg_port sets one shared port and is only valid for a 2-node "
                 "link; for >2 nodes drop it and let wg_port_base derive per-pair ports")
    for n in nodes:
        i = n["index"]
        n["wg_ip"] = f"10.0.80.{i}"
        n["wan_wifi_backup"] = n.get("wan_wifi_backup")   # optional Wi-Fi WAN failover (ssid + lifted password)
        n["local_subnet"] = f"192.168.{i*10}.0/24"
        n["local_gw"] = f"192.168.{i*10}.1"
        n["exits"] = []
        remotes = [by_index[j] for j in sorted(by_index) if j != i]
        for pos, r in enumerate(remotes):          # exits take ether2, ether3, …
            j = r["index"]
            octet = i * 10 + pos + 1
            n["exits"].append({
                "color": r["color"], "location": r["location"], "ddns": r["ddns"],
                "ssid": r["ssid"], "public_key": r["wg_public_key"],
                "remote_wg_ip": f"10.0.80.{j}",
                "ether": f"ether{2 + pos}", "vap": f"vap-{r['color']}",
                "iface": f"wg-{r['color']}", "table": f"to-{r['color']}",
                "bridge": f"bridge-{r['color']}",
                "subnet": f"192.168.{octet}.0/24", "gw": f"192.168.{octet}.1",
                "pair_port": explicit_port if explicit_port is not None else base + min(i, j) * 10 + max(i, j),
            })
        # LOCAL network gets the ports after the exits, up to ether5
        n["local_ethers"] = [f"ether{k}" for k in range(2 + len(n["exits"]), 6)]
        # ROAMING CLIENTS: each node serves its own test devices (e.g. iphone,
        # macbook) on wg-clients (10.0.<90+i>.0/24, full-tunnel -> they exit HERE).
        inv_clients = n.get("clients") or {}
        n["client_port"] = client_port
        n["client_subnet"] = f"10.0.{90 + i}.0/24"
        n["client_gw"] = f"10.0.{90 + i}.1"
        n["client_peers"] = [
            {"name": cn, "address": f"10.0.{90 + i}.{2 + idx}",
             "public_key": inv_clients.get(cn),
             "priv_key_name": f"{n['color']}_{cn}_wg_private_key"}
            for idx, cn in enumerate(client_names)
        ]
    return nodes


def render(env, template, ctx) -> str:
    return env.get_template(template).render(**ctx)


def write(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    print(f"  wrote {rel(path)}")


def write_encrypted(path: Path, content: str):
    enc = subprocess.run(
        ["sops", "--config", os.devnull, "--encrypt", "--age", AGE_RECIPIENT,
         "--input-type", "binary", "--output-type", "binary", "/dev/stdin"],
        input=content, check=True, capture_output=True, text=True).stdout
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(enc)
    print(f"  wrote {rel(path)}  (encrypted)")


def main():
    ap = argparse.ArgumentParser(description="Render AnchorPoint Mesh node configs.")
    ap.add_argument("--inventory", default="inventory/example.yaml")
    ap.add_argument("--out", default=str(OUT),
                    help="output dir for rendered node configs (default: "
                         "deployments/mesh; point at a lab instance for a lab render)")
    ap.add_argument("--no-secrets", action="store_true", help="redacted only")
    args = ap.parse_args()
    out_dir = Path(args.out)

    inv = yaml.safe_load((REPO / args.inventory).read_text())
    mesh = inv["mesh"]
    nodes = enrich(mesh, inv["nodes"])
    env = Environment(loader=FileSystemLoader(str(TEMPLATES)), undefined=StrictUndefined,
                      trim_blocks=True, lstrip_blocks=True, keep_trailing_newline=True)

    print(f"Rendering mesh '{mesh['name']}' — {len(nodes)} nodes -> {rel(out_dir)}")

    # redacted config + installer cheat-sheet (both non-secret; always)
    red = RedactingDict(redact=True)
    for n in nodes:
        ctx = {"mesh": mesh, "node": n, "nodes": nodes, "secrets": red}
        write(out_dir / n["id"] / "bootstrap.rsc", render(env, "mesh-node.rsc.j2", ctx))
        write(out_dir / n["id"] / "cheatsheet.md", render(env, "mesh-cheatsheet.md.j2", ctx))
        for c in n["client_peers"]:                 # redacted per-device client config (git-safe)
            write(out_dir / n["id"] / "clients" / f"{c['name']}.conf",
                  render(env, "wireguard-client.conf.j2", {"mesh": mesh, "node": n, "client": c, "secrets": red}))

    # diagram
    write(out_dir / "architecture.d2", render(env, "mesh-diagram.d2.j2", {"mesh": mesh, "nodes": nodes}))

    # sensitive (encrypted)
    if not args.no_secrets:
        if not AGE_RECIPIENT:
            sys.exit("Set AGE_RECIPIENT to your age PUBLIC key to write encrypted "
                     "configs (run `age-keygen`; see README), or pass --no-secrets.")
        secrets = RedactingDict(load_secrets(REPO / mesh["secrets_file"]), redact=False)
        for n in nodes:
            ctx = {"mesh": mesh, "node": n, "nodes": nodes, "secrets": secrets}
            write_encrypted(out_dir / n["id"] / "bootstrap.sensitive.rsc",
                            render(env, "mesh-node.rsc.j2", ctx))
            for c in n["client_peers"]:             # importable per-device client config (encrypted)
                write_encrypted(out_dir / n["id"] / "clients" / f"{c['name']}.sensitive.conf",
                                render(env, "wireguard-client.conf.j2", {"mesh": mesh, "node": n, "client": c, "secrets": secrets}))
    print("Done.")


if __name__ == "__main__":
    main()
