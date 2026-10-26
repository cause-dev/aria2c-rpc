#!/bin/sh
set -e

CONFIG=/config/aria2.conf

if [ ! -f "$CONFIG" ]; then
    RPC_SECRET=$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 24)
    sed "s|__RPC_SECRET__|$RPC_SECRET|" /etc/aria2/aria2.conf > "$CONFIG"
    echo "[entrypoint] Created $CONFIG with a random RPC secret:"
    echo "[entrypoint]   rpc-secret=$RPC_SECRET"
fi

touch /config/aria2.session
exec aria2c --conf-path="$CONFIG" "$@"