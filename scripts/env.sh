#!/usr/bin/env bash
# =============================================================================
# AnchorPoint — environment bootstrap.   ***  SOURCE this, don't run it  ***
#
#     source scripts/env.sh        # (or:  . scripts/env.sh)
#
# Idempotent and safe to source every time you open a shell. On first use it:
#   1. checks the CLIs (python3, age, sops),
#   2. generates your age key at ~/.age/keys.txt if you don't have one,
#   3. creates the Python venv + installs deps,
# then (every time) activates the venv and exports SOPS_AGE_KEY_FILE +
# AGE_RECIPIENT, which gen-mesh-secrets.py and render-mesh.py need.
#
# Works in both zsh (default) and bash. Nothing here is committed-data; your
# keys live in ~/.age and your secrets in the gitignored SOPS bundle.
# =============================================================================

# --- must be SOURCED, not executed (activate + exports must land in YOUR shell)
_ap_sourced=0
if [ -n "${ZSH_VERSION:-}" ]; then
  case "${ZSH_EVAL_CONTEXT:-}" in *file*) _ap_sourced=1 ;; esac
elif [ -n "${BASH_VERSION:-}" ]; then
  (return 0 2>/dev/null) && _ap_sourced=1
fi
if [ "$_ap_sourced" -eq 0 ]; then
  echo "env.sh must be SOURCED, not run:   source scripts/env.sh" >&2
  exit 1
fi
# From here on we are sourced: use 'return', never 'exit' (exit would close the shell).

# --- locate the repo root from this script's own path (zsh/bash safe) ---------
if [ -n "${ZSH_VERSION:-}" ]; then
  eval '_ap_self=${(%):-%N}'          # zsh-only syntax, hidden from bash via eval
elif [ -n "${BASH_SOURCE:-}" ]; then
  _ap_self="${BASH_SOURCE[0]}"
else
  _ap_self="$0"
fi
_ap_root="$(cd "$(dirname "$_ap_self")/.." && pwd)" || return 1

# --- prerequisite: CLIs -------------------------------------------------------
for _t in python3 age sops; do
  if ! command -v "$_t" >/dev/null 2>&1; then
    echo "AnchorPoint: '$_t' not found — install the CLIs:  brew install sops age d2" >&2
    unset _ap_sourced _ap_self _ap_root _t
    return 1
  fi
done

# --- prerequisite: your age key (generate once if missing) --------------------
_ap_key="${SOPS_AGE_KEY_FILE:-$HOME/.age/keys.txt}"
if [ ! -f "$_ap_key" ]; then
  echo "AnchorPoint: no age key at $_ap_key — generating one…"
  mkdir -p "$(dirname "$_ap_key")" && chmod 700 "$(dirname "$_ap_key")" 2>/dev/null
  if ! age-keygen -o "$_ap_key" >/dev/null 2>&1; then
    echo "AnchorPoint: age-keygen failed" >&2
    unset _ap_sourced _ap_self _ap_root _t _ap_key
    return 1
  fi
  chmod 600 "$_ap_key" 2>/dev/null
  echo "AnchorPoint: ⚠ BACK UP $_ap_key — it is the ONLY thing that can decrypt your secrets."
fi

# --- Python venv (create once; reuse after) -----------------------------------
if [ ! -d "$_ap_root/.venv" ]; then
  echo "AnchorPoint: creating .venv…"
  python3 -m venv "$_ap_root/.venv" || { unset _ap_sourced _ap_self _ap_root _t _ap_key; return 1; }
fi
# shellcheck disable=SC1091
. "$_ap_root/.venv/bin/activate" || { unset _ap_sourced _ap_self _ap_root _t _ap_key; return 1; }

# --- deps (install only if missing) ------------------------------------------
if ! python -c 'import jinja2, yaml, cryptography, ruamel.yaml' >/dev/null 2>&1; then
  echo "AnchorPoint: installing Python deps…"
  pip install --quiet --upgrade pip >/dev/null 2>&1
  if ! pip install --quiet jinja2 pyyaml cryptography ruamel.yaml; then
    echo "AnchorPoint: pip install failed" >&2
    unset _ap_sourced _ap_self _ap_root _t _ap_key
    return 1
  fi
fi

# --- export what the tools need ----------------------------------------------
export SOPS_AGE_KEY_FILE="$_ap_key"
export AGE_RECIPIENT="$(age-keygen -y "$_ap_key")"

echo "AnchorPoint env ready — venv active · AGE_RECIPIENT=$AGE_RECIPIENT"
echo "Next:  cp inventory/example.yaml inventory/my-link.yaml   (then edit it)"

unset _ap_sourced _ap_self _ap_root _t _ap_key
