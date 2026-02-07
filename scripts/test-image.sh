#!/usr/bin/env bash
# scripts/test-image.sh
# Security validation tests for container images

set -euo pipefail

IMAGE="${1:?Usage: $0 <image>}"
FAILURES=0

echo "Testing: $IMAGE"
echo ""

#
# Test 1: Non-root user (checked from host, not inside container)
#
echo -n "  ✓ Checking non-root user... "
USER_CONFIG=$(docker inspect "$IMAGE" --format='{{.Config.User}}' 2>/dev/null || echo "UNKNOWN")

if [[ "$USER_CONFIG" == "UNKNOWN" ]]; then
    echo "FAIL (could not inspect image)"
    FAILURES=$((FAILURES + 1))
elif [[ "$USER_CONFIG" == "" ]] || [[ "$USER_CONFIG" == "0" ]] || [[ "$USER_CONFIG" == "root" ]] || [[ "$USER_CONFIG" == "0:0" ]]; then
    echo "FAIL (running as root: $USER_CONFIG)"
    FAILURES=$((FAILURES + 1))
elif [[ "$USER_CONFIG" =~ ^65532 ]]; then
    echo "OK (UID 65532)"
else
    echo "WARN (non-standard UID: $USER_CONFIG)"
fi

#
# Test 2: No shell (checked by inspecting image layers)
#
echo -n "  ✓ Checking no shell... "
# Try to find shell binaries in image
if docker run --rm --entrypoint /bin/sh "$IMAGE" -c "exit 0" 2>/dev/null; then
    echo "FAIL (/bin/sh found)"
    FAILURES=$((FAILURES + 1))
elif docker run --rm --entrypoint /bin/bash "$IMAGE" -c "exit 0" 2>/dev/null; then
    echo "FAIL (/bin/bash found)"
    FAILURES=$((FAILURES + 1))
else
    echo "OK"
fi

#
# Test 3: Read-only filesystem compatibility
#
echo -n "  ✓ Checking read-only filesystem support... "
# Get entrypoint/cmd
ENTRYPOINT=$(docker inspect "$IMAGE" --format='{{.Config.Entrypoint}}' 2>/dev/null)
CMD=$(docker inspect "$IMAGE" --format='{{.Config.Cmd}}' 2>/dev/null)

if [[ "$ENTRYPOINT" != "[]" ]] && [[ "$ENTRYPOINT" != "" ]]; then
    # Has entrypoint, try to run with read-only
    if timeout 5 docker run --rm --read-only "$IMAGE" true 2>/dev/null; then
        echo "OK"
    else
        echo "WARN (image requires writable filesystem)"
    fi
else
    echo "SKIP (no entrypoint/cmd to test)"
fi

#
# Test 4: No capabilities required
#
echo -n "  ✓ Checking capability drop... "
if [[ "$ENTRYPOINT" != "[]" ]] && [[ "$ENTRYPOINT" != "" ]]; then
    if timeout 5 docker run --rm --cap-drop=ALL "$IMAGE" true 2>/dev/null; then
        echo "OK"
    else
        echo "WARN (image requires capabilities)"
    fi
else
    echo "SKIP (no entrypoint/cmd to test)"
fi

#
# Test 5: No package managers
#
echo -n "  ✓ Checking no package managers... "
HAS_PKG_MGR=false

for mgr in apt-get yum apk dnf zypper pip npm yarn; do
    if docker run --rm --entrypoint /usr/bin/$mgr "$IMAGE" --version 2>/dev/null; then
        echo "FAIL ($mgr found)"
        HAS_PKG_MGR=true
        FAILURES=$((FAILURES + 1))
        break
    fi
done

if [[ "$HAS_PKG_MGR" == "false" ]]; then
    echo "OK"
fi

#
# Test 6: Image size check
#
echo -n "  ✓ Checking image size... "
SIZE_MB=$(docker inspect "$IMAGE" --format='{{.Size}}' | awk '{print int($1/1024/1024)}')
if [[ $SIZE_MB -lt 50 ]]; then
    echo "OK (${SIZE_MB}MB - minimal)"
elif [[ $SIZE_MB -lt 200 ]]; then
    echo "OK (${SIZE_MB}MB - acceptable)"
else
    echo "WARN (${SIZE_MB}MB - large for minimal image)"
fi

#
# Summary
#
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ $FAILURES test(s) failed"
    exit 1
fi
