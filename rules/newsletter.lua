-------------------------------------------------------------------------------
-- rules/newsletter.lua
-- Rule template: Moves newsletter emails from INBOX to Newsletters,
-- and from Junk to Newsletters/Junk, excluding any senders in context.whitelisted_senders.
-- Zero deletions from Junk.
-------------------------------------------------------------------------------
return function(account, context)
    local acc = context.acc_config or {}
    local acc_id = acc.id or 1
    local junk_folder = acc.junk_folder or 'Junk'

    -- Destination folders:
    -- Newsletters: holds newsletters originating from INBOX
    -- Newsletters/Junk: holds newsletters originating from spam/junk
    local inbox_destination = 'Newsletters'
    local junk_destination = 'Newsletters/Junk'

    -- Ensure destination folders exist on server
    pcall(function()
        account:create_mailbox(inbox_destination)
        account:subscribe_mailbox(inbox_destination)
        account:create_mailbox(junk_destination)
        account:subscribe_mailbox(junk_destination)
    end)

    local function process_folder(source_folder, destination_folder)
        local mailbox = account[source_folder]
        if not mailbox then
            print(string.format('   [newsletter] Unable to access mailbox "%s".', source_folder))
            return
        end

        print(string.format('   [newsletter] Scanning "%s" for newsletters...', source_folder))

        -- Match messages with List-Unsubscribe or List-Id headers
        local ok, candidates = pcall(function()
            return mailbox:contain_field('List-Unsubscribe', '') +
                   mailbox:contain_field('List-Id', '')
        end)

        if not ok then
            io.stderr:write(string.format('   [newsletter] ERROR querying "%s": %s\n', source_folder, tostring(candidates)))
            return
        end

        if not candidates or #candidates == 0 then
            print(string.format('   [newsletter] No newsletters found in "%s".', source_folder))
            return
        end

        local total_matched = #candidates

        -- Exclude any whitelisted senders
        local excluded_count = 0
        if context.whitelisted_senders and next(context.whitelisted_senders) then
            for sender, _ in pairs(context.whitelisted_senders) do
                local ok_wl, wl_msgs = pcall(function()
                    return mailbox:contain_from(sender)
                end)
                if ok_wl and wl_msgs and #wl_msgs > 0 then
                    local before = #candidates
                    candidates = candidates - wl_msgs
                    excluded_count = excluded_count + (before - #candidates)
                end
            end
        end

        if #candidates > 0 then
            print(string.format('   [newsletter] Moving %d newsletter(s) from "%s" -> "%s" (%d whitelisted excluded)...',
                #candidates, source_folder, destination_folder, excluded_count))
            local move_ok, move_err = pcall(function()
                candidates:move_messages(account[destination_folder])
            end)
            if not move_ok then
                io.stderr:write(string.format('   [newsletter] ERROR moving messages from "%s" to "%s": %s\n',
                    source_folder, destination_folder, tostring(move_err)))
            end
        else
            print(string.format('   [newsletter] All %d candidate(s) in "%s" were excluded by whitelist.', total_matched, source_folder))
        end
    end

    -- 1. Process INBOX -> Newsletters
    process_folder('INBOX', inbox_destination)

    -- 2. Process Junk folder -> Newsletters/Junk
    local mailboxes = {}
    local list_ok, list_m = pcall(function()
        return account:list_all('', '*')
    end)
    if list_ok and type(list_m) == 'table' then
        mailboxes = list_m
    end

    local junk_exists = false
    for _, mbox in ipairs(mailboxes) do
        if mbox == junk_folder then
            junk_exists = true
            break
        end
    end

    -- If list_all was empty or failed, attempt direct status check
    if not junk_exists and #mailboxes == 0 then
        local status_ok, r = pcall(function()
            local exist = account[junk_folder]:check_status()
            return exist ~= -1
        end)
        if status_ok and r then
            junk_exists = true
        end
    end

    if junk_exists then
        process_folder(junk_folder, junk_destination)
    else
        -- Find server mailboxes containing "junk" (case-insensitive) for debug reporting
        local junk_matches = {}
        for _, mbox in ipairs(mailboxes) do
            if string.find(string.lower(mbox), 'junk') then
                table.insert(junk_matches, mbox)
            end
        end

        if #junk_matches > 0 then
            print(string.format('   [newsletter] [DEBUG] Configured junk folder "%s" not found on server.', junk_folder))
            print(string.format('   [newsletter] [DEBUG] Server mailbox candidates matching "junk": "%s".', table.concat(junk_matches, '", "')))
            print(string.format('   [newsletter] [DEBUG] To enable filtering newsletters from junk, set in your .env:'))
            for _, match in ipairs(junk_matches) do
                print(string.format('   [newsletter] [DEBUG]   ACCOUNT_%d_JUNK_FOLDER="%s"', acc_id, match))
            end
        else
            print(string.format('   [newsletter] [DEBUG] Configured junk folder "%s" not found on server, and no mailboxes containing "junk" were found.', junk_folder))
        end
    end
end
