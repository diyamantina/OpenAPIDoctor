#!/usr/bin/env bash
# Namespacing gate: one non-private top-level type per file. A file with more
# than one file-scope type declaration is a violation: split it, or mark helper
# types private/fileprivate.
#
# Portable: bash 3.2 (macOS) and bash 4+ (CI).

set -u

SRC="Sources"
if [ ! -d "$SRC" ]; then
  echo "namespacing: no $SRC yet, skipping."
  exit 0
fi

FAIL=0
while IFS= read -r f; do
  count=$(grep -cE "^(public |package |internal )?(actor|struct|enum|protocol|class|final class) [A-Z]" "$f")
  if [ "$count" -gt 1 ]; then
    echo "namespacing: $count file-scope types in $f (one per file)" >&2
    FAIL=1
  fi
done < <(find "$SRC" -name "*.swift")

if [ "$FAIL" -ne 0 ]; then
  echo "namespacing: gate failed (one non-private type per file)." >&2
fi
exit "$FAIL"
