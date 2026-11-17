#!/usr/bin/env bash
# Compile with the dev JDK, then run on the nonroot JRE with a read-only root.
set -euo pipefail
dev=$1
runtime=$2
tmp=$(mktemp -d)
builder=
runner=
volume=$(docker volume create)
cleanup() {
    [ -z "$builder" ] || docker rm -f "$builder" >/dev/null
    [ -z "$runner" ] || docker rm -f "$runner" >/dev/null
    docker volume rm "$volume" >/dev/null
    rm -rf "$tmp"
}
trap cleanup EXIT
start_and_check() {
    docker start -a "$1"
    [[ "$(docker inspect --format '{{.State.ExitCode}}' "$1")" == 0 ]]
}

cat > "$tmp/Probe.java" <<'JAVA'
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.ZoneId;
import java.util.concurrent.CompletableFuture;
import javax.net.ssl.SSLContext;
import javax.net.ssl.TrustManagerFactory;
import javax.net.ssl.X509TrustManager;

public class Probe {
    public static void main(String[] args) throws Exception {
        if (Runtime.version().feature() != 21) throw new AssertionError("Java 21 required");
        if (Boolean.getBoolean("requireNonRoot") && "root".equals(System.getProperty("user.name")))
            throw new AssertionError("Runtime must be nonroot");
        SSLContext.getDefault().createSSLEngine();
        var trust = TrustManagerFactory.getInstance(TrustManagerFactory.getDefaultAlgorithm());
        trust.init((java.security.KeyStore) null);
        if (((X509TrustManager) trust.getTrustManagers()[0]).getAcceptedIssuers().length == 0)
            throw new AssertionError("No trusted CA certificates");
        ZoneId.of("Asia/Singapore");
        if (CompletableFuture.supplyAsync(() -> 42).get() != 42) throw new AssertionError();
        var file = Files.createTempFile("java-probe", ".txt");
        Files.writeString(file, "ok");
        if (!Files.readString(file).equals("ok")) throw new AssertionError();
        Files.delete(file);
        System.out.println("Java, TLS trust, timezone, threads and temp files passed; user="
            + System.getProperty("user.name"));
    }
}
JAVA

builder=$(docker create -v "$volume:/probe" --entrypoint /bin/sh "$dev" -ec \
    'javac -d /probe /tmp/Probe.java && java -cp /probe Probe')
docker cp "$tmp/Probe.java" "$builder:/tmp/Probe.java"
start_and_check "$builder"

user=$(docker image inspect "$runtime" --format '{{.Config.User}}')
[[ "$user" == 65532 || "$user" == 65532:65532 ]] || {
    echo "Unexpected runtime user: $user" >&2; exit 1;
}
runner=$(docker create --read-only --tmpfs /tmp:rw,nosuid,nodev \
    --cap-drop ALL --security-opt no-new-privileges \
    --mount "type=volume,src=$volume,dst=/probe,readonly" \
    --entrypoint java "$runtime" -DrequireNonRoot=true -cp /probe Probe)
start_and_check "$runner"

if docker run --rm --entrypoint /bin/sh "$runtime" -c true >/dev/null 2>&1; then
    echo "Unexpected runtime shell" >&2; exit 1
fi
for tool in /sbin/apk javac; do
    if docker run --rm --entrypoint "$tool" "$runtime" --version >/dev/null 2>&1; then
        echo "Unexpected runtime tool: $tool" >&2; exit 1
    fi
done
echo "Java dev and runtime smoke tests passed"
