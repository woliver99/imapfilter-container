-------------------------------------------------------------------------------
-- rules/newsletter.lua
-- Rule template: Moves newsletter emails from INBOX and Junk to Newsletters,
-- excluding any senders in context.whitelisted_senders. Zero deletions.
-------------------------------------------------------------------------------
return function(account, context)
    local acc = context.acc_config or {}
    local target_folder = acc.newsletters_folder or 'Newsletters'
    local junk_folder = acc.junk_folder or 'Junk'

    local function process_folder(folder_name)
        local mailbox = account[folder_name]
        if not mailbox then
            return
        end

        -- Match messages with List-Unsubscribe or List-Id headers
        local ok, candidates = pcall(function()
            return mailbox:contain_field('List-Unsubscribe', '') +
                   mailbox:contain_field('List-Id', '')
        end)

        if not ok or not candidates or #candidates == 0 then
            return
        end

        -- Exclude any whitelisted senders
        if context.whitelisted_senders then
            for sender, _ in pairs(context.whitelisted_senders) do
                local wl_msgs = mailbox:contain_from(sender)
                candidates = candidates - wl_msgs
            end
        end

        if #candidates > 0 then
            print(string.format('   [newsletter] Moving %d newsletter(s) from %s -> %s', #candidates, folder_name, target_folder))
            candidates:move_messages(account[target_folder])
        end
    end

    process_folder('INBOX')
    process_folder(junk_folder)
end
