# 个人英文直播精选列表

这个仓库保存加密后的 APTV M3U 列表。频道以公开英文新闻、纪录片和生活节目为主，另保留少数中文频道。播放地址来自公开列表，每次更新会检查 HLS 播放清单和媒体片段；地区限制和节目版权仍以频道方规定为准。

## 文件

- `iptv.m3u.enc`：供现有 Cloudflare Worker 解密的列表；仓库不保存访问密钥或加密口令。
- `更新直播源.command`：在原 Mac 上双击即可重新筛选、检查、加密并推送；编辑脚本中的 `rules` 可增删关注的频道。
- `worker.js`：现有 APTV 订阅网关代码。

脚本在本机生成 `/Users/admin/iptv/output/iptv_zh_en.m3u`，供更新前检查。只想检查可运行 `./更新直播源.command --dry-run`；只更新本地列表可加 `--no-push`。正常运行时，仅在列表有变化且通过数量足够时，更新加密文件并推送到 GitHub。APTV 使用本机 `secrets.local.txt` 中的 `ACCESS_KEY` 时，原 Worker 订阅地址不需要更换。

原有较大的加密列表已在本机备份为 `/Users/admin/iptv/output/iptv_before_english_curated.m3u.enc`，也可以从 Git 历史恢复。
