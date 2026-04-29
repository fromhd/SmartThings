-- init.lua  (Naver Stock Tracker)
local Driver       = require "st.driver"
local capabilities = require "st.capabilities"
local cosock       = require "cosock"
local log          = require "log"

local bridge_api   = require "bridge_api"
local discovery    = require "discovery"

local DEFAULT_PORT = 8088

-- ──────────────────────────────────────────────────────────────────────────
-- Market label helper
-- ──────────────────────────────────────────────────────────────────────────
local function get_market_label()
  local kst  = os.date("!*t", os.time() + (9 * 3600))
  local hour = kst.hour
  if (hour >= 8 and hour < 9) or (hour >= 16 and hour < 20) then
    return "NXT"
  end
  return "KRX"
end

-- ──────────────────────────────────────────────────────────────────────────
-- Fetch & emit
-- ──────────────────────────────────────────────────────────────────────────
local function fetch_stock_data_and_emit(device)
  local ip        = device.preferences.bridgeIp   or ""
  local port      = tonumber(device.preferences.bridgePort) or DEFAULT_PORT
  local stockCode = device.preferences.stockCode  or "064350"
  local avgPrice  = tonumber(device.preferences.avgPrice) or 100000

  if ip == "" then
    log.warn("[naver-stock] bridge IP not set, skipping fetch")
    return
  end

  local url = "https://polling.finance.naver.com/api/realtime/domestic/stock/" .. stockCode

  cosock.spawn(function()
    local parsed, err = bridge_api.forward(ip, port, url, nil)
    if not parsed or not parsed.datas or not parsed.datas[1] then
      log.warn("[naver-stock] fetch failed: " .. tostring(err))
      pcall(device.emit_event, device, capabilities.healthCheck.healthStatus("offline"))
      return
    end

    local data      = parsed.datas[1]
    local name      = data.stockName or stockCode
    local price_str = data.closePrice or "0"

    local market_label = get_market_label()
    if market_label == "NXT"
      and data.overMarketPriceInfo
      and data.overMarketPriceInfo.overPrice then
      price_str = data.overMarketPriceInfo.overPrice
    end

    local raw_price = tonumber((string.gsub(price_str, ",", ""))) or 0
    local percentage = 0
    if avgPrice > 0 then
      percentage = math.floor(((raw_price - avgPrice) / avgPrice) * 1000 + 0.5) / 10
    end

    local price_text = string.format("%s: %s원", name, price_str)

    log.info(string.format("[naver-stock] %s | %s원 | %s%% | %s",
      name, price_str, percentage, market_label))

    local capPrice  = capabilities["reasonmusic47804.stockPrice"]
    local capMarket = capabilities["reasonmusic47804.stockMarket"]
    local capYield  = capabilities["reasonmusic47804.stockYield"]
    local capRaw    = capabilities["reasonmusic47804.stockRawPrice"]

    if capPrice  then local e = capPrice.price(price_text);        e.state_change = true; device:emit_event(e) end
    if capMarket then local e = capMarket.market(market_label);    e.state_change = true; device:emit_event(e) end
    if capYield  then local e = capYield.yield(percentage);        e.state_change = true; device:emit_event(e) end
    if capRaw    then local e = capRaw.rawPrice(raw_price);        e.state_change = true; device:emit_event(e) end

    device:emit_event(capabilities.healthCheck.healthStatus("online"))
  end, "naver-stock-fetch")
end

-- ──────────────────────────────────────────────────────────────────────────
-- Lifecycle handlers
-- ──────────────────────────────────────────────────────────────────────────
local function device_init(driver, device)
  log.info("[naver-stock] device_init: " .. device.device_network_id)

  fetch_stock_data_and_emit(device)

  local interval = tonumber(device.preferences.pollInterval) or 10
  local timer = device.thread:call_on_schedule(interval, function()
    fetch_stock_data_and_emit(device)
  end)
  device:set_field("stock_timer", timer)
end

local function device_removed(driver, device)
  log.info("[naver-stock] device_removed: " .. device.device_network_id)
  local timer = device:get_field("stock_timer")
  if timer then device.thread:cancel_timer(timer) end
end

local function info_changed(driver, device, event, args)
  fetch_stock_data_and_emit(device)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Capability handlers
-- ──────────────────────────────────────────────────────────────────────────
local function handle_refresh(driver, device, cmd)
  fetch_stock_data_and_emit(device)
end

-- ──────────────────────────────────────────────────────────────────────────
-- Driver
-- ──────────────────────────────────────────────────────────────────────────
local driver = Driver("Naver Stock Tracker", {
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

log.info("[naver-stock] Naver Stock Tracker driver starting")
driver:run()
