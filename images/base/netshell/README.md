# netshell

Kubernetes debug/troubleshooting sidecar container. Ships with network,
TLS, file, and process debugging tools. Runs as non-root (UID 65532),
has no package manager, and no SUID/SGID binaries.

## Included Tools

| Category | Tools |
|----------|-------|
| Network | curl, dig, nslookup, host, ping, traceroute, mtr, telnet, netstat, ifconfig, ip, ss, tcpdump, socat |
| TLS/Certs | openssl, ca-certificates |
| File/Data | jq, yq, nano, less, file, coreutils |
| Process | ps, top, htop, strace, lsof |
| Shell | bash, grep, sed, awk |

## Usage

### kubectl debug (ephemeral container)

Attach to a running pod for live debugging:

```bash
kubectl debug -it <pod-name> \
  --image=ghcr.io/ibshafique/base-images/netshell:latest \
  --target=<container-name>
```

This shares the process namespace of the target container, so you can
use `ps`, `strace -p <pid>`, and inspect `/proc`.

### kubectl debug (node debugging)

Debug a node by creating a privileged pod:

```bash
kubectl debug node/<node-name> \
  -it --image=ghcr.io/ibshafique/base-images/netshell:latest
```

### Pod sidecar

Add as a sidecar in a pod spec for persistent debugging access:

```yaml
spec:
  containers:
    - name: app
      image: my-app:latest
    - name: debug
      image: ghcr.io/ibshafique/base-images/netshell:latest
      command: ["sleep", "infinity"]
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        readOnlyRootFilesystem: true
        allowPrivilegeEscalation: false
        capabilities:
          drop: ["ALL"]
```

Then exec into it:

```bash
kubectl exec -it <pod-name> -c debug -- bash
```

### Docker

```bash
docker run -it --rm ghcr.io/ibshafique/base-images/netshell:latest
docker run --rm ghcr.io/ibshafique/base-images/netshell:latest curl -s https://example.com
```

### Docker Compose (network debugging)

```yaml
services:
  debug:
    image: ghcr.io/ibshafique/base-images/netshell:latest
    stdin_open: true
    tty: true
    network_mode: "service:my-app"
```

## Capabilities

Some tools require specific Linux capabilities to function. By default the
container drops all capabilities for security.

| Tool | Required Capability | How to grant |
|------|-------------------|--------------|
| `ping` | `CAP_NET_RAW` | `--cap-add NET_RAW` |
| `tcpdump` | `CAP_NET_RAW` | `--cap-add NET_RAW` |
| `strace` | `CAP_SYS_PTRACE` | `--cap-add SYS_PTRACE` (or use `kubectl debug --target`) |
| `mtr` | `CAP_NET_RAW` | `--cap-add NET_RAW` |

Example granting network capture capabilities:

```bash
kubectl debug -it <pod> \
  --image=ghcr.io/ibshafique/base-images/netshell:latest \
  --target=<container> \
  -- bash
```

For `tcpdump` in a pod spec, add to the security context:

```yaml
securityContext:
  capabilities:
    add: ["NET_RAW"]
```

## Security

- Runs as UID 65532 (nonroot) by default
- No package manager (apk removed at build time)
- No SUID/SGID binaries
- Works with read-only root filesystem
- Works with all capabilities dropped (tools that need caps will report errors)
- Idle sessions auto-exit after 1 hour (`TMOUT=3600`)
- Image is under 50MB
- Signed with Cosign (keyless, via GitHub Actions OIDC)
- Scanned with Trivy and Grype on every build

## Building

```bash
# Using the build DSL (requires bash 4+)
./build.sh build --load
./build.sh build test --load

# Using the Makefile
make build-netshell
```
