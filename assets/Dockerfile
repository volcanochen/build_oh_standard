FROM swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2

LABEL maintainer="OpenHarmony Builder"
LABEL description="OpenHarmony QEMU ARM64 Standard System Build Environment"

RUN echo 'export PATH=$PATH:/root/.local/bin' >> /root/.bashrc && \
    python3 -m pip install --user build/hb > /dev/null 2>&1 && \
    echo "hb installed successfully"

WORKDIR /workspace
VOLUME ["/workspace"]

ENV BUILD_PRODUCT=qemu-arm64-linux-min
ENV BUILD_VENDOR=ohemu
