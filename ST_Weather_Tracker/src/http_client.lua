-- http_client.lua
--
-- Minimal HTTP/1.0 client built on cosock TCP sockets.
--
-- Why a custom client instead of `cosock.asyncify("socket.http")`?
--   * On some hubs, the SDK-bundled socket.http reuses connections in ways
--     that break long polling against a small LAN bridge.
--   * HTTP/1.0 + Connection: close (server's default) lets us read the body
--     "until EOF" — no Transfer-Encoding/Content-Length parsing needed.
--   * The whole client is small enough to read top-to-bottom in one sitting,
--     which is the point of this sample.
--
-- This module exposes ONE function: request(method, host, port, path, body, headers).
-- All higher-level wrappers (ping, forward, redirect, callback) live in bridge_api.lua.

local cosock = require "cosock"
local log    = require "log"

local TIMEOUT = 10  -- seconds; overridden by callers when needed

local M = {}

-- Returns: status_code (number, 0 on transport failure), body (string), err (string|nil)
function M.request(method, host, port, path, body_str, req_headers)
  local sock, err = cosock.socket.tcp()
  if not sock then return 0, "", "socket_create: " .. tostring(err) end
  sock:settimeout(TIMEOUT)

  local ok, conn_err = sock:connect(host, tonumber(port))
  if not ok then
    sock:close()
    return 0, "", "connect: " .. tostring(conn_err)
  end

  local lines = {
    string.format("%s %s HTTP/1.0", method, path),
    string.format("Host: %s:%s", host, tostring(port)),
  }
  req_headers = req_headers or {}
  for k, v in pairs(req_headers) do
    lines[#lines + 1] = k .. ": " .. v
  end
  if body_str and #body_str > 0 then
    lines[#lines + 1] = "Content-Length: " .. #body_str
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = body_str or ""

  local _, send_err = sock:send(table.concat(lines, "\r\n"))
  if send_err then
    sock:close()
    return 0, "", "send: " .. tostring(send_err)
  end

  -- Read until the server closes the connection. LuaSocket returns
  -- (nil, "closed", partial) on normal end; collect any partial bytes.
  local chunks = {}
  while true do
    local chunk, recv_err, partial = sock:receive(4096)
    if chunk then
      chunks[#chunks + 1] = chunk
    else
      if partial and #partial > 0 then chunks[#chunks + 1] = partial end
      break
    end
  end
  sock:close()

  local full = table.concat(chunks)
  if full == "" then return 0, "", "empty_response" end

  local sep = full:find("\r\n\r\n", 1, true)
  if not sep then return 0, "", "no_header_separator" end

  local code = tonumber(full:match("^HTTP/%S+ (%d+)")) or 0
  local body = full:sub(sep + 4)

  if code == 0 then
    log.warn("[edgebridge][http] unparseable status line: " .. full:sub(1, 80))
  end
  return code, body, nil
end

return M
