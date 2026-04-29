-- discovery.lua  (Weather Tracker)
--
-- DNI format: weather-tracker:<slot>
-- On first install creates one device. Additional devices via addNewDevice pref.

local log = require "log"
local M   = {}

local DEVICE_PREFIX = "weather-tracker:"

local function make_dni(slot)
  return DEVICE_PREFIX .. tostring(slot)
end

local function find_max_slot(driver)
  local max_slot = 0
  for _, d in ipairs(driver:get_devices()) do
    local dni = d.device_network_id or ""
    local n = tonumber(dni:match("^weather%-tracker:(%d+)$"))
    if n and n > max_slot then max_slot = n end
  end
  return max_slot
end

local function create_device(driver, slot)
  local dni = make_dni(slot)
  log.info("[weather] creating device: " .. dni)
  driver:try_create_device({
    type                  = "LAN",
    device_network_id     = dni,
    label                 = "Weather Tracker",
    profile               = "main",
    manufacturer          = "SmartThings",
    model                 = "Weather Tracker",
    vendor_provided_label = "Weather Tracker",
  })
end

function M.add_setup_device(driver)
  create_device(driver, find_max_slot(driver) + 1)
end

function M.handle_discovery(driver, opts, cons)
  if find_max_slot(driver) == 0 then
    log.info("[weather] first install, creating slot 1")
    create_device(driver, 1)
  end
end

return M
