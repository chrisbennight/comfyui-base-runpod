# ============================================================================
# Stage 1: Builder - Download pinned sources and install all Python packages
# ============================================================================
FROM ubuntu:24.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

# ---- Version pins (set in docker-bake.hcl) ----
ARG COMFYUI_VERSION
ARG MANAGER_SHA
ARG KJNODES_SHA
ARG RGTHREE_SHA
ARG CUSTOM_SCRIPTS_SHA
ARG IMPACT_PACK_SHA
ARG INSPIRE_PACK_SHA
ARG CONTROLNET_AUX_SHA
ARG WAS_SUITE_SHA
ARG VIDEOHELPER_SHA
ARG WANVIDEO_SHA
ARG LTXVIDEO_SHA
ARG GGUF_SHA
ARG TORCH_VERSION
ARG TORCHVISION_VERSION
ARG TORCHAUDIO_VERSION

# ---- CUDA variant (set in docker-bake.hcl per target) ----
ARG CUDA_VERSION_DASH=12-8
ARG TORCH_INDEX_SUFFIX=cu128

# Install minimal dependencies needed for building
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    wget \
    curl \
    git \
    ca-certificates \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} libcusparse-dev-${CUDA_VERSION_DASH} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Install pip and pip-tools for lock file generation
RUN curl -sS https://bootstrap.pypa.io/get-pip.py -o get-pip.py && \
    python3.12 get-pip.py && \
    python3.12 -m pip install --no-cache-dir pip-tools && \
    rm get-pip.py

# Set CUDA environment for building
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Download pinned ComfyUI source
WORKDIR /tmp/build
RUN curl -fSL "https://github.com/comfyanonymous/ComfyUI/archive/refs/tags/${COMFYUI_VERSION}.tar.gz" -o comfyui.tar.gz && \
    mkdir -p ComfyUI && tar xzf comfyui.tar.gz --strip-components=1 -C ComfyUI && rm comfyui.tar.gz

# Download pinned custom node sources
# Each entry: <subdir> <owner/repo> <ARG name>
WORKDIR /tmp/build/ComfyUI/custom_nodes
RUN set -eux; \
    fetch() { local dir="$1" repo="$2" sha="$3"; \
      curl -fSL "https://github.com/${repo}/archive/${sha}.tar.gz" -o /tmp/n.tgz && \
      mkdir -p "$dir" && tar xzf /tmp/n.tgz --strip-components=1 -C "$dir" && rm /tmp/n.tgz; }; \
    fetch ComfyUI-Manager         ltdrdata/ComfyUI-Manager          "${MANAGER_SHA}"; \
    fetch ComfyUI-KJNodes         kijai/ComfyUI-KJNodes             "${KJNODES_SHA}"; \
    fetch rgthree-comfy           rgthree/rgthree-comfy             "${RGTHREE_SHA}"; \
    fetch ComfyUI-Custom-Scripts  pythongosssss/ComfyUI-Custom-Scripts "${CUSTOM_SCRIPTS_SHA}"; \
    fetch ComfyUI-Impact-Pack     ltdrdata/ComfyUI-Impact-Pack      "${IMPACT_PACK_SHA}"; \
    fetch ComfyUI-Inspire-Pack    ltdrdata/ComfyUI-Inspire-Pack     "${INSPIRE_PACK_SHA}"; \
    fetch comfyui_controlnet_aux  Fannovel16/comfyui_controlnet_aux "${CONTROLNET_AUX_SHA}"; \
    fetch was-node-suite-comfyui  WASasquatch/was-node-suite-comfyui "${WAS_SUITE_SHA}"; \
    fetch ComfyUI-VideoHelperSuite Kosinkadink/ComfyUI-VideoHelperSuite "${VIDEOHELPER_SHA}"; \
    fetch ComfyUI-WanVideoWrapper kijai/ComfyUI-WanVideoWrapper     "${WANVIDEO_SHA}"; \
    fetch ComfyUI-LTXVideo        Lightricks/ComfyUI-LTXVideo       "${LTXVIDEO_SHA}"; \
    fetch ComfyUI-GGUF            city96/ComfyUI-GGUF               "${GGUF_SHA}"

# Init git repos with upstream remotes so ComfyUI-Manager can detect versions
# and users can update via Manager at their own risk
RUN set -eux; \
    init_repo() { local dir="$1" repo="$2" ref="$3"; \
      cd "/tmp/build/ComfyUI/custom_nodes/$dir" && \
      git init -q && git add -A && \
      git -c user.name=- -c user.email=- commit -q -m "${dir} ${ref}" && \
      git remote add origin "https://github.com/${repo}.git"; }; \
    cd /tmp/build/ComfyUI && \
      git init -q && git add -A && \
      git -c user.name=- -c user.email=- commit -q -m "ComfyUI ${COMFYUI_VERSION}" && \
      git tag "${COMFYUI_VERSION}" && \
      git remote add origin https://github.com/comfyanonymous/ComfyUI.git; \
    init_repo ComfyUI-Manager          ltdrdata/ComfyUI-Manager           "${MANAGER_SHA}"; \
    init_repo ComfyUI-KJNodes          kijai/ComfyUI-KJNodes              "${KJNODES_SHA}"; \
    init_repo rgthree-comfy            rgthree/rgthree-comfy              "${RGTHREE_SHA}"; \
    init_repo ComfyUI-Custom-Scripts   pythongosssss/ComfyUI-Custom-Scripts "${CUSTOM_SCRIPTS_SHA}"; \
    init_repo ComfyUI-Impact-Pack      ltdrdata/ComfyUI-Impact-Pack       "${IMPACT_PACK_SHA}"; \
    init_repo ComfyUI-Inspire-Pack     ltdrdata/ComfyUI-Inspire-Pack      "${INSPIRE_PACK_SHA}"; \
    init_repo comfyui_controlnet_aux   Fannovel16/comfyui_controlnet_aux  "${CONTROLNET_AUX_SHA}"; \
    init_repo was-node-suite-comfyui   WASasquatch/was-node-suite-comfyui "${WAS_SUITE_SHA}"; \
    init_repo ComfyUI-VideoHelperSuite Kosinkadink/ComfyUI-VideoHelperSuite "${VIDEOHELPER_SHA}"; \
    init_repo ComfyUI-WanVideoWrapper  kijai/ComfyUI-WanVideoWrapper      "${WANVIDEO_SHA}"; \
    init_repo ComfyUI-LTXVideo         Lightricks/ComfyUI-LTXVideo        "${LTXVIDEO_SHA}"; \
    init_repo ComfyUI-GGUF             city96/ComfyUI-GGUF                "${GGUF_SHA}"

# Generate lock file from all requirements (including torch pins), then install with hash verification.
#
# Two passes:
#   1. PyPI deps go through pip-compile --generate-hashes -> pip install --require-hashes (reproducible, hash-verified).
#   2. VCS deps (git+/hg+/bzr+/svn+) are filtered out before pip-compile because pip cannot
#      hash-verify VCS URLs by design. They are installed in a separate, non-hashed step.
#
#      As of these node SHAs, the VCS deps are:
#        - ComfyUI-Impact-Pack -> facebookresearch/sam2 (SAM2 segmentation)
#        - was-node-suite-comfyui -> WASasquatch/{img2texture, cstr, ffmpy}
#
#      Security tradeoff: we pin the parent custom node SHAs, but the VCS URLs themselves
#      point at upstream HEAD and can drift. Follow-up: pin VCS URLs to specific commits.
#
# Each requirements file is appended with a forced trailing newline so a node's
# requirements.txt without a final \n can't fuse its last line into the next file's first
# line (e.g. WanVideoWrapper's `scipy` + controlnet_aux's `torch` -> `scipytorch`).
WORKDIR /tmp/build
RUN { cat ComfyUI/requirements.txt; echo; } > requirements.raw && \
    for node_dir in ComfyUI/custom_nodes/*/; do \
        if [ -f "$node_dir/requirements.txt" ]; then \
            { cat "$node_dir/requirements.txt"; echo; } >> requirements.raw; \
        fi; \
    done && \
    grep -E '^(git|hg|bzr|svn)\+' requirements.raw > requirements.vcs.txt || true && \
    grep -vE '^(git|hg|bzr|svn)\+' requirements.raw > requirements.in && \
    echo "GitPython" >> requirements.in && \
    echo "opencv-python" >> requirements.in && \
    echo "huggingface_hub[cli]" >> requirements.in && \
    echo "torch==${TORCH_VERSION}" >> constraints.txt && \
    echo "torchvision==${TORCHVISION_VERSION}" >> constraints.txt && \
    echo "torchaudio==${TORCHAUDIO_VERSION}" >> constraints.txt && \
    echo "pillow>=12.1.1" >> constraints.txt && \
    TORCH_INDEX_URL="https://download.pytorch.org/whl/${TORCH_INDEX_SUFFIX}" && \
    PIP_INDEX_URL=https://pypi.org/simple \
    PIP_EXTRA_INDEX_URL="${TORCH_INDEX_URL}" \
    PIP_CONSTRAINT=constraints.txt \
    pip-compile --generate-hashes --output-file=requirements.lock --strip-extras --allow-unsafe requirements.in && \
    python3.12 -m pip install --no-cache-dir --ignore-installed --require-hashes \
    --index-url https://pypi.org/simple \
    --extra-index-url "${TORCH_INDEX_URL}" \
    -r requirements.lock && \
    if [ -s requirements.vcs.txt ]; then \
        echo "Installing VCS deps (cannot be hash-verified):" && \
        cat requirements.vcs.txt && \
        python3.12 -m pip install --no-cache-dir --ignore-installed \
        --index-url https://pypi.org/simple \
        --extra-index-url "${TORCH_INDEX_URL}" \
        -r requirements.vcs.txt; \
    fi

# Pre-populate ComfyUI-Manager cache so first cold start skips the slow registry fetch
COPY scripts/prebake-manager-cache.py /tmp/prebake-manager-cache.py
RUN python3.12 /tmp/prebake-manager-cache.py /tmp/build/ComfyUI/user/__manager/cache

# Bake ComfyUI + custom nodes into a known location for runtime copy
RUN cp -r /tmp/build/ComfyUI /opt/comfyui-baked

# ============================================================================
# Stage 2: Runtime - Clean image with pre-installed packages
# ============================================================================
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV IMAGEIO_FFMPEG_EXE=/usr/bin/ffmpeg

# ---- CUDA variant (re-declared for runtime stage) ----
ARG CUDA_VERSION_DASH=12-8

# ---- Caddy version pin (set in docker-bake.hcl) ----
ARG CADDY_VERSION
ARG CADDY_SHA256

# Update and install runtime dependencies, CUDA, and common tools
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y --no-install-recommends \
    git \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    build-essential \
    libssl-dev \
    wget \
    gnupg \
    xz-utils \
    openssh-client \
    openssh-server \
    nano \
    curl \
    htop \
    tmux \
    ca-certificates \
    less \
    net-tools \
    iputils-ping \
    procps \
    openssl \
    ffmpeg \
    aria2 \
    && wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends cuda-minimal-build-${CUDA_VERSION_DASH} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm cuda-keyring_1.1-1_all.deb \
    && rm -f /usr/lib/python3.12/EXTERNALLY-MANAGED

# Copy Python packages and executables from builder stage
COPY --from=builder /usr/local/lib/python3.12 /usr/local/lib/python3.12
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy baked ComfyUI + custom nodes from builder stage
COPY --from=builder /opt/comfyui-baked /opt/comfyui-baked

# Remove uv to force ComfyUI-Manager to use pip (uv doesn't respect --system-site-packages properly)
RUN pip uninstall -y uv 2>/dev/null || true && \
    rm -f /usr/local/bin/uv /usr/local/bin/uvx

# Set CUDA environment variables
ENV PATH=/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/cuda/lib64

# Allow container to start on hosts with older CUDA 12.x drivers
ENV NVIDIA_REQUIRE_CUDA=""
ENV NVIDIA_DISABLE_REQUIRE=true
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=all

# Configure SSH for root login
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    mkdir -p /run/sshd && \
    rm -f /etc/ssh/ssh_host_*

# Workspace = mount point for the RunPod Network Volume (or pod volume)
RUN mkdir -p /workspace
WORKDIR /workspace

# Install Caddy (pinned version + SHA256). Used by start.sh as a reverse proxy
# in front of ComfyUI when ALLOWED_IPS is set, to enforce a source-IP allowlist.
RUN curl -fSL "https://github.com/caddyserver/caddy/releases/download/v${CADDY_VERSION}/caddy_${CADDY_VERSION}_linux_amd64.tar.gz" -o /tmp/caddy.tgz && \
    echo "${CADDY_SHA256}  /tmp/caddy.tgz" | sha256sum -c - && \
    tar xzf /tmp/caddy.tgz -C /usr/local/bin caddy && \
    rm /tmp/caddy.tgz && \
    mkdir -p /etc/caddy

COPY caddy/Caddyfile /etc/caddy/Caddyfile

# Copy bootstrap scripts
COPY scripts/download-models.sh /usr/local/bin/download-models.sh
RUN chmod +x /usr/local/bin/download-models.sh

# Expose ports: ComfyUI + SSH
EXPOSE 8188 22

# Copy start script
COPY start.sh /start.sh

# Set Python 3.12 as default
RUN update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 && \
    update-alternatives --set python3 /usr/bin/python3.12

ENTRYPOINT ["/start.sh"]
