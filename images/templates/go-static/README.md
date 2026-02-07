# Go Static Application Template

This template demonstrates building secure, minimal Go applications.

## Usage

1. Copy this template to your Go project:
   ```bash
   cp -r images/templates/go-static/* your-go-project/
   ```

2. Customize Dockerfile.template:
   - Replace `./cmd/yourapp` with your main package path
   - Customize EXPOSE port
   - Add environment variables if needed

3. Build:
   ```bash
   docker build -t your-app:latest -f Dockerfile.template .
   ```

4. Run:
   ```bash
   docker run -p 8080:8080 your-app:latest
   ```

## Example

See `example/` directory for a working HTTP server.

## Requirements

- Go 1.23+
- Docker Buildx
- Base image: `scratch-plus:latest`

## Security

- Static binary (CGO_ENABLED=0)
- Non-root user (UID 65532)
- Minimal base (scratch + CA certs)
- No shell, no package manager
- Health check included

## Customization

### Add dependencies at build time:
```dockerfile
RUN apk add --no-cache git ca-certificates
```

### Use CGO (requires glibc):
```dockerfile
# Change runtime base to distroless-static
FROM ghcr.io/.../distroless-static:latest

# Change build to:
RUN CGO_ENABLED=1 go build ...
```

### Add configuration files:
```dockerfile
COPY --chown=65532:65532 config.yaml /config/
```
