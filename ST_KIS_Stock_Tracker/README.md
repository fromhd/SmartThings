# 📈 KIS Stock Tracker_DaeGumi (SmartThings Edge Driver)

한국투자증권(KIS)의 Open API를 활용하여 국내/해외 주식 시세 및 수익률을 실시간으로 확인하는 스마트싱스 엣지 드라이버입니다.

## ✨ 주요 특징
- **전용 중계 서버:** `kis_ST_http_server.py`를 통해 KIS의 OAuth2 인증 및 실시간 웹소켓 데이터를 스마트싱스 허브로 중계합니다.
- **서버 관리 스크립트:** `kis_ST_http_server.sh`를 통해 백그라운드 실행 및 프로세스 다운 시 자동 재시작 기능을 지원합니다.
- **다양한 정보 제공:** 현재가, 전일 대비 등락, 평균 단가 대비 수익률(%)을 제공합니다.
- **서버 부하 최적화:** MQTT 로직을 제거하고 오직 스마트싱스 중계에만 집중하여 가볍고 빠르게 작동합니다.

## ⚙️ 설정 방법
1. **한국투자증권 개발자센터**에서 App Key와 App Secret을 발급받습니다.
2. 서버(NAS 등)에서 `kis_ST_http_server.py` 내부에 키 정보를 입력합니다.
3. 관리 스크립트로 서버를 가동합니다: 
   ```bash
   chmod +x kis_ST_http_server.sh
   ./kis_ST_http_server.sh start
   ```
4. 스마트싱스 앱 설정에서 파이썬 서버의 IP와 포트(9595), 그리고 Edge Bridge의 정보를 입력합니다.
