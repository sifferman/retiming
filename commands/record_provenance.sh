#!/usr/bin/env bash
# Record exactly what produced a result, into <outdir>/provenance.json.
#
# usage: stamp_provenance.sh <outdir> <sdc_path> <rtl_file>...
#
# This exists because the constraints files were regenerated partway through a
# 400-run sweep.  The old and new forms were semantically identical, but nothing
# in the results recorded which one a given run used, so the question could not be
# settled after the fact.  Now it can: every result carries the hash of its
# constraints and RTL.
set -uo pipefail
OUT="${1:?outdir}"; shift
SDC="${1:?sdc}"; shift

hash_of() { [ -f "$1" ] && sha1sum "$1" | cut -c1-12 || echo "missing"; }

mkdir -p "$OUT"
{
  echo "{"
  echo "  \"stamped_utc\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
  echo "  \"git_commit\": \"$(git rev-parse --short HEAD 2>/dev/null || echo uncommitted)\","
  echo "  \"git_dirty\": $( [ -n "$(git status --porcelain 2>/dev/null)" ] && echo true || echo false ),"
  echo "  \"sdc\": \"$(basename "$SDC")\","
  echo "  \"sdc_sha1\": \"$(hash_of "$SDC")\","
  printf '  "rtl": ['
  first=1
  for f in "$@"; do
    [ $first -eq 1 ] || printf ', '
    printf '{"file": "%s", "sha1": "%s"}' "$(basename "$f")" "$(hash_of "$f")"
    first=0
  done
  echo "]"
  echo "}"
} > "$OUT/provenance.json"
