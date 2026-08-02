#!/usr/bin/env bash
# probe_speed.sh — 判定下载慢是否由「单连接限速」引起
#
# 用法: bash probe_speed.sh "<URL>"
#
# 做法:
#   1) 单连接 12 秒限时下载, 测实际吞吐。
#   2) 6 路并行 10 秒限时下载(各取不同 1MB 区间), 测聚合吞吐。
#
# 判读:
#   - 单连接很慢(如 ~10KB/s) 且 并行明显更快(如 ~×N) => 单连接限速,
#     用 parallel_download.sh 分片并行下载可大幅提速。
#   - 单连接慢 且 并行也差不多(总吞吐没涨) => 整 IP/上行被限,
#     分片无效, 应换 CDN/镜像/其他网络。

set -u
URL="${1:?用法: probe_speed.sh <URL>}"

echo "=== 1) 单连接 12 秒限时 ==="
single=$(curl -s -r 0-20971519 --max-time 12 -o probe_single.bin -w '%{size_download}' "$URL" 2>/dev/null)
rm -f probe_single.bin 2>/dev/null
single="${single:-0}"
echo "单连接 12s 下载: ${single} 字节  (~$(( single / 12 )) 字节/s)"

echo "=== 2) 6 路并行 10 秒限时 ==="
pids=()
for i in 1 2 3 4 5 6; do
  s=$(( (i-1) * 1000000 )); e=$(( i * 1000000 - 1 ))
  curl -s -r ${s}-${e} -o "probe_$i.bin" --max-time 10 "$URL" &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done

total=0
for i in 1 2 3 4 5 6; do
  sz=$(wc -c < "probe_$i.bin" 2>/dev/null || echo 0)
  total=$(( total + sz ))
done
rm -f probe_*.bin 2>/dev/null
echo "6 路并行 10s 下载: ${total} 字节  (~$(( total / 10 )) 字节/s)"

single_bps=$(( single / 12 ))
para_bps=$(( total / 10 ))
if [ "$para_bps" -gt $(( single_bps * 2 )) ]; then
  echo "结论: 命中单连接限速 -> 用 parallel_download.sh 分片并行下载可显著提速"
else
  echo "结论: 并行未明显提速 -> 疑似整 IP/上行限速, 分片无效, 建议换 CDN/镜像"
fi
