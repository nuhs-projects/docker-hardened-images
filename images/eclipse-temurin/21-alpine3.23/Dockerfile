# Java 21 development and runtime images. Build from the repository root.
# Upstream Alpine variants scan clean without package removal or VEX exceptions.
# Debian 13 currently includes an unfixed gcc/libstdc++ finding.
FROM dhi.io/eclipse-temurin:21-jdk-alpine3.23-dev@sha256:bbae46d3bf41d3e48b32bc36d14025bacb69cab41e114729ccce7b24fa7b6074 AS dev

FROM dhi.io/eclipse-temurin:21-alpine3.23@sha256:e192d31f8dd997892c9ca8806cae41d48dfd8b2c09ac1f5cd635b0a2fe1a97bb AS runtime
