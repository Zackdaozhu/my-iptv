#!/bin/bash
# 双击运行后更新本地列表，并通过现有加密仓库发布；可加 --dry-run、--no-push。
set -u
ROOT="${IPTV_HOME:-/Users/admin/iptv}"
mkdir -p "$ROOT/output" "$ROOT/logs"
cd "$ROOT" || exit 1
export IPTV_HOME="$ROOT"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
# 保留可用代理；旧定时任务强制设置的 7890 若未运行则改为直连。
if [ "${HTTPS_PROXY:-${https_proxy:-}}" = "http://127.0.0.1:7890" ] && ! /usr/bin/nc -z 127.0.0.1 7890 2>/dev/null; then
  unset HTTPS_PROXY HTTP_PROXY https_proxy http_proxy
fi
if [ -z "${HTTPS_PROXY:-}" ] && [ -z "${https_proxy:-}" ] && /usr/bin/nc -z 127.0.0.1 7890 2>/dev/null; then
  export HTTPS_PROXY="http://127.0.0.1:7890" HTTP_PROXY="http://127.0.0.1:7890"
fi
/usr/bin/caffeinate -i /usr/bin/python3 - "$@" <<'PY'
import argparse, concurrent.futures, hashlib, html, ipaddress, os, re, shutil, subprocess, sys, time
import urllib.request, urllib.parse
from pathlib import Path
from datetime import datetime

root = Path(os.environ['IPTV_HOME'])
out = root / 'output' / 'iptv_zh_en.m3u'
legacy_out = root / 'output' / 'iptv_english_hk.m3u'
report = root / 'logs' / 'zh_en_latest.txt'
feeds = [
 'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_usa.m3u8',
 'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlists/playlist_india.m3u8',
 'https://raw.githubusercontent.com/wizakorhd/iptv/main/playlist-english-india.m3u',
 'https://raw.githubusercontent.com/wizakorhd/iptv/main/playlist-english-intl.m3u',
 'https://iptv-org.github.io/iptv/countries/in.m3u',
 'https://iptv-org.github.io/iptv/countries/ru.m3u',
 'https://iptv-org.github.io/iptv/countries/ua.m3u',
 'https://iptv-org.github.io/iptv/languages/eng.m3u',
 'https://iptv-org.github.io/iptv/countries/hk.m3u',
 'https://iptv-org.github.io/iptv/countries/cn.m3u',
 'https://raw.githubusercontent.com/mymsnn/DailyIPTV/main/outputs/cctv.m3u',
 'https://raw.githubusercontent.com/mymsnn/DailyIPTV/main/outputs/satellite.m3u',
]
# 只保留常看的中文主流频道与英文新闻；改此处即可增删频道。
# CNN International、TVB 等订阅或访问控制频道不会进入结果。
rules = [
 ('CNN-News18', 'English | India', r'^(?:CNN[ -]?News18|News18 English)$'),
 ('CNA', 'English | Asia', r'^(?:CNA|Channel News Asia|CNA International)$'),
 ('NDTV Profit', 'English | India', r'^NDTV Profit$'),
 ('DD India', 'English | India', r'^DD India$'),
 ('India Today', 'English | India', r'^India Today$'),
 ('BT TV', 'English | India', r'^(?:BT TV|Business Today TV)$'),
 ('CNBC TV18', 'English | India', r'^CNBC[ -]?TV18$'),
 ('News9Live', 'English | India', r'^News\s?9\s?Live$'),
 ('Mirror Now', 'English | India', r'^Mirror Now$'),
 ('NewsX', 'English | India', r'^NewsX$'),
 ('TV BRICS English', 'English | Russia/BRICS', r'^TV BRICS English$'),
 ('RT Documentary English', 'English | Russia', r'^RT Documentary English$'),
 ('INWILD', 'English | Documentary', r'^INWILD$'),
 ('INWONDER', 'English | Documentary', r'^INWONDER$'),
 ('INFAST', 'English | Documentary', r'^INFAST$'),
 ('Al Jazeera English', 'English | World News', r'^Al Jazeera English$'),
 ('France 24 English', 'English | World News', r'^France 24 English$'),
 ('DW English', 'English | World News', r'^DW English$'),
 ('Africanews English', 'English | World News', r'^Africanews English$'),
 ('NHK World-Japan', 'English | Asia', r'^NHK World-Japan$'),
 ('Arirang TV', 'English | Asia', r'^Arirang TV$'),
 ('TRT World', 'English | World News', r'^TRT World$'),
 ('WION', 'English | India', r'^WION$'),
 ('Bloomberg Originals', 'English | Documentary', r'^Bloomberg Originals$'),
 ('INTRAVEL', 'English | Documentary', r'^INTRAVEL$'),
 ('WildEarth', 'English | Documentary', r'^WildEarth$'),
 ('Documentary+', 'English | Documentary', r'^Documentary\+$'),
 ('Autentic History', 'English | Documentary', r'^Autentic History$'),
 ('Autentic Travel', 'English | Documentary', r'^Autentic Travel$'),
 ('Tastemade', 'English | Lifestyle', r'^Tastemade$'),
 ('This Old House', 'English | Lifestyle', r'^This Old House$'),
 ('FailArmy', 'English | Entertainment', r'^FailArmy$'),
 ('Bloomberg', 'English | US', r'^(?:Bloomberg(?: TV| Television| TV\+)?)(?: US)?$'),
 ('ABC News Live', 'English | US', r'^ABC News(?: Live)?$'),
 ('CBS News', 'English | US', r'^CBS News(?: 24/7)?$'),
 ('NBC News NOW', 'English | US', r'^NBC News(?: NOW)?$'),
 ('Reuters', 'English | US', r'^Reuters(?: TV| Now)?$'),
 ('CGTN English', 'English | China', r'^(?:CGTN|CGTN英语|CGTN English)$'),
]
for number in (31, 32, 33, 34, 35):
 rules.append((f'RTHK {number}', 'Hong Kong | RTHK', rf'^(?:RTHK|港台电视|港台電視|港台)\s*(?:TV)?\s*{number}$'))
for number in (1, 2, 4, 5, 6, 8, 10, 13):
 rules.append((f'CCTV-{number}', '中文 | 央视', rf'^(?:CCTV|央视|中央电视台)[- ]?{number}(?:\s*(?:HD|高清|超清|4K))?$'))
rules += [
 ('湖南卫视', '中文 | 卫视', r'^(?:湖南卫视|芒果卫视)$'),
 ('浙江卫视', '中文 | 卫视', r'^浙江卫视$'),
 ('江苏卫视', '中文 | 卫视', r'^江苏卫视$'),
 ('东方卫视', '中文 | 卫视', r'^(?:东方卫视|上海东方卫视)$'),
 ('北京卫视', '中文 | 卫视', r'^北京卫视$'),
 ('广东卫视', '中文 | 卫视', r'^广东卫视$'),
]

ap = argparse.ArgumentParser(description='生成中文主流频道和英文新闻的 APTV 精选列表')
ap.add_argument('--dry-run', action='store_true', help='只检查，不写文件')
ap.add_argument('--no-push', action='store_true', help='只更新本地文件，不加密推送 GitHub')
ap.add_argument('--timeout', type=float, default=8)
ap.add_argument('--workers', type=int, default=12)
ap.add_argument('--max-per-channel', type=int, default=5)
a = ap.parse_args()
headers = {'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120 Safari/537.36'}

def get(url, limit=1024*1024):
 request_headers=dict(headers)
 if limit<=2048: request_headers['Range']='bytes=0-2047'
 req = urllib.request.Request(url, headers=request_headers)
 with urllib.request.urlopen(req, timeout=a.timeout) as res:
  code = res.status
  body = res.read(limit)
  return code, body, res.geturl(), res.headers.get('Content-Type','')

def parse_m3u(data, source):
 result=[]; attrs={}; name=None
 for line in data.decode('utf-8','replace').splitlines():
  line=line.strip()
  if line.startswith('#EXTINF:'):
   name=line.split(',',1)[-1].strip()
   attrs=dict(re.findall(r'([\w-]+)="([^"]*)"',line))
  elif line and not line.startswith('#') and name is not None:
   result.append({'name':attrs.get('tvg-name') or name,'url':line,'id':attrs.get('tvg-id',''), 'logo':attrs.get('tvg-logo',''), 'source':source})
   name=None
 return result

def parse_file(path):
 try:
  return parse_m3u(path.read_bytes(),str(path)) if path.exists() else []
 except OSError:
  return []

def match(e):
 name=re.sub(r'\s*\[[^]]*\]\s*$','',e['name']).strip()
 name=re.sub(r'\s*\([^)]*(?:\d+p|HD|SD)[^)]*\)\s*$','',name,flags=re.I).strip()
 for canonical, group, pattern in rules:
  if re.fullmatch(pattern,name,re.I): return canonical,group
 return None

def allowed_url(url, canonical):
 p=urllib.parse.urlsplit(url)
 if p.scheme not in ('http','https') or not p.hostname or p.username or p.password: return False
 host=p.hostname.lower()
 if host in ('localhost','127.0.0.1') or host.endswith(('.local','.lan')): return False
 try:
  if not ipaddress.ip_address(host).is_global: return False
 except ValueError: pass
 def under(*domains):
  return any(host==d or host.endswith('.'+d) for d in domains)
 if re.search(r'(?:token|key|auth|signature|session|play_token|password)=',p.query,re.I): return False
 trusted_english={
  'CNN-News18':('jio.com','akamaized.net'),
  'CNA':('mediacorp.sg','mediacorp.com.sg','d2e1asnsl7br7b.cloudfront.net'),
  'NDTV Profit':('ndtvprofit.akamaized.net',),
  'DD India':('smartplaytv.in','nic.in'),
  'India Today':('intoday.in','d1rc86nwwc9fag.cloudfront.net'),
  'BT TV':('intoday.in',),
  'CNBC TV18':('n18syndication.akamaized.net',),
  'News9Live':('amagi.tv',),
  'Mirror Now':('dai.google.com',),
  'NewsX':('tangotv.in','smartplaytv.in'),
  'TV BRICS English':('tvbrics.com','bonus-tv.ru','mediacdn.ru'),
  'RT Documentary English':('rttv.com',),
  'INWILD':('amagi.tv',),
  'INWONDER':('amagi.tv',),
  'INFAST':('amagi.tv',),
  'Al Jazeera English':('getaj.net',),
  'France 24 English':('france24.com',),
  'DW English':('amagi.tv',),
  'Africanews English':('cdn-euronews.akamaized.net',),
  'NHK World-Japan':('nhkworld.jp',),
  'Arirang TV':('edgesuite.net',),
  'TRT World':('smartplaytv.in',),
  'WION':('vg-zeefta.akamaized.net',),
  'Bloomberg Originals':('bloomberg.com',),
  'INTRAVEL':('amagi.tv',),
  'WildEarth':('dqga3jatxofgx.cloudfront.net',),
  'Documentary+':('mediatailor.us-west-2.amazonaws.com',),
  'Autentic History':('mediatailor.us-east-1.amazonaws.com',),
  'Autentic Travel':('mediatailor.us-east-1.amazonaws.com',),
  'Tastemade':('amagi.tv',),
  'This Old House':('wurl.tv',),
  'FailArmy':('wurl.tv',),
  'Bloomberg':('bloomberg.com',),
  'ABC News Live':('abcnews-streams.akamaized.net',),
  'CBS News':('cbsnews.akamaized.net',),
  'NBC News NOW':('d1bl6tskrpq9ze.cloudfront.net',),
  'Reuters':('amagi.tv','wurl.tv'),
 }
 if canonical in trusted_english and not under(*trusted_english[canonical]): return False
 if canonical.startswith('RTHK') and not (host.endswith('.rthk.hk') or host=='rthk.hk' or host.endswith('.rthk.org.hk') or re.fullmatch(r'rthktv(?:31|32|33|34|35)-live\.akamaized\.net',host)): return False
 if canonical=='湖南卫视' and len(p.path)>180: return False
 if canonical.startswith('CCTV-') and not under('cctv.cn','cctv.com','cntv.cn','yangshipin.cn'): return False
 official_chinese={
  '湖南卫视':('hunantv.com','mgtv.com'),
  '浙江卫视':('cztv.com',),
  '江苏卫视':('jsbc.com','jsbc.com.cn'),
  '东方卫视':('smg.cn','bestv.com.cn'),
  '北京卫视':('brtn.cn','btime.com'),
  '广东卫视':('gdtv.cn','gdou.com'),
  'CGTN English':('cgtn.com',),
 }
 if canonical in official_chinese and not under(*official_chinese[canonical]): return False
 if re.search(r'(?:mytvsuper|tvb|cnngo|turnerlive)',host,re.I): return False
 return True

def check(e):
 try:
  start=time.monotonic(); code,body,final,ctype=get(e['url'],256*1024)
  if code != 200 or not body: return None
  text=body.decode('utf-8','replace')
  if '#EXTM3U' not in text[:200]: return None
  if re.search(r'#EXT-X-(?:KEY|SESSION-KEY):[^\n]*METHOD=(?!NONE)',text,re.I): return None
  if '#EXT-X-STREAM-INF' in text:
   variants=[]; lines=text.splitlines()
   for i,line in enumerate(lines[:-1]):
    if line.startswith('#EXT-X-STREAM-INF'):
     nxt=lines[i+1].strip()
     if nxt and not nxt.startswith('#'): variants.append(urllib.parse.urljoin(final,nxt))
   if not variants: return None
   target=variants[0]
   if not allowed_url(target,e['canonical']): return None
   code,body,final,_=get(target,128*1024)
   text=body.decode('utf-8','replace')
   if code!=200 or '#EXTM3U' not in text[:200]: return None
   if re.search(r'#EXT-X-(?:KEY|SESSION-KEY):[^\n]*METHOD=(?!NONE)',text,re.I): return None
  if '#EXTINF:' not in text and '#EXT-X-MEDIA-SEQUENCE:' not in text: return None
  segments=[line.strip() for line in text.splitlines() if line.strip() and not line.startswith('#')]
  if not segments: return None
  segment=urllib.parse.urljoin(final,segments[0])
  seg_host=urllib.parse.urlsplit(segment).hostname
  if not seg_host or urllib.parse.urlsplit(segment).scheme not in ('http','https'): return None
  try:
   if not ipaddress.ip_address(seg_host).is_global: return None
  except ValueError: pass
  seg_code,seg_body,_,_=get(segment,2048)
  if seg_code not in (200,206) or len(seg_body)<100: return None
  e['latency']=round(time.monotonic()-start,2)
  return e
 except Exception: return None

print('抓取精选公开列表…',flush=True)
items=[]; source_status=[]
for feed in feeds:
 try:
  code,body,_,_=get(feed,5*1024*1024)
  parsed=parse_m3u(body,feed)
  items+=parsed
  source_status.append(f'成功 {len(parsed)} 条 {feed}')
 except Exception as exc:
  source_status.append(f'失败 {feed}: {str(exc)[:100]}')
# 把已有 M3U 作为备用候选；仅选白名单中的频道，不改动原列表。
local_items=parse_file(root / 'output' / 'iptv_smooth.m3u') + parse_file(out)
items.extend(local_items)
source_status.append(f'本地已有候选 {len(local_items)} 条')
selected=[]; seen=set(); counts={}
for e in items:
 identity=match(e)
 if not identity: continue
 canonical,group=identity
 if not allowed_url(e['url'],canonical): continue
 key=(canonical,e['url'])
 if key in seen: continue
 seen.add(key); e['canonical']=canonical; e['group']=group
 if counts.get(canonical,0)>=a.max_per_channel: continue
 counts[canonical]=counts.get(canonical,0)+1; selected.append(e)
print(f'候选 {len(selected)} 条，检查 HTTP/HLS…',flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=max(1,min(a.workers,24))) as pool:
 checked=list(pool.map(check,selected))
valid=[e for e in checked if e]
best={}
for e in valid:
 key=e['canonical']
 if key not in best or e['latency']<best[key]['latency']: best[key]=e
order={name:i for i,(name,_,_) in enumerate(rules)}
final=sorted(best.values(),key=lambda e:order[e['canonical']])
lines=['#EXTM3U x-tvg-url="https://raw.githubusercontent.com/wizakorhd/iptv/main/guide.xml.gz"']
for e in final:
 esc=lambda s: html.escape(s or '',quote=True).replace('\n',' ')
 attrs=f'tvg-name="{esc(e["canonical"])}" group-title="{esc(e["group"])}"'
 if e['id']: attrs+=f' tvg-id="{esc(e["id"])}"'
 if e['logo']: attrs+=f' tvg-logo="{esc(e["logo"])}"'
 lines += [f'#EXTINF:-1 {attrs},{e["canonical"]}',e['url']]
summary='\n'.join([f'更新: {datetime.now():%Y-%m-%d %H:%M}',f'候选: {len(selected)}，HLS 有效: {len(valid)}，去重后: {len(final)}',*([f'{e["canonical"]}: {e["latency"]:.2f}s' for e in final]),'',*source_status,''])
print(summary)
if a.dry_run: print('演练完成，未写文件')
elif final:
 content='\n'.join(lines)+'\n'
 previous=out.read_text(encoding='utf-8') if out.exists() else ''
 previous_count=previous.count('#EXTINF:')
 if previous_count and len(final)<max(8,int(previous_count*0.6)):
  print('通过检查的频道明显少于上次，保留原列表；本次未发布。',file=sys.stderr)
  sys.exit(1)
 for target in (out,legacy_out):
  tmp=target.with_suffix('.m3u.tmp'); tmp.write_text(content,encoding='utf-8'); tmp.replace(target)
 report.write_text(summary,encoding='utf-8')
 print(f'APTV 文件: {out}')
 print(f'兼容原路径: {legacy_out}')
 print(f'结果日志: {report}')
 marker=root/'logs'/'zh_en_published.sha256'
 digest=hashlib.sha256(content.encode()).hexdigest()
 if a.no_push:
  print('按参数只更新本地文件。')
 elif marker.exists() and marker.read_text(encoding='utf-8').strip()==digest:
  print('播放列表没有变化，GitHub 无需更新。')
 else:
  repo=root/'repo'; encrypted=repo/'iptv.m3u.enc'; secret=root/'secrets.local.txt'
  if not (repo/'.git').exists() or not secret.exists():
   print('未找到现有 GitHub 仓库或本地加密口令；本地列表已生成。',file=sys.stderr)
   sys.exit(1)
  found=re.search(r'PASSPHRASE\s*=\s*(\S+)',secret.read_text(encoding='utf-8'))
  if not found:
   print('本地加密口令格式不正确；本地列表已生成。',file=sys.stderr)
   sys.exit(1)
  backup=root/'output'/'iptv_before_english_curated.m3u.enc'
  if encrypted.exists() and not backup.exists(): shutil.copy2(encrypted,backup)
  temp=encrypted.with_suffix('.enc.tmp')
  encrypted_result=subprocess.run(['openssl','enc','-aes-256-cbc','-pbkdf2','-iter','10000','-md','sha256','-salt','-pass','stdin','-in',str(out),'-out',str(temp)],input=found.group(1)+'\n',capture_output=True,text=True)
  if encrypted_result.returncode:
   print('加密失败；本地列表已生成。',file=sys.stderr)
   temp.unlink(missing_ok=True); sys.exit(1)
  temp.replace(encrypted)
  add=subprocess.run(['git','add','iptv.m3u.enc'],cwd=repo,capture_output=True,text=True)
  if add.returncode:
   print('GitHub 暂存失败；加密文件仍保存在本机。',file=sys.stderr); sys.exit(1)
  commit=subprocess.run(['git','commit','-m','update curated English IPTV'],cwd=repo,capture_output=True,text=True)
  if commit.returncode:
   print('GitHub 提交失败；加密文件仍保存在本机。',file=sys.stderr); sys.exit(1)
  push=subprocess.run(['git','push','origin','main'],cwd=repo,capture_output=True,text=True,timeout=60)
  if push.returncode:
   print('GitHub 推送失败；本地提交已保留，下次可重试。',file=sys.stderr); sys.exit(1)
  marker.write_text(digest+'\n',encoding='utf-8')
  print('已加密并推送到 GitHub；使用本机 ACCESS_KEY 的 APTV 订阅可继续刷新。')
else:
 print('没有通过检测的频道，保留上次文件。',file=sys.stderr)
 sys.exit(1)
PY
status=$?
echo
if [ -t 0 ]; then read -n 1 -s -r -p "按任意键关闭窗口"; echo; fi
exit "$status"
