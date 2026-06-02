#!/usr/bin/env bash
# Scripts/download-corpus.sh
#
# Fetches a stress-test corpus of real-world OpenAPI specs from the
# APIs-guru registry for ad-hoc validation. Output lands in `.corpus/`
# at the repo root (gitignored, not redistributed).
#
# The corpus is intentionally NOT bundled into the package's test
# target: those specs carry varied upstream licences and live with
# their original publishers. This script makes the download
# reproducible while keeping the public repo's contents author-owned.
#
# Usage:
#   ./Scripts/download-corpus.sh           # default sample (~20 specs)
#   ./Scripts/download-corpus.sh --all     # every spec listed (700+, ~30min)
#
# After download:
#   for f in .corpus/*.yaml; do swift run openapi-doctor "$f"; done

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORPUS_DIR="$REPO_ROOT/.corpus"
mkdir -p "$CORPUS_DIR"

ALL=0
if [[ "${1:-}" == "--all" ]]; then
    ALL=1
fi

# Curated sample covering common shapes:
# - Google APIs (often vendor-extension violations on tags)
# - Stripe (large, generally clean)
# - GitHub (large, mostly clean)
# - Various smaller community specs
SAMPLE=(
    "1password.com:events"
    "amazonaws.com:sso-oidc"
    "apisetu.gov.in:pmjay"
    "authentiq.io"
    "discourse.local"
    "ebay.com:buy-browse"
    "fec.gov"
    "github.com"
    "googleapis.com:identitytoolkit"
    "googleapis.com:oauth2"
    "googleapis.com:oslogin"
    "linode.com"
    "mastodon.social"
    "ote-godaddy.com:domains"
    "redhat.com:registry"
    "slack.com"
    "spotify.com"
    "stripe.com"
    "twilio.com:Api"
    "vk.com"
)

if (( ALL )); then
    echo "Fetching full APIs-guru index..."
    LIST_URL="https://api.apis.guru/v2/list.json"
    TMP_INDEX=$(mktemp)
    curl -sSL -o "$TMP_INDEX" "$LIST_URL"
    NAMES=()
    while IFS= read -r api; do NAMES+=("$api"); done < <(
        python3 -c "import json,sys; print('\n'.join(json.load(open('$TMP_INDEX')).keys()))"
    )
    rm "$TMP_INDEX"
else
    NAMES=("${SAMPLE[@]}")
fi

echo "Downloading ${#NAMES[@]} specs to $CORPUS_DIR..."
COUNT=0
for api in "${NAMES[@]}"; do
    safe=$(echo "$api" | tr ':/' '__')
    out="$CORPUS_DIR/${safe}.yaml"
    if [[ -f "$out" ]]; then
        continue
    fi
    yaml_url=$(curl -sSL "https://api.apis.guru/v2/specs/${api}.json" 2>/dev/null \
        | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    pref = d.get('preferred')
    versions = d.get('versions', {})
    v = versions.get(pref) or next(iter(versions.values()), {})
    print(v.get('swaggerYamlUrl') or v.get('swaggerUrl', ''))
except Exception:
    pass
")
    if [[ -z "$yaml_url" ]]; then
        # Fall back to looking up via the top-level list.json
        yaml_url=$(curl -sSL "https://api.apis.guru/v2/list.json" \
            | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    api = d.get('${api}')
    if api:
        pref = api.get('preferred')
        v = api['versions'].get(pref) or next(iter(api['versions'].values()), {})
        print(v.get('swaggerYamlUrl') or v.get('swaggerUrl', ''))
except Exception:
    pass
")
    fi
    if [[ -z "$yaml_url" ]]; then
        echo "  [MISS] $api"
        continue
    fi
    if curl -sSL --fail -o "$out" "$yaml_url" 2>/dev/null; then
        size=$(wc -c < "$out" | tr -d ' ')
        if (( size < 1000 )); then
            rm "$out"
            echo "  [TINY] $api ($size bytes)"
            continue
        fi
        COUNT=$((COUNT + 1))
        echo "  [$COUNT] $api -> $out ($(echo "scale=1; $size/1024" | bc)KB)"
    else
        echo "  [FAIL] $api"
    fi
done

echo
echo "Downloaded $COUNT spec(s) into $CORPUS_DIR"
echo "Next: run the validator over them:"
echo "  for f in $CORPUS_DIR/*.yaml; do swift run openapi-doctor \"\$f\"; done"
echo
echo "Or via the repair-mode bulk run:"
echo "  for f in $CORPUS_DIR/*.yaml; do swift run openapi-doctor --fix \"\$f\"; done"
