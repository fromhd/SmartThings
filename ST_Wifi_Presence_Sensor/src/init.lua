-- init.lua  (Wi-Fi Presence Sensor - Polling Version)
-- 허브가 OpenWRT HTTP 서버를 폴링하는 구조 (안정적)
local Driver       = require "st.driver"
local capabilities = require "st.capabilities"
local cosock       = require "cosock"
local log          = require "log"

local discovery    = require "discovery"

-- person ID → 컴포넌트 ID 매핑 (main은 "집 재실" 전용)
local ID_TO_COMPONENT = {
  Diego   = "diego",
  Jinee   = "jinee",
  YooJoo  = "yoojoo",
  HyukJoo = "hyukjoo",
}

-- 현재 재실 상태 캐시
local presence_cache = {
  Diego   = false,
  Jinee   = false,
  YooJoo  = false,
  HyukJoo = false,
}

----------------------------------------------------------------------------
-- OpenWRT HTTP 서버에서 재실 상태 폴링
----------------------------------------------------------------------------
local function poll_presence(driver, device)
  local ip   = device.preferences.openwrtIp   or "192.168.1.1"
  local port = tonumber(device.preferences.openwrtPort) or 8091

  cosock.spawn(function()
    local sock, err = cosock.socket.tcp()
    if not sock then
      log.warn("[wifi-presence] socket 생성 실패: " .. tostring(err))
      return
    end
    sock:settimeout(10)
    local ok, cerr = sock:connect(ip, port)
    if not ok then
      log.warn("[wifi-presence] 연결 실패 " .. ip .. ":" .. port .. " - " .. tostring(cerr))
      sock:close()
      return
    end

    sock:send("GET /status HTTP/1.0\r\nHost: " .. ip .. "\r\n\r\n")

    local chunks = {}
    while true do
      local chunk, rerr, partial = sock:receive(4096)
      if chunk then
        chunks[#chunks+1] = chunk
      else
        if partial and #partial > 0 then chunks[#chunks+1] = partial end
        break
      end
    end
    sock:close()

    local body = table.concat(chunks)
    local sep = body:find("\r\n\r\n", 1, true)
    if not sep then
      log.warn("[wifi-presence] 응답 파싱 실패")
      return
    end
    body = body:sub(sep + 4)
    log.info("[wifi-presence] 응답: " .. body)

    -- 개인별 상태 업데이트
    local anyone_home = false
    for name, comp_id in pairs(ID_TO_COMPONENT) do
      local status = body:match('"' .. name .. '"%s*:%s*"([^"]+)"')
      if status then
        local is_present = (status == "present")
        presence_cache[name] = is_present
        if is_present then anyone_home = true end

        local comp = device.profile.components[comp_id]
        if comp then
          local event = is_present
            and capabilities.presenceSensor.presence.present()
            or  capabilities.presenceSensor.presence.not_present()
          device:emit_component_event(comp, event)
          log.info(string.format("[wifi-presence] %s → %s", name, status))
        end
      end
    end

    -- 캐시 기준으로 "집 재실" (1명이라도 있으면 present)
    for _, v in pairs(presence_cache) do
      if v then anyone_home = true end
    end

    local home_comp = device.profile.components["main"]
    if home_comp then
      local home_event = anyone_home
        and capabilities.presenceSensor.presence.present()
        or  capabilities.presenceSensor.presence.not_present()
      device:emit_component_event(home_comp, home_event)
      log.info("[wifi-presence] 집 재실 → " .. (anyone_home and "present" or "not_present"))
    end

  end, "presence_poll")
end

----------------------------------------------------------------------------
-- 라이프사이클
----------------------------------------------------------------------------
local function device_init(driver, device)
  log.info("[wifi-presence] init: " .. tostring(device.label))

  -- 즉시 1회 폴링
  poll_presence(driver, device)

  -- 주기적 폴링 타이머
  local interval = tonumber(device.preferences.pollInterval) or 30
  local timer = device.thread:call_on_schedule(interval, function()
    poll_presence(driver, device)
  end)
  device:set_field("poll_timer", timer)
end

local function device_added(driver, device)
  log.info("[wifi-presence] added: " .. tostring(device.label))
  for _, comp_id in pairs(ID_TO_COMPONENT) do
    local comp = device.profile.components[comp_id]
    if comp then
      device:emit_component_event(comp, capabilities.presenceSensor.presence.not_present())
    end
  end
end

local function device_removed(driver, device)
  log.info("[wifi-presence] removed: " .. tostring(device.label))
  local timer = device:get_field("poll_timer")
  if timer then device.thread:cancel_timer(timer) end
end

local function info_changed(driver, device, event, args)
  poll_presence(driver, device)
end

local function handle_refresh(driver, device, cmd)
  log.info("[wifi-presence] refresh")
  poll_presence(driver, device)
end

----------------------------------------------------------------------------
-- 드라이버
----------------------------------------------------------------------------
local driver = Driver("ST Wifi Presence Sensor", {
  discovery = discovery.handle_discovery,
  lifecycle_handlers = {
    init        = device_init,
    added       = device_added,
    removed     = device_removed,
    infoChanged = info_changed,
  },
  capability_handlers = {
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
  },
})

log.info("[wifi-presence] 드라이버 시작")
driver:run()
