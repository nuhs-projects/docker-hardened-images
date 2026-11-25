# Java 21 development and runtime images. Build from the repository root.
# Upstream Alpine variants scan clean without package removal or VEX exceptions.
# Debian 13 currently includes an unfixed gcc/libstdc++ finding.
FROM dhi.io/eclipse-temurin:21-jdk-alpine3.23-dev@sha256:2295d1d463a763a035c942396eccb8c617c30546d98800330b4c51e8d310c3b7 AS dev

FROM dhi.io/eclipse-temurin:21-alpine3.23@sha256:759884cf654167c5b0e38cd19ae5720970c0abf3e11ec2bd5dd81359f5241979 AS runtime
