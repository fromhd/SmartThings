# 🏠 SmartThings Edge Drivers Collection

이 저장소는 스마트싱스(SmartThings) 허브의 **Edge Driver** 아키텍처를 기반으로 한 다양한 커스텀 드라이버들을 포함하고 있습니다. 모든 드라이버는 로컬 실행을 원칙으로 하며, 필요 시 Edge Bridge를 통해 외부 데이터를 연동합니다.

## 🚀 포함된 프로젝트

### 1. [📈 KIS Stock Tracker](./ST_KIS_Stock_Tracker/)
- 한국투자증권 Open API 연동 국내/해외 주식 시세 추적기
- 전용 파이썬 중계 서버를 통한 실시간 데이터 수집

### 2. [📊 Naver Stock Tracker](./ST_Naver_Stock_Tracker/)
- 네이버 금융 웹 API 기반의 간편한 국내 주식 시세 추적기
- API 키 없이 종목 코드만으로 즉시 연동 가능

### 3. [🌤️ Weather Tracker](./ST_Weather_Tracker/)
- 기상청 초단기실황 데이터를 활용한 정밀 기상 감지기
- 실제 강수량 기반의 창문 제어 및 온습도 자동화 지원

### 4. [🏠 Wi-Fi Presence Sensor](./ST_Wifi_Presence_Sensor/)
- OpenWRT 공유기 연동 Wi-Fi 기반 가족 재실 감지기
- ubus 시스템을 활용한 저지연/저부하 감지 방식

---

## 🛠️ 공통 요구사항
- **SmartThings Hub:** v2, v3 또는 Aeotec Hub
- **[Edge Bridge](https://github.com/toddaustin07/edgebridge):** 일부 드라이버(Stock, Weather)는 외부 통신을 위해 로컬 네트워크 내의 Edge Bridge 서버가 필요합니다.

## 📄 라이선스
각 프로젝트 폴더의 LICENSE 파일을 참조하세요.
