#!/bin/sh
set -e

echo "[startup] PUBLIC_IP = ${PUBLIC_IP}"

# Detect the fly-global-services secondary IP on eth0.
# fly.io shows it as a secondary inet address (e.g. 172.19.x.x/29 secondary).
# Outbound UDP must originate from this IP — fly.io maps it to the dedicated
# public IPv4 at the edge. The primary eth0 IP (172.19.x.x private) and the
# manually-added public IP are both blocked outbound by the fly.io gateway.
GLOSVCS=$(ip -4 addr show dev eth0 | awk '/inet.*secondary/{gsub("/.*","",$2); print $2}')

if [ -z "$GLOSVCS" ]; then
    echo "[startup] WARNING: could not detect fly-global-services IP — outbound UDP source will be wrong"
else
    GW=$(ip route show default | awk '/via/{print $3; exit}')
    echo "[startup] fly-global-services IP = $GLOSVCS, gateway = $GW"
    ip route replace default via "$GW" dev eth0 src "$GLOSVCS"
    echo "[startup] Default route src set to $GLOSVCS — ENet replies will use this source IP"
fi

echo "[startup] Launching game server..."
exec stdbuf -o0 ./fp-mager.x86_64 --headless --server 2>&1
