-- init.lua  (Wi-Fi Presence Sensor v2 — hotplug + uhttpd 방식)
-- 공유기가 /www/presence.json 파일을 관리하고
-- 허브가 주기적으로 폴링합니다 (상주 Python 프로세스 없음)
local Driver       = require "st.driver"
local capabilities = require "st.capabilities"
local cosock       = require "cosock"
local log          = require "log"

local discovery    = require "discovery"

-- person ID → 컴포넌트 ID 매핑
local ID_TO_COMPONENT = {
  Diego   = "diego",
  Jinee   = "jinee",
  YooJoo  = "yoojoo",
  HyukJoo = "hyukjoo",
}

local presence_cache = {
  Diego   = false,
  Jinee   = false,
  YooJoo  = false,
  HyukJoo = false,
}

----------------------------------------------------------------------------
-- uhttpd가 서빙하는 /presence.json 폴링
-- URL: http://<openwrt_ip>/presence.json
----------------------------------------------------------------------------
local function poll_presence(driver, device)
  local ip   = device.preferences.openwrtIp or "192.168.1.1"
  local port = 80   -- uhttpd 기본 포트

  cosock.spawn(function()
    local sock, err = cosock.socket.tcp()
    if not sock then
      log.warn("[wifi-presence-v2] socket 실패: " .. tostring(err))
      return
    end
    sock:settimeout(10)
    local ok, cerr = sock:connect(ip, port)
    if not ok then
      log.warn("[wifi-presence-v2] 연결 실패: " .. tostring(cerr))
      sock:close()
      return
    end

    sock:send("GET /presence.json HTTP/1.0\r\nHost: " .. ip .. "\r\n\r\n")

    local chunks = {}
    while true do
      local chunk, _, partial = sock:receive(4096)
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
    if not sep then return end
    body = body:sub(sep + 4)

    log.info("[wifi-presence-v2] " .. body)

    local anyone_home = false
    for name, comp_id in pairs(ID_TO_COMPONENT) do
      local status = body:match('"' .. name .. '"%s*:%s*"([^"]+)"')
      if status then
        local is_present = (status == "present")
        presence_cache[name] = is_present
        if is_present then anyone_home = true end

        local comp = device.profile.components[comp_id]
        if comp then
          device:emit_component_event(comp,
            is_present
              and capabilities.presenceSensor.presence.present()
              or  capabilities.presenceSensor.presence.not_present()
          )
        end
      end
    end

    -- 캐시 재확인 (누군가라도 있으면)
    for _, v in pairs(presence_cache) do
      if v then anyone_home = true end
    end

    local home_comp = device.profile.components["main"]
    if home_comp then
      device:emit_component_event(home_comp,
        anyone_home
          and capabilities.presenceSensor.presence.present()
          or  capabilities.presenceSensor.presence.not_present()
      )
    end
    log.info("[wifi-presence-v2] 집 재실 → " .. (anyone_home and "present" or "not_present"))

  end, "presence_poll_v2")
end

----------------------------------------------------------------------------
-- 라이프사이클
----------------------------------------------------------------------------
local function device_init(driver, device)
  log.info("[wifi-presence-v2] init")
  poll_presence(driver, device)

  local interval = tonumber(device.preferences.pollInterval) or 60
  local timer = device.thread:call_on_schedule(interval, function()
    poll_presence(driver, device)
  end)
  device:set_field("poll_timer", timer)
end

local function device_added(driver, device)
  log.info("[wifi-presence-v2] added")
  for _, comp_id in pairs(ID_TO_COMPONENT) do
    local comp = device.profile.components[comp_id]
    if comp then
      device:emit_component_event(comp, capabilities.presenceSensor.presence.not_present())
    end
  end
end

local function device_removed(driver, device)
  local timer = device:get_field("poll_timer")
  if timer then device.thread:cancel_timer(timer) end
end

local function info_changed(driver, device, event, args)
  poll_presence(driver, device)
end

local function handle_refresh(driver, device, cmd)
  poll_presence(driver, device)
end

----------------------------------------------------------------------------
-- 드라이버
----------------------------------------------------------------------------
local driver = Driver("ST Wifi Presence Sensor v2", {
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

log.info("[wifi-presence-v2] 드라이버 시작")
driver:run()
