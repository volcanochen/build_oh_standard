#!/bin/bash

# OpenHarmony QEMU ARM64 构建脚本
# 适用于 OpenHarmony 标准系统
# 用法: ./build_qemu.sh [--gn-only] [--clean]

set -e

PRODUCT_NAME="qemu-arm64-linux-min"
VENDOR="ohemu"
DOCKER_IMAGE="swr.cn-south-1.myhuaweicloud.com/openharmony-docker/docker_oh_standard:3.2"
WORKSPACE="/workspace"

echo "=== OpenHarmony QEMU ARM64 构建脚本 ==="
echo "产品: ${PRODUCT_NAME}@${VENDOR}"
echo "镜像: ${DOCKER_IMAGE}"
echo ""

if [ ! -f ".repo/manifests/default.xml" ]; then
    echo "错误: 请在 OpenHarmony 源码根目录运行此脚本"
    exit 1
fi

if ! command -v docker &> /dev/null; then
    echo "错误: 未安装 Docker，请先安装 Docker"
    exit 1
fi

GN_ONLY=false
CLEAN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --gn-only)
            GN_ONLY=true
            ;;
        --clean)
            CLEAN=true
            ;;
        *)
            echo "未知参数: $1"
            echo "用法: $0 [--gn-only] [--clean]"
            exit 1
            ;;
    esac
    shift
done

echo "1. 拉取 Docker 镜像..."
docker pull "${DOCKER_IMAGE}"

if [ "$CLEAN" = true ]; then
    echo "2. 清理构建产物..."
    docker run --rm -v "$(pwd):${WORKSPACE}" -w "${WORKSPACE}" \
        "${DOCKER_IMAGE}" \
        bash -c "rm -rf ${WORKSPACE}/out ${WORKSPACE}/build/resources/args/*.json"
fi

echo "3. 复制 Rust 标准库..."
docker run --rm -v "$(pwd):${WORKSPACE}" -w "${WORKSPACE}" \
    "${DOCKER_IMAGE}" \
    bash -c "cp ${WORKSPACE}/prebuilts/rustc/linux-x86_64/current/lib/libstd*.so /usr/lib/ 2>/dev/null || true"

if [ "$GN_ONLY" = true ]; then
    echo "4. 验证 GN 依赖..."
    BUILD_COMMAND="hb build --gn-only"
else
    echo "4. 执行完整构建..."
    BUILD_COMMAND="hb build -f --load-test-config false"
fi

docker run --rm -v "$(pwd):${WORKSPACE}" -w "${WORKSPACE}" \
    "${DOCKER_IMAGE}" \
    bash -c "
        python3 -m pip install --user build/hb > /dev/null 2>&1 && \
        export PATH=/root/.local/bin:\$PATH && \
        hb set --product-name ${PRODUCT_NAME}@${VENDOR} && \
        ${BUILD_COMMAND}
    "

if [ "$GN_ONLY" = false ]; then
    echo ""
    echo "5. 检查构建结果..."
    if [ -f "out/qemu-arm-linux/packages/phone/images/Image" ]; then
        echo "✅ 构建成功!"
        ls -lh out/qemu-arm-linux/packages/phone/images/
    else
        echo "❌ 构建失败!"
        if [ -f "out/qemu-arm-linux/build.log" ]; then
            echo "最后几行构建日志:"
            tail -50 out/qemu-arm-linux/build.log
        fi
    fi
fi

echo ""
echo "=== 构建完成 ==="