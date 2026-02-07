#!/usr/bin/env bash
# scripts/verify-reproducibility.sh
# Verifies content reproducibility (not bit-for-bit digest reproducibility)

set -euo pipefail

IMAGE="${1:?Usage: $0 <image-name>}"

echo "Testing content reproducibility for: $IMAGE"
echo "Note: Digests may differ due to compression, but contents should match"
echo ""

# Determine context directory
if [[ -d "images/base/$IMAGE" ]]; then
    CONTEXT="images/base/$IMAGE"
elif [[ -d "images/runtime/$IMAGE" ]]; then
    CONTEXT="images/runtime/$IMAGE"
elif [[ -d "images/demo/$IMAGE" ]]; then
    CONTEXT="images/demo/$IMAGE"
else
    echo "Error: Image $IMAGE not found"
    exit 1
fi

# Set reproducible timestamp
SOURCE_DATE_EPOCH=$(git log -1 --format=%ct -- "$CONTEXT")
export SOURCE_DATE_EPOCH

echo "Using SOURCE_DATE_EPOCH: $SOURCE_DATE_EPOCH ($(date -d @$SOURCE_DATE_EPOCH 2>/dev/null || date -r $SOURCE_DATE_EPOCH))"
echo ""

# Clean build (no cache)
echo "Building image (attempt 1)..."
docker buildx build \
    --build-arg SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    --platform linux/amd64 \
    --tag test-reproducible:1 \
    --load \
    --no-cache \
    "$CONTEXT" > /dev/null 2>&1

echo "Building image (attempt 2)..."
docker buildx build \
    --build-arg SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    --platform linux/amd64 \
    --tag test-reproducible:2 \
    --load \
    --no-cache \
    "$CONTEXT" > /dev/null 2>&1

# Get digests
DIGEST1=$(docker inspect test-reproducible:1 --format '{{.Id}}')
DIGEST2=$(docker inspect test-reproducible:2 --format '{{.Id}}')

echo "Digest 1: $DIGEST1"
echo "Digest 2: $DIGEST2"
echo ""

# Export to OCI format for content comparison
echo "Exporting images for content comparison..."
docker save test-reproducible:1 -o /tmp/image1.tar
docker save test-reproducible:2 -o /tmp/image2.tar

# Extract and compare layer contents (not compressed layers)
mkdir -p /tmp/image1 /tmp/image2
cd /tmp/image1 && tar xf /tmp/image1.tar && cd - > /dev/null
cd /tmp/image2 && tar xf /tmp/image2.tar && cd - > /dev/null

# Compare manifest content (excluding timestamps)
MANIFEST1=$(jq -S 'del(.[] | select(.RepoTags) | .Created)' /tmp/image1/manifest.json)
MANIFEST2=$(jq -S 'del(.[] | select(.RepoTags) | .Created)' /tmp/image2/manifest.json)

if [[ "$MANIFEST1" == "$MANIFEST2" ]]; then
    echo "✓ Content-reproducible: Manifests match (excluding timestamps)"
else
    echo "✗ NOT content-reproducible: Manifests differ"
    echo "Diff:"
    diff <(echo "$MANIFEST1") <(echo "$MANIFEST2") || true
fi

# Compare layer file contents
echo ""
echo "Comparing layer contents..."

LAYERS1=$(find /tmp/image1 -name "layer.tar" | sort)
LAYERS2=$(find /tmp/image2 -name "layer.tar" | sort)

LAYER_COUNT=$(echo "$LAYERS1" | wc -l)
MATCHING_LAYERS=0

for i in $(seq 1 $LAYER_COUNT); do
    LAYER1=$(echo "$LAYERS1" | sed -n "${i}p")
    LAYER2=$(echo "$LAYERS2" | sed -n "${i}p")

    # Extract layer contents
    mkdir -p /tmp/layer1/$i /tmp/layer2/$i
    tar xf "$LAYER1" -C /tmp/layer1/$i
    tar xf "$LAYER2" -C /tmp/layer2/$i

    # Compare file lists and contents (ignore timestamps)
    if diff -r -q /tmp/layer1/$i /tmp/layer2/$i > /dev/null 2>&1; then
        MATCHING_LAYERS=$((MATCHING_LAYERS + 1))
        echo "  Layer $i: ✓ MATCH"
    else
        echo "  Layer $i: ✗ DIFFER"
        diff -r /tmp/layer1/$i /tmp/layer2/$i | head -20
    fi
done

# Cleanup
echo ""
echo "Cleaning up..."
docker rmi test-reproducible:1 test-reproducible:2 > /dev/null 2>&1
rm -rf /tmp/image1 /tmp/image2 /tmp/image1.tar /tmp/image2.tar
rm -rf /tmp/layer1 /tmp/layer2

# Final verdict
echo ""
if [[ "$MATCHING_LAYERS" -eq "$LAYER_COUNT" ]]; then
    echo "✓ CONTENT-REPRODUCIBLE"
    echo "  All layer contents match exactly"
    echo "  Note: Image digests may still differ due to compression metadata"
    exit 0
else
    echo "✗ NOT CONTENT-REPRODUCIBLE"
    echo "  $MATCHING_LAYERS/$LAYER_COUNT layers match"
    exit 1
fi
