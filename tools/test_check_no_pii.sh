#!/usr/bin/env bash
# 门禁脚本的正反例：放行既有演示与严格合成形态，拦截真实形态和过宽启发式边界，
# 且输出不含命中原文。
set -euo pipefail
cd "$(dirname "$0")/.."

pass_log="$(mktemp)"
fail_log="$(mktemp)"
trap 'rm -f "$pass_log" "$fail_log"' EXIT

if ! python3 tools/check_no_pii.py tools/pii_check_fixtures/pass >"$pass_log" 2>&1; then
  echo "FAIL：合成样例夹具不应被拦截"
  cat "$pass_log"
  exit 1
fi
if ! grep -q '^OK' "$pass_log"; then
  echo "FAIL：正例未输出通过说明"
  cat "$pass_log"
  exit 1
fi

set +e
python3 tools/check_no_pii.py tools/pii_check_fixtures/fail >"$fail_log" 2>&1
fail_status=$?
set -e
if [ "$fail_status" -eq 0 ]; then
  echo "FAIL：真实形态夹具应当被拦截"
  cat "$fail_log"
  exit 1
fi

for required in \
  "waybill" \
  "pickup_code" \
  "phone" \
  "real_shaped.dart" \
  "real_shaped_adjacent.dart" \
  "docs_hit.md" \
  "heuristic_too_loose.dart" \
  "p2_shapes.dart"
do
  if ! grep -q "$required" "$fail_log"; then
    echo "FAIL：反例输出缺少 $required"
    cat "$fail_log"
    exit 1
  fi
done

# P1-A / P2 文件都应出现对应规则（同一文件可有多条规则）
if ! grep -E 'heuristic_too_loose\.dart:[0-9]+  pickup_code$' "$fail_log" | grep -q .; then
  echo "FAIL：低熵短码反例未被标为 pickup_code"
  exit 1
fi
if ! grep -E 'heuristic_too_loose\.dart:[0-9]+  waybill$' "$fail_log" | grep -q .; then
  echo "FAIL：过宽运单反例未被标为 waybill"
  exit 1
fi
if ! grep -E 'p2_shapes\.dart:[0-9]+  phone$' "$fail_log" | grep -q .; then
  echo "FAIL：点分手机号反例未被标为 phone"
  exit 1
fi
if ! grep -E 'p2_shapes\.dart:[0-9]+  waybill$' "$fail_log" | grep -q .; then
  echo "FAIL：带分隔运单或 JD 前缀反例未被标为 waybill"
  exit 1
fi
# P1：中文紧贴运单/取件码时必须命中（Unicode \b 会漏）
if ! grep -E 'real_shaped_adjacent\.dart:[0-9]+  waybill$' "$fail_log" | grep -q .; then
  echo "FAIL：中文紧贴运单反例未被标为 waybill"
  exit 1
fi
if ! grep -E 'real_shaped_adjacent\.dart:[0-9]+  pickup_code$' "$fail_log" | grep -q .; then
  echo "FAIL：中文紧贴取件码反例未被标为 pickup_code"
  exit 1
fi

# 输出不得包含夹具里的真实形态原文（含审查用虚构边界样例）
leaked=0
for secret in \
  JT4729183057264 \
  7-4-3185 \
  13924681357 \
  YD3817264590231 \
  8-6-2471 \
  12-1-1121 \
  10-1-1001 \
  JT8801234567890 \
  JT1121212112121 \
  139.2468.1357 \
  YT-4729183057264 \
  JD3817264590231 \
  3-5-6036
do
  if grep -Fq "$secret" "$fail_log"; then
    echo "FAIL：输出泄漏了夹具标记"
    leaked=1
  fi
done
# 也不应把整行原文打出来（例如 const tracking = ...）
if grep -Eq "const tracking|pickupCode =|pickupLowUniq|waybillLocal|dottedPhone|hyphenWaybill" "$fail_log"; then
  echo "FAIL：输出包含命中行原文"
  leaked=1
fi
if [ "$leaked" -ne 0 ]; then
  echo "---- redacted rules ----"
  grep -E ':[0-9]+  (phone|waybill|pickup_code)$|^PII check failed$' "$fail_log" || true
  exit 1
fi

echo "OK：门禁正反例通过，输出不含命中原文"
