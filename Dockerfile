FROM nvidia/cuda:13.3.1-devel-ubuntu26.04

ARG DEBIAN_FRONTEND=noninteractive

LABEL description="spiral-fitting"
LABEL org.opencontainers.image.source="https://github.com/ScrollPrize/villa"

ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

# ---------- System deps (mirrors villa's install_build_deps.sh) ----------
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        software-properties-common ca-certificates curl unzip && \
    add-apt-repository -y universe && \
    apt-get update -y && \
    apt-get install -y --no-install-recommends \
        build-essential clang lld llvm flang-21 libclang-rt-21-dev mold \
        git cmake ninja-build ccache pkg-config \
        qt6-base-dev \
        libboost-system-dev libboost-program-options-dev \
        libceres-dev libsuitesparse-dev \
        libopencv-dev libopencv-contrib-dev \
        libcgal-dev libmpfr-dev libgmp-dev \
        libblosc-dev libzstd-dev libcurl4-openssl-dev \
        nlohmann-json3-dev libavahi-client-dev \
        liblz4-dev libtiff-dev \
        zlib1g-dev gfortran libopenblas-dev liblapack-dev liblapacke-dev libomp-dev \
        libscotch-dev libscotchmetis-dev libhwloc-dev \
        file bzip2 wget jq \
        python3 python3-dev python3-venv python3-pip \
        python-is-python3 \
        tmux htop nano vim less rclone && \
    ln -sf /usr/bin/flang-21 /usr/local/bin/flang && \
    rm -rf /var/lib/apt/lists/*

# ---------- Clone villa ----------
WORKDIR /opt
RUN git clone --depth 1 https://github.com/ScrollPrize/villa.git

# ---------- Build VC3D binaries ----------
WORKDIR /opt/villa/volume-cartographer
RUN cmake --preset ci-release-gcc && \
    cmake --build --preset ci-release-gcc -j$(nproc) && \
    cmake --install build/ci-release-gcc --prefix /usr/local --component vc_runtime && \
    find build/ci-release-gcc -name '*.o' -delete 2>/dev/null || true

# ---------- Python: PyTorch + spiral deps + VC Python bindings ----------
RUN pip install --break-system-packages \
        torch torchvision --index-url https://download.pytorch.org/whl/cu126

RUN pip install --break-system-packages \
        -e /opt/villa/volume-cartographer/scripts/spiral

RUN pip install --break-system-packages \
        -e /opt/villa/volume-cartographer

# ---------- JupyterLab ----------
RUN pip install --break-system-packages jupyterlab

# ---------- Convenience ----------
RUN install -m 0755 /dev/stdin /usr/local/bin/vc3d <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
exec env OMP_NUM_THREADS=8 OMP_WAIT_POLICY=PASSIVE OMP_NESTED=FALSE nice ionice VC3D "$@"
BASH

WORKDIR /root

EXPOSE 8888

RUN install -m 0755 /dev/stdin /usr/local/bin/start.sh <<'BASH'
#!/usr/bin/env bash
echo "============================================="
echo "  ScrollPrize Spiral Fitting — Ready!"
echo "============================================="
echo ""
echo "Python:  $(python --version)"
echo "PyTorch: $(python -c 'import torch; print(torch.__version__)')"
echo "CUDA:    $(python -c 'import torch; print(torch.cuda.is_available())')"
echo "GPU:     $(python -c 'import torch; print(torch.cuda.get_device_name(0) if torch.cuda.is_available() else "N/A")' 2>/dev/null || echo 'N/A')"
echo "VC:      $(python -c 'import vc; print("OK")' 2>/dev/null || echo 'not found')"
echo ""
echo "--- Setup ---"
echo "  cp -r /opt/villa /your/target/dir/villa"
echo ""
echo "--- Download dataset with rclone (~90 GB) ---"
echo "  mkdir -p /your/target/dir/data/phercparis4"
echo "  rclone copy :http: /your/target/dir/data/phercparis4 \\"
echo "    --http-url https://dl.ash2txt.org/datasets/spiral_datasets/PHercParis4/ \\"
echo "    --transfers 8 -P"
echo ""
echo "--- Then run ---"
echo "  cd /your/target/dir/villa/volume-cartographer/scripts/spiral"
echo "  # edit dataset_path in fit_spiral.py"
echo "  python fit_spiral.py"
echo ""
echo "JupyterLab starting on port 8888..."
echo ""

# Launch JupyterLab in the background
jupyter lab \
    --ip=0.0.0.0 \
    --port=8888 \
    --no-browser \
    --allow-root \
    --ServerApp.token='' \
    --ServerApp.password='' \
    --ServerApp.allow_origin='*' \
    --ServerApp.root_dir='/' &

# Keep container alive (also keeps RunPod's web terminal working)
exec sleep infinity
BASH

CMD ["/usr/local/bin/start.sh"]