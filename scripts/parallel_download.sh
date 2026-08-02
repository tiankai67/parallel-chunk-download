#!/usr/bin/env bash
# parallel_download.sh — 用并行分片突破「单连接限速」的下载器
#
# 原理: 部分源站对每个 TCP 连接限速(如 ~10KB/s),但不限制总带宽。
#       把文件按字节范围切成 N 片, 用 curl -r 并发拉取, 再合并, 即可把
#       N 条连接的带宽叠加起来。
#
# 用法:
#   bash parallel_download.sh "<URL>" [输出文件名] [分片数]
#
# 依赖: bash, curl(支持 -r / --speed-limit), wc, cat
# 说明:
#   - 自动从 HTTP 头读取 Content-Length, 并确认 Accept-Ranges: bytes。
#   - 不支持 Range 时自动退回单连接下载(带重试)。
#   - 每片下载带 --speed-limit/--speed-time, 僵死连接会被放弃并重试, 不会挂死。
#   - 合并后用字节数校验; 不一致则报错退出(文件可能损坏)。

set -u

URL="${1:?用法: parallel_download.sh <URL> [输出文件名] [分片数]}"
OUT="${2:-$(basename "$URL")}"
N="${3:-16}"

# ---- 探测: 文件大小 + Range 支持 ----
HEAD=$(curl -sI --max-time 30 "$URL")
LEN=$(printf '%s\n' "$HEAD" | tr -d '\r' | awk -F': ' 'tolower($1)=="content-length"{print $2; exit}')
RANGES=$(printf '%s\n' "$HEAD" | tr -d '\r' | awk -F': ' 'tolower($1)=="accept-ranges"{print tolower($2); exit}')

if [ -z "$LEN" ]; then
  echo "无法获取 Content-Length, 服务器可能不支持。改用单连接下载。" >&2
  curl -L --retry 5 --retry-delay 2 -o "$OUT" "$URL"
  exit $?
fi

if [ "$RANGES" != "bytes" ]; then
  echo "警告: 服务器不支持 Accept-Ranges(bytes), 无法分片, 退回单连接下载。" >&2
  curl -L --retry 5 --retry-delay 2 -o "$OUT" "$URL"
  exit $?
fi

TOTAL=$LEN
CHUNK=$(( (TOTAL + N - 1) / N ))

rm -f part_* "$OUT" 2>/dev/null

pids=()
for ((i=0; i<N; i++)); do
  start=$(( i * CHUNK ))
  if [ "$i" -eq $((N-1)) ]; then
    end=$((TOTAL-1))
  else
    end=$(( (i+1)*CHUNK - 1 ))
  fi
  need=$(( end - start + 1 ))
  name=$(printf "part_%03d" "$i")
  (
    for ((t=1; t<=10; t++)); do
      curl -s --speed-limit 4000 --speed-time 8 \
           --retry 4 --retry-delay 1 --retry-all-errors \
           --connect-timeout 20 --max-time 120 \
           -r "${start}-${end}" -o "$name" "$URL"
      sz=$(wc -c < "$name")
      if [ "$sz" -eq "$need" ]; then break; fi
    done
    sz=$(wc -c < "$name")
    if [ "$sz" -ne "$need" ]; then
      echo "CHUNK_FAIL $name got=$sz need=$need" >&2
    fi
  ) &
  pids+=($!)
done

echo "已派发 $N 个分片并行下载, 等待完成..."
for p in "${pids[@]}"; do wait "$p"; done

echo "=== 合并 $N 片 ==="
: > "$OUT"
for ((j=0; j<N; j++)); do
  cat "$(printf "part_%03d" "$j")" >> "$OUT"
done
fsz=$(wc -c < "$OUT")
rm -f part_* 2>/dev/null   # Windows Defender 偶发锁文件, 忽略报错

echo "最终大小: $fsz / 期望: $TOTAL"
if [ "$fsz" -eq "$TOTAL" ]; then
  echo "OK: 下载完整 ($OUT)"
  file "$OUT" 2>/dev/null
  exit 0
else
  echo "FAIL: 大小不符, 文件可能损坏, 请重下或减小分片数" >&2
  exit 1
fi
