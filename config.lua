-------------------------------------------------------------------------------
-- imapfilter configuration for Hotmail/Outlook email cleanup
-------------------------------------------------------------------------------

-- Global Options
options.timeout = 120
options.subscribe = true
options.create = true
options.expunge = true

-- Credentials from environment
local username = os.getenv('HOTMAIL_USER')
local password = os.getenv('HOTMAIL_PASS')

if not username or username == '' then
    error('Configuration error: HOTMAIL_USER environment variable is unset or empty.')
end

if not password or password == '' then
    error('Configuration error: HOTMAIL_PASS environment variable is unset or empty.')
end

-- Connect to Outlook / Hotmail IMAP server with SSL/TLS
local account = IMAP {
    server = 'outlook.office365.com',
    port = 993,
    username = username,
    password = password,
    ssl = 'auto',
}

-------------------------------------------------------------------------------
-- Filter Rules
-------------------------------------------------------------------------------

-- 1. Match any incoming mail in INBOX with List-Unsubscribe or List-Id headers
local newsletters = account.INBOX:contain_field('List-Unsubscribe', '') +
                    account.INBOX:contain_field('List-Id', '')

-- Move matched newsletters/promotions to Newsletters folder
newsletters:move_messages(account['Newsletters'])

-- 2. Purge messages in the Junk folder older than 14 days
local old_junk = account['Junk']:is_older(14)
old_junk:delete_messages()
