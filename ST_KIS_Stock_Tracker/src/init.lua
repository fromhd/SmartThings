-- init.lua
local Driver       = require "st.driver"
local capabilities = require "st.capabilities"
local cosock       = require "cosock"
local bridge_api   = require "bridge_api"
local json         = require "dkjson"
local log          = require "log"

local discovery    = require "discovery"

-- Helper to format numbers with commas
local function format_commas(amount)
  local formatted = tostring(amount)
  while true do  
    formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
    if (k==0) then
      break
    end
  end
  return formatted
end

local function fetch_stock_data_and_emit(device)
  local domain = device.preferences.serverDomain or ""
  local port = device.preferences.serverPort or "9595"
  local bridgeIp = device.preferences.bridgeIp or ""
  local bridgePort = tonumber(device.preferences.bridgePort) or 8088
  local stockCode = device.preferences.stockCode or "064350"
  local stockName = device.preferences.stockName or "현대로템"
  local avgPrice = device.preferences.avgPrice or 100000

  if domain == "" or port == "" or bridgeIp == "" then
    return
  end

  local url = string.format("http://%s:%s/price?code=%s", domain, port, stockCode)

  cosock.spawn(function()
    local data, err = bridge_api.forward(bridgeIp, bridgePort, url, nil)

    if not data or err then
      log.warn("[kis-stock-tracker] Proxy Request failed: " .. tostring(err))
      pcall(device.emit_event, device, capabilities.healthCheck.healthStatus("offline"))
      return
    end

    if not data.price then
      log.warn("[kis-stock-tracker] Missing price in response data")
      pcall(device.emit_event, device, capabilities.healthCheck.healthStatus("offline"))
      return
    end

    local price_str = tostring(data.price)
    local market_label = data.market or "KRX"

    local raw_price = tonumber(price_str) or 0
    local percentage = 0
    if avgPrice > 0 then
      percentage = ((raw_price - avgPrice) / avgPrice) * 100
      percentage = math.floor(percentage * 10 + 0.5) / 10
    end

    local price_with_comma = format_commas(raw_price)
    local price_text = string.format("%s: %s원", stockName, price_with_comma)
    
    log.info(string.format("[kis-stock-tracker] %s | Price: %s | Yield: %s%%", stockName, price_with_comma, percentage))
    
    local capPrice = capabilities["reasonmusic47804.stockPrice"]
    local capMarket = capabilities["reasonmusic47804.stockMarket"]
    local capYield = capabilities["reasonmusic47804.stockYield"]
    local capRaw = capabilities["reasonmusic47804.stockRawPrice"]
    
    if capPrice then device:emit_event(capPrice.price(price_text)) end
    if capMarket then device:emit_event(capMarket.market(market_label)) end
    if capYield then device:emit_event(capYield.yield(percentage)) end
    if capRaw then device:emit_event(capRaw.rawPrice(raw_price)) end

    device:emit_event(capabilities.healthCheck.healthStatus("online"))
  end, "stock-fetch")
end

----------------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------------

local function device_init(driver, device)
  log.info("[kis-stock-tracker] device_init: " .. device.device_network_id)

  fetch_stock_data_and_emit(device)
  
  -- Revert to 3 seconds for near real-time updates!
  local timer = device.thread:call_on_schedule(3, function()
    fetch_stock_data_and_emit(device)
  end)
  device:set_field("stock_timer", timer)
end

local function device_removed(driver, device)
  log.info("[kis-stock-tracker] device_removed: " .. device.device_network_id)
  local timer = device:get_field("stock_timer")
  if timer then
    device.thread:cancel_timer(timer)
  end
end

local function info_changed(driver, device, event, args)
  fetch_stock_data_and_emit(device)
end

----------------------------------------------------------------------------
-- Capability handlers
----------------------------------------------------------------------------

local function handle_refresh(driver, device, cmd)
  fetch_stock_data_and_emit(device)
end

----------------------------------------------------------------------------
-- Driver
----------------------------------------------------------------------------

local driver = Driver("KIS Stock Tracker", {
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

log.info("[kis-stock-tracker] KIS Stock Tracker driver starting")
driver:run()
