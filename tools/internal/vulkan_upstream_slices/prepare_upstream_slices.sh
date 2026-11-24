#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# prepare_upstream_slices.sh
#
# Deterministic, non-destructive verifier, summary reporter, and patch-series
# exporter for splitting the Castle Game Engine Vulkan 1.3+ RHI branch into
# 8 dependency-ordered, acyclic upstream PR slices against
# castle-engine/castle-engine.
#
# Safety guarantees:
#   - NEVER modifies tracked repository files, git index, or branches.
#   - NEVER pushes to any remote or opens any pull request.
#   - Compatible with bash 3.2+ (Linux, macOS Apple Silicon, Windows Git Bash)
#     and both full git clones and shallow CI checkouts (actions/checkout).
# ------------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
MANIFEST_FILE="${SCRIPT_DIR}/slice_manifest.tsv"
DEFAULT_MERGE_BASE="e97e84b7aa51f628a7978c5420cefb53a3da05ab"

DO_VERIFY=0
DO_SUMMARY=0
EXPORT_DIR=""
EXPLICIT_BASE=""

usage() {
  cat <<'EOF'
Usage: prepare_upstream_slices.sh [options]

Options:
  --verify                 Verify slice_manifest.tsv integrity, file existence,
                           zero duplicates, line-ending hygiene, acyclic Pascal
                           uses-clause slice ordering, and (when base commit is
                           present in git history) 100% git diff partition coverage.
  --summary                Print per-slice file breakdown table (Slices 1..8 + 0).
  --base=<commit-or-ref>   Explicit base commit/ref for git diff verification
                           and patch export (default: auto-detect upstream/master
                           merge-base or e97e84b7aa51f628a7978c5420cefb53a3da05ab).
  --export-patches=<dir>   Export clean per-slice .patch files (Slices 1..8, with
                           Slice 3 split into core vs 03b-examples-auto-dproj)
                           into <dir> without modifying the working tree.
  -h, --help               Show this help message.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --verify)
      DO_VERIFY=1
      ;;
    --summary)
      DO_SUMMARY=1
      ;;
    --base=*)
      EXPLICIT_BASE="${arg#*=}"
      ;;
    --export-patches=*)
      EXPORT_DIR="${arg#*=}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ "$DO_VERIFY" -eq 0 ] && [ "$DO_SUMMARY" -eq 0 ] && [ -z "$EXPORT_DIR" ]; then
  DO_VERIFY=1
  DO_SUMMARY=1
fi

if [ ! -f "$MANIFEST_FILE" ]; then
  echo "ERROR: Missing slice manifest: $MANIFEST_FILE" >&2
  exit 1
fi

cd "$REPO_ROOT"

resolve_base_commit() {
  if [ -n "$EXPLICIT_BASE" ]; then
    if git rev-parse --verify --quiet "${EXPLICIT_BASE}^{commit}" >/dev/null 2>&1; then
      git rev-parse "${EXPLICIT_BASE}^{commit}"
      return 0
    fi
    echo "ERROR: Explicit --base='${EXPLICIT_BASE}' is not reachable in local git history." >&2
    return 1
  fi

  if git rev-parse --verify --quiet "upstream/master^{commit}" >/dev/null 2>&1; then
    git merge-base upstream/master HEAD
    return 0
  fi

  if git rev-parse --verify --quiet "${DEFAULT_MERGE_BASE}^{commit}" >/dev/null 2>&1; then
    echo "$DEFAULT_MERGE_BASE"
    return 0
  fi

  echo ""
  return 0
}

BASE_COMMIT="$(resolve_base_commit)"

# ------------------------------------------------------------------------------
# 1. Manifest Integrity, Disk Existence, Line-Ending Hygiene & Pascal uses DAG
# ------------------------------------------------------------------------------
if [ "$DO_VERIFY" -eq 1 ]; then
  echo "[vulkan-slices] Verifying manifest structure and repository files..."

  # Check LF hygiene on shell script itself (guaranteed via .gitattributes *.sh text eol=lf)
  if LC_ALL=C grep -q $'\r' "${SCRIPT_DIR}/prepare_upstream_slices.sh"; then
    echo "ERROR: prepare_upstream_slices.sh contains CRLF line endings (expected pure LF)." >&2
    exit 1
  fi

  awk -F '\t' '
    BEGIN {
      errors = 0
      total = 0
    }
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      if (NF != 4) {
        printf("ERROR: Line %d: expected 4 tab-separated columns, got %d\n", NR, NF) > "/dev/stderr"
        errors++
        next
      }
      sid = $1
      slug = $2
      cat = $3
      path = $4

      if (sid !~ /^[0-8]$/) {
        printf("ERROR: Line %d: invalid slice_id \"%s\" for %s\n", NR, sid, path) > "/dev/stderr"
        errors++
      }
      if (cat != "core" && cat != "auto-dproj" && cat != "branch-meta") {
        printf("ERROR: Line %d: invalid category \"%s\" for %s\n", NR, cat, path) > "/dev/stderr"
        errors++
      }
      if (sid == "0" && cat != "branch-meta") {
        printf("ERROR: Line %d: slice 0 entry %s must have category branch-meta\n", NR, path) > "/dev/stderr"
        errors++
      }
      if (sid != "0" && cat == "branch-meta") {
        printf("ERROR: Line %d: non-zero slice %s entry %s cannot be branch-meta\n", NR, sid, path) > "/dev/stderr"
        errors++
      }
      if (path in seen) {
        printf("ERROR: Duplicate path \"%s\" on line %d (first seen on line %d)\n", path, NR, seen[path]) > "/dev/stderr"
        errors++
      }
      seen[path] = NR
      slice_counts[sid]++
      total++
    }
    END {
      for (s = 1; s <= 8; s++) {
        if (slice_counts[s] + 0 == 0) {
          printf("ERROR: Slice %d has 0 assigned files\n", s) > "/dev/stderr"
          errors++
        }
      }
      if (errors > 0) exit 1
      printf("[vulkan-slices] Manifest syntax OK (%d unique tracked entries across Slices 0..8).\n", total)
    }
  ' "$MANIFEST_FILE"

  # Verify every listed path exists on disk
  MISSING_ON_DISK=0
  while IFS=$'\t' read -r sid slug cat relpath; do
    relpath="${relpath%$'\r'}"
    case "$sid" in
      ""|\#*) continue ;;
    esac
    if [ ! -e "$relpath" ]; then
      echo "ERROR: Manifest file missing on disk: $relpath (slice $sid)" >&2
      MISSING_ON_DISK=$((MISSING_ON_DISK + 1))
    fi
  done < "$MANIFEST_FILE"

  if [ "$MISSING_ON_DISK" -ne 0 ]; then
    echo "ERROR: $MISSING_ON_DISK manifest file(s) missing on disk." >&2
    exit 1
  fi

  # Verify required documentation & release notes exist and are non-empty
  for doc_file in \
    "doc/vulkan_renderer.md" \
    "doc/vulkan_release_notes.md" \
    "doc/vulkan_upstream_pr_guide.md"; do
    if [ ! -s "$doc_file" ]; then
      echo "ERROR: Required documentation file missing or empty: $doc_file" >&2
      exit 1
    fi
  done

  # Verify strict acyclic Pascal uses-clause ordering across Slices 1..8:
  # No .pas unit in Slice S (1..8) may list in its uses clause any unit whose .pas
  # file is assigned to a strictly later Slice T > S!
  echo "[vulkan-slices] Verifying acyclic Pascal uses-clause DAG across Slices 1..8..."
  awk -F '\t' '
    function basename_no_ext(p,    n, arr, base) {
      n = split(p, arr, "/")
      base = tolower(arr[n])
      sub(/\.pas$/, "", base)
      return base
    }
    function dirname_of(p,    idx) {
      idx = match(p, /\/[^\/]*$/)
      if (idx > 0) return substr(p, 1, idx - 1)
      return "."
    }
    function slurp_file(fpath,    line, content) {
      content = ""
      while ((getline line < fpath) > 0) {
        content = content "\n" line
      }
      close(fpath)
      return content
    }
    function expand_local_includes(pas_path, raw,    dir, out, pre, post, tag, inc_file, inc_path) {
      dir = dirname_of(pas_path)
      out = ""
      while (match(raw, /\{\$[iI]([nN][cC][lL][uU][dD][eE])?[[:space:]]+[^}[:space:]]+[[:space:]]*\}/)) {
        pre = substr(raw, 1, RSTART - 1)
        tag = substr(raw, RSTART, RLENGTH)
        post = substr(raw, RSTART + RLENGTH)
        sub(/^\{\$[iI]([nN][cC][lL][uU][dD][eE])?[[:space:]]+/, "", tag)
        sub(/[[:space:]]*\}$/, "", tag)
        inc_path = dir "/" tag
        inc_file = slurp_file(inc_path)
        if (inc_file == "") {
          inc_path = dir "/" tolower(tag)
          inc_file = slurp_file(inc_path)
        }
        out = out pre "\n" inc_file "\n"
        raw = post
      }
      return out raw
    }
    function strip_pascal_comments_and_strings(s,    out, i, len, ch, next_ch, state) {
      # state: 0=code, 1=single-quote, 2={...}, 3=(*...*), 4=//...
      out = ""
      len = length(s)
      state = 0
      for (i = 1; i <= len; i++) {
        ch = substr(s, i, 1)
        next_ch = (i < len) ? substr(s, i + 1, 1) : ""
        if (state == 0) {
          if (ch == "\x27") { state = 1; out = out " " }
          else if (ch == "{") { state = 2; out = out " " }
          else if (ch == "(" && next_ch == "*") { state = 3; i++; out = out " " }
          else if (ch == "/" && next_ch == "/") { state = 4; i++; out = out " " }
          else { out = out ch }
        } else if (state == 1) {
          if (ch == "\x27") {
            if (next_ch == "\x27") { i++ }
            else { state = 0 }
          }
        } else if (state == 2) {
          if (ch == "}") state = 0
        } else if (state == 3) {
          if (ch == "*" && next_ch == ")") { state = 0; i++ }
        } else if (state == 4) {
          if (ch == "\n") { state = 0; out = out "\n" }
        }
      }
      return out
    }
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      sid = $1 + 0
      path = $4
      if (sid >= 1 && path ~ /\.pas$/ && (path ~ /^src\// || path ~ /^tools\// || path ~ /^tests\//)) {
        u = basename_no_ext(path)
        unit_slice[u] = sid
        unit_path[u] = path
        pas_files[++pas_count] = path
        pas_slice[pas_count] = sid
      }
    }
    END {
      violations = 0
      for (idx = 1; idx <= pas_count; idx++) {
        p = pas_files[idx]
        s_from = pas_slice[idx]
        raw = slurp_file(p)
        expanded = expand_local_includes(p, raw)
        clean = tolower(strip_pascal_comments_and_strings(expanded))
        rest = clean
        while (match(rest, /(^|[^a-z0-9_.])uses[[:space:]\n]+[^;]+;/)) {
          clause = substr(rest, RSTART, RLENGTH)
          rest = substr(rest, RSTART + RLENGTH)
          sub(/^.*uses[[:space:]\n]+/, "", clause)
          sub(/;$/, "", clause)
          n = split(clause, items, ",")
          for (k = 1; k <= n; k++) {
            tok = items[k]
            sub(/[[:space:]\n]+in[[:space:]\n]+.*$/, "", tok)
            gsub(/^[[:space:]\n]+|[[:space:]\n]+$/, "", tok)
            if (tok != "" && (tok in unit_slice)) {
              s_to = unit_slice[tok]
              if (s_to > s_from) {
                printf("ERROR: Forward slice dependency violation: %s (Slice %d) uses %s (%s in Slice %d)\n",
                  p, s_from, tok, unit_path[tok], s_to) > "/dev/stderr"
                violations++
              }
            }
          }
        }
      }
      if (violations > 0) exit 1
      printf("[vulkan-slices] Pascal uses-clause DAG OK (%d .pas units checked, 0 forward cross-slice dependencies).\n", pas_count)
    }
  ' "$MANIFEST_FILE"

  # Full git diff partition verification when BASE_COMMIT is available
  if [ -n "$BASE_COMMIT" ]; then
    echo "[vulkan-slices] Verifying 100% git diff coverage against base commit ${BASE_COMMIT}..."
    TMP_DIFF="$(mktemp)"
    TMP_MAN="$(mktemp)"
    trap 'rm -f "$TMP_DIFF" "$TMP_MAN"' EXIT

    # Combine committed changes since BASE_COMMIT plus any staged/unstaged/untracked manifest files
    {
      git diff --name-only "${BASE_COMMIT}..HEAD"
      git diff --name-only
      git diff --cached --name-only
      git ls-files --others --exclude-standard
    } | awk 'NF > 0' | LC_ALL=C sort -u > "$TMP_DIFF"

    awk -F '\t' '{ sub(/\r$/, "") } !/^[[:space:]]*#/ && NF == 4 { print $4 }' "$MANIFEST_FILE" | LC_ALL=C sort -u > "$TMP_MAN"

    UNASSIGNED="$(LC_ALL=C comm -23 "$TMP_DIFF" "$TMP_MAN" || true)"
    NOT_IN_DIFF="$(LC_ALL=C comm -13 "$TMP_DIFF" "$TMP_MAN" || true)"

    if [ -n "$UNASSIGNED" ]; then
      echo "ERROR: Changed files missing from slice_manifest.tsv:" >&2
      echo "$UNASSIGNED" | sed 's/^/  - /' >&2
      exit 1
    fi
    if [ -n "$NOT_IN_DIFF" ]; then
      echo "ERROR: Entries in slice_manifest.tsv that are unchanged vs ${BASE_COMMIT}:" >&2
      echo "$NOT_IN_DIFF" | sed 's/^/  - /' >&2
      exit 1
    fi
    DIFF_COUNT="$(wc -l < "$TMP_DIFF" | tr -d ' ')"
    echo "[vulkan-slices] Git diff partition OK: 100% exact 1-to-1 coverage (${DIFF_COUNT}/${DIFF_COUNT} changed files)."
  else
    echo "[vulkan-slices] Note: Shallow git clone detected (merge-base commit not in local history); skipped git diff set comparison."
  fi
fi

# ------------------------------------------------------------------------------
# 2. Summary Table
# ------------------------------------------------------------------------------
if [ "$DO_SUMMARY" -eq 1 ]; then
  echo ""
  echo "================================================================================"
  echo " Castle Game Engine — Vulkan 1.3+ Upstream PR Slices Summary"
  echo "================================================================================"
  awk -F '\t' '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    {
      sid = $1 + 0
      slug[sid] = $2
      cat = $3
      total[sid]++
      if (cat == "auto-dproj") auto_dproj[sid]++
      else core[sid]++
      grand_total++
      if (sid >= 1) upstream_total++
      if (sid >= 1 && cat != "auto-dproj") upstream_core++
    }
    END {
      printf(" %-7s %-44s %8s %10s %8s\n", "Slice", "PR Slug", "Core", "AutoDproj", "Total")
      printf(" ------------------------------------------------------------------------------\n")
      for (s = 1; s <= 8; s++) {
        printf(" PR #%-3d %-44s %8d %10d %8d\n",
          s, slug[s], core[s] + 0, auto_dproj[s] + 0, total[s] + 0)
      }
      printf(" ------------------------------------------------------------------------------\n")
      printf(" %-7s %-44s %8d %10d %8d\n",
        "1..8", "Total Upstream PR Scope", upstream_core + 0, auto_dproj[3] + 0, upstream_total + 0)
      if (total[0] + 0 > 0) {
        printf(" %-7s %-44s %8d %10d %8d\n",
          "Meta(0)", slug[0] " (branch-only)", core[0] + 0, 0, total[0] + 0)
      }
      printf(" %-7s %-44s %8s %10s %8d\n", "ALL", "Repository Diff Coverage", "-", "-", grand_total + 0)
    }
  ' "$MANIFEST_FILE"
  echo "================================================================================"
fi

# ------------------------------------------------------------------------------
# 3. Optional Read-Only Patch Series Export
# ------------------------------------------------------------------------------
if [ -n "$EXPORT_DIR" ]; then
  if [ -z "$BASE_COMMIT" ]; then
    echo "ERROR: --export-patches requires full git history reaching the merge-base commit (pass --base=<commit> or fetch upstream)." >&2
    exit 1
  fi

  mkdir -p "$EXPORT_DIR"
  SERIES_FILE="${EXPORT_DIR}/SERIES.txt"
  : > "$SERIES_FILE"

  for s in 1 2 3 4 5 6 7 8; do
    SLUG="$(awk -F '\t' -v target="$s" '{ sub(/\r$/, "") } $1 == target { print $2; exit }' "$MANIFEST_FILE")"
    PATCH_NAME="$(printf '%02d-%s.patch' "$s" "$SLUG")"
    PATCH_PATH="${EXPORT_DIR}/${PATCH_NAME}"

    MAP_FILES="$(mktemp)"
    awk -F '\t' -v target="$s" '{ sub(/\r$/, "") } $1 == target && $3 != "auto-dproj" { print $4 }' "$MANIFEST_FILE" > "$MAP_FILES"

    # Export committed + working-tree diff against BASE_COMMIT for core files in slice s
    git diff --binary "${BASE_COMMIT}" -- $(cat "$MAP_FILES") > "$PATCH_PATH"
    rm -f "$MAP_FILES"
    echo "$PATCH_NAME" >> "$SERIES_FILE"
    echo "[vulkan-slices] Wrote ${PATCH_PATH}"

    if [ "$s" -eq 3 ]; then
      AUTO_PATCH_NAME="03b-examples-auto-dproj.patch"
      AUTO_PATCH_PATH="${EXPORT_DIR}/${AUTO_PATCH_NAME}"
      AUTO_FILES="$(mktemp)"
      awk -F '\t' '{ sub(/\r$/, "") } $1 == "3" && $3 == "auto-dproj" { print $4 }' "$MANIFEST_FILE" > "$AUTO_FILES"
      if [ -s "$AUTO_FILES" ]; then
        git diff --binary "${BASE_COMMIT}" -- $(cat "$AUTO_FILES") > "$AUTO_PATCH_PATH"
        echo "$AUTO_PATCH_NAME" >> "$SERIES_FILE"
        echo "[vulkan-slices] Wrote ${AUTO_PATCH_PATH}"
      fi
      rm -f "$AUTO_FILES"
    fi
  done

  echo "[vulkan-slices] Exported upstream patch series (base ${BASE_COMMIT}) -> ${EXPORT_DIR}"
fi
