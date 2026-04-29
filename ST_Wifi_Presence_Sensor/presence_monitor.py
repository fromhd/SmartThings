import subprocess
import json
import time
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler

# --- 설정 ---
FAMILIES = {
    "E8:88:43:43:CC:D5": "Diego",
    "58:79:E0:B8:D7:78": "Jinee",
    "BC:6A:D1:23:25:E8": "YooJoo",
    "88:46:04:A1:36:49": "HyukJoo"
}
CHECK_INTERVAL = 30   # 와이파이 체크 간격 (초)
SERVER_PORT    = 8091  # SmartThings 허브가 폴링할 포트
# -------------

# 현재 재실 상태 (스레드 공유)
current_status = {name: "not_present" for name in FAMILIES.values()}
status_lock = threading.Lock()

def get_connected_macs():
    """ubus를 통해 현재 와이파이에 연결된 MAC 주소 목록을 가져옵니다."""
    macs = set()
    try:
        interfaces = subprocess.check_output(
            "ubus list hostapd.*", shell=True
        ).decode().splitlines()
        for iface in interfaces:
            output = subprocess.check_output(
                f"ubus call {iface} get_clients", shell=True
            ).decode()
            data = json.loads(output)
            if "clients" in data:
                macs.update(data["clients"].keys())
    except Exception as e:
        print(f"[monitor] ubus 오류: {e}")
    return {mac.upper() for mac in macs}

def monitor_loop():
    """백그라운드: 와이파이 접속 상태를 주기적으로 체크"""
    print("[monitor] 시작")
    while True:
        connected = get_connected_macs()
        with status_lock:
            for mac, name in FAMILIES.items():
                current_status[name] = "present" if mac.upper() in connected else "not_present"
        print(f"[monitor] {current_status}")
        time.sleep(CHECK_INTERVAL)

class PresenceHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/status":
            with status_lock:
                body = json.dumps(current_status).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass  # 불필요한 로그 억제

if __name__ == "__main__":
    print(f"[server] SmartThings Wifi Presence Monitor 시작")
    print(f"[server] 모니터링: {list(FAMILIES.keys())}")
    print(f"[server] HTTP 서버: 0.0.0.0:{SERVER_PORT}")

    # 백그라운드 모니터링 스레드
    t = threading.Thread(target=monitor_loop, daemon=True)
    t.start()

    # HTTP 서버 (메인 스레드)
    server = HTTPServer(("0.0.0.0", SERVER_PORT), PresenceHandler)
    server.serve_forever()
