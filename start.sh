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

    printenv | grep -E '^RUNPOD_|^PATH=|^_=|^CUDA|^LD_LIBRARY_PATH|^PYTHONPATH|^HF_|^HUGGING' | while read -r line; do
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
export_env_vars

mkdir -p /workspace

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
FIXED_ARGS="--listen 0.0.0.0 --port 8188 --enable-cors-header"
if [ -s "$ARGS_FILE" ]; then
    CUSTOM_ARGS=$(grep -v '^#' "$ARGS_FILE" | tr '\n' ' ')
    if [ -n "$CUSTOM_ARGS" ]; then
        FIXED_ARGS="$FIXED_ARGS $CUSTOM_ARGS"
    fi
fi

echo "[comfyui] Starting with args: $FIXED_ARGS"
python main.py $FIXED_ARGS &
COMFY_PID=$!
trap "kill $COMFY_PID 2>/dev/null" SIGTERM SIGINT
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
