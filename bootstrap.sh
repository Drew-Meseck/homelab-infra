#!/usr/bin/env bash
# Run ONCE on the docker host to create the shared networks that services join.
# Safe to re-run: `docker network create` is a no-op if the network exists.
set -euo pipefail

for net in edge data; do
	if docker network inspect "$net" >/dev/null 2>&1; then
		echo "network '$net' already exists"
	else
		docker network create "$net"
		echo "created network '$net'"
	fi
done

echo
echo "Next: copy each service's .env.example -> .env, fill in values, then:"
echo "  (cd caddy    && docker compose up -d)"
echo "  (cd postgres && docker compose up -d)"
echo "  (cd jellyfin && docker compose up -d)"
