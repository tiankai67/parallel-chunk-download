---
name: parallel-chunk-download
description: "Download files from servers that throttle per-connection speed by splitting the file into chunks and fetching them in parallel with curl HTTP Range requests, then merging and verifying. Use when a user reports a direct download being extremely slow, stalling at a few KB/s, or needs to fetch a large file from a rate-limited, single-origin, or no-CDN server that supports byte-range requests."
agent_created: true
---

# Parallel Chunk Download

## Overview

Some origin servers (small vendor hosts, no-CDN single machines) cap **each TCP
connection** at a low speed (e.g. ~10 KB/s) instead of capping total per-IP
bandwidth. A normal single-connection download therefore crawls, but opening
many connections in parallel aggregates the bandwidth (N connections × per-conn
limit). This skill diagnoses that situation and downloads the file by slicing
it into byte ranges, fetching the slices concurrently with `curl -r`, then
merging and verifying.

## When to use

Trigger this skill when the user says things like:

- "这个下载怎么这么慢 / 网速非常慢"
- "直接下只有几 KB/s"
- "帮我快速下载这个文件 / 把这个安装包下下来"
- Any large-file download that stalls while the user's own network is fine.

Do **not** use it for: normal-speed downloads, or servers that already return
the full file fast. It adds overhead and many parallel connections, so only
apply it when a real bottleneck is confirmed.

## Workflow

### Step 1 — Confirm the bottleneck is per-connection rate limiting

Run a single-connection timed fetch and a short parallel probe. The decisive
signal: a single connection is very slow, but several parallel connections are
much faster (aggregated). Use `scripts/probe_speed.sh <URL>`.

- Single connection slow (~10 KB/s) **and** parallel probe fast (~×N) ⇒
  per-connection limit ⇒ this skill works.
- Single connection slow **and** parallel also slow (same total) ⇒ per-IP or
  upstream cap ⇒ parallel chunks will NOT help; advise the user to use a CDN /
  mirror / download manager with a different network instead.

Server must support `Accept-Ranges: bytes` (check via `curl -sI`). If it does
not, parallel chunking is impossible and the skill falls back to a plain
retrying download automatically.

### Step 2 — Download in parallel chunks

Run the bundled downloader:

```bash
bash scripts/parallel_download.sh "<URL>" [输出文件名] [分片数]
```

Defaults: output name = basename of URL, chunk count = 16. Use more chunks
(e.g. 24–32) when the per-connection limit is very low. The script:

1. `curl -sI` to read `Content-Length` and confirm `Accept-Ranges: bytes`.
2. Splits the file into N equal byte ranges.
3. Spawns N background `curl -r START-END` jobs. Each job self-retries on
   stalls via `--speed-limit 4000 --speed-time 8` (abort a connection that
   drops below 4 KB/s for 8 s, then retry up to 10×).
4. Concatenates the chunks in order and verifies the final byte count equals
   `Content-Length`. A mismatch ⇒ the file is corrupt; re-run or lower chunk
   count.

### Step 3 — Verify integrity

After download, confirm the file is valid:

```bash
python -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1]); print('OK' if z.testzip() is None else 'CORRUPT')" <file>
```

(adjust for the file type). The downloader already checks byte count; this
catches truncated merges.

## Environment gotchas (learned the hard way)

The bundled script already avoids these, but note them when adapting:

- **No `seq`/`tee`/`xxd`** in some Windows-Git-Bash sandboxes. Use C-style
  `for ((i=0;i<N;i++))` loops and `echo` instead of `tee`.
- **`/tmp` may not exist** there — write temp chunk files to the current
  working directory, not `/tmp`.
- **Windows Defender locks freshly written files** briefly; `rm -f part_*`
  may print "Device or resource busy". Ignore it (`2>/dev/null`); it does not
  affect the merged output.
- **A stalled single connection does not time out on its own** unless the
  whole transfer exceeds `--max-time`. Always pair long downloads with
  `--speed-limit`/`--speed-time` so a hung connection is detected and retried
  quickly.

## Resources

- `scripts/parallel_download.sh` — the reusable parallel chunk downloader.
- `scripts/probe_speed.sh` — single-vs-parallel speed probe to confirm the
  per-connection limit before committing to a full download.
- `references/diagnosis.md` — deeper notes on how to read the probe numbers
  and decide whether parallelization will help.
