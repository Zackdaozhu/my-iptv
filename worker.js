/**
 * IPTV 加密订阅网关 (Cloudflare Worker)
 *
 * 作用：只有 URL 携带正确密钥时才返回解密后的直播列表。
 *
 * 需要配置 3 个环境变量（在 Cloudflare 控制台 -> Worker -> Settings -> Variables and Secrets）：
 *   ACCESS_KEY  访问密钥（用户自定，会放进 APTV 的 URL 里，如 ?key=xxx）
 *   PASSPHRASE  加密口令（加密 iptv.m3u 时用的口令）
 *   ENC_URL     加密文件的地址，例如：
 *               https://raw.githubusercontent.com/<你>/<仓库>/main/iptv.m3u.enc
 *
 * 部署后 APTV 里填：
 *   https://<你的worker>.workers.dev/?key=你的ACCESS_KEY
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1) 校验访问密钥
    const key = url.searchParams.get("key") || "";
    if (key !== env.ACCESS_KEY) {
      return new Response("Forbidden", { status: 403 });
    }

    // 2) 命中缓存直接返回（缓存键含 ?key=，只有持密钥者能命中）
    const cache = caches.default;
    const cached = await cache.match(request);
    if (cached) return cached;

    // 3) 拉取加密文件
    const resp = await fetch(env.ENC_URL);
    if (!resp.ok) return new Response("upstream fetch failed", { status: 502 });
    const buf = new Uint8Array(await resp.arrayBuffer());

    // 4) 校验 openssl "Salted__" 格式
    if (buf.length < 32 || new TextDecoder().decode(buf.slice(0, 8)) !== "Salted__") {
      return new Response("bad encrypted file", { status: 502 });
    }
    const salt = buf.slice(8, 16); // openssl 盐为 8 字节
    const ct = buf.slice(16);      // 之后是密文

    // 5) 用与加密时一致的参数派生密钥 (PBKDF2-HMAC-SHA256, 10000 次)
    const enc = new TextEncoder();
    const baseKey = await crypto.subtle.importKey(
      "raw", enc.encode(env.PASSPHRASE), "PBKDF2", false, ["deriveBits"]
    );
    const bits = await crypto.subtle.deriveBits(
      { name: "PBKDF2", salt, iterations: 10000, hash: "SHA-256" },
      baseKey, 384
    );
    const dk = new Uint8Array(bits);
    const aesKey = await crypto.subtle.importKey(
      "raw", dk.slice(0, 32), "AES-CBC", false, ["decrypt"]
    );
    const iv = dk.slice(32, 48);

    // 6) 解密
    const pt = await crypto.subtle.decrypt({ name: "AES-CBC", iv }, aesKey, ct);

    // 7) 返回明文 M3U
    const out = new Response(pt, {
      headers: {
        "content-type": "audio/x-mpegurl; charset=utf-8",
        "cache-control": "public, max-age=300",
      },
    });
    await cache.put(request, out.clone());
    return out;
  },
};
