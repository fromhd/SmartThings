# 🏠 Wi-Fi Presence Sensor (SmartThings Edge Driver)

OpenWRT 공유기의 Wi-Fi 접속 정보를 활용하여 가족 구성원의 재실 상태를 정교하게 추적하는 스마트싱스 엣지 드라이버입니다.

## ✨ 주요 특징
- **개별 구성원 추적:** 가족 구성원별(Diego, Jinee, YooJoo, HyukJoo)로 독립적인 재실 상태를 관리합니다.
- **통합 홈 재실:** 한 명이라도 집에 있으면 '집 재실(main)' 상태가 `present`로 유지됩니다.
- **가벼운 리소스:** OpenWRT의 `ubus` 시스템 명령어를 직접 사용하여 공유기 부하를 최소화합니다.
- **실시간성:** Python 스크립트가 백그라운드에서 감시하고, 엣지 드라이버가 주기적으로 상태를 동기화합니다.

## 🛠️ 시스템 구조
1. **OpenWRT (Python):** `presence_monitor.py`가 Wi-Fi 클라이언트 목록을 감시하고 HTTP JSON API(`/status`)를 제공합니다.
2. **SmartThings Hub (Lua):** 엣지 드라이버가 OpenWRT의 API를 폴링하여 상태를 업데이트합니다.

## ⚙️ 설정 방법

### 1. OpenWRT 설정 (공유기)
- `presence_monitor.py` 파일을 OpenWRT 공유기 내부(예: `/root/`)에 복사합니다.
- 스크립트 내 `FAMILIES` 변수에 가족의 MAC 주소를 등록합니다.
- 스크립트를 실행합니다:
  ```bash
  python3 presence_monitor.py
  ```
  *(팁: `procd` 등을 사용하여 부팅 시 자동 실행되도록 설정하는 것을 권장합니다.)*

### 2. 스마트싱스 앱 설정
- 드라이버 설치 후 기기를 추가합니다.
- 기기 설정에서 다음 정보를 입력합니다:
  - **OpenWRT IP:** 공유기의 로컬 IP (예: 192.168.1.1)
  - **OpenWRT Port:** 기본값 `8091`
  - **Polling Interval:** 상태 확인 주기 (기본 30초)

## 💡 참고 사항
- 본 드라이버는 허브의 로컬 네트워크(LAN) 내에서 작동하므로 별도의 클라우드 통신이 필요 없습니다.
- Wi-Fi의 특성상 기기의 절전 모드 진입 시 일시적으로 `not_present`로 보일 수 있으므로, 자동화 구성 시 'N분 동안 유지' 조건을 사용하는 것이 좋습니다.
