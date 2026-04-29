-- bridge_api.lua
local log    = require "log"
local json   = require "dkjson"
local http   = require "http_client"

local M = {}

-- ──────────────────────────────────────────────────────────────────────────
-- URL Encoding Helpers
-- ──────────────────────────────────────────────────────────────────────────

-- Percent-encode a single URL component (RFC 3986 unreserved set).
local function urlencode(s)
  return (tostring(s):gsub("([^%w%-%_%.%~])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- "Minimal" encode for a complete URL that may already contain %-escapes.
local function urlencode_url(s)
  return (tostring(s):gsub("([^%w%-%_%.%~:/?=&#%%+@,;!$'()])", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

-- ──────────────────────────────────────────────────────────────────────────
-- Public API
-- ──────────────────────────────────────────────────────────────────────────

function M.ping(ip, port)
  local code, body, err = http.request("POST", ip, port, "/api/ping", "", nil)
  if code == 0 then
    local reason = "connect_refused"
    if err and err:find("timeout", 1, true) then reason = "timeout" end
    return nil, reason
  end
  if code ~= 200 then return nil, "http_" .. tostring(code) end
  local parsed = json.decode(body or "")
  return (type(parsed) == "table") and parsed or {}, nil
end

function M.detect_variant(ping_response)
  if type(ping_response) ~= "table" then return nil end
  if ping_response.bridgeDevice then return "aeb" end
  return "edgebridge"
end

----------------------------------------------------------------------------
-- forward(ip, port, target_url, headers, method, body)
----------------------------------------------------------------------------
function M.forward(ip, port, target_url, headers, method, body)
  method = method or "GET"
  -- 인코딩 없이 원본 URL 그대로 전달 시도
  local path = "/api/forward?url=" .. target_url
  
  local code, resp_body, err = http.request(method, ip, port, path, body, headers)
  
  if code == 0 then return nil, err or "transport" end
  if code ~= 200 then return nil, "http_" .. tostring(code), resp_body end
  
  local parsed, _, jerr = json.decode(resp_body)
  if jerr then return nil, "json_parse" end
  return parsed, nil
end

function M.forward_with_token(ip, port, target_url, token)
  return M.forward(ip, port, target_url, { ["Authorization"] = "Bearer " .. tostring(token or "") })
end

function M.register_redirect(ip, port, path, target_url)
  local qs = "/api/redirect?path=" .. urlencode(path)
                          .. "&target=" .. urlencode(target_url)
  local code, body, err = http.request("POST", ip, port, qs, "", nil)
  if code == 0 then return false, err or "transport" end
  if code ~= 200 then return false, "http_" .. tostring(code) end
  return true, nil
end

function M.delete_redirect(ip, port, path)
  local qs = "/api/redirect?path=" .. urlencode(path)
  local code = http.request("DELETE", ip, port, qs, "", nil)
  return code == 200
end

return M
