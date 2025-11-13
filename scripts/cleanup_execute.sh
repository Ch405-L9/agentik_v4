#!/usr/bin/env bash
# Agentik V3 Cleanup Execution
# This ACTUALLY performs the cleanup

set -euo pipefail

cd ~/agentik_v3

echo "════════════════════════════════════════"
echo "   AGENTIK V3 - CLEANUP EXECUTION"
echo "════════════════════════════════════════"
echo ""
echo "⚠️  This will modify your project!"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo ""
echo "Starting cleanup..."
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. CREATE ARCHIVE DIRECTORIES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "→ Creating archive directories..."
mkdir -p TAKE-OUT/old-code
mkdir -p TAKE-OUT/old-configs
mkdir -p TAKE-OUT/old-scripts
mkdir -p .secrets

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. ARCHIVE OLD/UNUSED FILES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "→ Archiving old code to TAKE-OUT/..."

# Old pipeline code
[ -d "keywords-data" ] && mv -v keywords-data TAKE-OUT/old-configs/ 2>/dev/null || true
[ -d "leadgen_audit" ] && mv -v leadgen_audit TAKE-OUT/old-code/ 2>/dev/null || true
[ -f "phase1_preflight.py" ] && mv -v phase1_preflight.py TAKE-OUT/old-code/ 2>/dev/null || true
[ -f "state_machine.py" ] && mv -v state_machine.py TAKE-OUT/old-code/ 2>/dev/null || true
[ -f "json_logger.py" ] && mv -v json_logger.py TAKE-OUT/old-code/ 2>/dev/null || true
[ -f "robots_guard.py" ] && mv -v robots_guard.py TAKE-OUT/old-code/ 2>/dev/null || true

# Old documentation
[ -f "shn-11.txt" ] && mv -v shn-11.txt TAKE-OUT/ 2>/dev/null || true

# Old scripts (keep newer versions in scripts/)
[ -f "check_before_push.sh" ] && mv -v check_before_push.sh TAKE-OUT/old-scripts/ 2>/dev/null || true
[ -f "cleanup_secrets.sh" ] && mv -v cleanup_secrets.sh TAKE-OUT/old-scripts/ 2>/dev/null || true

# Git artifacts
[ -f "gitleaks_after.json" ] && mv -v gitleaks_after.json TAKE-OUT/ 2>/dev/null || true
[ -f ".gitleaksignore" ] && mv -v .gitleaksignore TAKE-OUT/ 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. DELETE PYTHON CACHE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "→ Deleting Python cache files..."

# Find and delete .pyc files
PYCS_DELETED=$(find . -name "*.pyc" -type f -delete -print 2>/dev/null | wc -l)
echo "  Deleted $PYCS_DELETED .pyc files"

# Find and delete __pycache__ directories
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
echo "  Deleted __pycache__ directories"

# Root level __init__.py (unnecessary)
[ -f "__init__.py" ] && rm -v __init__.py || true
[ -f "__init__.cpython-311.pyc" ] && rm -v __init__.cpython-311.pyc || true
[ -f "phase1_preflight.cpython-311.pyc" ] && rm -v phase1_preflight.cpython-311.pyc || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. HANDLE WEIRD VENV LOCATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ -d "path/to/venv" ]; then
    echo "→ Found venv at weird location (path/to/venv)"
    echo "  OPTIONS:"
    echo "  1. Delete it (if you have .venv or want to recreate)"
    echo "  2. Move to .venv (recommended)"
    echo "  3. Keep as-is"
    echo ""
    read -p "Choice (1/2/3): " venv_choice
    
    case $venv_choice in
        1)
            echo "  Deleting path/to/venv..."
            rm -rf path/
            ;;
        2)
            echo "  Moving to .venv..."
            mv path/to/venv .venv
            rm -rf path/
            ;;
        3)
            echo "  Keeping as-is"
            ;;
        *)
            echo "  Invalid choice, skipping"
            ;;
    esac
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. CLEAN UP SECRETS DIRECTORY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ -d ".secrets(*.GITIGNORE*)" ]; then
    echo "→ Moving .secrets(*) to .secrets/"
    mv ".secrets(*.GITIGNORE*)"/* .secrets/ 2>/dev/null || true
    rmdir ".secrets(*.GITIGNORE*)" 2>/dev/null || true
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. CREATE CLEAN .gitignore
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo "→ Updating .gitignore..."
cat > .gitignore << 'GITIGNORE'
# Environment
.env
.env.local
.env.backup
*.env.backup

# Secrets
.secrets/
credentials.env
*.key
*.pem

# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
.venv/
venv/
env/
path/to/venv/

# Databases
*.db
*.sqlite
*.sqlite3

# Outputs
outputs/lighthouse/*.json
outputs/lighthouse/*.html
outputs/csv/*.csv
outputs/shn/*.json
outputs/logs/*.log

# OS
.DS_Store
Thumbs.db
*.tmp
*.bak
*~

# IDE
.vscode/
.idea/
*.swp
*.swo

# Archives
TAKE-OUT/

# Build artifacts
*.report.json
shn_*.json
GITIGNORE

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# SUMMARY
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
echo "════════════════════════════════════════"
echo "   ✅ CLEANUP COMPLETE"
echo "════════════════════════════════════════"
echo ""
echo "ARCHIVED TO:"
echo "  - TAKE-OUT/old-code/"
echo "  - TAKE-OUT/old-configs/"
echo "  - TAKE-OUT/old-scripts/"
echo ""
echo "CLEAN PROJECT STRUCTURE:"
tree -L 2 -I 'TAKE-OUT|.secrets|__pycache__|*.pyc|.venv|venv|path' -a
echo ""
