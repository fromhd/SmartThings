-- discovery.lua  (v2 — hotplug 방식)
local log = require "log"
local M   = {}

local DNI = "wifi-presence-family-v2"

local function device_exists(driver)
  for _, d in ipairs(driver:get_devices()) do
    if d.device_network_id == DNI then return true end
  end
  return false
end

function M.handle_discovery(driver, opts, cons)
  log.info("[wifi-presence-v2] discovery called")
  if not device_exists(driver) then
    log.info("[wifi-presence-v2] creating family presence v2 device")
    driver:try_create_device({
      type                  = "LAN",
      device_network_id     = DNI,
      label                 = "Family Presence v2",
      profile               = "main",
      manufacturer          = "SmartThings-OpenWRT",
      model                 = "WifiPresenceSensor-v2",
      vendor_provided_label = "Family Presence v2",
    })
  else
    log.info("[wifi-presence-v2] device already exists")
  end
end

return M
