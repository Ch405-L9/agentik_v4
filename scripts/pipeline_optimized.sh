#!/usr/bin/env bash
# Optimized Pipeline for AMD Ryzen 5 5500
# Hardware: 6 cores / 12 threads / 16 GB RAM
# Parallel: 4 Lighthouse workers, 6 Discovery workers

set -Eeuo pipefail

cd "$(dirname "$0")/.."

# Logging
LOG_DIR="outputs/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pipeline_$(date -u +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "AGENTIK V3 - Optimized Pipeline"
echo "Hardware: AMD Ryzen 5 5500 (6C/12T)"
echo "Started: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
echo "=========================================="
echo

# Activation
if [[ -f .venv/bin/activate ]]; then
    source .venv/bin/activate
    echo "✓ Python venv active"
elif [[ -f ~/.venv_agentik/bin/activate ]]; then
    source ~/.venv_agentik/bin/activate
    echo "✓ Shared Python venv active"
else
    echo "⚠️  No venv found - using system Python"
fi

# Secrets
if [[ -f ~/.secrets/.env ]]; then
    source ~/.secrets/.env
    echo "✓ Secrets loaded ($(realpath ~/.secrets/.env))"
elif [[ -f ./.secrets/.env ]]; then
    source ./.secrets/.env
    echo "✓ Secrets loaded (./.secrets/.env)"
else
    echo "⚠️  No secrets file - Discovery will use DuckDuckGo only"
fi

echo

# Pre-flight check
echo "[1/5] Pre-flight check..."
if python3 scripts/precheck.py; then
    echo "✓ Pre-flight passed"
else
    echo "✗ Pre-flight failed - fix issues above"
    exit 1
fi
echo

# Stage selection
STAGE="${1:-all}"

case "$STAGE" in
    discover|discovery)
        echo "[2/5] Running Discovery (parallel)..."
        time python3 scripts/discover.py \
            --config configs/manifest.yaml \
            --output configs/domains.txt \
            --provider all \
            --max-results 50 \
            --verbose
        echo "✓ Discovery complete"
        ;;
    
    email|emails)
        echo "[2/5] Extracting domains from emails..."
        time bash scripts/email_to_urls.sh
        
        if [[ -f outputs/urls.txt ]]; then
            # Copy to domains.txt for audit stage
            cp outputs/urls.txt configs/domains.txt
            echo "✓ Email extraction complete ($(wc -l < outputs/urls.txt) domains)"
        else
            echo "✗ Email extraction failed"
            exit 2
        fi
        ;;
    
    audit)
        echo "[3/5] Running Lighthouse audits (PARALLEL - 4 workers)..."
        
        # Use new parallel runner
        if [[ -f scripts/run_parallel.py ]]; then
            time python3 scripts/run_parallel.py
        else
            # Fallback to serial
            echo "[WARN] Parallel runner not found, using serial mode"
            time bash scripts/run.sh
        fi
        
        REPORTS=$(ls -1 outputs/lighthouse/*.report.json 2>/dev/null | wc -l | tr -d ' ')
        echo "✓ Lighthouse complete ($REPORTS reports)"
        ;;
    
    compile)
        echo "[4/5] Compiling results to CSV..."
        time python3 src/main.py
        
        if [[ -f outputs/csv/results.csv ]]; then
            ROWS=$(wc -l < outputs/csv/results.csv)
            echo "✓ Compile complete ($ROWS rows)"
        else
            echo "✗ Compile failed"
            exit 2
        fi
        ;;
    
    enrich)
        echo "[5/5] Enriching contacts (optional)..."
        if [[ -f outputs/enriched/enriched.csv ]]; then
            echo "⚠️  Enriched data already exists, skipping"
        elif [[ -f scripts/enrich_contacts.py ]]; then
            time python3 scripts/enrich_contacts.py \
                --input_path outputs/contacts/contacts.csv \
                --output_path outputs/enriched/enriched.csv \
                --provider upgini \
                --search_keys EMAIL || echo "⚠️  Enrichment failed (optional)"
        else
            echo "⚠️  Enrichment script not found, skipping"
        fi
        ;;
    
    all)
        # Full pipeline
        echo "Running FULL pipeline..."
        echo
        
        # Step 1: Choose input mode
        if [[ -f outputs/contacts/contacts.csv ]]; then
            echo "[MODE] Email-list detected"
            "$0" email
        elif [[ -f configs/manifest.yaml ]]; then
            echo "[MODE] Discovery keywords detected"
            "$0" discover
        else
            echo "[ERROR] No input source found"
            echo "  Need: outputs/contacts/contacts.csv OR configs/manifest.yaml"
            exit 3
        fi
        
        echo
        
        # Step 2: Audit (parallel)
        "$0" audit
        echo
        
        # Step 3: Compile
        "$0" compile
        echo
        
        # Step 4: Enrich (optional)
        "$0" enrich || true
        echo
        
        # Summary
        echo "=========================================="
        echo "PIPELINE COMPLETE"
        echo "=========================================="
        
        if [[ -f outputs/csv/results.csv ]]; then
            echo "✓ Results: outputs/csv/results.csv"
            echo "  Domains audited: $(tail -n +2 outputs/csv/results.csv | wc -l)"
        fi
        
        if [[ -f outputs/enriched/enriched.csv ]]; then
            echo "✓ Enriched: outputs/enriched/enriched.csv"
        fi
        
        echo
        echo "Log: $LOG_FILE"
        echo "Duration: $SECONDS seconds"
        echo "=========================================="
        ;;
    
    clean)
        echo "Cleaning temporary files..."
        bash scripts/repo_clean.sh 2>/dev/null || {
            rm -rf outputs/lighthouse/*.json outputs/lighthouse/*.html
            rm -rf outputs/csv/*.csv
            rm -rf outputs/enriched/
            rm -f outputs/urls.txt outputs/BUILD_REPORT.txt
            echo "✓ Clean complete"
        }
        ;;
    
    *)
        echo "Usage: $0 {discover|email|audit|compile|enrich|all|clean}"
        echo
        echo "Stages:"
        echo "  discover  - Search for domains using keywords (parallel)"
        echo "  email     - Extract domains from email list"
        echo "  audit     - Run Lighthouse audits (PARALLEL - 4 workers)"
        echo "  compile   - Compile audit results to CSV"
        echo "  enrich    - Enrich contacts with metadata (optional)"
        echo "  all       - Run full pipeline (auto-detect input mode)"
        echo "  clean     - Remove temporary files"
        echo
        echo "Hardware Optimization:"
        echo "  Parallel Lighthouse: 4 workers (safe for 16 GB RAM)"
        echo "  Parallel Discovery:  6 workers (I/O bound)"
        echo "  Expected speedup:    3-4x faster than serial"
        exit 64
        ;;
esac

echo
echo "✓ Stage '$STAGE' complete"
exit 0
