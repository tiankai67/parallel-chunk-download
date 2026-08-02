# parallel-chunk-download

> 用并行分片突破「单连接限速」的下载技能 / A download skill that bypasses per-connection rate limiting via parallel chunked Range requests.

---

## 中文说明

### 这是什么

一些源站（小厂商自建服务器、无 CDN 的单机 nginx）会对**每个 TCP 连接**限速（典型 ~10 KB/s），但不限制你开多少条连接。于是普通单连接下载慢如牛，但开 N 条并行连接就能把带宽叠加起来（N × 单连接限速）。

本仓库把「切片 + 并行下载 + 合并 + 校验」封装成一个可复用技能，并附带两个脚本。

### 原理

1. 用 `curl -I` 读取 `Content-Length`，并确认服务端支持 `Accept-Ranges: bytes`。
2. 把文件按字节范围切成 N 片。
3. 用 `curl -r START-END` 并发拉取每一片，每片自带 `--speed-limit/--speed-time` 自我重试（僵死连接会被放弃并重连，不会整体挂死）。
4. 按序合并，并校验最终字节数 = `Content-Length`。

### 安装为 WorkBuddy 技能

```bash
# 把本仓库内容放到用户级技能目录即可（跨工作区可用）
git clone https://github.com/tiankai67/parallel-chunk-download.git
mkdir -p ~/.workbuddy/skills/parallel-chunk-download
cp -r parallel-chunk-download/* ~/.workbuddy/skills/parallel-chunk-download/
```

安装后，对 WorkBuddy 说「用 parallel-chunk-download 技能下载这个 <URL>」即可自动触发。

### 直接使用脚本

```bash
# 并行分片下载（默认 16 片）
bash scripts/parallel_download.sh "<URL>" [输出文件名] [分片数]

# 先探测：是否命中单连接限速（决定是否值得分片）
bash scripts/probe_speed.sh "<URL>"
```

- 服务端不支持 `Accept-Ranges` 时，下载脚本会自动退回单连接（带重试）。
- 并行吞吐未明显快于单连接 → 说明是「整 IP / 上行限速」，分片无效，应换 CDN / 镜像 / 迅雷 P2P。

### 目录结构

```
parallel-chunk-download/
├── SKILL.md                 # 技能定义（WorkBuddy 读取）
├── scripts/
│   ├── parallel_download.sh # 通用并行分片下载器
│   └── probe_speed.sh        # 单连接 vs 并行 速度探针
├── references/
│   └── diagnosis.md          # 限速类型诊断与调参说明
└── README.md
```

### 环境注意事项

- 部分 Windows Git Bash 沙箱缺少 `seq` / `tee` / `xxd`，且 `/tmp` 不存在；脚本已规避，临时分片写到当前目录。
- Windows Defender 会短暂锁定刚写入的文件，`rm` 可能报 `Device or resource busy`，忽略即可，不影响合并产物。

### 许可证

MIT

---

## English

### What is this

Some origin servers (small vendor hosts, single-machine nginx without a CDN) cap **each TCP connection** at a low speed (typically ~10 KB/s) but do not limit how many connections you open. A normal single-connection download therefore crawls, while opening N parallel connections aggregates the bandwidth (N × per-connection limit).

This repo packages the "slice + parallel download + merge + verify" workflow into a reusable skill, plus two standalone scripts.

### How it works

1. `curl -I` reads `Content-Length` and confirms the server supports `Accept-Ranges: bytes`.
2. The file is split into N equal byte ranges.
3. Each slice is fetched concurrently with `curl -r START-END`. Every slice self-retries via `--speed-limit/--speed-time` (a stalled connection is abandoned and reconnected, so the whole job never hangs).
4. Slices are concatenated in order and the final byte count is verified against `Content-Length`.

### Install as a WorkBuddy skill

```bash
git clone https://github.com/tiankai67/parallel-chunk-download.git
mkdir -p ~/.workbuddy/skills/parallel-chunk-download
cp -r parallel-chunk-download/* ~/.workbuddy/skills/parallel-chunk-download/
```

Once installed, tell WorkBuddy something like "use the parallel-chunk-download skill to download this <URL>" and it will trigger automatically.

### Use the scripts directly

```bash
# Parallel chunked download (16 chunks by default)
bash scripts/parallel_download.sh "<URL>" [output-name] [chunk-count]

# Probe first: is it per-connection throttling? (decides whether chunking helps)
bash scripts/probe_speed.sh "<URL>"
```

- If the server does not support `Accept-Ranges`, the downloader automatically falls back to a single retrying connection.
- If parallel throughput is not clearly faster than a single connection, the bottleneck is per-IP / upstream capacity — chunking will not help; use a CDN / mirror / P2P client instead.

### Directory layout

```
parallel-chunk-download/
├── SKILL.md                 # Skill definition (read by WorkBuddy)
├── scripts/
│   ├── parallel_download.sh # Generic parallel chunk downloader
│   └── probe_speed.sh        # Single-connection vs parallel speed probe
├── references/
│   └── diagnosis.md          # Throttling diagnosis and tuning notes
└── README.md
```

### Environment notes

- Some Windows Git Bash sandboxes lack `seq` / `tee` / `xxd` and have no `/tmp`; the scripts avoid these and write temp chunks to the current directory.
- Windows Defender may briefly lock freshly written files, so `rm` can print `Device or resource busy` — ignore it; it does not affect the merged output.

### License

MIT
