-------------------------------------------------------------------------------
-- src/engine.lua
-- Core modular runner: Discovers accounts from environment variables and
-- executes assigned Lua rule templates per account.
-------------------------------------------------------------------------------

-- Global Options
options.timeout = 120
options.subscribe = true
options.create = true
options.expunge = true

-------------------------------------------------------------------------------
-- Base64 Encoder (pure Lua, zero dependencies)
-------------------------------------------------------------------------------
local b64_chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64_encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2^i - b % 2^(i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6 - i) or 0) end
        return b64_chars:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

-------------------------------------------------------------------------------
-- File Helper Utilities
-------------------------------------------------------------------------------
local function read_file(path)
    local f = io.open(path, 'r')
    if f then
        local content = f:read('*all')
        f:close()
        return content
    end
    return nil
end

local function write_file(path, content)
    local f = io.open(path, 'w')
    if f then
        f:write(content)
        f:close()
        return true
    end
    return false
end

-------------------------------------------------------------------------------
-- ntfy Notification Subsystem
-------------------------------------------------------------------------------
local ntfy_url = os.getenv('NTFY_URL')
local ntfy_token = os.getenv('NTFY_TOKEN')
local ntfy_user = os.getenv('NTFY_USER')
local ntfy_pass = os.getenv('NTFY_PASS')
local ntfy_threshold = tonumber(os.getenv('NTFY_ERROR_THRESHOLD')) or 3

local function send_ntfy(title, message, priority, tags)
    if not ntfy_url or ntfy_url == '' then
        return
    end

    local auth_header = ''
    if ntfy_token and ntfy_token ~= '' then
        auth_header = string.format(" -H %q", string.format("Authorization: Bearer %s", ntfy_token))
    elseif ntfy_user and ntfy_user ~= '' and ntfy_pass and ntfy_pass ~= '' then
        auth_header = string.format(" -u %q:%q", ntfy_user, ntfy_pass)
    end

    local cmd = string.format(
        "curl -s -S -X POST %q%s -H %q -H %q -H %q -d %q",
        ntfy_url,
        auth_header,
        string.format("Title: %s", title or "imapfilter Alert"),
        string.format("Priority: %s", priority or "high"),
        string.format("Tags: %s", tags or "warning,email"),
        message
    )

    local status, output = pipe_from(cmd)
    if status ~= 0 then
        io.stderr:write(string.format("WARN: Failed sending ntfy notification: %s\n", tostring(output)))
    end
end

local function read_ntfy_state(acc_id)
    local path = string.format('/tokens/ntfy_state_%s.json', tostring(acc_id))
    local content = read_file(path)
    if not content then
        return { consecutive_failures = 0, alert_sent = false }
    end
    local failures = tonumber(string.match(content, '"consecutive_failures"%s*:%s*(%d+)')) or 0
    local alert_sent = string.match(content, '"alert_sent"%s*:%s*(%a+)') == 'true'
    return {
        consecutive_failures = failures,
        alert_sent = alert_sent,
    }
end

local function write_ntfy_state(acc_id, state)
    os.execute('mkdir -p /tokens')
    local path = string.format('/tokens/ntfy_state_%s.json', tostring(acc_id))
    local content = string.format(
        '{\n  "consecutive_failures": %d,\n  "alert_sent": %s\n}\n',
        state.consecutive_failures,
        state.alert_sent and 'true' or 'false'
    )
    write_file(path, content)
end

local function handle_account_error(acc, err_msg)
    local state = read_ntfy_state(acc.id)
    state.consecutive_failures = state.consecutive_failures + 1

    io.stderr:write(string.format(
        'ERROR processing %s (consecutive failures: %d, alert threshold: %d): %s\n',
        acc.name, state.consecutive_failures, ntfy_threshold, tostring(err_msg)
    ))

    -- Trigger push notification only after consecutive failures reach threshold
    if state.consecutive_failures >= ntfy_threshold and not state.alert_sent then
        print(string.format('==> Consecutive failure threshold (%d) reached for %s. Sending ntfy alert...', ntfy_threshold, acc.name))
        local title = string.format('imapfilter Alert: %s', acc.name)
        local body = string.format(
            'Account %s (%s) has failed %d consecutive times:\n\n%s',
            acc.name, acc.username, state.consecutive_failures, tostring(err_msg)
        )
        send_ntfy(title, body, 'high', 'warning,skull,email')
        state.alert_sent = true
    end

    write_ntfy_state(acc.id, state)
end

local function handle_account_success(acc)
    local state = read_ntfy_state(acc.id)
    if state.alert_sent then
        print(string.format('==> %s has recovered after prior failures. Sending ntfy recovery alert...', acc.name))
        local title = string.format('imapfilter Recovered: %s', acc.name)
        local body = string.format(
            'Account %s (%s) has successfully reconnected and resumed email processing.',
            acc.name, acc.username
        )
        send_ntfy(title, body, 'default', 'white_check_mark,email')
    end

    if state.consecutive_failures > 0 or state.alert_sent then
        state.consecutive_failures = 0
        state.alert_sent = false
        write_ntfy_state(acc.id, state)
    end
end

-------------------------------------------------------------------------------
-- Persistent Token Storage & Auto-Refresh (/tokens Named Volume)
-------------------------------------------------------------------------------
local function read_token_cache(acc_id)
    local path = string.format('/tokens/account_%s.json', tostring(acc_id))
    local content = read_file(path)
    if not content then return nil end
    local access_token = string.match(content, '"access_token"%s*:%s*"([^"]+)"')
    local expires_at = tonumber(string.match(content, '"expires_at"%s*:%s*(%d+)'))
    local refresh_token = string.match(content, '"refresh_token"%s*:%s*"([^"]+)"')
    if access_token and expires_at then
        return {
            access_token = access_token,
            expires_at = expires_at,
            refresh_token = refresh_token,
        }
    end
    return nil
end

local function write_token_cache(acc_id, access_token, expires_at, refresh_token)
    os.execute('mkdir -p /tokens')
    local path = string.format('/tokens/account_%s.json', tostring(acc_id))
    local content = string.format(
        '{\n  "access_token": %q,\n  "expires_at": %d,\n  "refresh_token": %q\n}\n',
        access_token,
        expires_at,
        refresh_token or ''
    )
    write_file(path, content)
end

local function get_oauth2_sasl(acc)
    local cached = read_token_cache(acc.id)
    local access_token = nil

    -- Use cached token if valid for at least 5 more minutes (300s)
    if cached and cached.access_token and cached.expires_at and (cached.expires_at > os.time() + 300) then
        access_token = cached.access_token
    else
        local refresh_token = (cached and cached.refresh_token and cached.refresh_token ~= '') and cached.refresh_token or acc.refresh_token
        if not refresh_token or refresh_token == '' then
            error(string.format('No refresh token available for %s. Please run "python3 scripts/get_microsoft_token.py".', acc.name))
        end

        print(string.format('    -> Refreshing OAuth2 access token for %s...', acc.name))
        local client_id = acc.client_id
        local tenant = acc.tenant
        local token_url = string.format('https://login.microsoftonline.com/%s/oauth2/v2.0/token', tenant)
        local scope = acc.scope

        local post_data = string.format(
            'client_id=%s&grant_type=refresh_token&refresh_token=%s&scope=%s',
            client_id,
            refresh_token,
            scope:gsub(' ', '%%20')
        )

        local cmd = string.format("curl -s -S -X POST %q -H 'Content-Type: application/x-www-form-urlencoded' -d %q", token_url, post_data)
        local status, resp = pipe_from(cmd)
        if status ~= 0 then
            error(string.format('OAuth2 token refresh curl request failed (status %s): %s', tostring(status), tostring(resp)))
        end

        local new_token = string.match(resp, '"access_token"%s*:%s*"([^"]+)"')
        if not new_token then
            local err_desc = string.match(resp, '"error_description"%s*:%s*"([^"]+)"') or string.match(resp, '"error"%s*:%s*"([^"]+)"') or resp
            error(string.format('OAuth2 token endpoint error: %s', err_desc))
        end

        local expires_in = tonumber(string.match(resp, '"expires_in"%s*:%s*(%d+)')) or 3600
        local updated_refresh = string.match(resp, '"refresh_token"%s*:%s*"([^"]+)"') or refresh_token
        local expires_at = os.time() + expires_in

        write_token_cache(acc.id, new_token, expires_at, updated_refresh)
        access_token = new_token
        print(string.format('    -> Successfully refreshed OAuth2 access token (valid for %ds).', expires_in))
    end

    local raw_sasl = string.format('user=%s\1auth=Bearer %s\1\1', acc.username, access_token)
    return base64_encode(raw_sasl)
end

-------------------------------------------------------------------------------
-- Rule Template Loader
-------------------------------------------------------------------------------
local rule_cache = {}

local function load_rule(rule_name)
    if rule_cache[rule_name] then
        return rule_cache[rule_name]
    end

    local candidate_paths = {
        string.format('/rules/%s.lua', rule_name),
        string.format('/config/rules/%s.lua', rule_name),
        string.format('/usr/local/share/imapfilter/rules/%s.lua', rule_name),
        string.format('./rules/%s.lua', rule_name),
    }

    for _, path in ipairs(candidate_paths) do
        local chunk, err = loadfile(path)
        if chunk then
            local ok, rule_fn = pcall(chunk)
            if ok and type(rule_fn) == 'function' then
                rule_cache[rule_name] = rule_fn
                return rule_fn
            elseif ok and type(rule_fn) ~= 'function' then
                -- In case the file directly performs actions when called
                local wrapper = function(account, context)
                    return chunk(account, context)
                end
                rule_cache[rule_name] = wrapper
                return wrapper
            else
                io.stderr:write(string.format('ERROR: Failed evaluating rule template "%s" (%s): %s\n', rule_name, path, tostring(rule_fn)))
            end
        end
    end

    return nil
end

-------------------------------------------------------------------------------
-- Account Discovery (ACCOUNT_<N>_ or ACCOUNT<N>_)
-------------------------------------------------------------------------------
local accounts = {}
local idx = 1

while true do
    local user = os.getenv(string.format('ACCOUNT_%d_USER', idx)) or
                 os.getenv(string.format('ACCOUNT%d_USER', idx))

    if not user or user == '' then
        break
    end

    local pass = os.getenv(string.format('ACCOUNT_%d_PASS', idx)) or
                 os.getenv(string.format('ACCOUNT%d_PASS', idx))

    local refresh_token = os.getenv(string.format('ACCOUNT_%d_REFRESH_TOKEN', idx)) or
                          os.getenv(string.format('ACCOUNT%d_REFRESH_TOKEN', idx))

    if (not pass or pass == '') and (not refresh_token or refresh_token == '') then
        error(string.format('Configuration error: ACCOUNT_%d_USER is set but neither ACCOUNT_%d_PASS nor ACCOUNT_%d_REFRESH_TOKEN is provided.', idx, idx, idx))
    end

    local client_id = os.getenv(string.format('ACCOUNT_%d_CLIENT_ID', idx)) or
                      os.getenv(string.format('ACCOUNT%d_CLIENT_ID', idx)) or
                      '9e5f94bc-e8a4-4e73-b8be-63364c29d753'

    local tenant = os.getenv(string.format('ACCOUNT_%d_TENANT', idx)) or
                   os.getenv(string.format('ACCOUNT%d_TENANT', idx)) or
                   'common'

    local scope = os.getenv(string.format('ACCOUNT_%d_SCOPE', idx)) or
                  os.getenv(string.format('ACCOUNT%d_SCOPE', idx)) or
                  'offline_access https://outlook.office.com/IMAP.AccessAsUser.All'

    local server = os.getenv(string.format('ACCOUNT_%d_SERVER', idx)) or
                   os.getenv(string.format('ACCOUNT%d_SERVER', idx)) or
                   'outlook.office365.com'

    local port = tonumber(os.getenv(string.format('ACCOUNT_%d_PORT', idx)) or
                          os.getenv(string.format('ACCOUNT%d_PORT', idx))) or 993

    local ssl = os.getenv(string.format('ACCOUNT_%d_SSL', idx)) or
                os.getenv(string.format('ACCOUNT%d_SSL', idx)) or
                'auto'

    local name = os.getenv(string.format('ACCOUNT_%d_NAME', idx)) or
                 os.getenv(string.format('ACCOUNT%d_NAME', idx)) or
                 string.format('Account %d (%s)', idx, user)

    local rules = os.getenv(string.format('ACCOUNT_%d_RULES', idx)) or
                  os.getenv(string.format('ACCOUNT%d_RULES', idx)) or
                  'whitelist,newsletter'

    local newsletters_folder = os.getenv(string.format('ACCOUNT_%d_NEWSLETTERS_FOLDER', idx)) or
                               os.getenv(string.format('ACCOUNT%d_NEWSLETTERS_FOLDER', idx)) or
                               'Newsletters'

    local junk_folder = os.getenv(string.format('ACCOUNT_%d_JUNK_FOLDER', idx)) or
                        os.getenv(string.format('ACCOUNT%d_JUNK_FOLDER', idx)) or
                        'Junk'

    local whitelist_folder = os.getenv(string.format('ACCOUNT_%d_WHITELIST_FOLDER', idx)) or
                            os.getenv(string.format('ACCOUNT%d_WHITELIST_FOLDER', idx)) or
                            'Whitelist'

    table.insert(accounts, {
        id = idx,
        name = name,
        server = server,
        port = port,
        username = user,
        password = pass,
        refresh_token = refresh_token,
        client_id = client_id,
        tenant = tenant,
        scope = scope,
        ssl = ssl,
        rules = rules,
        newsletters_folder = newsletters_folder,
        junk_folder = junk_folder,
        whitelist_folder = whitelist_folder,
    })

    idx = idx + 1
end

if #accounts == 0 then
    error('Configuration error: No email accounts configured. Please set ACCOUNT_1_USER and ACCOUNT_1_PASS or ACCOUNT_1_REFRESH_TOKEN in your environment.')
end

-------------------------------------------------------------------------------
-- Sequential Execution with Failure Isolation & Repeated-Error Tracking
-------------------------------------------------------------------------------
local has_errors = false

for _, acc in ipairs(accounts) do
    local ok, err = pcall(function()
        print(string.format('==> Processing %s [%s@%s:%d]...', acc.name, acc.username, acc.server, acc.port))

        local account = nil
        if acc.refresh_token and acc.refresh_token ~= '' then
            local oauth2_token = get_oauth2_sasl(acc)
            account = IMAP {
                server = acc.server,
                port = acc.port,
                username = acc.username,
                oauth2 = oauth2_token,
                ssl = acc.ssl,
            }
        else
            account = IMAP {
                server = acc.server,
                port = acc.port,
                username = acc.username,
                password = acc.password,
                ssl = acc.ssl,
            }
        end

        -- Isolated context per account (whitelist never leaks between accounts)
        local context = {
            acc_config = acc,
            whitelisted_senders = {},
        }

        -- Parse comma-separated list of rule template names
        for rule_name in string.gmatch(acc.rules, '([^,%s]+)') do
            local rule_fn = load_rule(rule_name)
            if rule_fn then
                print(string.format('    -> Applying rule template "%s"...', rule_name))
                local r_ok, r_err = pcall(rule_fn, account, context)
                if not r_ok then
                    io.stderr:write(string.format('ERROR running rule "%s" on %s: %s\n', rule_name, acc.name, tostring(r_err)))
                end
            else
                io.stderr:write(string.format('WARN: Rule template "%s" not found for %s. Skipping.\n', rule_name, acc.name))
            end
        end

        print(string.format('==> Completed %s.', acc.name))
    end)

    if ok then
        handle_account_success(acc)
    else
        has_errors = true
        handle_account_error(acc, err)
    end
end

if has_errors then
    error('One or more email accounts encountered errors during processing.')
end
