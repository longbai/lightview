#!/bin/bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
project_directory="$(cd "$script_directory/.." && pwd)"
source_directory="$project_directory/Vendor/libwebp/upstream"

build_architecture() {
    local architecture="$1"
    local deployment_target="$2"
    local output_directory="$project_directory/build/vendor/$architecture"

    cmake -S "$source_directory" -B "$output_directory" \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DCMAKE_OSX_ARCHITECTURES="$architecture" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="$deployment_target" \
        -DCMAKE_C_FLAGS_RELEASE="-Os -fvisibility=hidden" \
        -DCMAKE_C_FLAGS_MINSIZEREL="-Os -DNDEBUG -fvisibility=hidden" \
        -DBUILD_SHARED_LIBS=OFF \
        -DWEBP_BUILD_ANIM_UTILS=OFF \
        -DWEBP_BUILD_CWEBP=OFF \
        -DWEBP_BUILD_DWEBP=OFF \
        -DWEBP_BUILD_GIF2WEBP=OFF \
        -DWEBP_BUILD_IMG2WEBP=OFF \
        -DWEBP_BUILD_VWEBP=OFF \
        -DWEBP_BUILD_WEBPINFO=OFF \
        -DWEBP_BUILD_LIBWEBPMUX=OFF \
        -DWEBP_BUILD_WEBPMUX=OFF \
        -DWEBP_BUILD_EXTRAS=OFF \
        -DWEBP_BUILD_WEBP_JS=OFF \
        -DWEBP_BUILD_FUZZTEST=OFF \
        -DWEBP_ENABLE_SIMD=ON

    cmake --build "$output_directory" --config MinSizeRel \
        --target webpdecoder webpdemux --parallel 8

    test -f "$output_directory/libwebpdecoder.a"
    test -f "$output_directory/libwebpdemux.a"
}

build_architecture x86_64 10.15
build_architecture arm64 11.0

for architecture in x86_64 arm64; do
    shasum -a 256 \
        "$project_directory/build/vendor/$architecture/libwebpdecoder.a" \
        "$project_directory/build/vendor/$architecture/libwebpdemux.a"
done
