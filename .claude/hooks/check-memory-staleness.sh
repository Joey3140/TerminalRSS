#!/bin/bash
# claude-harness — memory staleness detector
# UserPromptSubmit hook — flags age rot, reference rot, zero-ref aging, duplicates
# Warn-only (exit 0 always)

cat > /dev/null

if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  SANITIZED=$(echo "$CLAUDE_PROJECT_DIR" | sed 's|/|-|g')
  MEMORY_DIR="$HOME/.claude/projects/$SANITIZED/memory"
else
  MEMORY_DIR="$HOME/.claude/projects/-$(cd "$(dirname "$0")/../.." && pwd | sed 's|/|-|g')/memory"
fi

if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

WARNINGS=""
NOW=$(date +%s)
STALE_DAYS=30
STALE_SECONDS=$((STALE_DAYS * 86400))

for f in "$MEMORY_DIR"/*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  [ "$BASENAME" = "MEMORY.md" ] && continue

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

DESCS_TMP=$(mktemp)
trap 'rm -f "$DESCS_TMP"' EXIT
for f in "$MEMORY_DIR"/*.md; do
  [ -f "$f" ] || continue
  BASENAME=$(basename "$f")
  [ "$BASENAME" = "MEMORY.md" ] && continue
  DESC=$(grep '^description:' "$f" 2>/dev/null | sed 's/^description: *//')
  [ -n "$DESC" ] && echo "$BASENAME|$DESC" >> "$DESCS_TMP"
done

if [ -f "$DESCS_TMP" ] && [ "$(wc -l < "$DESCS_TMP" | tr -d ' ')" -gt 1 ]; then
  while IFS='|' read -r file1 desc1; do
    while IFS='|' read -r file2 desc2; do
      [ "$file1" = "$file2" ] && continue
      [ "$file1" \> "$file2" ] && continue
      WORDS1=$(echo "$desc1" | tr ' ,;:—-' '\n' | grep -E '.{3,}' | sort -u)
      WORDS2=$(echo "$desc2" | tr ' ,;:—-' '\n' | grep -E '.{3,}' | sort -u)
      TOTAL1=$(echo "$WORDS1" | wc -l | tr -d ' ')
      W1_TMP=$(mktemp)
      W2_TMP=$(mktemp)
      echo "$WORDS1" > "$W1_TMP"
      echo "$WORDS2" > "$W2_TMP"
      SHARED=$(comm -12 "$W1_TMP" "$W2_TMP" | wc -l | tr -d ' ')
      rm -f "$W1_TMP" "$W2_TMP"
      if [ "$TOTAL1" -gt 0 ] && [ "$SHARED" -gt 0 ]; then
        OVERLAP=$((SHARED * 100 / TOTAL1))
        if [ "$OVERLAP" -ge 60 ]; then
          WARNINGS="${WARNINGS}POSSIBLE DUPLICATE: $file1 and $file2 (${OVERLAP}% word overlap)\n"
        fi
      fi
    done < "$DESCS_TMP"
  done < "$DESCS_TMP"
fi

if [ -n "$WARNINGS" ]; then
  echo "" >&2
  echo "=== Memory Staleness Report ===" >&2
  echo -e "$WARNINGS" >&2
  echo "Run: ls -lt ~/.claude/projects/*/memory/ to review" >&2
  echo "===============================" >&2
fi

exit 0
