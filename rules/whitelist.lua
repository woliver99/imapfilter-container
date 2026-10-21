-------------------------------------------------------------------------------
-- rules/whitelist.lua
-- Rule template: Scans the Whitelist folder and extracts sender email addresses
-------------------------------------------------------------------------------
return function(account, context)
    local acc = context.acc_config or {}
    local folder_name = acc.whitelist_folder or 'Whitelist'

    -- Ensure Whitelist folder exists on server
    pcall(function()
        account:create_mailbox(folder_name)
    end)

    local mailbox = account[folder_name]
    if not mailbox then
        return
    end

    -- Select all messages in the Whitelist folder
    local ok, messages = pcall(function()
        return mailbox:select_all()
    end)

    if not ok or not messages or #messages == 0 then
        print(string.format('   [whitelist] Whitelist folder "%s" is empty. (0 whitelisted senders)', folder_name))
        return
    end

    -- Fetch From headers
    local from_fields = mailbox:fetch_fields({ 'From' }, messages)
    if not from_fields then
        return
    end

    local count = 0
    for _, header in pairs(from_fields) do
        -- Extract email from "From: User Name <user@domain.com>" or "From: user@domain.com"
        local email = string.match(header, '<([^>]+)>') or
                      string.match(header, 'From:%s*([%w%.%-_]+@[%w%.%-_]+)') or
                      string.match(header, '([%w%.%-_]+@[%w%.%-_]+)')

        if email and email ~= '' then
            email = string.lower(email)
            if not context.whitelisted_senders[email] then
                context.whitelisted_senders[email] = true
                count = count + 1
            end
        end
    end

    print(string.format('   [whitelist] Loaded %d whitelisted sender(s) from "%s".', count, folder_name))
end
