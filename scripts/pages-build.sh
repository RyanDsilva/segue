#!/bin/sh
# Cloudflare Pages build command (WS6 4.4): builds the user guide into website/guide, which
# Pages then publishes with the rest of website/ (build output directory `website`). The
# Node version comes from .node-version (the mise pin); pnpm is fetched at the pinned version.
set -eu
cd "$(dirname "$0")/.."
want="v$(tr -d '[:space:]' < .node-version)"
have="$(node --version)"
if [ "$have" != "$want" ]; then
  echo "pages-build: node $have, but .node-version wants $want" >&2
  exit 1
fi
export ASTRO_TELEMETRY_DISABLED=1
npx --yes pnpm@12.14.0 --dir guide install --frozen-lockfile
npx --yes pnpm@12.14.0 --dir guide build
