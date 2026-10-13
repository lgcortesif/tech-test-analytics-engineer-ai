#!/usr/bin/env python3
"""One command: rebuild the warehouse from scratch, then run every check.

    python3 bin/run.py

Runs bin/build.py and, only if it succeeds, bin/test.py, with the same interpreter.
Exits with the first non-zero exit code (build failure, failing checks, or modified data/).
"""
import os, subprocess, sys

BIN = os.path.dirname(os.path.abspath(__file__))

def step(label, script):
    print(f"== {label}", flush=True)
    return subprocess.call([sys.executable, os.path.join(BIN, script)])

def main():
    rc = step("build: load data/ and run models/", "build.py")
    if rc != 0:
        print(f"\nbuild failed (exit {rc}); checks not run")
        sys.exit(rc)
    print()
    rc = step("test: verify data/ checksums and run tests/", "test.py")
    print(f"\n{'OK' if rc == 0 else f'FAILED (exit {rc})'}")
    sys.exit(rc)

if __name__ == "__main__":
    main()
