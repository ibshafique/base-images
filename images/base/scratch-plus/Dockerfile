# images/base/scratch-plus/Dockerfile
FROM alpine:3.19@sha256:6457d53fb065d6f250e1504b9bc42d5b6c65941d57532c072d929dd0628977d0 AS builder

# Create minimal passwd/group files for non-root user
RUN echo "nonroot:x:65532:65532:nonroot:/home/nonroot:/sbin/nologin" > /etc/passwd.minimal && \
    echo "nonroot:x:65532:" > /etc/group.minimal

FROM scratch

# Copy minimal user files
COPY --from=builder /etc/passwd.minimal /etc/passwd
COPY --from=builder /etc/group.minimal /etc/group

# Copy CA certificates (pinned Alpine version)
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Set non-root user
USER 65532:65532

# Metadata
LABEL org.opencontainers.image.title="scratch-plus"
LABEL org.opencontainers.image.description="Minimal scratch image with CA certificates and non-root user"
LABEL org.opencontainers.image.source="https://github.com/ibshafique/base-images"
