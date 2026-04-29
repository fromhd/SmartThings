# 📈 KIS Stock Tracker (SmartThings Edge Driver)

한국투자증권(KIS)의 Open API를 활용하여 국내 및 해외 주식 시세와 수익률을 스마트싱스에서 실시간으로 확인하세요.

## ✨ 주요 특징
- **전용 중계 서버:** `kis_ST_http_server.py`가 KIS의 OAuth2 인증과 실시간 웹소켓 데이터를 안정적으로 처리합니다.
- **자동 관리 기능:** `kis_ST_http_server.sh`를 통해 백그라운드 실행 및 프로세스 다운 시 자동 복구를 지원합니다.
- **실시간 데이터:** 약 3초 간격의 빠른 폴링으로 실시간에 가까운 주가 변동을 추적합니다.
- **상세 정보 제공:** 현재가, 전일 대비 등락뿐만 아니라 평단가 기반의 실시간 수익률(%)을 제공합니다.
- **최적화된 아키텍처:** MQTT 의존성을 제거하고 다이렉트 중계 방식으로 전환하여 성능을 극대화했습니다.

## ⚙️ 설정 방법

### 1. KIS API 준비
- [한국투자증권 개발자센터](https://apiportal.koreainvestment.com/)에서 App Key와 App Secret을 발급받습니다.

### 2. 서버 설정 (NAS 또는 PC)
- `kis_ST_http_server.py` 파일의 설정 섹션에 발급받은 키 정보를 입력합니다.
- 서버를 가동합니다:
  ```bash
  chmod +x kis_ST_http_server.sh
  ./kis_ST_http_server.sh start
  ```

### 3. 스마트싱스 앱 설정
- **Server Domain/IP:** 파이썬 서버의 주소
- **Server Port:** 기본값 `9595`
- **Bridge IP/Port:** Edge Bridge 서버 정보 (8088)
- **Stock Code:** 종목 코드 (예: 064350)
- **Avg Price:** 보유 주식의 평균 단가 (수익률 계산용)

## 💡 참고 사항
- 본 드라이버는 Edge Bridge를 통해 외부 서버와 통신합니다.
- 해외 주식의 경우 KIS API 설정에 따라 티커(Ticker)를 사용합니다.
