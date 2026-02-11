# netshell — Kubernetes debug/troubleshooting sidecar
# Multi-stage build: install tools, strip SUID/apk, copy to clean layer

# ---- Stage 1: Install tools ----
FROM alpine:3.21 AS builder

RUN apk add --no-cache \
    # Shell
    bash \
    # Network diagnostics
    curl \
    bind-tools \
    iputils \
    mtr \
    busybox-extras \
    net-tools \
    iproute2 \
    tcpdump \
    socat \
    # TLS / certificates
    openssl \
    ca-certificates \
    # File and data tools
    jq \
    yq \
    coreutils \
    file \
    less \
    nano \
    # Process and system tools
    procps \
    strace \
    htop \
    lsof \
    # Timezone data
    tzdata \
    # Strip all SUID/SGID bits (security hardening)
    && find / -type f \( -perm -4000 -o -perm -2000 \) -exec chmod ug-s {} + 2>/dev/null || true

# Create nonroot user (UID 65532, matching repo convention)
RUN echo "nonroot:x:65532:65532:nonroot:/home/nonroot:/bin/bash" > /etc/passwd \
    && echo "nonroot:x:65532:" > /etc/group \
    && mkdir -p /home/nonroot \
    && chown 65532:65532 /home/nonroot

# Remove package manager so it cannot be used at runtime
RUN rm -rf /sbin/apk /etc/apk /lib/apk /var/cache/apk /usr/share/apk

# ---- Stage 2: Clean final image (no package manager in any layer) ----
FROM scratch

COPY --from=builder / /

USER 65532:65532
WORKDIR /home/nonroot

# Auto-exit idle sessions after 1 hour (prevents forgotten debug containers)
ENV TERM=xterm-256color \
    TMOUT=3600

# CMD (not ENTRYPOINT) so `docker run <image> curl ...` replaces the command,
# and `kubectl debug` can pass arbitrary commands naturally
CMD ["/bin/bash"]

LABEL org.opencontainers.image.title="netshell"
LABEL org.opencontainers.image.description="Kubernetes debug/troubleshooting sidecar with network, TLS, and process tools. Non-root, no package manager, no SUID binaries."
LABEL org.opencontainers.image.source="https://github.com/ibshafique/base-images"
LABEL io.kubernetes.ephemeral-container="true"
