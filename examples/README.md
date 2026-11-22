# Example generated output

These are **sample** files produced by `render-mesh.py` from the two-site example in
[`../inventory/example.yaml`](../inventory/example.yaml) (Hamburg ↔ Barcelona) — so you
can see exactly what the tool generates before you run it.

> ⚠️ **The secret values here are fake placeholders, not real credentials.** Every key,
> password, passphrase and the DuckDNS token read like `EXAMPLE-…-NOT-A-REAL-KEY` /
> `…-NOT-REAL`, and the endpoints are example DuckDNS names (`anchorpoint-<city>.duckdns.org`).
> They are deliberately un-key-like so they can't be mistaken for secrets — they cannot be
> used and must never be deployed.

## In a real run (how it actually works)
- `gen-mesh-secrets.py` generates a **unique, random** keypair + admin password + Wi-Fi
  passphrase per site, stored only in the SOPS-**encrypted** `secrets/<name>.sops.yaml`
  (gitignored — never committed).
- `render-mesh.py` writes the real per-site config to `deployments/<site>/`: the full
  config as `bootstrap.sensitive.rsc` (**encrypted**), plus a redacted `bootstrap.rsc`
  with the secrets masked. It also writes, per site, a WireGuard config for each roaming
  test device (`clients/<device>.sensitive.conf`, **encrypted**) to import into the
  iPhone/MacBook app. All of `deployments/` is gitignored.

So your real output is never readable-with-secrets in git — the readable files below exist
only to illustrate the structure, with the secrets swapped for obvious junk.

## Files here
| File | What it is |
|------|------------|
| `node_<site>/bootstrap.rsc` | the complete RouterOS config for that site (the real tool writes this to the *encrypted* `bootstrap.sensitive.rsc`; shown here with fake secrets so it's readable) |
| `node_<site>/cheatsheet.md` | the printable installer card for that site |
| `node_<site>/clients/<device>.conf` | the per-device WireGuard config (iPhone / MacBook) to import; the real tool also writes an *encrypted* `<device>.sensitive.conf` — shown here with a fake key |
| `architecture.d2` / `architecture.svg` | the link diagram |

Regenerate these (after editing the template or example) with:
```bash
scripts/render-mesh.py --inventory inventory/example.yaml --no-secrets --out /tmp/x
# then replace the <REDACTED:…> / REPLACE_… tokens with the EXAMPLE-… placeholders
```
