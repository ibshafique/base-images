# images/base/distroless-static/Dockerfile
FROM gcr.io/distroless/static-debian12:nonroot

# Already has:
# - /etc/passwd with nonroot user (UID 65532)
# - /etc/group with nonroot group (GID 65532)
# - CA certificates
# - No shell, no package manager

LABEL org.opencontainers.image.title="distroless-static"
LABEL org.opencontainers.image.description="Google Distroless static image (glibc-based)"
LABEL org.opencontainers.image.source="https://github.com/ibshafique/base-images"
