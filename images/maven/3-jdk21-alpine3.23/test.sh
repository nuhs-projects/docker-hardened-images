#!/usr/bin/env bash
# Package a small Maven project with the dev image, as a build stage does, then
# run the jar it built. The image has no runtime target, so it takes only the
# dev image.
set -euo pipefail
dev=$1
tmp=$(mktemp -d)
builder=
volume=$(docker volume create)
cleanup() {
    [ -z "$builder" ] || docker rm -f "$builder" >/dev/null
    docker volume rm "$volume" >/dev/null
    rm -rf "$tmp"
}
trap cleanup EXIT

mkdir -p "$tmp/project/src/main/java/probe"
cat > "$tmp/project/pom.xml" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>probe</groupId>
  <artifactId>probe</artifactId>
  <version>1</version>
  <packaging>jar</packaging>
  <properties>
    <maven.compiler.release>21</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
</project>
XML
cat > "$tmp/project/src/main/java/probe/Probe.java" <<'JAVA'
package probe;

import javax.net.ssl.SSLContext;

public class Probe {
    public static void main(String[] args) throws Exception {
        if (Runtime.version().feature() != 21) throw new AssertionError("Java 21 required");
        SSLContext.getDefault().createSSLEngine();
        System.out.println("Maven-built jar ran on Java " + Runtime.version());
    }
}
JAVA

# A shell, as Dockerfile RUN steps need, then Maven itself: version, a
# package build (plugins come from Maven Central over TLS) and the result
builder=$(docker create -v "$volume:/build" --entrypoint /bin/sh "$dev" -ec '
    mvn -B -v | grep -E "^(Apache Maven 3\.|Java version: 21\.)"
    cp -r /tmp/project/. /build/
    mvn -B -q package
    java -cp target/probe-1.jar probe.Probe')
docker cp "$tmp/project" "$builder:/tmp/project"
docker start -a "$builder"
[[ "$(docker inspect --format '{{.State.ExitCode}}' "$builder")" == 0 ]]

workdir=$(docker image inspect "$dev" --format '{{.Config.WorkingDir}}')
[[ "$workdir" == /build ]] || { echo "Unexpected working directory: $workdir" >&2; exit 1; }
echo "Maven dev smoke test passed"
