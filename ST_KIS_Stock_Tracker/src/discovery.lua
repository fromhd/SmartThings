-- discovery.lua
--
-- On first install, create one device (in the "setup" profile) so the user
-- has something to tap. After onboarding completes, the user can spawn
-- additional setup devices on the same hub via the `addNewDevice`
-- preference toggle in the main profile.
--
-- DNI format: edgebridge-base:<slot>
-- where <slot> is auto-incremented (max existing slot + 1).

local log = require "log"

local M = {}

local DEVICE_PREFIX = "hs-stock-tracker:"

local function make_dni(slot)
  return DEVICE_PREFIX .. tostring(slot)
end

local function find_max_slot(driver)
  local max_slot = 0
  for _, d in ipairs(driver:get_devices()) do
    local dni = d.device_network_id or ""
    local n = tonumber(dni:match("^hs%-stock%-tracker:(%d+)$"))
    if n and n > max_slot then max_slot = n end
  end
  return max_slot
end

local function create_device(driver, slot)
  local dni = make_dni(slot)
  log.info("[edgebridge][discovery] creating: " .. dni)
  driver:try_create_device({
    type              = "LAN",
    device_network_id = dni,
    label             = "KIS Stock Tracker",
    profile           = "main",
    manufacturer      = "SmartThings",
    model             = "Stock Tracker",
    vendor_provided_label = "KIS Stock Tracker",
  })
end

-- Called from main-profile info_changed when the user flips addNewDevice ON.
-- Spawns a fresh setup-profile device, leaving the existing device alone.
function M.add_setup_device(driver)
  create_device(driver, find_max_slot(driver) + 1)
end

-- Called once on driver install if the user has zero devices.
function M.handle_discovery(driver, opts, cons)
  if #driver:get_devices() == 0 then
    log.info("[edgebridge][discovery] first install, creating slot 1")
    create_device(driver, 1)
  end
end

return M
