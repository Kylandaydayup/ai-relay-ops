#!/usr/bin/env bash
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-image-build.sh"
init_image_build "$@"

images="${BASE_IMAGES:-oven/bun:1 golang:1.26.1-alpine golang:1.25.8 debian:bookworm-slim debian:latest python:3.12-slim maven:3.9.9-eclipse-temurin-21 eclipse-temurin:21-jre node:20-alpine node:20.20.1 nginx:alpine postgres:16-alpine alpine:latest}"
for image in $images; do
  ensured="$(ensure_base_image "$image")"
  echo "$image -> $ensured"
done
