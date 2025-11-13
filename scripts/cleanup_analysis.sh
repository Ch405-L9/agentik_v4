#!/usr/bin/env bash
# Agentik V3 Cleanup Analysis
# Run this to see what will be moved/deleted BEFORE doing it

set -euo pipefail

cd ~/agentik_v3

echo "════════════════════════════════════════"
echo "   AGENTIK V3 - CLEANUP ANALYSIS"
echo "════════════════════════════════════════"
echo ""

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ESSENTIAL FILES (KEEP IN ROOT)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${GREEN}✓ ESSENTIAL (keep in root):${NC}"
echo "  - configs/"
echo "  - scripts/"
echo "  - src/"
echo "  - outputs/"
echo "  - tests/"
echo "  - requirements.txt"
echo "  - .gitignore"
echo "  - README.md"
echo "  - LICENSE"
echo "  - .env (if exists)"
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MOVE TO TAKEOUT (archive)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${YELLOW}📦 ARCHIVE TO TAKEOUT/:${NC}"

ARCHIVE_ITEMS=(
    "keywords-data"
    "leadgen_audit"
    "phase1_preflight.py"
    "state_machine.py"
    "shn-11.txt"
    "json_logger.py"
    "robots_guard.py"
    "check_before_push.sh"
    "cleanup_secrets.sh"
    "gitleaks_after.json"
    ".gitleaksignore"
)

for item in "${ARCHIVE_ITEMS[@]}"; do
    if [ -e "$item" ]; then
        echo "  → $item"
    fi
done
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# DELETE (python cache, old venv)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo -e "${RED}🗑️  DELETE (python cache & weird venv):${NC}"

# Python cache files
PYCS=$(find . -name "*.pyc" -o -name "*.cpython-*.pyc" 2>/dev/null | wc -l)
echo "  → $PYCS .pyc files"

PYCACHE=$(find . -type d -name "__pycache__" 2>/dev/null | wc -l)
echo "  → $PYCACHE __pycache__ directories"

# Old/weird venv location
if [ -d "path/to/venv" ]; then
    echo "  → path/to/venv/ (wrong location, should be .venv)"
fi

# Duplicate __init__.py files
if [ -f "__init__.py" ]; then
    echo "  → __init__.py (root level, unnecessary)"
fi

echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "════════════════════════════════════════"
echo "   SUMMARY"
echo "════════════════════════════════════════"

ARCHIVE_COUNT=0
for item in "${ARCHIVE_ITEMS[@]}"; do
    [ -e "$item" ] && ARCHIVE_COUNT=$((ARCHIVE_COUNT+1))
done

DELETE_COUNT=$((PYCS + PYCACHE))
[ -d "path/to/venv" ] && DELETE_COUNT=$((DELETE_COUNT+1))
[ -f "__init__.py" ] && DELETE_COUNT=$((DELETE_COUNT+1))

echo "Files to archive:  $ARCHIVE_COUNT"
echo "Items to delete:   $DELETE_COUNT"
echo ""
echo "Run cleanup_execute.sh to proceed"
echo ""
