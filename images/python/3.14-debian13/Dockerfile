# Hardened Python 3.14 on Debian 13, based on Docker Hardened Images (DHI).
#
# Two targets, published as <namespace>/python:3.14-debian13[-dev]:
#   dev      build stage image: shell, apt and pip kept (needed to install
#            dependencies); setuid bits cleared
#   runtime  what applications ship: no shell or package manager (as in DHI),
#            and pip, setuptools and wheel purged, so the packages they vendor
#            (certifi, urllib3, msgpack, ...) cannot fail a scan
#
# Build from the repository root (hardening/ is copied in):
#   docker buildx build --target runtime -f images/python/3.14-debian13/Dockerfile .
#
# Upstream images are pinned by digest; Dependabot opens a PR when DHI
# publishes a new one. Pulling from dhi.io needs `docker login dhi.io` with a
# Docker Hub account (free).

FROM dhi.io/python:3.14-debian13-dev@sha256:60dbebd00c5332a2d5984a96f33b76d6e42167095a9db8c49cd0038ac388de77 AS dev
RUN --mount=type=bind,source=hardening,target=/hardening \
    python3 /hardening/harden.py --strip-setuid \
    # pip's SBOM lists the setuptools pip was built with (70.3.0), which is not
    # installed; Docker Scout reads it and reports that setuptools' CVEs
    && rm /usr/lib/python3/dist-packages/pip/_vendor/bom.cdx.json

FROM dhi.io/python:3.14-debian13@sha256:d20d953b545c83acd9e1b6b6b6d27cf14de38e6a39689334f71454c33cf41893 AS runtime
# No shell in this image: the hardening runs with its own Python, as root,
# then the image drops back to DHI's nonroot user
USER 0
# OpenSSL: DHI's -dev image (pinned above) already ships a newer build of the
# same packages than its runtime image; take that build, so the runtime does
# not wait for DHI to republish
RUN --mount=type=bind,source=hardening,target=/hardening \
    --mount=type=bind,from=dev,target=/dhi-dev \
    ["python3", "/hardening/harden.py", "--strip-setuid", "--purge", \
     "python3-pip", "python3-pip-whl", \
     "python3-setuptools", "python3-setuptools-whl", \
     "python3-wheel", "python3-wheel-whl", \
     # Unused: Python's pyexpat has expat compiled in, and nothing else in
     # the image links libexpat
     "libexpat1", \
     "--install-from", "/dhi-dev", \
     "--install", "libssl3t64", "openssl", "openssl-provider-legacy"]
USER 65532
