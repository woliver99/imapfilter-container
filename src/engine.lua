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

    if not pass or pass == '' then
        error(string.format('Configuration error: ACCOUNT_%d_USER is set but ACCOUNT_%d_PASS is unset or empty.', idx, idx))
    end

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
        ssl = ssl,
        rules = rules,
        newsletters_folder = newsletters_folder,
        junk_folder = junk_folder,
        whitelist_folder = whitelist_folder,
    })

    idx = idx + 1
end

if #accounts == 0 then
    error('Configuration error: No email accounts configured. Please set ACCOUNT_1_USER and ACCOUNT_1_PASS in your environment.')
end

-------------------------------------------------------------------------------
-- Sequential Execution with Failure Isolation
-------------------------------------------------------------------------------
local has_errors = false

for _, acc in ipairs(accounts) do
    local ok, err = pcall(function()
        print(string.format('==> Processing %s [%s@%s:%d]...', acc.name, acc.username, acc.server, acc.port))
        local account = IMAP {
            server = acc.server,
            port = acc.port,
            username = acc.username,
            password = acc.password,
            ssl = acc.ssl,
        }

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

    if not ok then
        has_errors = true
        io.stderr:write(string.format('ERROR processing %s: %s\n', acc.name, tostring(err)))
    end
end

if has_errors then
    error('One or more email accounts encountered errors during processing.')
end
