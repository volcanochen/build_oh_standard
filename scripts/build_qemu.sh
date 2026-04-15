#!/bin/bash
# OpenHarmony QEMU ARM64 构建脚本
# 用法: ./build_qemu.sh [--clean] [--gn-only]

set -e

PRODUCT_NAME="qemu-arm64-linux-min"
VENDOR="ohemu"
DOCKER_IMAGE="swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2"
WORKSPACE="/workspace"

# 解析参数
CLEAN=false
GN_ONLY=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)
            CLEAN=true
            shift
            ;;
        --gn-only)
            GN_ONLY=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            exit 1
            ;;
    esac
done

# 进入工作目录
cd "$(dirname "$0")/../.."
if [ ! -d ".git" ]; then
    echo "错误: 必须在 OpenHarmony 源码根目录运行"
    exit 1
fi

# 清理 (在 Docker 容器内以 root 权限执行，避免权限问题)
if [ "$CLEAN" = true ]; then
    echo "清理旧构建 (在 Docker 容器内执行)..."
    docker run --rm \
        -v "$(pwd):${WORKSPACE}" \
        -w "${WORKSPACE}" \
        "${DOCKER_IMAGE}" \
        bash -c "rm -rf /workspace/out"
fi

# 下载预编译工具 (如果需要)
if [ ! -d "prebuilts" ]; then
    echo "下载预编译工具..."
    bash build/prebuilts_download.sh
fi

# 构建命令
BUILD_CMD="python3 -m pip install --user build/hb && \
    hb set --product-name ${PRODUCT_NAME}@${VENDOR} && \
    hb build -f"

if [ "$GN_ONLY" = true ]; then
    BUILD_CMD="python3 -m pip install --user build/hb && \
        hb set --product-name ${PRODUCT_NAME}@${VENDOR} && \
        hb build --gn-only"
fi

# 执行构建
echo "开始构建: $PRODUCT_NAME@$VENDOR"
echo "Docker 镜像: $DOCKER_IMAGE"
echo ""

docker run --rm \
    -v "$(pwd):${WORKSPACE}" \
    -w "${WORKSPACE}" \
    "${DOCKER_IMAGE}" \
    bash -c "${BUILD_CMD}"

echo ""
echo "构建完成!"
if [ "$GN_ONLY" = false ]; then
    echo "产物位置: out/qemu-arm-linux/packages/phone/images/"
    ls -lh out/qemu-arm-linux/packages/phone/images/ 2>/dev/null | grep -E "Image|system|vendor|userdata|ramdisk" || true
    echo ""
    echo "--- Build Hash Check ---"
    sha256sum out/qemu-arm-linux/packages/phone/images/Image 2>/dev/null || echo "Image not found"
fi