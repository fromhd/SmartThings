import asyncio
import websockets
import json
import requests
import paho.mqtt.client as mqtt
from datetime import datetime
import sys
from aiohttp import web

# --- [설정 영역] ---
APP_KEY = "한투APP KEY"
APP_SECRET = "한투SECRET KEY"

MQTT_BROKER = "MQTT서버주소"
MQTT_PORT = 1883
MQTT_USER = "MQTT서버ID"
MQTT_PASS = "MQTT서버비번"

URL = "https://openapi.koreainvestment.com:9443"
WS_URL = "ws://ops.koreainvestment.com:21000"

access_token = ""
approval_key = ""
reconnect_needed = False

# [상태 관리]
mqtt_stock_code = "064350"
http_stock_codes = set()
latest_prices = {}
subscription_queue = asyncio.Queue()

def log_print(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}")
    sys.stdout.flush()

# --- [인증 함수] ---
def get_access_token():
    try:
        res = requests.post(f"{URL}/oauth2/tokenP", json={"grant_type": "client_credentials", "appkey": APP_KEY, "appsecret": APP_SECRET}, timeout=5)
        return res.json().get("access_token")
    except: return None

def get_approval_key():
    try:
        res = requests.post(f"{URL}/oauth2/Approval", json={"grant_type": "client_credentials", "appkey": APP_KEY, "secretkey": APP_SECRET}, timeout=5)
        return res.json().get("approval_key")
    except: return None

def get_tr_id():
    now = datetime.now()
    if (8 <= now.hour < 9) or (16 <= now.hour < 20):
        return "H0NXCNT0", "NXT"
    return "H0STCNT0", "KRX"

def get_current_price_rest(code, market_label, is_mqtt=False):
    global access_token
    div_code = "UN" if market_label == "NXT" else "J"
    
    headers = {
        "Content-Type": "application/json",
        "authorization": f"Bearer {access_token}",
        "appkey": APP_KEY, "appsecret": APP_SECRET,
        "tr_id": "FHKST01010100"
    }
    params = {"fid_cond_mrkt_div_code": div_code, "fid_input_iscd": code}
    try:
        res = requests.get(f"{URL}/uapi/domestic-stock/v1/quotations/inquire-price", headers=headers, params=params, timeout=5)
        out = res.json().get('output', {})
        p, d, r = out.get('stck_prpr'), out.get('prdy_vrss'), out.get('prdy_ctrt')
        
        if p and int(p) > 0:
            latest_prices[code] = {"price": p, "diff": d, "rate": r, "market": market_label}
            if is_mqtt:
                payload = f"{p},{d},{r},{market_label}"
                mqtt_client.publish("stock/data", payload)
                log_print(f"📦 [MQTT] 초기값 동기화 완료: {payload}")
            else:
                log_print(f"📦 [HTTP] 초기값 동기화 완료: {code} -> {p}원")
    except Exception as e:
        log_print(f"⚠️ REST 조회 실패: {e}")

async def kis_websocket_handler():
    global approval_key, access_token, reconnect_needed
    log_print(f"🔥 오라클 클라우드 멀티플렉스 중계기 가동")
    
    while True:
        try:
            if not access_token: access_token = get_access_token()
            if not approval_key: approval_key = get_approval_key()
            tr_id, market_label = get_tr_id()

            # 웹소켓 시작 전, 현재 관리 중인 모든 종목 구독 큐에 넣기
            all_codes = http_stock_codes.copy()
            all_codes.add(mqtt_stock_code)
            for code in all_codes:
                await subscription_queue.put(code)

            async with websockets.connect(WS_URL, ping_interval=30) as ws:
                while not reconnect_needed:
                    try:
                        # 1. 신규 구독 요청 처리
                        while not subscription_queue.empty():
                            new_code = subscription_queue.get_nowait()
                            sub_data = {
                                "header": {"approval_key": approval_key, "custtype": "P", "tr_type": "1", "content-type": "utf-8"},
                                "body": {"input": {"tr_id": tr_id, "tr_key": new_code}}
                            }
                            await ws.send(json.dumps(sub_data))
                            log_print(f"✅ [{market_label}] 웹소켓 구독 추가: {new_code}")

                        # 2. 데이터 수신 (0.5초 대기)
                        data = await asyncio.wait_for(ws.recv(), timeout=0.5)
                        
                        if data[0] in ['0', '1']:
                            parts = data.split('|')
                            if len(parts) < 4: continue
                            body = parts[3].split('^')
                            
                            code, price, diff, rate = body[0], body[2], body[4], body[5]
                            
                            if price and price.isdigit() and int(price) > 0:
                                latest_prices[code] = {"price": price, "diff": diff, "rate": rate, "market": market_label}
                                
                                if code == mqtt_stock_code:
                                    payload = f"{price},{diff},{rate},{market_label}"
                                    mqtt_client.publish("stock/data", payload)
                                    log_print(f"🚀 [MQTT] 체결 발생!: {payload}")
                                else:
                                    log_print(f"🚀 [HTTP] 체결 발생!: {code} -> {price}원 ({rate}%)")
                        
                        elif '"tr_id":"PING"' in data:
                            await ws.send(json.dumps({"header": {"tr_id": "PING"}}))
                            
                    except asyncio.TimeoutError:
                        if get_tr_id()[0] != tr_id: 
                            reconnect_needed = True; break
                        continue 
                
                if reconnect_needed:
                    log_print("🔄 시장 전환 재연결...")
                    reconnect_needed = False
        except Exception as e:
            log_print(f"❌ 에러: {e}"); await asyncio.sleep(5)

# --- [HTTP 웹서버 파트] ---
async def handle_price(request):
    code = request.rel_url.query.get('code')
    if not code:
        return web.json_response({"error": "종목코드가 없습니다."}, status=400)
    
    if code not in http_stock_codes and code != mqtt_stock_code:
        log_print(f"🌐 [HTTP] 새로운 스마트싱스 요청: {code}")
        http_stock_codes.add(code)
        tr_id, market_label = get_tr_id()
        get_current_price_rest(code, market_label, is_mqtt=False)
        await subscription_queue.put(code)

    data = latest_prices.get(code, {})
    return web.json_response(data)

async def start_web_server():
    app = web.Application()
    app.add_routes([web.get('/price', handle_price)])
    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, '0.0.0.0', 9595)
    await site.start()
    log_print("🌍 HTTP 서버(9595 포트) 가동 완료")

# --- [MQTT 설정] ---
def on_message(client, userdata, msg):
    global mqtt_stock_code
    new_code = msg.payload.decode()
    if new_code != mqtt_stock_code:
        log_print(f"📥 [MQTT] 아두이노 종목 교체 요청: {new_code}")
        mqtt_stock_code = new_code
        global access_token
        if not access_token: access_token = get_access_token()
        tr_id, market_label = get_tr_id()
        get_current_price_rest(new_code, market_label, is_mqtt=True)
        subscription_queue.put_nowait(new_code)

mqtt_client = mqtt.Client(callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
mqtt_client.username_pw_set(MQTT_USER, MQTT_PASS)
mqtt_client.on_message = on_message

async def main():
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT)
    mqtt_client.subscribe("stock/request")
    mqtt_client.loop_start()
    
    global access_token
    if not access_token: access_token = get_access_token()
    tr_id, market_label = get_tr_id()
    get_current_price_rest(mqtt_stock_code, market_label, is_mqtt=True)
    
    await asyncio.gather(
        start_web_server(),
        kis_websocket_handler()
    )

if __name__ == "__main__":
    asyncio.run(main())
