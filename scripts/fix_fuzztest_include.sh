#!/bin/bash
# 修复 access_token fuzztest include 路径问题
# 用法: ./fix_fuzztest_include.sh

set -e

ACCESS_TOKEN_PATH="base/security/access_token"
FUZZTEST_DIR="${ACCESS_TOKEN_PATH}/test/fuzztest/access_token_stub"
MISSING_PATH="interfaces/innerkits/accesstoken/src"

echo "检查并修复 fuzztest BUILD.gn 文件..."

if [ ! -d "$FUZZTEST_DIR" ]; then
    echo "错误: 目录不存在: $FUZZTEST_DIR"
    exit 1
fi

FIXED=0
SKIPPED=0

for dir in "$FUZZTEST_DIR"/*/; do
    if [ ! -d "$dir" ]; then
        continue
    fi

    BUILD_GN="$dir/BUILD.gn"
    if [ ! -f "$BUILD_GN" ]; then
        continue
    fi

    # 检查是否已包含缺失路径
    if grep -q "$MISSING_PATH" "$BUILD_GN" 2>/dev/null; then
        echo "  [跳过] $(basename "$dir") - 已包含"
        ((SKIPPED++))
        continue
    fi

    # 添加缺失的 include 路径
    if grep -q "include_dirs = \[" "$BUILD_GN" 2>/dev/null; then
        sed -i "/include_dirs = \[/a\\    \"\${access_token_path}/${MISSING_PATH}\"," "$BUILD_GN"
        echo "  [修复] $(basename "$dir")"
        ((FIXED++))
    else
        echo "  [警告] $(basename "$dir") - 未找到 include_dirs"
    fi
done

echo ""
echo "修复完成: $FIXED 个文件已修复, $SKIPPED 个文件已跳过"
