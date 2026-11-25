# NUHS Hardened Container Images

Base images for NUHS applications, built only on
[Docker Hardened Images](https://dhi.io) (DHI) with the parts applications do
not need removed, and published only when Docker Scout finds no fixable
vulnerability and Trivy finds no secret. See
[Why only Docker Hardened Images](#why-only-docker-hardened-images) for why
no other base is accepted.

Maintained by NUHS for NUHS applications. Anyone may use them under the
[Apache License 2.0](LICENSE), as is, without warranty or support.
Vulnerabilities are patched on a best-effort basis: no fix or response time
is promised.

## Why only Docker Hardened Images

Every image in this repository is built from DHI images on `dhi.io`, pinned by
digest. This applies to every build stage and to anything copied in with
`--from`, not only to the final image. Images built on any other base (Docker
Official Images, distribution images, `scratch`, or another vendor's hardened
images) are not accepted, and CI rejects them (see
[Security checks](#security-checks)).

The reasons:

- **A smaller starting point.** DHI runtime images ship without a shell or
  package manager and run as a nonroot user
  ([DHI docs](https://docs.docker.com/dhi/)). This repository only removes
  what is left, rather than rebuilding a minimal image from a general-purpose
  one.
- **Benchmarked upstream.** The DHI images used here are labelled
  `com.docker.dhi.compliance: "cis"`. Docker states that such images comply
  with all controls in Section 4 (container images and build files) of the
  [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker), except
  Docker Content Trust, which Docker has retired in favour of cosign
  signatures ([DHI CIS Benchmark](https://docs.docker.com/dhi/core-concepts/cis/)).
- **Supply-chain evidence from upstream.** DHI images come with signed SBOMs,
  VEX statements and SLSA Build Level 3 provenance
  ([DHI docs](https://docs.docker.com/dhi/)). The SBOM, provenance and
  signature this repository adds extend that chain rather than start one.
- **Scans that match what Docker Hub shows.** Docker publishes VEX statements
  marking the CVEs that do not affect DHI images. CI scans with them and
  attaches them to every image it pushes. Without them, Docker Scout reports
  about 40 CVEs in the Python dev image instead of 3, and the gate would be
  either noisy or loosened. No other base has an equivalent here.
- **Patches we can track.** Docker rebuilds DHI images for OS and language
  fixes. Dependabot watches `dhi.io` and opens a PR for each new digest.
- **One pipeline.** Image names, the full-version tag (read from
  `com.docker.dhi.version`), the VEX download and Dependabot all assume DHI.
  A second kind of base would need a second path through each of them.

What this does not give you:

- **CIS compliance of these images.** The CIS label is set by Docker on its
  own images. Images built from them inherit the label through `FROM`, so the
  images published here also carry `com.docker.dhi.compliance: "cis"`, but
  Docker has not assessed them. This repository keeps the Section 4 controls
  (nonroot runtime user, no unneeded packages, setuid and setgid bits
  cleared, no secrets in layers, signed images, rebuilt on every upstream
  patch), but does not claim certification. The Benchmark's host, daemon and
  runtime sections are for whoever runs the containers.
- **A vendor SLA.** These images use DHI's free tier, where patches follow
  Docker's release cadence. The 7-day fix SLA for critical CVEs, and the FIPS
  and STIG variants, are in DHI's paid tiers only
  ([Docker Hardened Images](https://www.docker.com/products/hardened-images/)).
- **Images DHI does not publish.** If DHI has no image for a runtime or
  distribution version, neither does this repository.

Pulling from `dhi.io` needs a Docker Hub login (a free account), locally and
in CI. If DHI's terms or availability change, this policy is revisited.

## Images

| Image                                              | Use                                                 |
| -------------------------------------------------- | --------------------------------------------------- |
| `yongchenglow88/python:3.14-debian13`              | Runtime: what your application ships on             |
| `yongchenglow88/python:3.14-debian13-dev`          | Build stage: install dependencies                   |
| `yongchenglow88/eclipse-temurin:21-alpine3.23`     | Java 21 JRE runtime: what your application ships on |
| `yongchenglow88/eclipse-temurin:21-alpine3.23-dev` | Java 21 JDK build stage: compile and package        |
| `yongchenglow88/maven:3-jdk21-alpine3.23-dev`      | Maven 3 and Java 21 JDK build stage: `mvn package`  |

Image names and tags follow the DHI image each is built on
(`dhi.io/python:3.14-debian13` becomes `python:3.14-debian13`). Each image is
also tagged with the full version of that DHI image, such as
`python:3.14.10-debian13` and `python:3.14.10-debian13-dev`: the short tag
moves to each new version, the full-version tag stays on one version (it
still moves when DHI rebuilds that version with OS patches). Eclipse Temurin
is the exception: see [Java 21](#java-21-eclipse-temurin-alpine-323).

Published images support `linux/amd64` and `linux/arm64`, with an SBOM,
provenance and a cosign signature. Signatures are OCI referrers, not
`sha256-*.sig` tags, so verify with cosign 2.6 or later.
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

The runtime images have no shell and no package manager, and run as user 65532. Build everything in the `-dev` stage and copy the result across.

Maven has only a `-dev` image, as DHI publishes it only as one. Build with it
and run on the Java runtime:

```dockerfile
FROM yongchenglow88/maven:3-jdk21-alpine3.23-dev@sha256:<digest> AS build
COPY . .
RUN mvn -B package

FROM yongchenglow88/eclipse-temurin:21-alpine3.23@sha256:<digest>
COPY --from=build /build/target/app.jar /app/app.jar
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

## What is hardened

Every image has a `dev` and a `runtime` target, built from one Dockerfile on
DHI images pinned by digest. [`hardening/harden.py`](hardening/harden.py)
does the work; it needs only Python, so it also runs in runtime images that
have no shell.

### Python 3.14 (Debian 13)

|                        | dev                                                                                                           | runtime                                                                             |
| ---------------------- | ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| Upstream               | `dhi.io/python:3.14-debian13-dev`                                                                             | `dhi.io/python:3.14-debian13`                                                       |
| Shell, apt             | kept (build steps need them)                                                                                  | none (as in DHI)                                                                    |
| pip, setuptools, wheel | kept (needed to install dependencies); pip's own SBOM removed, as it lists a setuptools that is not installed | purged, with their dpkg records, so scanners no longer see them or what they vendor |
| libexpat1              | kept                                                                                                          | purged: unused, as Python's `pyexpat` has expat compiled in                         |
| OpenSSL                | as in DHI                                                                                                     | replaced by the newer build DHI ships in its `-dev` image                           |
| setuid / setgid bits   | cleared                                                                                                       | cleared                                                                             |
| User                   | root                                                                                                          | 65532                                                                               |

Scanned with DHI's VEX statements on 2026-11-17, what remains has no fixed
version in any Debian release yet:

- both targets: CVE-2026-125709 (medium), libstdc++ from Debian 13's gcc-14;
  numpy, scipy, scikit-learn and pandas need the library
- `-dev` only: CVE-2026-128241 (medium, expat's `xmlwf` tool, which is not
  installed) and CVE-2024-2236 (low, libgcrypt, needed by apt)

### Java 21 (Eclipse Temurin, Alpine 3.23)

|                                  | dev                                                  | runtime                                      |
| -------------------------------- | ---------------------------------------------------- | -------------------------------------------- |
| Upstream                         | `dhi.io/eclipse-temurin:21-jdk-alpine3.23-dev` (JDK) | `dhi.io/eclipse-temurin:21-alpine3.23` (JRE) |
| Changes                          | none needed                                          | none needed                                  |
| Shell, package manager, compiler | kept                                                 | none (as in DHI)                             |
| User                             | root                                                 | 65532                                        |

The images are published under the runtime's tag, `21-alpine3.23` and
`21-alpine3.23-dev`, although DHI's dev image is tagged
`21-jdk-alpine3.23-dev`.

The full-version tag is the JDK's own version, read from the image's
`JAVA_VERSION`, with `+` written as `_` as in the Docker Official Images:
`21.0.13.1_2-alpine3.23` and `21.0.13.1_2-alpine3.23-dev` for Temurin
21.0.13.1+2. DHI's `com.docker.dhi.version` label is not used here because it
drops the update number of a patch release (it labels 21.0.13.1+2 as
`21.0.13.2`), so a fixed build would sort below the build it replaces
(21.0.13+9, labelled `21.0.13.9`). CI fails if the dev and runtime images
carry different JDK versions.

Debian 13 was evaluated first, but its gcc and libstdc++ packages have an
unfixed CVE, which the Java gate does not allow. Alpine 3.23 is used instead;
check each application's native libraries against it (Alpine uses musl, not
glibc).

The smoke test compiles a Java probe in dev and runs it on a read-only
runtime, on both platforms, checking TLS trust, timezone data, threads and
temporary files.

### Maven 3 (Java 21, Alpine 3.23)

|                                  | dev                                        |
| -------------------------------- | ------------------------------------------ |
| Upstream                         | `dhi.io/maven:3-jdk21-alpine3.23-dev`      |
| Changes                          | none needed                                |
| JDK                              | Eclipse Temurin 21, as in the Java images  |
| Shell, package manager, compiler | kept                                       |
| User, working directory          | root, `/build`                             |

DHI publishes Maven only as a `-dev` image, so there is no runtime target and
no `3-jdk21-alpine3.23` tag: run what it builds on
`eclipse-temurin:21-alpine3.23`. The full-version tag comes from the dev
image's label without its `-dev` suffix, for example
`3.10.1-r0-jdk21-alpine3.23-dev`. It is held to the Java gate: zero reported
vulnerabilities.

The smoke test checks the shell and the Maven and Java versions, packages a
small project (its plugins come from Maven Central) and runs the jar, on both
platforms.

## How it stays patched

1. **Dependabot** checks dhi.io daily and opens a PR when DHI publishes a new
   digest of an image we use.
2. **PR** (`.github/workflows/pr.yml`): builds the changed images, runs each
   image's `test.sh`, and runs the [security checks](#security-checks).
3. **Release** (`release.yml`): on merge to `main`, the same checks, then the
   push to Docker Hub for both platforms, and signing.
4. **Rescan** (`rescan.yml`): every night, Docker Scout scans the published
   images; a new vulnerability opens one issue per image (covering both
   targets and platforms), and the issue closes once every scan passes.

Docker publishes VEX statements for DHI images, marking the CVEs that do not
affect them. Scout applies them to DHI's own images but not to images built on
them, so CI downloads them ([`dhi-vex.sh`](.github/scripts/dhi-vex.sh)), scans
with them, and attaches them to every image it pushes.

## Security checks

Every pull request must pass, through the single `PR / done` check:

- every image's base: each `FROM`, `COPY --from` and `RUN --mount=...,from=`
  is a `dhi.io` image pinned by digest or an earlier stage
  ([`check-dhi-base.sh`](.github/scripts/check-dhi-base.sh))
- each changed image's `test.sh`
- Docker Scout, with DHI's VEX statements, in each target and on both
  platforms. Scout is the only vulnerability gate, so CI agrees with what
  Docker Hub shows.
  - Python: no fixable vulnerability. A CVE that Debian has not fixed yet
    cannot be removed by rebuilding; to fail on those too, set the repository
    variable `SCOUT_ONLY_FIXED` to `false`.
  - Java (Eclipse Temurin and Maven): zero reported vulnerabilities, fixed or
    not. `SCOUT_ONLY_FIXED` does not relax this.
- Trivy: secrets baked into an image layer
- gitleaks: secrets in the PR's commits
- actionlint and zizmor: the workflows themselves (zizmor at medium severity
  and above)

Every action is pinned to a commit SHA; Dependabot updates them. Dockerfiles
are not checked with `docker build --check`, as that needs a dhi.io login and
the lint job has no secrets.

## Adding an image

1. Check that DHI publishes the image you need. If it does not, open an issue
   instead of a PR: see
   [Why only Docker Hardened Images](#why-only-docker-hardened-images).
2. Create `images/<repo>/<tag>/` (for example
   `images/eclipse-temurin/21-debian13/`) with a `Dockerfile` that has a `dev`
   and a `runtime` target, and an executable `test.sh <dev> <runtime>`. If DHI
   publishes only a `-dev` image (as for Maven), leave out the `runtime` stage;
   `test.sh` then takes only `<dev>`. A Java image's repository goes in
   `java_repos` in [`list-images.sh`](.github/scripts/list-images.sh). Every
   `FROM` must be `dhi.io/<image>@sha256:<digest>` or an earlier stage, and so
   must every `--from`.
3. Purge what the runtime does not need with `harden.py --purge`. In an image
   with neither a shell nor Python (Java runtime images), run the hardening in
   an earlier stage, which must also be a DHI image.
4. Open a PR. The CI picks the folder up; no workflow changes are needed. It
   publishes as `<namespace>/<repo>:<tag>` and `:<tag>-dev`, plus the full
   version from the DHI runtime image's `com.docker.dhi.version` label (the
   dev image's, without `-dev`, when there is no runtime; Eclipse Temurin
   uses the JDK's `JAVA_VERSION` instead). Name
   the folders after the DHI image: `<repo>` as DHI's repository, `<tag>` as
   its runtime tag.

Build and test locally from the repository root:

```sh
docker login dhi.io     # Docker Hub account, free
.github/scripts/check-dhi-base.sh   # needs bash 4 or later
for t in dev runtime; do
  docker buildx build --load --target $t -t local/python-$t -f images/python/3.14-debian13/Dockerfile .
done
images/python/3.14-debian13/test.sh local/python-dev local/python-runtime
```

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

## References

- [Docker Hardened Images documentation](https://docs.docker.com/dhi/):
  minimal and nonroot images, signed SBOMs, VEX, SLSA Build Level 3
  provenance, tiers and patch cadence
- [DHI CIS Benchmark](https://docs.docker.com/dhi/core-concepts/cis/):
  Section 4 scope, the Docker Content Trust exception, the CIS label
- [Docker Hardened Images product page](https://www.docker.com/products/hardened-images/):
  paid tiers, SLA, FIPS and STIG variants
- [Reading the `com.docker.dhi.compliance` label](https://www.docker.com/blog/making-the-most-of-your-docker-hardened-images-enterprise-trial-part-2/)
  (Docker blog)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [DHI catalog](https://dhi.io)
