#!/usr/bin/env python3
"""
Parallel Lighthouse Runner with Chrome Cleanup
"""
import subprocess
import signal
import atexit
import os
import sys
import time
from multiprocessing import Pool
from pathlib import Path
from tqdm import tqdm

try:
    import psutil
except ImportError:
    print("ERROR: psutil not installed. Run: pip install psutil")
    sys.exit(1)

# Global process tracking
CHROME_PIDS = set()

def cleanup_all_chrome():
    """Kill all Chrome processes spawned by this script"""
    for pid in list(CHROME_PIDS):
        try:
            kill_chrome_tree(pid)
        except:
            pass
    CHROME_PIDS.clear()

def kill_chrome_tree(parent_pid):
    """Kill Chrome process and all children"""
    try:
        parent = psutil.Process(parent_pid)
        children = parent.children(recursive=True)
        
        # Terminate children first
        for child in children:
            try:
                child.terminate()
            except:
                pass
        
        # Wait for graceful shutdown
        gone, alive = psutil.wait_procs(children, timeout=2)
        
        # Force kill stragglers
        for p in alive:
            try:
                p.kill()
            except:
                pass
        
        # Kill parent
        parent.terminate()
        try:
            parent.wait(timeout=2)
        except:
            try:
                parent.kill()
            except:
                pass
    except (psutil.NoSuchProcess, psutil.AccessDenied):
        pass

def signal_handler(signum, frame):
    """Handle Ctrl+C gracefully"""
    print("\n[CLEANUP] Stopping all Chrome processes...")
    cleanup_all_chrome()
    sys.exit(0)

# Register cleanup handlers
atexit.register(cleanup_all_chrome)
signal.signal(signal.SIGTERM, signal_handler)
signal.signal(signal.SIGINT, signal_handler)

def run_lighthouse(url):
    """Run Lighthouse with proper cleanup"""
    chrome_flags = (
        "--headless=new "
        "--no-sandbox "
        "--disable-gpu "
        "--disable-dev-shm-usage "
        "--disable-software-rasterizer "
        "--disable-extensions "
        "--no-first-run "
        "--no-default-browser-check "
        "--disable-background-networking "
        "--disable-sync "
        "--metrics-recording-only "
        "--mute-audio"
    )
    
    slug = url.replace("https://", "").replace("http://", "")
    slug = "".join([c if c.isalnum() or c in "._-" else "_" for c in slug])
    out_base = f"outputs/lighthouse/{slug}"
    
    proc = None
    try:
        # Start process in new session
        proc = subprocess.Popen(
            [
                "lighthouse", url,
                "--preset=desktop",
                "--only-categories=performance,accessibility,seo,best-practices",
                "--output=json",
                "--output=html",
                f"--output-path={out_base}",
                "--save-assets",
                "--quiet",
                f"--chrome-flags={chrome_flags}",
                "--max-wait-for-load=45000"
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            preexec_fn=os.setsid  # New process group
        )
        
        # Track PID
        CHROME_PIDS.add(proc.pid)
        
        # Wait with timeout
        stdout, stderr = proc.communicate(timeout=60)
        
        # Clean up this specific process tree
        kill_chrome_tree(proc.pid)
        CHROME_PIDS.discard(proc.pid)
        
        success = proc.returncode == 0
        return {
            "url": url, 
            "success": success,
            "error": None if success else stderr.decode()[:200]
        }
    
    except subprocess.TimeoutExpired:
        if proc:
            kill_chrome_tree(proc.pid)
            CHROME_PIDS.discard(proc.pid)
        return {"url": url, "success": False, "error": "Timeout after 60s"}
    
    except Exception as e:
        if proc:
            kill_chrome_tree(proc.pid)
            CHROME_PIDS.discard(proc.pid)
        return {"url": url, "success": False, "error": str(e)[:200]}

def main():
    # Load domains
    domains_file = Path("configs/domains.txt")
    if not domains_file.exists():
        print(f"ERROR: {domains_file} not found")
        sys.exit(1)
    
    with open(domains_file) as f:
        domains = [line.strip() for line in f if line.strip() and not line.startswith("#")]
    
    if not domains:
        print("ERROR: No domains found")
        sys.exit(1)
    
    # Add https:// if missing
    urls = [d if d.startswith("http") else f"https://{d}" for d in domains]
    
    # Create output dir
    Path("outputs/lighthouse").mkdir(parents=True, exist_ok=True)
    
    # Run parallel
    workers = 4
    print(f"[RUN] Parallel Lighthouse with {workers} workers")
    print(f"[RUN] Processing {len(urls)} domains")
    
    start_time = time.time()
    
    with Pool(processes=workers) as pool:
        results = list(tqdm(
            pool.imap(run_lighthouse, urls),
            total=len(urls),
            desc="Progress",
            unit="domain"
        ))
    
    elapsed = time.time() - start_time
    
    # Summary
    success_count = sum(1 for r in results if r["success"])
    failed = [r for r in results if not r["success"]]
    
    print("\n" + "="*60)
    print("AUDIT SUMMARY")
    print("="*60)
    print(f"Total domains:  {len(urls)}")
    print(f"Successful:     {success_count} ({success_count/len(urls)*100:.1f}%)")
    print(f"Failed:         {len(failed)} ({len(failed)/len(urls)*100:.1f}%)")
    print(f"Total time:     {elapsed:.1f}s ({elapsed/60:.1f} min)")
    print(f"Avg time:       {elapsed/len(urls):.1f}s per domain")
    
    if failed:
        print(f"\nFailed domains:")
        for r in failed[:20]:  # Show first 20
            print(f"  • {r['url']}: {r.get('error', 'Unknown error')}")
    
    print(f"\nOutput: {Path('outputs/lighthouse').absolute()}")
    print("Next: python3 src/main.py  # Compile to CSV")
    print("="*60)

if __name__ == "__main__":
    try:
        main()
    finally:
        # Final cleanup
        cleanup_all_chrome()
