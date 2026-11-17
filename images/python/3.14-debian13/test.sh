#!/usr/bin/env bash
# Smoke test both targets.
# Usage: test.sh <dev image> <runtime image>
set -euo pipefail

dev=$1
runtime=$2

echo "--- dev: pip installs a wheel into a venv"
docker run --rm "$dev" sh -c '
    python3 -m venv /tmp/venv \
    && /tmp/venv/bin/pip install --quiet --disable-pip-version-check six \
    && /tmp/venv/bin/python -c "import six"'

echo "--- runtime: runs as nonroot, standard library works"
docker run --rm "$runtime" python3 -c '
import os, ssl, sqlite3, ctypes, zlib, lzma, bz2, threading
import xml.etree.ElementTree as ET
assert os.getuid() == 65532, os.getuid()
assert ET.fromstring("<a><b/></a>").find("b") is not None   # pyexpat
t = threading.Thread(target=lambda: None); t.start(); t.join()
print("python ok, openssl", ssl.OPENSSL_VERSION)'

echo "--- runtime: pip, setuptools and wheel are gone"
docker run --rm "$runtime" python3 -c '
import importlib.util as u
left = [m for m in ("pip", "setuptools", "wheel", "_distutils_hack") if u.find_spec(m)]
assert not left, left'

echo "--- runtime: no shell"
if docker run --rm --entrypoint sh "$runtime" -c true 2>/dev/null; then
    echo "runtime image has a shell" >&2
    exit 1
fi

echo "smoke tests passed"
