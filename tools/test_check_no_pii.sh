#!/usr/bin/env bash
# 门禁脚本的正反例：放行可辨识合成样例，拦截真实形态，且输出不含命中原文。
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

for required in "waybill" "pickup_code" "phone" "real_shaped.dart" "docs_hit.md"; do
  if ! grep -q "$required" "$fail_log"; then
    echo "FAIL：反例输出缺少 $required"
    cat "$fail_log"
    exit 1
  fi
done

# 输出不得包含夹具里的真实形态原文
leaked=0
for secret in JT4729183057264 7-4-3185 13924681357 YD3817264590231 8-6-2471; do
  if grep -Fq "$secret" "$fail_log"; then
    echo "FAIL：输出泄漏了夹具标记"
    leaked=1
  fi
done
# 也不应把整行原文打出来（例如 const tracking = ...）
if grep -Eq "const tracking|pickupCode =" "$fail_log"; then
  echo "FAIL：输出包含命中行原文"
  leaked=1
fi
if [ "$leaked" -ne 0 ]; then
  # 只展示规则行，避免复述标记
  echo "---- redacted rules ----"
  grep -E ':[0-9]+  (phone|waybill|pickup_code)$|^PII check failed$' "$fail_log" || true
  exit 1
fi

echo "OK：门禁正反例通过，输出不含命中原文"
