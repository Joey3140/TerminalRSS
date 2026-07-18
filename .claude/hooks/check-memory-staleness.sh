#!/bin/bash
# claude-harness — memory staleness detector
# UserPromptSubmit hook — flags age rot, reference rot, zero-ref aging, duplicates
# Warn-only (exit 0 always)

cat > /dev/null

# Derive memory path from CLAUDE_PROJECT_DIR.
# Claude Code's project dir name uses '-' for BOTH '/' and ' ', so sanitize both.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  SOURCE_PATH="$CLAUDE_PROJECT_DIR"
else
  SOURCE_PATH="$(cd "$(dirname "$0")/../.." && pwd)"
fi
SANITIZED=$(echo "$SOURCE_PATH" | sed 's|[/ ]|-|g')
MEMORY_DIR="$HOME/.claude/projects/$SANITIZED/memory"

if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# One trap covers every temp file — a timeout kill mid-run leaked INDEX_TMP
# when cleanup relied on inline rm
INDEX_TMP=""
DESCS_TMP=""
trap 'rm -f "$INDEX_TMP" "$DESCS_TMP"' EXIT

WARNINGS=""
NOW=$(date +%s)
STALE_DAYS=30
STALE_SECONDS=$((STALE_DAYS * 86400))

for f in "$MEMORY_DIR"/*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  [ "$BASENAME" = "MEMORY.md" ] && continue

  # Age rot: flag files not modified in 30+ days
  if [ "$(uname)" = "Darwin" ]; then
    FILE_MTIME=$(stat -f '%m' "$f")
  else
    FILE_MTIME=$(stat -c '%Y' "$f")
  fi
  AGE=$((NOW - FILE_MTIME))
  if [ "$AGE" -gt "$STALE_SECONDS" ]; then
    DAYS_OLD=$((AGE / 86400))
    WARNINGS="${WARNINGS}STALE MEMORY (${DAYS_OLD}d): $BASENAME\n"
  fi
done

# Index rot: MEMORY.md entries pointing to nonexistent files
# FIX(#1): Use temp file instead of pipe-to-while to avoid subshell variable loss
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  INDEX_TMP=$(mktemp)
  grep -oE '\([a-zA-Z0-9_-]+\.md\)' "$MEMORY_DIR/MEMORY.md" | tr -d '()' > "$INDEX_TMP" 2>/dev/null || true
  while read -r linked; do
    [ -z "$linked" ] && continue
    if [ ! -f "$MEMORY_DIR/$linked" ]; then
      WARNINGS="${WARNINGS}INDEX ROT: MEMORY.md links to $linked but file does not exist\n"
    fi
  done < "$INDEX_TMP"
  rm -f "$INDEX_TMP"
fi

# Zero-ref aging: memories never referenced and older than 14 days
ZERO_REF_SECONDS=$((14 * 86400))
for f in "$MEMORY_DIR"/*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  [ "$BASENAME" = "MEMORY.md" ] && continue

  REFS=$(grep '^refs:' "$f" 2>/dev/null | awk '{print $2}')
  [ -z "$REFS" ] && continue
  if [ "$REFS" -eq 0 ]; then
    if [ "$(uname)" = "Darwin" ]; then
      FILE_MTIME=$(stat -f '%m' "$f")
    else
      FILE_MTIME=$(stat -c '%Y' "$f")
    fi
    AGE=$((NOW - FILE_MTIME))
    if [ "$AGE" -gt "$ZERO_REF_SECONDS" ]; then
      DAYS_OLD=$((AGE / 86400))
      WARNINGS="${WARNINGS}ZERO-REF (${DAYS_OLD}d, never used): $BASENAME — candidate for removal\n"
    fi
  fi
done

# Duplicate detection: flag memory files with very similar descriptions
# FIX(#2): Use temp files instead of process substitution (bash 3.2 compat)
DESCS_TMP=$(mktemp)
for f in "$MEMORY_DIR"/*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  [ "$BASENAME" = "MEMORY.md" ] && continue
  DESC=$(grep '^description:' "$f" 2>/dev/null | sed 's/^description: *//')
  [ -n "$DESC" ] && echo "$BASENAME|$DESC" >> "$DESCS_TMP"
done

# FIX(#3): Single awk pass — the old nested shell loops forked ~12 processes
# per file pair (O(n^2) pairs), blowing the 5s hook timeout past ~15 memories.
if [ -f "$DESCS_TMP" ] && [ "$(wc -l < "$DESCS_TMP" | tr -d ' ')" -gt 1 ]; then
  DUPES=$(awk -F'|' '
    { file[NR] = $1; desc[NR] = $2 }
    END {
      for (i = 1; i <= NR; i++) {
        n = split(desc[i], w, /[ ,;:—-]+/)
        cnt[i] = 0
        for (k = 1; k <= n; k++) {
          if (length(w[k]) >= 3 && !((i, w[k]) in set)) {
            set[i, w[k]] = 1
            cnt[i]++
            list[i] = list[i] SUBSEP w[k]
          }
        }
      }
      for (i = 1; i <= NR; i++) {
        for (j = 1; j <= NR; j++) {
          if (file[i] == file[j] || file[i] > file[j]) continue
          m = split(substr(list[i], 2), wi, SUBSEP)
          shared = 0
          for (k = 1; k <= m; k++) if ((j, wi[k]) in set) shared++
          if (cnt[i] > 0 && shared > 0) {
            overlap = int(shared * 100 / cnt[i])
            if (overlap >= 60)
              printf "POSSIBLE DUPLICATE: %s and %s (%d%% word overlap)\n", file[i], file[j], overlap
          }
        }
      }
    }' "$DESCS_TMP")
  [ -n "$DUPES" ] && WARNINGS="${WARNINGS}${DUPES}\n"
fi

if [ -n "$WARNINGS" ]; then
  echo "" >&2
  echo "=== Memory Staleness Report ===" >&2
  echo -e "$WARNINGS" >&2
  echo "Run: ls -lt ~/.claude/projects/*/memory/ to review" >&2
  echo "===============================" >&2
fi

exit 0
