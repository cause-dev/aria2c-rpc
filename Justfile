# Justfile for the aria2 Podman Quadlet stack

set shell := ["bash", "-c"]

project_dir := justfile_directory()
containerfile := project_dir / "Containerfile"
quadlets_src := project_dir / "quadlets"

image := "localhost/aria2:latest"
container := "aria2"
service := "aria2.service"

quadlet_dir := env_var_or_default("ARIA2_QUADLET_DIR", home_directory() / ".config/containers/systemd")
config_dir := env_var_or_default("ARIA2_CONFIG_DIR", home_directory() / ".config/aria2")
downloads_dir := env_var_or_default("ARIA2_DOWNLOADS_DIR", home_directory() / "Downloads/aria2")

rpc_url := "http://localhost:6800/jsonrpc"

default:
    @just --list --unsorted

# ─── Build ──────────────────────────────────────────────────────────
# Build the image from Containerfile
build:
    podman build -f {{ containerfile }} -t {{ image }} {{ project_dir }}

# Lint entrypoint.sh (requires shellcheck)
lint:
    shellcheck entrypoint.sh

# Parse the live aria2.conf; exits non-zero if invalid
validate:
    @out=$(podman run --rm --entrypoint aria2c \
        -v {{ config_dir }}:/config:Z {{ image }} \
        --conf-path=/config/aria2.conf 2>&1 || true); \
    if echo "$out" | grep -q "no URI"; then \
        echo "✓ aria2.conf parses cleanly"; \
    else \
        echo "✗ aria2.conf is invalid:"; echo "$out" | head -20; exit 1; \
    fi

# ─── Sync ───────────────────────────────────────────────────────────

# Sync every *.container from quadlets/ to systemd user dir, then reload
sync:
    mkdir -p {{ quadlet_dir }}
    cp -v {{ quadlets_src }}/*.container {{ quadlet_dir }}/
    systemctl --user daemon-reload
    @echo "✓ quadlets synced"

# Show what would be synced (no writes)
sync-check:
    @echo "Source: {{ quadlets_src }}"
    @echo "Target: {{ quadlet_dir }}"
    @echo ""
    @diff -ru --brief {{ quadlets_src }}/ {{ quadlet_dir }}/ 2>/dev/null || true
    @echo "(run 'just sync' to apply)"

# Overwrite live config with project version — DANGER: clobbers RPC secret
push-config:
    @echo "⚠  This overwrites {{ config_dir }}/aria2.conf with the project version."
    @echo "   The project file contains __RPC_SECRET__ and the substitution only"
    @echo "   happens on first run — RPC auth will break until you edit the secret."
    @read -p "Type 'yes' to continue: " ans; \
    [ "$ans" = "yes" ] || { echo "Aborted."; exit 1; }
    cp -v {{ project_dir }}/aria2.conf {{ config_dir }}/aria2.conf
    @echo ""
    @echo "Now restore the secret:  just config"

# Full cycle: build → sync → restart → status
deploy: build sync
    -systemctl --user reset-failed {{ service }}
    systemctl --user restart {{ service }}
    @systemctl --user status --no-pager {{ service }}

# ─── Lifecycle ──────────────────────────────────────────────────────

start:
    systemctl --user start {{ service }}

stop:
    systemctl --user stop {{ service }}

restart:
    systemctl --user restart {{ service }}

# Reset failed state and restart (use when stuck in 'activating')
reset:
    -systemctl --user reset-failed {{ service }}
    systemctl --user restart {{ service }}

status:
    systemctl --user status --no-pager {{ service }}

# ─── Observability ──────────────────────────────────────────────────

logs:
    journalctl --user -u {{ service }} -f

tail:
    journalctl --user -u {{ service }} -b --no-pager -n 50

show:
    @systemctl --user status --no-pager {{ service }}
    @echo ""
    @echo "── recent logs ──"
    @journalctl --user -u {{ service }} -b --no-pager -n 20

# ─── Introspection ──────────────────────────────────────────────────

shell:
    podman exec -it {{ container }} sh

rpc-secret:
    @grep '^rpc-secret=' {{ config_dir }}/aria2.conf | cut -d= -f2-

rpc-test:
    @curl -sS --data-binary \
        '{"jsonrpc":"2.0","method":"aria2.getVersion","id":1}' \
        -H "Content-Type: application/json" {{ rpc_url }}; echo

ports:
    podman port {{ container }}

# ─── Editing ────────────────────────────────────────────────────────

# Edit the live aria2.conf
config:
    ${EDITOR:-vi} {{ config_dir }}/aria2.conf

# Edit the quadlet source in the project
edit-quadlet:
    ${EDITOR:-vi} {{ quadlets_src }}/aria2.container

# Edit the project's build-time config
edit-config:
    ${EDITOR:-vi} {{ project_dir }}/aria2.conf

# Edit the entrypoint script
edit-entrypoint:
    ${EDITOR:-vi} {{ project_dir }}/entrypoint.sh

# ─── Cleanup ────────────────────────────────────────────────────────

clean:
    -systemctl --user stop {{ service }}
    -podman rmi {{ image }}

nuke:
    @echo "This will delete:"
    @echo "  {{ config_dir }}"
    @echo "  {{ downloads_dir }}"
    @echo "  {{ quadlet_dir }}/aria2.container"
    @read -p "Type 'yes' to continue: " ans; \
    [ "$ans" = "yes" ] || { echo "Aborted."; exit 1; }
    -systemctl --user stop {{ service }}
    -podman rmi {{ image }}
    rm -rf {{ config_dir }} {{ downloads_dir }}
    rm -f {{ quadlet_dir }}/aria2.container
    -systemctl --user daemon-reload
    @echo "✓ nuked"
