#!/bin/bash
set -e

# Workspace layout (RunPod Network Volume should be mounted at /workspace)
COMFYUI_DIR="/workspace/ComfyUI"
VENV_DIR="$COMFYUI_DIR/.venv"
ARGS_FILE="/workspace/comfyui_args.txt"

# ---------------------------------------------------------------------------- #
#                          Function Definitions                                #
# ---------------------------------------------------------------------------- #

setup_ssh() {
    mkdir -p ~/.ssh

    if [ ! -f /etc/ssh/ssh_host_ed25519_key ]; then
        ssh-keygen -A -q
    fi

    if [[ $PUBLIC_KEY ]]; then
        echo "$PUBLIC_KEY" >> ~/.ssh/authorized_keys
        chmod 700 -R ~/.ssh
        echo "[ssh] PUBLIC_KEY installed for root."
    else
        RANDOM_PASS=$(openssl rand -base64 12)
        echo "root:${RANDOM_PASS}" | chpasswd
        echo "============================================================"
        echo "[ssh] No PUBLIC_KEY set. Generated root password:"
        echo "      ${RANDOM_PASS}"
        echo "      (Set PUBLIC_KEY env to use key auth instead.)"
        echo "============================================================"
    fi

    echo "PermitUserEnvironment yes" >> /etc/ssh/sshd_config
    /usr/sbin/sshd
}

# Point HF and torch caches at the persistent volume so model downloads
# triggered at runtime (transformers, diffusers, torch.hub, etc.) survive
# pod swaps. User-provided values are honored.
setup_caches() {
    export HF_HOME="${HF_HOME:-/workspace/.cache/huggingface}"
    export TORCH_HOME="${TORCH_HOME:-/workspace/.cache/torch}"
    mkdir -p "$HF_HOME" "$TORCH_HOME"
    echo "[cache] HF_HOME=$HF_HOME"
    echo "[cache] TORCH_HOME=$TORCH_HOME"
}

# If ALLOWED_IPS is set, start Caddy as a reverse proxy in front of ComfyUI
# with a source-IP allowlist. Caddy listens on 0.0.0.0:8188 (the port RunPod
# exposes) and forwards to ComfyUI on 127.0.0.1:8189. ComfyUI itself is bound
# to localhost so the only way in is through Caddy's allowlist.
#
# When ALLOWED_IPS is unset, ComfyUI binds to 127.0.0.1:8188 and Caddy is not
# started — access via SSH tunnel only.
maybe_start_caddy() {
    if [ -z "${ALLOWED_IPS:-}" ]; then
        echo "[caddy] ALLOWED_IPS unset — Caddy NOT started."
        echo "[caddy] ComfyUI will bind to 127.0.0.1 only; reach it via SSH tunnel:"
        echo "[caddy]   ssh -L 8188:localhost:8188 root@<pod>.proxy.runpod.net"
        COMFY_LISTEN="127.0.0.1"
        COMFY_PORT=8188
        return
    fi
    echo "[caddy] ALLOWED_IPS=${ALLOWED_IPS} — starting Caddy with source-IP allowlist."
    export ALLOWED_IPS
    COMFY_LISTEN="127.0.0.1"
    COMFY_PORT=8189
    mkdir -p /var/log
    nohup caddy run --config /etc/caddy/Caddyfile --adapter caddyfile \
        > /var/log/caddy.log 2>&1 &
    CADDY_PID=$!
    sleep 1
    if ! kill -0 "$CADDY_PID" 2>/dev/null; then
        echo "[caddy] ERROR: Caddy failed to start. Tail of /var/log/caddy.log:"
        tail -30 /var/log/caddy.log || true
        exit 1
    fi
    echo "[caddy] Caddy running (pid $CADDY_PID): 0.0.0.0:8188 -> 127.0.0.1:8189"
    echo "[caddy] Verify your detected IP: GET /__whoami"
}

# Propagate selected env vars so SSH/non-interactive shells inherit them
export_env_vars() {
    ENV_FILE="/etc/environment"
    PAM_ENV_FILE="/etc/security/pam_env.conf"
    SSH_ENV_DIR="/root/.ssh/environment"

    cp "$ENV_FILE" "${ENV_FILE}.bak" 2>/dev/null || true
    cp "$PAM_ENV_FILE" "${PAM_ENV_FILE}.bak" 2>/dev/null || true

    > "$ENV_FILE"
    > "$PAM_ENV_FILE"
    mkdir -p /root/.ssh
    > "$SSH_ENV_DIR"

    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^HF_|^HUGGING|^TORCH_HOME' | while read -r line; do
        name=$(echo "$line" | cut -d= -f1)
        value=$(echo "$line" | cut -d= -f2-)
        echo "$name=\"$value\"" >> "$ENV_FILE"
        echo "$name DEFAULT=\"$value\"" >> "$PAM_ENV_FILE"
        echo "$name=\"$value\"" >> "$SSH_ENV_DIR"
        echo "export $name=\"$value\"" >> /etc/rp_environment
    done

    grep -q rp_environment ~/.bashrc 2>/dev/null || echo 'source /etc/rp_environment' >> ~/.bashrc
    grep -q rp_environment /etc/bash.bashrc 2>/dev/null || echo 'source /etc/rp_environment' >> /etc/bash.bashrc

    chmod 644 "$ENV_FILE" "$PAM_ENV_FILE"
    chmod 600 "$SSH_ENV_DIR"
}

# ---------------------------------------------------------------------------- #
#                               Main Program                                   #
# ---------------------------------------------------------------------------- #

setup_ssh
mkdir -p /workspace
setup_caches
maybe_start_caddy
export_env_vars

if [ ! -f "$ARGS_FILE" ]; then
    cat > "$ARGS_FILE" <<'EOF'
# Add custom ComfyUI CLI args here, one per line. Lines starting with `#` are ignored.
# Examples:
#   --max-batch-size 8
#   --preview-method auto
#   --reserve-vram 1.5
EOF
fi

# First-boot setup: copy baked ComfyUI to the (persistent) workspace
if [ ! -d "$COMFYUI_DIR" ]; then
    echo "[setup] First boot: copying baked ComfyUI to $COMFYUI_DIR ..."
    cp -r /opt/comfyui-baked "$COMFYUI_DIR"
fi

# Create or reuse venv (uses --system-site-packages so torch/numpy/etc. come from the image)
if [ ! -d "$VENV_DIR" ]; then
    echo "[setup] Creating venv at $VENV_DIR ..."
    python3.12 -m venv --system-site-packages "$VENV_DIR"
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
    python -m ensurepip --upgrade > /dev/null
else
    # shellcheck disable=SC1091
    source "$VENV_DIR/bin/activate"
fi

# Warm up pip so ComfyUI-Manager's 5s timeout check doesn't fail on cold start
python -m pip --version > /dev/null 2>&1 || true

# Optional: bootstrap a default model set into /workspace/ComfyUI/models
if [ "${BOOTSTRAP_MODELS:-0}" = "1" ]; then
    echo "[setup] BOOTSTRAP_MODELS=1 — running download-models.sh ..."
    /usr/local/bin/download-models.sh || echo "[setup] WARNING: model bootstrap returned non-zero"
fi

# Launch ComfyUI; keep container alive on crash so SSH stays accessible
cd "$COMFYUI_DIR"
FIXED_ARGS="--listen ${COMFY_LISTEN} --port ${COMFY_PORT} --enable-cors-header"
if [ -s "$ARGS_FILE" ]; then
    CUSTOM_ARGS=$(grep -v '^#' "$ARGS_FILE" | tr '\n' ' ')
    if [ -n "$CUSTOM_ARGS" ]; then
        FIXED_ARGS="$FIXED_ARGS $CUSTOM_ARGS"
    fi
fi

echo "[comfyui] Starting with args: $FIXED_ARGS"
python main.py $FIXED_ARGS &
COMFY_PID=$!
trap "kill \$COMFY_PID 2>/dev/null; [ -n \"\${CADDY_PID:-}\" ] && kill \$CADDY_PID 2>/dev/null" SIGTERM SIGINT
wait $COMFY_PID || true

cat <<EOF
============================================================
ComfyUI exited. SSH is still up so you can debug.

To restart manually:
  cd $COMFYUI_DIR && source $VENV_DIR/bin/activate
  python main.py $FIXED_ARGS
============================================================
EOF

sleep infinity
