# images/base/wolfi-micro/Dockerfile
FROM cgr.dev/chainguard/wolfi-base:latest AS builder

# Install minimal packages
RUN apk add --no-cache \
    ca-certificates \
    tzdata

# Extract minimal user files
RUN grep "^nonroot:" /etc/passwd > /etc/passwd.minimal && \
    grep "^nonroot:" /etc/group > /etc/group.minimal

FROM scratch

# Copy user files
COPY --from=builder /etc/passwd.minimal /etc/passwd
COPY --from=builder /etc/group.minimal /etc/group

# Copy certificates and timezone data
COPY --from=builder /etc/ssl/certs/ /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo

USER 65532:65532

LABEL org.opencontainers.image.title="wolfi-micro"
LABEL org.opencontainers.image.description="Minimal Wolfi-based runtime with timezone support"
