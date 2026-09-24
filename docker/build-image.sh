#!/bin/bash
set -Eeuo pipefail
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_root=$(cd -- "$here/.." && pwd)
image=${IMAGE:-antivirus:optimized}
binary_image=${BINARY_IMAGE:-antivirus:optimized-binaries}
mode=${BUILD_MODE:-fast}

if [[ "$mode" != fast && "$mode" != source ]]; then
    echo 'BUILD_MODE must be fast or source.' >&2
    exit 1
fi
if [[ "$image" == "$binary_image" ]]; then
    echo 'IMAGE and BINARY_IMAGE must differ so the reusable binary image is preserved.' >&2
    exit 1
fi
# The workspace copies are authoritative; never overwrite local edits by
# silently importing configuration from the old deployment folder.
if [[ ! -s "$here/config/clamd.conf" || ! -s "$here/config/freshclam.conf" ]]; then
    echo "Missing authoritative configuration in $here/config/." >&2
    echo "For a first import, run $here/import-config.py /path/to/antivirus" >&2
    exit 1
fi
if grep -Eq '^[[:space:]]*LocalSocket[[:space:]]' "$here/config/clamd.conf"; then
    echo 'This image expects TCP-only configuration.' >&2
    exit 1
fi
revision=$(git -C "$source_root" rev-parse HEAD)
if [[ "$mode" == source ]]; then
    tree_hash=$(python3 "$here/source-manifest.py" "$source_root")
    args=(--build-arg "BUILD_JOBS=${BUILD_JOBS:-2}"
          --build-arg "SOURCE_REVISION=$revision"
          --build-arg "SOURCE_TREE_SHA256=$tree_hash")
    if [[ -n "${RUST_IMAGE:-}" ]]; then args+=(--build-arg "RUST_IMAGE=$RUST_IMAGE"); fi
    if [[ -n "${DEBIAN_IMAGE:-}" ]]; then args+=(--build-arg "DEBIAN_IMAGE=$DEBIAN_IMAGE"); fi
    docker build --progress=plain -f "$here/Dockerfile" -t "$binary_image" "${args[@]}" "$@" "$source_root"
elif ! docker image inspect "$binary_image" >/dev/null 2>&1; then
    echo "Missing reusable image $binary_image. Run BUILD_MODE=source $here/build-image.sh once." >&2
    exit 1
fi
# Keep the original binary provenance labels. A config-only repack must not
# claim its binaries were compiled from the current checkout.
docker build --progress=plain -f "$here/Dockerfile.fast" -t "$image" \
    --build-arg "BINARY_IMAGE=$binary_image" \
    --build-arg "PACKAGING_REVISION=$revision" "$@" "$source_root"
echo "Packaged $image using existing binaries from $binary_image"
if [[ -n "${SAVE_IMAGE:-}" ]]; then
    docker image save "$image" | gzip > "$SAVE_IMAGE"
    echo "Saved $SAVE_IMAGE"
fi
