#!/usr/bin/env bash
# Helpers for driving the Cadence/Xilinx tools on eq1.
#
# eq1's ~/.bashrc unconditionally prints a Xilinx banner, which corrupts the
# scp/rsync wire protocol ("Received message too long").  We therefore never use
# scp or rsync -- all transfers are tar streams over ssh, whose stdin/stdout are
# unaffected by remote stdout chatter.

set -uo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../flows/common/env.sh"

REMOTE_ROOT="${REMOTE_ROOT:-retiming_work}"

eq_ssh() { ssh -o BatchMode=yes "$EQ_HOST" "$@"; }

# Strip the login banner from captured output.
eq_clean() { grep -v -E "^(Autocomplete|XILINX_XRT|PATH|LD_LIBRARY_PATH|PYTHONPATH) " || true; }

# Push the parts of the repo the remote tools need.
eq_push() {
  local dirs=("$@")
  [ ${#dirs[@]} -eq 0 ] && dirs=(benchmarks flows scripts)
  ( cd "$RETIMING_ROOT" && tar cf - "${dirs[@]}" ) | \
    eq_ssh "mkdir -p ~/$REMOTE_ROOT && cd ~/$REMOTE_ROOT && tar xf -" 2>&1 | eq_clean
}

# Push the selected PDK's views, and pre-decompress liberty if needed.
eq_push_pdk() {
  eq_ssh "mkdir -p ~/$REMOTE_ROOT/pdk/lef ~/$REMOTE_ROOT/pdk/lib" 2>&1 | eq_clean
  tar cf - -C "$(dirname "$PDK_TECH_LEF")" \
      "$(basename "$PDK_TECH_LEF")" "$(basename "$PDK_SC_LEF")" | \
    eq_ssh "cd ~/$REMOTE_ROOT/pdk/lef && tar xf -" 2>&1 | eq_clean

  # Some platforms ship liberty gzipped (gf180), others plain (nangate45).
  if [ -n "${PDK_LIB_PLAIN:-}" ] && [ -f "${PDK_LIB_PLAIN}" ]; then
    cat "$PDK_LIB_PLAIN" | \
      eq_ssh "cat > ~/$REMOTE_ROOT/pdk/lib/$PDK_LIB_BASENAME" 2>&1 | eq_clean
  elif [ -n "${PDK_LIB_GZ:-}" ] && [ -f "$PDK_LIB_GZ" ]; then
    gunzip -c "$PDK_LIB_GZ" | \
      eq_ssh "cat > ~/$REMOTE_ROOT/pdk/lib/$PDK_LIB_BASENAME" 2>&1 | eq_clean
  else
    echo "eq_push_pdk: no liberty found for RT_PDK=$RT_PDK" >&2
  fi

  # gf180 additionally ships ss/ff corners, which the multi-corner axis uses.
  if [ "$RT_PDK" = "gf180" ]; then
    for c in "$PDK_CORNER_SS" "$PDK_CORNER_FF"; do
      gz="$PDK_DIR/lib/${PDK_LIBNAME}__${c}.lib.gz"
      [ -f "$gz" ] || continue
      gunzip -c "$gz" | \
        eq_ssh "cat > ~/$REMOTE_ROOT/pdk/lib/${PDK_LIBNAME}__${c}.lib" 2>&1 | eq_clean
    done
  fi
  eq_ssh "ls -la ~/$REMOTE_ROOT/pdk/lib ~/$REMOTE_ROOT/pdk/lef | tail -8" 2>&1 | eq_clean
}

# Pull a results directory back.
#
# We cannot stream a tar straight down stdout: eq1 prints a Xilinx banner on
# every shell startup, which lands in front of the tar bytes and destroys the
# archive.  So the remote side base64-encodes between sentinels and we decode
# only the payload.  Costs 33% transfer overhead on small report files; worth it
# for a transfer that actually works.
eq_pull() {
  local remote="$1" local_dest="$2"
  mkdir -p "$local_dest"
  local tmp
  tmp="$(mktemp)"
  eq_ssh "cd ~/$REMOTE_ROOT && echo __RTBEGIN__ && tar czf - $remote 2>/dev/null | base64 -w0 && echo && echo __RTEND__" \
    < /dev/null > "$tmp" 2>/dev/null
  if ! grep -q __RTBEGIN__ "$tmp"; then
    echo "eq_pull: no sentinel in remote output for $remote" >&2
    rm -f "$tmp"; return 1
  fi
  sed -n '/__RTBEGIN__/,/__RTEND__/p' "$tmp" \
    | grep -v -E '__RTBEGIN__|__RTEND__' | tr -d '\n' \
    | base64 -d 2>/dev/null | tar xzf - -C "$local_dest" 2>/dev/null
  local rc=$?
  rm -f "$tmp"
  return $rc
}

# Environment prelude for any Cadence tool run on eq1.
eq_cadence_prelude() {
  cat <<'PRE'
export CDS_SKIP_OS_CHECK_ON_STARTUP=1
export LD_LIBRARY_PATH=$HOME/Utils/eda-compat-libs:${LD_LIBRARY_PATH:-}
export PATH=/mada/software/cadence/DDI231/GENUS231/bin:/mada/software/cadence/DDI231/INNOVUS231/bin:$PATH
PRE
}
