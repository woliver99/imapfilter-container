-------------------------------------------------------------------------------
-- imapfilter multi-account configuration for automated email cleanup
-------------------------------------------------------------------------------

-- Global Options
options.timeout = 120
options.subscribe = true
options.create = true
options.expunge = true

-------------------------------------------------------------------------------
-- Account Discovery
-------------------------------------------------------------------------------
-- Discovers accounts starting from ACCOUNT1_*, ACCOUNT2_*, etc.
local accounts = {}
local idx = 1

while true do
    local user = os.getenv(string.format('ACCOUNT%d_USER', idx))
    if not user or user == '' then
        break
    end

    local pass = os.getenv(string.format('ACCOUNT%d_PASS', idx))
    if not pass or pass == '' then
        error(string.format('Configuration error: ACCOUNT%d_USER is set but ACCOUNT%d_PASS is unset or empty.', idx, idx))
    end

    local server = os.getenv(string.format('ACCOUNT%d_SERVER', idx)) or 'outlook.office365.com'
    local port = tonumber(os.getenv(string.format('ACCOUNT%d_PORT', idx))) or 993
    local ssl = os.getenv(string.format('ACCOUNT%d_SSL', idx)) or 'auto'
    local name = os.getenv(string.format('ACCOUNT%d_NAME', idx)) or string.format('Account %d (%s)', idx, user)
    local newsletters_folder = os.getenv(string.format('ACCOUNT%d_NEWSLETTERS_FOLDER', idx)) or 'Newsletters'
    local junk_folder = os.getenv(string.format('ACCOUNT%d_JUNK_FOLDER', idx)) or 'Junk'
    local junk_days = tonumber(os.getenv(string.format('ACCOUNT%d_JUNK_DAYS', idx))) or 14

    table.insert(accounts, {
        id = idx,
        name = name,
        server = server,
        port = port,
        username = user,
        password = pass,
        ssl = ssl,
        newsletters_folder = newsletters_folder,
        junk_folder = junk_folder,
        junk_days = junk_days,
    })

    idx = idx + 1
end

if #accounts == 0 then
    error('Configuration error: No email accounts configured. Please set ACCOUNT1_USER and ACCOUNT1_PASS in your environment.')
end

-------------------------------------------------------------------------------
-- Account Processing Loop with Failure Isolation
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

        -- 1. Match incoming mail with List-Unsubscribe or List-Id headers
        local newsletters = account.INBOX:contain_field('List-Unsubscribe', '') +
                            account.INBOX:contain_field('List-Id', '')

        -- Move matched newsletters to the designated folder
        newsletters:move_messages(account[acc.newsletters_folder])

        -- 2. Purge messages in the junk folder older than retention period
        local junk_mailbox = account[acc.junk_folder]
        if junk_mailbox then
            local old_junk = junk_mailbox:is_older(acc.junk_days)
            old_junk:delete_messages()
        end

        print(string.format('==> Completed processing %s.', acc.name))
    end)

    if not ok then
        has_errors = true
        io.stderr:write(string.format('ERROR processing %s: %s\n', acc.name, tostring(err)))
    end
end

if has_errors then
    error('One or more email accounts encountered errors during processing.')
end
