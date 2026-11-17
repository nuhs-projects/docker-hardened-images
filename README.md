# NUHS Hardened Container Images

Base images for NUHS applications, built on
[Docker Hardened Images](https://dhi.io) (DHI) with the parts applications do
not need removed, and published only when Docker Scout finds no fixable
vulnerability and Trivy finds no secret.

Maintained by NUHS for NUHS applications. Anyone may use them under the
[Apache License 2.0](LICENSE), as is, without warranty or support.
Vulnerabilities are patched on a best-effort basis: no fix or response time
is promised.

## Images

| Image | Use |
| --- | --- |
| `yongchenglow88/python:3.14-debian13` | Runtime: what your application ships on |
| `yongchenglow88/python:3.14-debian13-dev` | Build stage: install dependencies |
| `yongchenglow88/java:21-alpine3.23` | Java 21 JRE runtime: what your application ships on |
| `yongchenglow88/java:21-alpine3.23-dev` | Java 21 JDK build stage: compile and package |

Published images support `linux/amd64` and `linux/arm64`, also under a dated tag
(`3.14-debian13-20261117`), with an SBOM, provenance and a cosign signature.
Pin the digest in your Dockerfile, not just the tag.

```dockerfile
FROM yongchenglow88/python:3.14-debian13-dev@sha256:<digest> AS build
RUN python3 -m venv /opt/venv
COPY requirements.txt .
RUN /opt/venv/bin/pip install --no-cache-dir --require-hashes -r requirements.txt

FROM yongchenglow88/python:3.14-debian13@sha256:<digest>
COPY --from=build /opt/venv /opt/venv
COPY src/ /app/
WORKDIR /app
CMD ["/opt/venv/bin/python", "-m", "service"]
```

The runtime image has no shell, no package manager and no pip, and runs as
user 65532. Build everything in the `-dev` stage and copy the result across.

## Java 21

`images/java/21-alpine3.23/Dockerfile` provides a digest-pinned DHI JDK dev
image and a DHI JRE runtime. Neither needs package removal. The runtime is
nonroot (65532) and has no shell, package manager or compiler. The smoke test
compiles a Java probe in dev and runs it on a read-only runtime, checking TLS
trust, timezone data, threads and temporary files.

Java has a stricter gate: **zero reported vulnerabilities**, including unfixed
findings, in both targets and on both platforms, as reported by Docker Scout.
`SCOUT_ONLY_FIXED` cannot relax this Java gate.
Debian 13 was evaluated first, but its required gcc/libstdc++ packages have an
unfixed CVE. Alpine 3.23 is therefore used and must be tested for each
application's native-library compatibility.

## What is hardened

Both targets are built from one Dockerfile per image, on DHI images pinned by
digest. [`hardening/harden.py`](hardening/harden.py) does the work; it needs
only Python, so it also runs in runtime images that have no shell.

| | dev | runtime |
| --- | --- | --- |
| Upstream | `dhi.io/python:3.14-debian13-dev` | `dhi.io/python:3.14-debian13` |
| Shell, apt | kept (build steps need them) | none (as in DHI) |
| pip, setuptools, wheel | kept (needed to install dependencies); pip's own SBOM removed, as it lists a setuptools that is not installed | purged, with their dpkg records, so scanners no longer see them or what they vendor |
| libexpat1 | kept | purged: unused, as Python's `pyexpat` has expat compiled in |
| OpenSSL | as in DHI | replaced by the newer build DHI ships in its `-dev` image |
| setuid / setgid bits | cleared | cleared |
| User | root | 65532 |

Scanned with DHI's VEX statements on 2026-11-17, what remains has no fixed
version in any Debian release yet:

- both targets: CVE-2026-125709 (medium), libstdc++ from Debian 13's gcc-14;
  numpy, scipy, scikit-learn and pandas need the library
- `-dev` only: CVE-2026-128241 (medium, expat's `xmlwf` tool, which is not
  installed) and CVE-2024-2236 (low, libgcrypt, needed by apt)

## How it stays patched

1. **Dependabot** checks dhi.io daily and opens a PR when DHI publishes a new
   digest of an image we use.
2. **PR** (`.github/workflows/pr.yml`): builds the changed images, runs each
   image's `test.sh`, and fails on any fixable vulnerability Docker Scout
   finds, in either target. See [Security checks](#security-checks).
3. **Release** (`release.yml`): on merge to `main`, the same checks, then the
   push to Docker Hub for both platforms, and signing.
4. **Rescan** (`rescan.yml`): every night, Docker Scout scans the published
   images; a new vulnerability opens an issue.

For Python, the gate is "no fixable vulnerability": a CVE that Debian has not fixed yet
cannot be removed by rebuilding. To fail on those too, set the repository
variable `SCOUT_ONLY_FIXED` to `false`.

Docker publishes VEX statements for DHI images, marking the CVEs that do not
affect them. Scout applies them to DHI's own images but not to images built on
them, so CI downloads them ([`dhi-vex.sh`](.github/scripts/dhi-vex.sh)), scans
with them, and attaches them to every image it pushes. Without them Scout
reports about 40 CVEs in the dev image instead of 3.

## Adding an image

1. Create `images/<repo>/<tag>/` (for example `images/java/21-debian13/`)
   with a `Dockerfile` that has a `dev` and a `runtime` target, `FROM` DHI
   images pinned by digest, and an executable `test.sh <dev> <runtime>`.
2. Purge what the runtime does not need with `harden.py --purge`. In an image
   with neither a shell nor Python (Java runtime images), run the hardening in
   an earlier stage instead.
3. Open a PR. The CI picks the folder up; no workflow changes are needed. It
   publishes as `<namespace>/<repo>:<tag>` and `:<tag>-dev`.

Build and test locally from the repository root:

```sh
docker login dhi.io     # Docker Hub account, free
for t in dev runtime; do
  docker buildx build --load --target $t -t local/python-$t -f images/python/3.14-debian13/Dockerfile .
done
images/python/3.14-debian13/test.sh local/python-dev local/python-runtime
```

## Security checks

Every pull request must pass, through the single `PR / done` check:

- each changed image's `test.sh`
- Docker Scout: fixable vulnerabilities (any, for Java), with DHI's VEX
  statements. Scout is the only vulnerability gate, so CI agrees with what
  Docker Hub shows.
- Trivy: secrets baked into an image layer
- gitleaks: secrets in the PR's commits
- actionlint and zizmor: the workflows themselves (zizmor at medium severity
  and above)

Every action is pinned to a commit SHA; Dependabot updates them. Dockerfiles
are not checked with `docker build --check`, as that needs a dhi.io login and
the lint job has no secrets.

## Repository setup

- Actions secrets **and** Dependabot secrets: `DOCKERHUB_USERNAME`,
  `DOCKERHUB_TOKEN` (a Docker Hub personal access token, read & write).
  Dependabot PRs only see Dependabot secrets.
- Actions variable: `DOCKERHUB_NAMESPACE` (`yongchenglow88`).
- Branch protection on `main`: require a PR and the `PR / done` check.
- Environment `release`, with required reviewers: Release jobs that push
  wait for approval. Without it, the jobs run unattended. The Docker Hub
  secrets can stay at repository level; to move them to the environment,
  also make them optional in `build.yml`'s `workflow_call` and drop the
  repository copies.
- Organisation: require two-factor authentication.

Before making the repository public:

- Settings > Code security: enable secret scanning and push protection.
- Settings > Actions > General: require approval for workflows from outside
  collaborators (all of them, not only first-time contributors).
- Check that `PR / done` is the required check, and that the Docker Hub token
  is not shared with anything else.

## Moving to an NUHS namespace

The images are published under a personal Docker Hub account until NUHS has
its own. To move: create the namespace, change `DOCKERHUB_NAMESPACE`, run
Release by hand, and update the `FROM` lines that use these images (pinned
digests stay the same, so only the name changes).
