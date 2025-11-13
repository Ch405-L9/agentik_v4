#!/usr/bin/env bash
# Smart Pipeline - Auto-selects input source
set -euo pipefail

cd ~/agentik_v3
source .venv/bin/activate

MODE="${1:-auto}"  # discovery | emails | auto

echo "════════════════════════════════════════"
echo "   AGENTIK SMART PIPELINE"
echo "════════════════════════════════════════"

case "$MODE" in
  discovery)
    echo "→ MODE: Discovery (Keywords → Search)"
    python3 scripts/discover.py \
      --config configs/manifest.yaml \
      --output configs/domains.txt \
      --max-results 25
    ;;
  
  emails)
    echo "→ MODE: Email Lists (Contacts → Domains)"
    if [[ ! -f outputs/contacts/contacts.csv ]]; then
      echo "✗ Missing outputs/contacts/contacts.csv"
      exit 1
    fi
    bash scripts/email_to_urls.sh outputs/contacts/contacts.csv
    cp outputs/urls.txt configs/domains.txt
    ;;
  
  auto)
    echo "→ MODE: Auto-detect"
    # Check what data is available
    HAS_CONTACTS=$([ -f outputs/contacts/contacts.csv ] && echo "yes" || echo "no")
    HAS_KEYS=$([ -n "${GOOGLE_API_KEY:-}" ] && echo "yes" || echo "no")
    
    if [[ "$HAS_CONTACTS" == "yes" ]]; then
      echo "  ✓ Found contacts.csv → Using email mode"
      bash scripts/email_to_urls.sh outputs/contacts/contacts.csv
      cp outputs/urls.txt configs/domains.txt
    elif [[ "$HAS_KEYS" == "yes" ]]; then
      echo "  ✓ Found API keys → Using discovery mode"
      python3 scripts/discover.py \
        --config configs/manifest.yaml \
        --output configs/domains.txt \
        --max-results 25
    else
      echo "  ⚠ No data source found!"
      echo "    Need either:"
      echo "    - outputs/contacts/contacts.csv (email mode)"
      echo "    - GOOGLE_API_KEY set (discovery mode)"
      exit 1
    fi
    ;;
  
  *)
    echo "Usage: $0 {discovery|emails|auto}"
    exit 1
    ;;
esac

# Count domains
DOMAIN_COUNT=$(wc -l < configs/domains.txt)
echo ""
echo "✓ Input ready: $DOMAIN_COUNT domains → configs/domains.txt"
echo ""

# Run the rest of the pipeline
echo "→ Running Lighthouse audits..."
bash scripts/run.sh

echo "→ Compiling results..."
python3 src/main.py

echo ""
echo "════════════════════════════════════════"
echo "   ✅ COMPLETE"
echo "════════════════════════════════════════"
echo "Results: outputs/csv/results.csv"
cat outputs/csv/results.csv
