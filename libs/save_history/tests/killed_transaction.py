"""Kill an actual process after SQLite spills uncommitted pages to disk."""
import pathlib
import subprocess
import sys
import tempfile
import time

with tempfile.TemporaryDirectory(prefix="save-history-kill-", dir=".") as directory:
    root = pathlib.Path(directory).resolve()
    database, ready = root / "history.sqlite", root / "ready"
    subprocess.run([sys.argv[1], "kill_prepare", str(database)], check=True)
    process = subprocess.Popen([sys.argv[1], "kill_hold", str(database), str(ready)])
    try:
        deadline = time.monotonic() + 15
        while not ready.exists():
            if process.poll() is not None:
                raise RuntimeError("writer exited before writing transaction")
            if time.monotonic() > deadline:
                raise RuntimeError("writer never reached uncommitted state")
            time.sleep(0.01)
        assert pathlib.Path(str(database) + "-journal").stat().st_size > 0
    finally:
        process.kill()
        process.wait(timeout=10)
    subprocess.run([sys.argv[1], "kill_check", str(database)], check=True)
print("PASS killed writer rolls back state and head")
