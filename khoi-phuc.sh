#!/bin/bash
# =====================================================================================================
#  PAN - TRANG KHOI PHUC MAY CHU MOI
#  Dung khi VPS cu hong han: thue VPS Ubuntu moi (22.04 / 24.04), dang nhap SSH (root) roi dan 1 dong:
#      curl -fsSL https://raw.githubusercontent.com/hoc-ai/pan-khoi-phuc/main/khoi-phuc.sh | sudo bash
#  Lenh in ra 1 dia chi https://<IP>:8443/?ma=... -> mo tren trinh duyet -> tai tep "Bo khoi phuc"
#  (khoi-phuc-vps-....sh, tai tu trang Sao luu may chu luc may cu con song) -> chon ban -> Khoi phuc.
#  Tep nay KHONG chua bi mat nao: khoa vao Google Drive / NAS + mat khau giai ma nam trong tep Bo khoi phuc cua anh/chi.
#  Trang chay rieng (systemd-run), tat SSH khong sao; tu tat + xoa tep sau 30 phut ke tu khi khoi phuc xong.
# =====================================================================================================
set -e
[ "$(id -u)" = 0 ] || { echo "Can chay bang root: ... | sudo bash"; exit 1; }
CONG=${PAN_KP_CONG:-8443}
DIR=/root/pan-khoi-phuc-web
export DEBIAN_FRONTEND=noninteractive
echo "== Chuan bi (python3, openssl, ufw)..."
if ! command -v python3 >/dev/null || ! command -v openssl >/dev/null || ! command -v ufw >/dev/null; then
  apt-get update -qq && apt-get install -y -qq python3 openssl ufw >/dev/null
fi
systemctl stop pan-khoi-phuc-web 2>/dev/null || true
systemctl reset-failed pan-khoi-phuc-web 2>/dev/null || true
rm -rf "$DIR"; mkdir -p "$DIR"; chmod 700 "$DIR"
IP=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || true)
[ -n "$IP" ] || IP=$(hostname -I | awk '{print $1}')
openssl req -x509 -newkey rsa:2048 -nodes -days 7 -subj "/CN=PAN khoi phuc" -addext "subjectAltName=IP:$IP" \
  -keyout "$DIR/khoa.pem" -out "$DIR/chung_chi.pem" >/dev/null 2>&1
MA=$(openssl rand -hex 10)
# cong trang: them luat ufw (ke ca khi ufw chua bat) -> bo khoi phuc bat ufw van khong chan trang giua chung
ufw allow "$CONG/tcp" >/dev/null 2>&1 || true

cat > "$DIR/trang.py" <<'PY'
import html, http.server, json, os, re, secrets, shutil, socketserver, ssl, subprocess, sys, threading, time
CONG, MA, DIR = int(sys.argv[1]), sys.argv[2], sys.argv[3]
KIT = os.path.join(DIR, "bo-khoi-phuc.sh")
TT = {"buoc": "cho_tep", "log": [], "ds": [], "ban": "", "loi": "", "tien_do": "", "mien": []}
KHOA = threading.Lock()
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

def them_log(dong):
    dong = ANSI.sub("", dong).rstrip()
    if not dong:
        return
    with KHOA:
        # rclone --progress: khong ghi vao nhat ky, chi giu 1 dong tien do (dong "Transferred: x MiB / y MiB, z%")
        t = dong.strip()
        if t.startswith(("Transferred:", "Checks:", "Elapsed time:", "Transferring:", "* ")):
            if t.startswith("Transferred:") and "iB" in t:
                TT["tien_do"] = "Đã tải " + t.split(":", 1)[1].split(", ETA")[0].strip()
            return
        m = re.fullmatch(r"\s+(\S+)\s+->\s+(\S+)", dong)
        if m:
            TT["mien"].append(m.group(1) + " → " + m.group(2))
        TT["log"].append(dong)
        del TT["log"][:-400]

def chay(lenh, xong):
    def lam():
        try:
            p = subprocess.Popen(lenh, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, cwd=DIR)
            dem = b""
            while True:
                c = p.stdout.read(1)
                if not c:
                    break
                if c in (b"\n", b"\r"):
                    them_log(dem.decode("utf-8", "replace")); dem = b""
                else:
                    dem += c
            them_log(dem.decode("utf-8", "replace"))
            xong(p.wait())
        except Exception as e:
            them_log("LOI: %s" % e); xong(1)
    threading.Thread(target=lam, daemon=True).start()

def tat_sau(giay):
    def lam():
        time.sleep(giay)
        try:
            os.remove(KIT)
        except OSError:
            pass
        subprocess.call(["ufw", "delete", "allow", "%d/tcp" % CONG], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        shutil.rmtree(DIR, ignore_errors=True)
        os._exit(0)
    threading.Thread(target=lam, daemon=True).start()

TRANG = """<!doctype html><html lang="vi"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PAN – Khôi phục máy chủ</title><style>
body{font:15px/1.5 system-ui,Segoe UI,Arial,sans-serif;background:#f3f4f6;color:#111827;margin:0}
main{max-width:760px;margin:24px auto;padding:0 16px}h1{font-size:22px;margin:0 0 4px}.phu{color:#6b7280;font-size:13px}
.the{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:18px 20px;margin:14px 0}
.the h2{font-size:16px;margin:0 0 8px}.so{display:inline-block;width:24px;height:24px;border-radius:50%;background:#2563eb;color:#fff;text-align:center;font-size:13px;line-height:24px;margin-right:6px}
.tat{opacity:.45}button{background:#1f2937;color:#fff;border:0;border-radius:6px;padding:9px 16px;font-size:14px;cursor:pointer}
button.do{background:#b91c1c}button:disabled{opacity:.5;cursor:default}
pre{background:#0f172a;color:#e2e8f0;border-radius:6px;padding:12px;font-size:12.5px;max-height:420px;overflow:auto;white-space:pre-wrap;word-break:break-all}
.ban{display:block;padding:6px 8px;border:1px solid #e5e7eb;border-radius:6px;margin:6px 0;cursor:pointer}.ban:hover{background:#f9fafb}
.tot{color:#15803d;font-weight:600}.mien{background:#f0fdf4;border:1px solid #bbf7d0;border-radius:6px;padding:8px 12px;font-family:Consolas,monospace;font-size:13px}.loi{color:#b91c1c;font-weight:600}.canh{background:#fffbeb;border:1px solid #fcd34d;border-radius:6px;padding:10px 12px;font-size:13px}
</style></head><body><main>
<h1>Khôi phục máy chủ PAN</h1><div class="phu">Dựng lại CRM, chat, website, https trên máy chủ mới này từ bản sao lưu trên Google Drive / NAS.</div>
<div class="the" id="b1"><h2><span class="so">1</span>Chọn tệp Bộ khôi phục</h2>
<p class="phu">Tệp <b>khoi-phuc-vps-….sh</b> đã tải từ trang <i>Sao lưu máy chủ → Bộ khôi phục…</i> (cất trong USB / máy tính). Tệp chỉ gửi lên chính máy chủ này.</p>
<input type="file" id="tep" accept=".sh"> <button id="gui">Đọc tệp</button> <span id="tt1" class="phu"></span></div>
<div class="the tat" id="b2"><h2><span class="so">2</span>Chọn bản sao lưu</h2><div id="ds" class="phu">Chờ bước 1…</div>
<p><button class="do" id="kp" disabled>Khôi phục bản đã chọn</button></p>
<div class="canh">Máy chủ này sẽ được cài PAN và chép toàn bộ dữ liệu của bản đã chọn (5–20 phút). Đừng tắt trang / máy chủ khi đang chạy.</div></div>
<div class="the tat" id="b3"><h2><span class="so">3</span>Tiến trình</h2><div id="kq"></div><div id="td" class="phu"></div><pre id="log">…</pre></div>
</main><script>
var chon='', buoc='';
function $(i){return document.getElementById(i)}
$('gui').onclick=function(){var f=$('tep').files[0];if(!f){$('tt1').textContent='Chưa chọn tệp.';return}
 $('tt1').textContent='Đang đọc… (lần đầu cài công cụ mất 1–2 phút)';$('gui').disabled=true;
 fetch('tep',{method:'POST',body:f,credentials:'same-origin'}).then(function(r){return r.json()}).then(function(d){if(d.loi){$('tt1').textContent=d.loi;$('gui').disabled=false}})};
$('kp').onclick=function(){if(!chon||!confirm('Khôi phục bản '+chon+' lên máy chủ này?'))return;$('kp').disabled=true;
 fetch('khoi-phuc',{method:'POST',body:JSON.stringify({ban:chon}),credentials:'same-origin'})};
function ve(d){
 buoc=d.buoc;$('log').textContent=d.log.join('\\n')||'…';$('log').scrollTop=1e9;$('td').textContent=d.buoc=='dang_khoi_phuc'?d.tien_do:'';
 $('b2').classList.toggle('tat',!(d.buoc=='chon_ban'||d.buoc=='dang_khoi_phuc'||d.buoc=='xong'));
 $('b3').classList.toggle('tat',d.buoc=='cho_tep');
 if(d.buoc=='dang_doc'){$('tt1').textContent='Đang đọc tệp, cài công cụ, tìm bản sao lưu…'}
 if(d.buoc=='cho_tep'&&d.loi){$('tt1').textContent=d.loi;$('gui').disabled=false}
 if(d.buoc=='chon_ban'||d.buoc=='loi_kp'){ $('tt1').textContent='✓ Đã đọc tệp.';
  if(!$('ds').dataset.ve){$('ds').dataset.ve=1;$('ds').innerHTML='';d.ds.forEach(function(b,i){var l=document.createElement('label');l.className='ban';
   l.innerHTML='<input type="radio" name="ban"> <b>'+b.replace('ngay/','Hằng ngày · ').replace('thang/','Đầu tháng · ')+'</b>';
   l.querySelector('input').onchange=function(){chon=b;$('kp').disabled=false};$('ds').appendChild(l);if(i==0){l.querySelector('input').checked=true;chon=b;$('kp').disabled=false}})}}
 if(d.buoc=='dang_khoi_phuc'){$('kp').disabled=true;$('kq').innerHTML='⏳ Đang khôi phục bản <b>'+d.ban+'</b>…'}
 if(d.buoc=='xong'){$('kp').disabled=true;var m=d.mien.length?'<div class="mien">'+d.mien.map(function(x){return x.replace(/[<>&]/g,'')}).join('<br>')+'</div>':'';
  $('kq').innerHTML='<p class="tot">✓ KHÔI PHỤC XONG bản '+d.ban+'.</p><p>Việc còn lại: vào trang quản lý tên miền (Cloudflare / nhà đăng ký), trỏ các tên miền sau về IP mới. 5–30 phút sau https tự có lại.</p>'+m+'<p class="phu">Trang này tự tắt + xóa sau 30 phút.</p>'}
 if(d.buoc=='loi_kp'){$('kq').innerHTML='<p class="loi">✗ Khôi phục lỗi – xem nhật ký bên dưới. Có thể chọn bản khác rồi thử lại.</p>';$('kp').disabled=!chon}
}
function hoi(){fetch('tt',{credentials:'same-origin',cache:'no-store'}).then(function(r){return r.json()}).then(ve).catch(function(){}).then(function(){setTimeout(hoi,buoc=='xong'?10000:2000)})}
hoi();
</script></body></html>"""

class XuLy(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass
    def dung_ma(self):
        q = self.path.split("?", 1)[1] if "?" in self.path else ""
        m = re.search(r"(?:^|&)ma=([0-9a-f]+)", q)
        c = re.search(r"(?:^|;\s*)pankp=([0-9a-f]+)", self.headers.get("Cookie", ""))
        for v in (m and m.group(1), c and c.group(1)):
            if v and secrets.compare_digest(v, MA):
                return True
        return False
    def gui(self, ma, loai, than, cookie=False):
        b = than.encode() if isinstance(than, str) else than
        self.send_response(ma)
        self.send_header("Content-Type", loai)
        self.send_header("Content-Length", str(len(b)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("Referrer-Policy", "no-referrer")
        if cookie:
            self.send_header("Set-Cookie", "pankp=%s; Path=/; HttpOnly; Secure; SameSite=Strict" % MA)
        self.end_headers()
        self.wfile.write(b)
    def json(self, d):
        self.gui(200, "application/json; charset=utf-8", json.dumps(d, ensure_ascii=False))
    def do_GET(self):
        if not self.dung_ma():
            return self.gui(403, "text/plain; charset=utf-8", "Sai ma. Mo dung dia chi lenh da in ra (co ?ma=...).")
        p = self.path.split("?")[0]
        if p == "/":
            return self.gui(200, "text/html; charset=utf-8", TRANG, cookie=True)
        if p == "/tt":
            with KHOA:
                return self.json({k: TT[k] for k in ("buoc", "log", "ds", "ban", "loi", "tien_do", "mien")})
        self.gui(404, "text/plain", "404")
    def do_POST(self):
        if not self.dung_ma():
            return self.gui(403, "text/plain", "Sai ma")
        n = int(self.headers.get("Content-Length") or 0)
        if n > 4 * 1024 * 1024:
            return self.json({"loi": "Tệp quá lớn – không phải Bộ khôi phục."})
        than = self.rfile.read(n)
        p = self.path.split("?")[0]
        if p == "/tep":
            with KHOA:
                if TT["buoc"] in ("dang_doc", "dang_khoi_phuc", "xong"):
                    return self.json({"loi": "Đang chạy, chờ chút."})
            if not than.startswith(b"#!/bin/bash") or b"BO KHOI PHUC MAY CHU PAN" not in than[:2000]:
                return self.json({"loi": "Đây không phải tệp Bộ khôi phục PAN (khoi-phuc-vps-….sh)."})
            fd = os.open(KIT, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "wb") as f:
                f.write(than.replace(b"\r\n", b"\n"))
            with KHOA:
                TT.update(buoc="dang_doc", log=[], ds=[], loi="")
            def xong(ma):
                with KHOA:
                    ds = [d for d in TT["log"] if re.fullmatch(r"(ngay|thang)/[0-9_-]{4,20}", d)]
                    ds.sort(key=lambda d: (d.startswith("ngay/"), d), reverse=True)
                    if ma == 0 and ds:
                        TT.update(buoc="chon_ban", ds=ds)
                    else:
                        TT.update(buoc="cho_tep", loi="Không đọc được bản sao lưu từ nơi lưu – xem nhật ký (sai tệp / mất mạng / nơi lưu đã đổi mật khẩu?).")
            chay(["bash", KIT, "--danh-sach"], xong)
            return self.json({"ok": 1})
        if p == "/khoi-phuc":
            try:
                ban = json.loads(than or b"{}").get("ban", "")
            except ValueError:
                ban = ""
            with KHOA:
                if TT["buoc"] not in ("chon_ban", "loi_kp") or ban not in TT["ds"]:
                    return self.json({"loi": "Bản không hợp lệ."})
                TT.update(buoc="dang_khoi_phuc", ban=ban, tien_do="", mien=[])
                TT["log"].append("")
                TT["log"].append("======== KHÔI PHỤC BẢN %s ========" % ban)
            def xong(ma):
                with KHOA:
                    TT["buoc"] = "xong" if ma == 0 else "loi_kp"
                if ma == 0:
                    try:
                        os.remove(KIT)
                    except OSError:
                        pass
                    tat_sau(1800)
            chay(["bash", KIT, ban.split("/", 1)[1]], xong)
            return self.json({"ok": 1})
        self.gui(404, "text/plain", "404")

class MayChu(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True

may = MayChu(("0.0.0.0", CONG), XuLy)
ng = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ng.load_cert_chain(os.path.join(DIR, "chung_chi.pem"), os.path.join(DIR, "khoa.pem"))
may.socket = ng.wrap_socket(may.socket, server_side=True)
tat_sau(6 * 3600)  # quen chua dung -> tu tat sau 6 gio
may.serve_forever()
PY

if [ -n "$PAN_KP_TRUOC" ]; then   # chay truc tiep (dien tap trong docker, khong co systemd)
  echo "Mo: https://$IP:$CONG/?ma=$MA"
  exec python3 "$DIR/trang.py" "$CONG" "$MA" "$DIR"
fi
systemd-run --quiet --unit=pan-khoi-phuc-web --property=WorkingDirectory="$DIR" python3 "$DIR/trang.py" "$CONG" "$MA" "$DIR"
sleep 1
systemctl is-active -q pan-khoi-phuc-web || { echo "Khong chay duoc trang khoi phuc:"; journalctl -u pan-khoi-phuc-web -n 20 --no-pager; exit 1; }
printf '\n\033[1;32m Trang khoi phuc da chay.\033[0m Mo tren trinh duyet:\n\n    \033[1mhttps://%s:%s/?ma=%s\033[0m\n\n' "$IP" "$CONG" "$MA"
echo " - Trinh duyet bao 'khong an toan' (chung chi tu tao) -> bam Nang cao / Advanced -> Tiep tuc. Ket noi van duoc ma hoa."
echo " - Neu khong mo duoc: mo cong $CONG/TCP trong tuong lua cua nha cung cap VPS."
echo " - Ma tren dia chi la chia khoa cua trang - khong gui cho ai. Trang tu tat sau khi khoi phuc xong 30 phut."
