-- init.lua  (Rain/Snow Tracker)
--
-- 기상청 초단기실황(getUltraSrtNcst) API를 EdgeBridge를 통해 조회하여
-- 현재 날씨 상태(SKY+PTY)를 표시하고, 강수 여부를 waterSensor로 반영합니다.
--
-- SKY 코드 (PTY=0일 때 사용):
--   1 = 맑음, 3 = 구름많음, 4 = 흐림
--
-- PTY 코드:
--   0 = 없음  → dry
--   1 = 비    → wet  / "🌧️ 비"
--   2 = 비/눈 → wet  / "🌨️ 비/눈"
--   3 = 눈    → wet  / "❄️ 눈"
--   4 = 소나기 → wet / "⛈️ 소나기"

local Driver       = require "st.driver"
local capabilities = require "st.capabilities"
local cosock       = require "cosock"
local log          = require "log"

local bridge_api   = require "bridge_api"
local discovery    = require "discovery"

local DEFAULT_PORT      = 8088
local DEFAULT_INTERVAL  = 5   -- 분
local BASE_URL = "http://apis.data.go.kr/1360000/VilageFcstInfoService_2.0/getUltraSrtNcst"

-- 커스텀 capability (대시보드 표시용 한국어 텍스트)
local weatherCond = capabilities["reasonmusic47804.weatherCondition"]

-- ──────────────────────────────────────────────────────────────────────────
-- URL 인코딩 (RFC 3986)
-- ──────────────────────────────────────────────────────────────────────────
local function urlencode(s)
  return (tostring(s):gsub("([^%w%-%_%.%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- ──────────────────────────────────────────────────────────────────────────
-- KST 기준 base_date / base_time 계산
-- 기상청 초단기실황: 매 정시 발표, 약 10분 후 조회 가능
-- minute < 10이면 직전 시각 사용 (날짜 변경선 고려)
-- ──────────────────────────────────────────────────────────────────────────
local function get_base_datetime()
  local now_ts = os.time() + (9 * 3600)
  local kst    = os.date("!*t", now_ts)
  
  -- 10분 이전이면 데이터가 아직 안 올라왔을 수 있으므로 1시간 전 데이터 조회
  if kst.min < 10 then
    kst = os.date("!*t", now_ts - 3600)
  end
  
  local base_date = string.format("%04d%02d%02d", kst.year, kst.month, kst.day)
  local base_time = string.format("%02d00", kst.hour)
  return base_date, base_time
end

-- ──────────────────────────────────────────────────────────────────────────
-- SKY + PTY 코드 → 종합 날씨 텍스트
-- ──────────────────────────────────────────────────────────────────────────
-- SKY: 맑음/구름많음/흐림 (PTY=0일 때만 사용)
local SKY_LABEL = {
  [1] = "☀️ 맑음",
  [3] = "🌥️ 구름많음",
  [4] = "☁️ 흐림",
}

-- PTY: 강수 형태 (PTY>0이면 SKY 무시)
local PTY_LABEL = {
  [1] = "🌧️ 비",
  [2] = "🌨️ 비/눈",
  [3] = "❄️ 눈",
  [4] = "⛈️ 소나기",
}

-- 종합 날씨 텍스트 생성
local function get_weather_label(sky, pty, rn1)
  if pty ~= 0 then
    -- 강수 형태가 있으면 PTY 기준으로 표시
    local base = PTY_LABEL[pty] or ("PTY:" .. tostring(pty))
    return string.format("%s (%.1fmm)", base, rn1 or 0)
  else
    -- 강수 없으면 SKY 기준으로 표시 (강수량 0)
    local base = SKY_LABEL[sky] or "☀️ 맑음"
    return string.format("%s (0.0mm)", base)
  end
end

local function is_precipitation(pty, rn1)
  -- PTY가 0이 아니고, 강수량(RN1)도 0.1mm 초과여야 실제 강수로 판단
  return pty ~= 0 and (rn1 or 0) > 0.1
end

-- ──────────────────────────────────────────────────────────────────────────
-- 기상청 API URL 생성 (EdgeBridge forward용)
-- ──────────────────────────────────────────────────────────────────────────
local function build_weather_url(api_key, nx, ny)
  local base_date, base_time = get_base_datetime()
  return BASE_URL
    .. "?serviceKey=" .. api_key
    .. "&numOfRows=10"
    .. "&pageNo=1"
    .. "&dataType=JSON"
    .. "&base_date=" .. base_date
    .. "&base_time=" .. base_time
    .. "&nx="        .. tostring(nx)
    .. "&ny="        .. tostring(ny)
end

-- ──────────────────────────────────────────────────────────────────────────
-- 날씨 조회 및 이벤트 발행
-- ──────────────────────────────────────────────────────────────────────────
local function fetch_weather_and_emit(device)
  local ip       = device.preferences.bridgeIp or ""
  local port     = tonumber(device.preferences.bridgePort) or DEFAULT_PORT
  local api_key  = device.preferences.apiKey or ""
  local nx       = math.floor(tonumber(device.preferences.gridNx) or 84)
  local ny       = math.floor(tonumber(device.preferences.gridNy) or 95)
  local debug    = device.preferences.enableDebugLog == true

  if ip == "" then
    log.warn("[rain/snow] bridgeIp not set, skipping")
    return
  end
  if api_key == "" then
    log.warn("[rain/snow] apiKey not set, skipping")
    return
  end

  log.info(string.format("[rain/snow] connecting to bridge: %s:%d", ip, port))
  local url = build_weather_url(api_key, nx, ny)
  if debug then log.info("[rain/snow] request url: " .. url) end

  cosock.spawn(function()
    local parsed, err = bridge_api.forward(ip, port, url, nil)

    -- ── 오류 처리 ──────────────────────────────────────────────────────
    if not parsed then
      log.warn("[rain/snow] fetch failed: " .. tostring(err))
      pcall(device.emit_event, device, capabilities.healthCheck.healthStatus("offline"))
      return
    end

    -- ── 기상청 특유의 에러 메시지 체크 ──────────────────────────────────
    if parsed.response and parsed.response.header and parsed.response.header.resultCode ~= "00" then
      log.warn(string.format("[rain/snow] API Error: %s (%s)",
        tostring(parsed.response.header.resultCode),
        tostring(parsed.response.header.resultMsg)))
      pcall(device.emit_event, device, capabilities.healthCheck.healthStatus("offline"))
      return
    end

    -- ── 응답 구조 확인 ─────────────────────────────────────────────────
    local ok, items = pcall(function()
      return parsed.response.body.items.item
    end)
    
    if not ok or type(items) ~= "table" then
      log.warn("[rain/snow] unexpected API response structure or no data")
      if debug and parsed then log.info("[rain/snow] response body: " .. tostring(parsed)) end
      pcall(device.emit_event, device, capabilities.healthCheck.healthStatus("offline"))
      return
    end

    -- ── PTY, RN1, SKY 추출 ────────────────────────────────────────────
    local pty = 0
    local rn1 = 0
    local sky = 1  -- 기본값: 맑음
    local t1h = nil  -- 기온 (°C)
    local reh = nil  -- 습도 (%)
    for _, item in ipairs(items) do
      if item.category == "PTY" then
        pty = tonumber(item.obsrValue) or 0
      elseif item.category == "RN1" then
        rn1 = tonumber(item.obsrValue) or 0
      elseif item.category == "SKY" then
        sky = tonumber(item.obsrValue) or 1
      elseif item.category == "T1H" then
        t1h = tonumber(item.obsrValue)
      elseif item.category == "REH" then
        reh = tonumber(item.obsrValue)
      end
    end

    local raining = is_precipitation(pty, rn1)
    local label   = get_weather_label(sky, pty, rn1)

    log.info(string.format("[rain/snow] SKY=%d PTY=%d RN1=%.1f T1H=%s REH=%s → %s (raining=%s)",
      sky, pty, rn1, tostring(t1h), tostring(reh), label, tostring(raining)))

    -- ── 이벤트 발행 ────────────────────────────────────────────────────
    -- waterSensor: 자동화 룰 조건용 (PTY>0 AND RN1>0.1mm 일 때만 wet)
    local ws = capabilities.waterSensor
    if raining then
      pcall(device.emit_event, device, ws.water.wet())
    else
      pcall(device.emit_event, device, ws.water.dry())
    end

    -- weatherCondition: 대시보드 종합 날씨 상태 표시용
    if weatherCond and weatherCond.condition then
      pcall(device.emit_event, device, weatherCond.condition({ value = label }))
    end

    -- temperatureMeasurement: 기온 (자동화 조건용, 대시보드 미표시)
    if t1h ~= nil then
      pcall(device.emit_event, device,
        capabilities.temperatureMeasurement.temperature({ value = t1h, unit = "C" }))
    end

    -- reasonmusic47804.outdoorHumidity: 실외 습도 (자동화 조건용, 습도 탭 미분류)
    local outdoorHumidity = capabilities["reasonmusic47804.outdoorHumidity"]
    if reh ~= nil and outdoorHumidity and outdoorHumidity.humidity then
      pcall(device.emit_event, device,
        outdoorHumidity.humidity({ value = reh, unit = "%" }))
    end

    pcall(device.emit_event, device, capabilities.healthCheck.healthStatus("online"))
  end, "rain-snow-fetch")
end

-- ──────────────────────────────────────────────────────────────────────────
-- 타이머 재시작 헬퍼
-- ──────────────────────────────────────────────────────────────────────────
local function restart_timer(device)
  local old_timer = device:get_field("weather_timer")
  if old_timer then
    pcall(function() device.thread:cancel_timer(old_timer) end)
  end

  local interval_min = tonumber(device.preferences.pollInterval) or DEFAULT_INTERVAL
  local interval_sec = math.max(60, interval_min * 60)

  local timer = device.thread:call_on_schedule(interval_sec, function()
    fetch_weather_and_emit(device)
  end)
  device:set_field("weather_timer", timer)
  log.info(string.format("[weather] polling every %d sec", interval_sec))
end

-- ──────────────────────────────────────────────────────────────────────────
-- Lifecycle
-- ──────────────────────────────────────────────────────────────────────────
local function device_init(driver, device)
  log.info("[rain/snow] device_init: " .. device.device_network_id)
  fetch_weather_and_emit(device)
  restart_timer(device)
end

local function device_removed(driver, device)
  log.info("[rain/snow] device_removed: " .. device.device_network_id)
  local timer = device:get_field("weather_timer")
  if timer then pcall(function() device.thread:cancel_timer(timer) end) end
end

local function info_changed(driver, device, event, args)
  log.info("[rain/snow] preferences changed, re-fetching")
  fetch_weather_and_emit(device)
  restart_timer(device)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Capability handler: refresh
-- ──────────────────────────────────────────────────────────────────────────
local function handle_refresh(driver, device, cmd)
  fetch_weather_and_emit(device)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Driver
-- ──────────────────────────────────────────────────────────────────────────
local driver = Driver("Rain/Snow Tracker", {
  discovery = discovery.handle_discovery,

  lifecycle_handlers = {
    init        = device_init,
    removed     = device_removed,
    infoChanged = info_changed,
  },

  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
  },
})

log.info("[rain/snow] Rain/Snow Tracker driver starting")
driver:run()
