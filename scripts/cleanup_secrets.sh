#!/usr/bin/env bash
set -euo pipefail
ROOT="$(pwd)"
BACKUP_DIR="$HOME/agentik_secrets_backup/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$BACKUP_DIR"
echo "Backup dir: $BACKUP_DIR"

# 1) Backup obvious sensitive env files (move them out of repo)
for f in .env .env.OLD env ENV-corrected.txt "Give to engineer for Example.txt" "Give to engineer for Example.txt~" "ENV-corrected.txt"; do
  if [ -f "$f" ]; then
    echo "Backing up $f -> $BACKUP_DIR/"
    mv -- "$f" "$BACKUP_DIR/" || cp -- "$f" "$BACKUP_DIR/" && rm -f "$f"
  fi
done

# If gpg is available, encrypt any remaining plain backups
if command -v gpg >/dev/null 2>&1; then
  echo "Encrypting backup dir with gpg (symmetric). You will be prompted for a passphrase."
  tar -C "$BACKUP_DIR" -czf - . | gpg --symmetric --cipher-algo AES256 -o "$BACKUP_DIR".tar.gz.gpg
  echo "Encrypted backup: $BACKUP_DIR.tar.gz.gpg"
fi

# 2) Remove in-repo venv and recreate outside repo
if [ -d ".venv" ]; then
  echo "Removing .venv from repo (will delete) ..."
  # If active, try to deactivate first (best-effort)
  if [ -n "${VIRTUAL_ENV:-}" ]; then
    echo "Detected active virtualenv at $VIRTUAL_ENV; please deactivate if you want to keep it active."
  fi
  rm -rf .venv
  echo ".venv removed. Create new venv outside repo:"
  PY_BIN="$(which python3 || which python || true)"
  if [ -n "$PY_BIN" ]; then
    NEW_VENV_PARENT="$(dirname "$ROOT")/agentik-venv"
    echo "Creating venv at: $NEW_VENV_PARENT"
    "$PY_BIN" -m venv "$NEW_VENV_PARENT"
    echo "To activate later: source $NEW_VENV_PARENT/bin/activate"
  else
    echo "Python not found; skip recreating venv."
  fi
else
  echo "No .venv directory present."
fi

# 3) Add .venv and common outputs to .gitignore
GITIGNORE=".gitignore"
touch "$GITIGNORE"
for pat in ".venv/" "venv/" "env/" "*.pyc" "__pycache__/" "outputs/lighthouse/" "outputs/*.report.json" "outputs/*.json" "outputs/shn_*.json"; do
  if ! grep -Fxq "$pat" "$GITIGNORE"; then
    echo "$pat" >> "$GITIGNORE"
    echo "Added $pat to $GITIGNORE"
  fi
done

# 4) Redact common key patterns in candidate files (safe replacements)
# Files come from your gitleaks output — add more as needed
FILES=(
  "README.md"
  "PROBLEMS.txt"
  "Staged Run Results.txt"
  "Terminal-Problems.txt"
  "outputs/lighthouse/example.com.report.json"
  "tests/test_discover.py"
  "NEW FILES TO INSERT (AND REPLACE IF NEEDED)/test_discover.py"
  "Give to engineer for Example.txt"
  "Env-corrected.txt"
  "env"
  "ENV-corrected.txt"
)

# Build a unique list that exists
EXISTING_FILES=()
for f in "${FILES[@]}"; do
  if [ -f "$f" ]; then EXISTING_FILES+=("$f"); fi
done

# Patterns & safe placeholders:
# - Google API key: AIza...
# - AWS access key: AKIA...
# - Generic API keys: 32+ char alnum (guarded)
# - JWT-like tokens: long base64 segments
# - Private key blocks (BEGIN RSA PRIVATE KEY ... END RSA PRIVATE KEY) -> remove content (leave header)
for f in "${EXISTING_FILES[@]}"; do
  echo "Sanitizing $f"
  # backup original
  cp -p -- "$f" "$BACKUP_DIR/$(basename "$f").orig"
  # redact GCP-style API keys
  perl -i -pe "s/AIza[0-9A-Za-z_\-]{35}/AIza_REDACTED/g" "$f" || true
  # redact AWS ACCESS KEY IDs (AKIA...)
  perl -i -pe "s/AKIA[0-9A-Z]{16}/AKIA_REDACTED/g" "$f" || true
  # redact 40+ char hexish API keys (generic)
  perl -i -pe "s/[A-Za-z0-9\-\_]{30,}/APIKEY_REDACTED/g" "$f" || true
  # redact JWT-like (three segments with dots and base64url-ish chars) — conservative
  perl -i -pe "s/[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]{8,}/JWT_REDACTED/g" "$f" || true
  # remove private key bodies but keep header/footer
  perl -0777 -i -pe "s/-----BEGIN (?:RSA |EC |)PRIVATE KEY-----(?:.|\\n)*?-----END (?:RSA |EC |)PRIVATE KEY-----/-----BEGIN PRIVATE KEY-----\\nPRIVATE_KEY_REDACTED\\n-----END PRIVATE KEY-----/g" "$f" || true
done

# 5) Re-run gitleaks to confirm (if gitleaks installed)
if command -v gitleaks >/dev/null 2>&1; then
  echo "Running gitleaks detect now (output -> gitleaks_after.json)"
  gitleaks detect --source=. --report-path=gitleaks_after.json || true
  echo "gitleaks report: gitleaks_after.json"
  echo "Open it to inspect results. If it still shows secrets, inspect files in report and redact manually."
else
  echo "gitleaks not installed (or not on PATH). Install it and run: gitleaks detect --source=. --report-path=gitleaks_after.json"
fi

echo "CLEANUP COMPLETE. Backup stored at: $BACKUP_DIR"
echo "If gitleaks shows no findings, you may proceed to git init / commit / push steps (see instructions)."
