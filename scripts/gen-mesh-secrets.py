#!/usr/bin/env python3
"""
AnchorPoint Mesh — secrets generator.

For every node in the inventory, generates (offline, X25519):
  <name>_wg_private_key           -> encrypted bundle
  <name>_admin_password           -> encrypted bundle   (random)
  <name>_wifi_passphrase          -> encrypted bundle   (random)
  <name>_<client>_wg_private_key  -> encrypted bundle   (one per roaming client, if mesh.clients set)
  duckdns_token                   -> encrypted bundle   (lifted from mesh.duckdns_token, if DuckDNS used)
and writes the DERIVED public keys back into the inventory (node wg_public_key and
node.clients.<client>, non-secret). Plaintext private material never hits disk —
the DuckDNS token is moved into the bundle and blanked in the inventory.
"<name>" is each node's identifier (its `color` field — a city, a code, anything).

Idempotent: existing bundle keys are detected BY NAME (no decryption) and left
alone unless --rotate <name>. Public keys are (re)written whenever we (re)gen a
keypair.

  scripts/gen-mesh-secrets.py --inventory inventory/example.yaml   # fill all missing
  scripts/gen-mesh-secrets.py --rotate barcelona                   # one node only
  scripts/gen-mesh-secrets.py --list

Requires: pip install cryptography ruamel.yaml ; sops on PATH
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import secrets as pysecrets
import string
import subprocess
import sys
from pathlib import Path

try:
    from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
    from cryptography.hazmat.primitives.serialization import (
        Encoding, NoEncryption, PrivateFormat, PublicFormat)
    from ruamel.yaml import YAML
except ImportError:
    sys.exit("Missing deps. Run:  pip install cryptography ruamel.yaml")

REPO = Path(__file__).resolve().parent.parent
INVENTORY = REPO / "inventory" / "example.yaml"
# Your age PUBLIC key (recipient). Set it in the environment — never hardcode a
# personal key in a shared repo. Generate one with `age-keygen -o ~/.age/keys.txt`
# (copy its "Public key:" line), then:  export AGE_RECIPIENT=age1...
AGE_RECIPIENT = os.environ.get("AGE_RECIPIENT", "").strip()


def wg_keypair() -> tuple[str, str]:
    priv = X25519PrivateKey.generate()
    pr = priv.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
    pu = priv.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)
    return base64.b64encode(pr).decode(), base64.b64encode(pu).decode()


def gen_pw(n: int) -> str:
    return "".join(pysecrets.choice(string.ascii_letters + string.digits) for _ in range(n))


def existing_keys(path: Path) -> set[str]:
    if not path.exists():
        return set()
    return {m.group(1) for line in path.read_text().splitlines()
            if (m := re.match(r"^([A-Za-z0-9_]+):", line)) and m.group(1) != "sops"}


def sops_create(path: Path, mapping: dict):
    body = "".join(f"{k}: '{v}'\n" for k, v in mapping.items())
    enc = subprocess.run(
        ["sops", "--config", os.devnull, "--encrypt", "--age", AGE_RECIPIENT,
         "--input-type", "yaml", "--output-type", "yaml", "/dev/stdin"],
        input=body, check=True, capture_output=True, text=True).stdout
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(enc)


def sops_set(path: Path, key: str, value: str):
    subprocess.run(["sops", "set", str(path), f'["{key}"]', json.dumps(value)],
                   check=True, capture_output=True, text=True)


def main():
    ap = argparse.ArgumentParser(description="Generate AnchorPoint Mesh secrets.")
    ap.add_argument("--rotate", metavar="NAME", help="regenerate one node's keypair")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--inventory", default=str(INVENTORY),
                    help="inventory YAML (default: inventory/example.yaml)")
    args = ap.parse_args()

    inventory_path = Path(args.inventory)
    yaml = YAML()
    yaml.preserve_quotes = True
    inv = yaml.load(inventory_path.read_text())
    bundle = REPO / inv["mesh"]["secrets_file"]
    colors = [n["color"] for n in inv["nodes"]]
    client_names = inv["mesh"].get("clients") or []   # roaming test clients per node
    have = existing_keys(bundle)

    if args.list:
        print(f"Bundle: {bundle.name}  ({'exists' if bundle.exists() else 'MISSING'})")
        for c in colors:
            for suf in ("wg_private_key", "admin_password", "wifi_passphrase"):
                k = f"{c}_{suf}"
                print(f"  [{'x' if k in have else ' '}] {k}")
            for cn in client_names:
                k = f"{c}_{cn}_wg_private_key"
                print(f"  [{'x' if k in have else ' '}] {k}")
        if any(n.get("duckdns_subdomain") for n in inv["nodes"]):
            print(f"  [{'x' if 'duckdns_token' in have else ' '}] duckdns_token  (DuckDNS, shared)")
        return

    new: dict[str, str] = {}
    pubs: dict[str, str] = {}
    for node in inv["nodes"]:
        c = node["color"]
        pk = f"{c}_wg_private_key"
        if args.rotate == c or pk not in have:
            priv, pub = wg_keypair()
            new[pk] = priv
            node["wg_public_key"] = pub          # non-secret -> inventory
            pubs[c] = pub
        for suf, length in (("admin_password", 24), ("wifi_passphrase", 20)):
            k = f"{c}_{suf}"
            if k not in have or args.rotate == c:
                new[k] = gen_pw(length)
        # roaming test clients (iphone, macbook, ...) — each gets its own keypair;
        # private key -> bundle, public key -> inventory (node.clients.<name>).
        if client_names:
            nc = node.get("clients")
            if not isinstance(nc, dict):
                nc = {}
                node["clients"] = nc
            for cn in client_names:
                ck = f"{c}_{cn}_wg_private_key"
                if args.rotate == c or ck not in have:
                    priv, pub = wg_keypair()
                    new[ck] = priv
                    nc[cn] = pub
                    pubs[f"{c}/{cn}"] = pub

    # DuckDNS token: one shared account secret. Lift it from the inventory into the
    # encrypted bundle, then blank it in the inventory so no plaintext token lingers.
    token_lifted = False
    if any(n.get("duckdns_subdomain") for n in inv["nodes"]) and "duckdns_token" not in have:
        tok = inv["mesh"].get("duckdns_token")
        if tok and str(tok) not in ("REPLACE_duckdns_token", "__in_sops_bundle__"):
            new["duckdns_token"] = str(tok)
            inv["mesh"]["duckdns_token"] = "__in_sops_bundle__"   # moved to the bundle
            token_lifted = True
        else:
            print("  NOTE: DuckDNS subdomains are set but no token is in the bundle.\n"
                  "        Put your DuckDNS token in mesh.duckdns_token and re-run, or:\n"
                  f"        sops set {bundle.name} '[\"duckdns_token\"]' '\"<token>\"'")

    if not new:
        print("Nothing to do — all keys present. (--rotate <color> to regenerate.)")
        return

    if not bundle.exists():
        if not AGE_RECIPIENT:
            sys.exit("Set AGE_RECIPIENT to your age PUBLIC key before creating the "
                     "secrets bundle (run `age-keygen`; see README).")
        sops_create(bundle, new)
    else:
        for k, v in new.items():
            sops_set(bundle, k, v)

    if pubs or token_lifted:                      # persist pubkeys + token blanking into inventory
        yaml.dump(inv, inventory_path.open("w"))

    print(f"Updated {bundle.name} — set {len(new)} key(s):")
    for k in new:
        print(f"  + {k}")
    if pubs:
        print("\nPublic keys written to inventory:")
        for c, p in pubs.items():
            print(f"  {c:7} {p}")
    print("\nNext:  scripts/render-mesh.py")


if __name__ == "__main__":
    main()
