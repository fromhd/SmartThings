-- bridge_api.lua
--
-- Wrappers for the EdgeBridge / AndroidEdgeBridge HTTP API. This is the file
-- you copy-and-paste into your own driver and adapt.
--
-- Compatibility:
--   * /api/ping, /api/forward, /api/redirect work on BOTH Todd Austin's
--     original EdgeBridge AND on AndroidEdgeBridge.
--   * /api/callback is AndroidEdgeBridge ONLY. Calling it against the
--     original EdgeBridge returns 404. Use ping() to detect which variant
--     you're talking to (the AEB ping response includes a `bridgeDevice`
--     field; the original does not).

local log    = require "log"
local json   = require "dkjson"
local http   = require "http_client"

local M = {}

-- Percent-encode a single URL component (RFC 3986 unreserved set).
local function urlencode(s)
  return (tostring(s):gsub("([^%w%-%_%.%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

----------------------------------------------------------------------------
-- ping(ip, port)
--
-- Health check. POSTs /api/ping.
--
-- "Alive" requires ALL of:
--   1. TCP connect succeeds within ~10 seconds
--   2. HTTP status code == 200
--
-- Body content is intentionally NOT validated:
--   * Todd Austin's original EdgeBridge returns an empty body (200 OK).
--   * AndroidEdgeBridge returns a JSON payload with version/battery/etc.
-- Both are healthy. We parse the body if it happens to be JSON so callers
-- can inspect it (see detect_variant), but a missing/empty body is fine.
--
-- Any transport/HTTP failure returns (nil, reason). The reason string is a
-- coarse category: "connect_refused" | "timeout" | "http_<code>"
--
-- Example call (against AEB):
--   curl -X POST http://192.168.1.50:8088/api/ping
--   -> {"bridgeVersion":"0.0.7", "bridgeDevice":"AndroidEdgeBridge", ...}
-- Against Todd's EdgeBridge:
--   curl -X POST http://192.168.1.50:8088/api/ping
--   -> (empty body, HTTP 200)
----------------------------------------------------------------------------
function M.ping(ip, port)
  local code, body, err = http.request("POST", ip, port, "/api/ping", "", nil)
  if code == 0 then
    -- Translate transport errors into a small set of categories.
    local reason = "connect_refused"
    if err and err:find("timeout", 1, true) then reason = "timeout" end
    return nil, reason
  end
  if code ~= 200 then return nil, "http_" .. tostring(code) end

  -- Best-effort JSON parse. Empty body or non-JSON is fine -- still alive.
  local parsed = json.decode(body or "")
  return (type(parsed) == "table") and parsed or {}, nil
end

-- Convenience: returns "aeb" | "edgebridge" | nil based on a ping response.
-- AndroidEdgeBridge sets `bridgeDevice` in its ping payload; the original
-- EdgeBridge does not. Callers use this to gate AEB-only features (callback).
function M.detect_variant(ping_response)
  if type(ping_response) ~= "table" then return nil end
  if ping_response.bridgeDevice then return "aeb" end
  return "edgebridge"
end

----------------------------------------------------------------------------
-- forward(ip, port, target_url, headers)
--
-- Ask the bridge to fetch <target_url> and return the response. Useful when
-- the hub can't reach the WAN directly, or you want centralized rate
-- limiting / header injection at the bridge layer.
--
-- Example call:
--   GET http://<bridge>:<port>/api/forward?url=https://httpbin.org/get
--
-- This sample returns the parsed JSON body. For non-JSON responses, see
-- the raw `http.request` underneath.
----------------------------------------------------------------------------
function M.forward(ip, port, target_url, headers)
  local path = "/api/forward?url=" .. target_url  -- bridge expects the URL raw
  local code, body, err = http.request("GET", ip, port, path, nil, headers)
  if code == 0 then return nil, err or "transport" end
  if code ~= 200 then return nil, "http_" .. tostring(code) end
  local parsed, _, jerr = json.decode(body)
  if jerr then return nil, "json_parse" end
  return parsed, nil
end

----------------------------------------------------------------------------
-- forward_with_token(ip, port, target_url, token)
--
-- SAMPLE: same as forward(), but injects an `Authorization: Bearer <token>`
-- header. The demo HTML uses this to round-trip a sample token through
-- httpbin.org/headers and confirm that:
--   (a) the bridge passes Authorization headers through unmodified, and
--   (b) UTF-8 / non-ASCII tokens survive the round-trip intact.
--
-- Replace `target_url` with your actual API endpoint when adapting.
----------------------------------------------------------------------------
function M.forward_with_token(ip, port, target_url, token)
  return M.forward(ip, port, target_url, { ["Authorization"] = "Bearer " .. tostring(token or "") })
end

----------------------------------------------------------------------------
-- register_redirect(ip, port, path, target_url)
--
-- Tell the bridge: "anyone hitting http://<bridge>:<port><path> should be
-- proxied to <target_url>". The bridge stores this mapping in memory.
--
-- Why this matters here:
--   The driver's in-hub HTTP server (setup_server.lua) binds to an
--   *ephemeral* port chosen by the hub. That port can change across hub
--   restarts or LAN config changes. Showing that volatile URL directly on
--   the setup card would break user bookmarks.
--
--   So we register a STABLE path on the bridge ("/sample") that always
--   redirects to wherever the hub's HTTP server currently lives.
--   Users see http://<bridge>:8088/sample — same URL forever.
--
-- Idempotency: re-registering the same path overwrites the old target. The
-- driver caches a session_key in a device field so repeated lifecycle
-- callbacks don't spam the bridge.
--
-- Example call:
--   POST http://<bridge>:8088/api/redirect?path=/sample
--                                          &target=http://192.168.1.10:43215/
----------------------------------------------------------------------------
function M.register_redirect(ip, port, path, target_url)
  local qs = "/api/redirect?path=" .. urlencode(path)
                          .. "&target=" .. urlencode(target_url)
  local code, body, err = http.request("POST", ip, port, qs, "", nil)
  if code == 0 then
    log.warn("[edgebridge][redirect] transport: " .. tostring(err))
    return false, err or "transport"
  end
  if code ~= 200 then
    log.warn(string.format("[edgebridge][redirect] http %d: %s", code, body:sub(1, 120)))
    return false, "http_" .. tostring(code)
  end
  log.info("[edgebridge][redirect] registered " .. path .. " -> " .. target_url)
  return true, nil
end

----------------------------------------------------------------------------
-- delete_redirect(ip, port, path)  (cleanup helper)
----------------------------------------------------------------------------
function M.delete_redirect(ip, port, path)
  local qs = "/api/redirect?path=" .. urlencode(path)
  local code = http.request("DELETE", ip, port, qs, "", nil)
  return code == 200
end

----------------------------------------------------------------------------
-- register_callback(ip, port, name, value)              -- AEB ONLY
-- read_callback(ip, port, name)                         -- AEB ONLY
--
-- AndroidEdgeBridge stores a string value under <name>. Anyone on the LAN
-- who can hit the bridge can POST to update it, or GET to read it back.
-- Useful for one-way data drops from external scripts/webhooks into your
-- driver (the driver polls /api/callback/<name>).
--
-- Original EdgeBridge does NOT implement these endpoints — calls return
-- HTTP 404. Callers should run ping() first and check detect_variant() ==
-- "aeb" before invoking.
--
-- Example calls:
--   POST http://<bridge>:8088/api/callback?name=demo  body: {"value":"hello"}
--   GET  http://<bridge>:8088/api/callback/demo
--   ->   {"value":"hello"}
----------------------------------------------------------------------------
function M.register_callback(ip, port, name, value)
  local qs = "/api/callback?name=" .. urlencode(name)
  local body_str = json.encode({ value = tostring(value or "") })
  local code, body = http.request("POST", ip, port, qs, body_str,
    { ["Content-Type"] = "application/json" })
  if code == 200 then return true, nil end
  if code == 404 then return false, "not_supported" end  -- not AEB
  return false, "http_" .. tostring(code)
end

function M.read_callback(ip, port, name)
  local code, body = http.request("GET", ip, port, "/api/callback/" .. urlencode(name), nil, nil)
  if code == 200 then
    local parsed, _, jerr = json.decode(body)
    if jerr then return nil, "json_parse" end
    return parsed, nil
  end
  if code == 404 then return nil, "not_supported" end  -- not AEB, or no such name
  return nil, "http_" .. tostring(code)
end

return M
