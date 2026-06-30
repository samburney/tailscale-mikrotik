#!/usr/bin/env sh
# Copyright (c) 2024 Fluent Networks Pty Ltd & AUTHORS All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.
#
# Updates tailscale respository and runs `docker build` with flags configured for 
# docker distribution. 
# 
############################################################################
#
# WARNING: Tailscale is not yet officially supported in Docker,
# Kubernetes, etc.
#
# It might work, but we don't regularly test it, and it's not as polished as
# our currently supported platforms. This is provided for people who know
# how Tailscale works and what they're doing.
#
# Our tracking bug for officially support container use cases is:
#    https://github.com/tailscale/tailscale/issues/504
#
# Also, see the various bugs tagged "containers":
#    https://github.com/tailscale/tailscale/labels/containers
#
############################################################################
#
# Set PLATFORM as required for your router model. See:
# https://mikrotik.com/products/matrix
#
PLATFORM="${PLATFORM:-linux/arm64}"
TAILSCALE_VERSION=1.98.8
VERSION=0.1.40

# Set other script values to be platform-specific
HOST_PLATFORM=$(docker version -f '{{.Server.Os}}/{{.Server.Arch}}')
PLATFORM_COMPAT=$(echo "$PLATFORM" | sed -E 's/[^-0-9a-z]/-/gI; s/-+/-/g')
FILENAME="tailscale-${TAILSCALE_VERSION}-${PLATFORM_COMPAT}.tar"

# Determine if a cross-platform builder is required
if [ "$PLATFORM" = "$HOST_PLATFORM" ]; then
  BUILDER="default"
else
  BUILDER="${PLATFORM_COMPAT}-builder"
  if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
    docker buildx create --name "${BUILDER}" --platform "${PLATFORM}" --use
  fi
fi

# Accept additional `docker buildx build` flags, defaulting to `--no-cache`.
# `--use-cache` is negates the default `--no-cache`.
USE_CACHE=0
ARGC=$#
i=0
while [ "$i" -lt "$ARGC" ]; do
  arg="$1"
  shift
  if [ "$arg" = "--use-cache" ]; then
    USE_CACHE=1
  else
    set -- "$@" "$arg"
  fi
  i=$((i + 1))
done

if [ "$USE_CACHE" -eq 0 ] && [ "$#" -eq 0 ]; then
  set -- --no-cache
fi

set -eu

rm -f "${FILENAME}"

if [ ! -d ./tailscale/.git ]
then
    git -c advice.detachedHead=false clone https://github.com/tailscale/tailscale.git --branch v$TAILSCALE_VERSION
else
    git -C ./tailscale/ fetch origin v$TAILSCALE_VERSION && \
    git -C ./tailscale/ -c advice.detachedHead=false checkout v$TAILSCALE_VERSION
fi

TS_USE_TOOLCHAIN="Y"
cd tailscale && eval $(./build_dist.sh shellvars) && cd ..

docker buildx build \
  "$@" \
  --build-arg TAILSCALE_VERSION=$TAILSCALE_VERSION \
  --build-arg VERSION_LONG=$VERSION_LONG \
  --build-arg VERSION_SHORT=$VERSION_SHORT \
  --build-arg VERSION_GIT_HASH=$VERSION_GIT_HASH \
  --platform $PLATFORM \
  --builder $BUILDER \
  --load -t ghcr.io/fluent-networks/tailscale-mikrotik:$VERSION-$TAILSCALE_VERSION .

skopeo copy docker-daemon:ghcr.io/fluent-networks/tailscale-mikrotik:$VERSION-$TAILSCALE_VERSION docker-archive:"$FILENAME"
