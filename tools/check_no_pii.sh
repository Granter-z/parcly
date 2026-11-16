#!/usr/bin/env bash
# 提交前检查：公开仓库中不得出现真实手机号、真实形态运单号、真实形态取件码。
# 默认扫描 test/、docs/、lib/ 以及根目录 README.md、CLAUDE.md。
# 已 gitignore 的真实样本目录、以及 tools/pii_check_fixtures/ 不在默认范围。
# 命中时只打印「路径:行号  规则」，不输出原文。
# 放行仅限 tools/pii_allowlist.txt 精确登记，或严格演示形态
# （全同数字、长零填充、整段连续、极短取件占位）。
# 用法：
#   bash tools/check_no_pii.sh
#   bash tools/check_no_pii.sh path/to/dir
set -euo pipefail
cd "$(dirname "$0")/.."
exec python3 tools/check_no_pii.py "$@"
