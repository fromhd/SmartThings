-- discovery.lua
-- Naver Stock Tracker 패턴 그대로 적용 — 장치가 없을 때만 1개 생성

local log = require "log"

local M = {}

local DNI = "wifi-presence-family"

local function device_exists(driver)
  for _, d in ipairs(driver:get_devices()) do
    if d.device_network_id == DNI then return true end
  end
  return false
end

function M.handle_discovery(driver, opts, cons)
  log.info("[wifi-presence] discovery called")
  if not device_exists(driver) then
    log.info("[wifi-presence] creating family presence device")
    driver:try_create_device({
      type                  = "LAN",
      device_network_id     = DNI,
      label                 = "Family Presence",
      profile               = "main",
      manufacturer          = "SmartThings-OpenWRT",
      model                 = "WifiPresenceSensor",
      vendor_provided_label = "Family Presence",
    })
  else
    log.info("[wifi-presence] device already exists, skipping")
  end
end

return M
