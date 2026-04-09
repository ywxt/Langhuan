-- Login handler example snippet for Langhuan Lua feeds.
--
-- Usage:
-- 1) Copy the `login = { ... }` section into your feed's returned table.
-- 2) Adjust `entry.url` and parse rules to your site.
-- 3) Keep auth payload as plain table; Rust persists it as JSON.

local function trim(s)
    if s == nil then
        return ""
    end
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function find_query_param(url, key)
    if url == nil or key == nil then
        return nil
    end
    local pattern = "[?&]" .. key .. "=([^&#]+)"
    return url:match(pattern)
end

local function find_first(body, pattern)
    if body == nil then
        return nil
    end
    local value = body:match(pattern)
    if value == nil then
        return nil
    end
    local text = trim(value)
    if text == "" then
        return nil
    end
    return text
end

-- Merge this into your feed return table:
-- return {
--   search = { ... },
--   book_info = { ... },
--   chapters = { ... },
--   paragraphs = { ... },
--   login = login_handlers,
-- }

local login_handlers = {
    -- Open this URL in WebView from Flutter.
    entry = function()
        return {
            url = meta.base_url .. "/login",
            title = "Source Login",
        }
    end,

    -- Parse auth payload from WebView context.
    -- `page` shape:
    -- {
    --   current_url = "https://...",
    --   response = "<html>...</html>",
    --   response_headers = {
    --     {"Header-Name", "value"},
    --     ...
    --   },
    --   cookies = {
    --     {
    --       name = "session",
    --       value = "...",
    --       domain = "example.com" | nil,
    --       path = "/" | nil,
    --       expires = "..." | nil,
    --       secure = true | false | nil,
    --       http_only = true | false | nil,
    --       same_site = "Lax" | "Strict" | "None" | nil,
    --     },
    --     ...
    --   },
    -- }
    parse = function(page)
        local current_url = page.current_url or ""
        local response = page.response or ""
        local response_headers = page.response_headers or {}
        local cookies = page.cookies or {}

        -- Example 1: token returned in URL query after OAuth redirect.
        local token = find_query_param(current_url, "token")

        -- Example 2: session id embedded in html by the site.
        local session_id = find_first(response, 'data%-session%-id=["\']([^"\']+)["\']')

        -- Example 3: csrf meta value for subsequent API calls.
        local csrf = find_first(response, '<meta%s+name=["\']csrf%-token["\']%s+content=["\']([^"\']+)["\']')

        -- Example 4: token returned by custom response header.
        local header_token = nil
        for i = 1, #response_headers do
            local pair = response_headers[i]
            local key = pair and pair[1] or ""
            local value = pair and pair[2] or ""
            if key:lower() == "x-auth-token" and value ~= "" then
                header_token = value
                break
            end
        end

        -- Example 5: session cookie from structured cookie entries.
        local cookie_header = nil
        for i = 1, #cookies do
            local c = cookies[i]
            local name = c and c.name or ""
            local value = c and c.value or ""
            if name ~= "" then
                local item = name .. "=" .. value
                if cookie_header == nil then
                    cookie_header = item
                else
                    cookie_header = cookie_header .. "; " .. item
                end
            end
        end

        -- Return any JSON-serializable table. Rust will persist it.
        return {
            token = token,
            header_token = header_token,
            session_id = session_id,
            csrf = csrf,
            cookie_header = cookie_header,
            captured_from = current_url,
            updated_at = os.time(),
        }
    end,

    -- Called for every outbound HttpRequest after request handler returns.
    patch_request = function(context, request, auth)
        -- Context example:
        -- context.operation: search | book_info | chapters | paragraphs
        -- context.feed_id, context.book_id, context.chapter_id

        if request.headers == nil then
            request.headers = {}
        end

        if auth.token ~= nil and auth.token ~= "" then
            request.headers["Authorization"] = "Bearer " .. auth.token
        elseif auth.header_token ~= nil and auth.header_token ~= "" then
            request.headers["Authorization"] = "Bearer " .. auth.header_token
        end

        if auth.session_id ~= nil and auth.session_id ~= "" then
            request.headers["Cookie"] = "session_id=" .. auth.session_id
        elseif auth.cookie_header ~= nil and auth.cookie_header ~= "" then
            request.headers["Cookie"] = auth.cookie_header
        end

        if auth.csrf ~= nil and auth.csrf ~= "" then
            request.headers["X-CSRF-Token"] = auth.csrf
        end

        -- You can branch by operation if needed.
        if context.operation == "search" then
            request.headers["X-Feed-Operation"] = "search"
        end

        return request
    end,
}

return {
    login = login_handlers,
}
