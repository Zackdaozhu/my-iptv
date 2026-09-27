# 我的 IPTV 直播列表（加密）

本仓库存放的是 **AES-256 加密后** 的直播列表，任何人都可以直接看到文件，但没有密钥无法解密使用。

## 文件说明

- `iptv.m3u.enc` — 加密后的直播列表（约 1000+ 可播放频道）
- `worker.js` — Cloudflare Worker 解密网关（配合使用）
- 解密/导入方法见下方

## 如何导入 APTV

1. 将 `worker.js` 部署到 Cloudflare Workers（免费）
2. 在 Worker 的「Variables and Secrets」里配置：
   - `ACCESS_KEY`：你的访问密钥
   - `PASSPHRASE`：加密口令
   - `ENC_URL`：本仓库 `iptv.m3u.enc` 的 raw 地址
3. APTV 里添加订阅，URL 填：
   ```
   https://你的worker.workers.dev/?key=你的ACCESS_KEY
   ```

> 具体步骤见仓库外的《部署说明》。

## 免责声明

直播源收集自公开网络，仅供个人学习使用，请勿商用。
