# imapfilter-container

A lightweight, self-hosted email cleanup daemon powered by `imapfilter`. Connects to multiple IMAP email accounts over SSL, automatically routes newsletter and promotional mail to a `Newsletters` folder, and protects whitelisted senders.

Container images are published to GitHub Packages at `ghcr.io/woliver99/imapfilter-container`.

---

## Quick Start

### 1. `docker-compose.yml`

```yaml
services:
  imapfilter:
    image: ghcr.io/woliver99/imapfilter-container:latest
    container_name: imapfilter
    restart: unless-stopped
    env_file:
      - .env
    volumes:
      - ./rules:/rules:ro
      - imapfilter-tokens:/tokens

volumes:
  imapfilter-tokens:
```

### 2. Configure Accounts (`.env`)

Copy the example environment file:

```bash
cp .env.example .env
```

#### Option A: Microsoft Accounts (Hotmail / Outlook / Office365) via OAuth 2.0
> [!NOTE]
> Since September 2024, Microsoft permanently disabled Basic Authentication for personal accounts. Modern OAuth 2.0 (`XOAUTH2`) is required.

Run the interactive zero-dependency token generator:
```bash
python3 scripts/get_microsoft_token.py
```
This opens your browser to sign in once, tests IMAP connection, and prints the configuration for your `.env` file:
```env
ACCOUNT_1_USER=alice@hotmail.com
ACCOUNT_1_REFRESH_TOKEN=your_refresh_token_here
ACCOUNT_1_RULES=whitelist,newsletter
```

Tokens are automatically cached and renewed inside the secure Docker named volume `imapfilter-tokens`, surviving server restarts indefinitely.

#### Option B: Other Email Providers (Password / App Password)
For Gmail (App Password), Fastmail, Yahoo, or self-hosted servers:
```env
ACCOUNT_2_USER=bob@gmail.com
ACCOUNT_2_PASS=your_app_password
ACCOUNT_2_SERVER=imap.gmail.com
ACCOUNT_2_RULES=whitelist,newsletter
```

### 3. Optional: ntfy Push Notifications
Receive push notifications to your phone or desktop only if an account encounters **repeated, consecutive errors** (e.g. token expired, password changed, connection failure):
```env
NTFY_URL=https://ntfy.sh/your-secret-topic
# Optional Bearer token for protected topics:
NTFY_TOKEN=tk_123456789abcdef
# Consecutive failure threshold before alerting (default: 3)
NTFY_ERROR_THRESHOLD=3
```

### 4. Launch Service

```bash
docker compose up -d
docker compose logs -f
```

---

## How Whitelisting Works

Whitelisting is completely managed directly from your email app:

1. A `Whitelist` folder is automatically maintained **inside** your `Newsletters` folder (`Newsletters/Whitelist`).
2. When you want to whitelist a sender, **simply drag or move any received email from that sender into `Newsletters/Whitelist`**.
3. On every run, the bot reads the `From:` headers of all emails in `Newsletters/Whitelist` and ensures their emails in `INBOX` and `Junk` are never touched or moved.
4. **Strict Account Isolation**: Whitelist entries are isolated per account (Account 1's whitelist never affects Account 2).

---

## Custom Lua Rule Templates

Rule templates are standalone Lua files in [`rules/`](rules/):

- **`whitelist`** (built-in): Extracts whitelisted senders from the `Whitelist` folder.
- **`newsletter`** (built-in): Moves newsletters with `List-Unsubscribe` or `List-Id` from `INBOX` and `Junk` to `Newsletters` (zero deletions).
- **Custom Rules**: You can add any custom rule by placing a `.lua` file into `./rules/` and listing its name in `ACCOUNT_<N>_RULES`.

### Example Custom Rule (`rules/receipts.lua`)

```lua
return function(account, context)
    local receipts = account.INBOX:contain_subject('Receipt') +
                     account.INBOX:contain_subject('Invoice')
    if receipts and #receipts > 0 then
        receipts:move_messages(account['Receipts'])
    end
end
```

Then in `.env`:
```env
ACCOUNT_1_RULES=whitelist,newsletter,receipts
```

---

## Configuration Reference

Each account (`ACCOUNT_1_*`, `ACCOUNT_2_*`, up to `ACCOUNT_<N>_*`) supports the following parameters:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ACCOUNT_<N>_USER` | *Required* | Email address or username |
| `ACCOUNT_<N>_REFRESH_TOKEN` | *Optional* | Microsoft OAuth 2.0 refresh token (recommended for Hotmail/Outlook) |
| `ACCOUNT_<N>_PASS` | *Optional* | Email password or App Password (for password-based providers) |
| `ACCOUNT_<N>_RULES` | `whitelist,newsletter` | Comma-separated list of rule templates to execute |
| `ACCOUNT_<N>_SERVER` | `outlook.office365.com` | IMAP server hostname |
| `ACCOUNT_<N>_PORT` | `993` | IMAP SSL port |
| `ACCOUNT_<N>_SSL` | `auto` | SSL/TLS protocol version |
| `ACCOUNT_<N>_NEWSLETTERS_FOLDER` | `Newsletters` | Destination folder for newsletters |
| `ACCOUNT_<N>_JUNK_FOLDER` | `Junk` | Source junk/spam folder |
| `NTFY_URL` | *Optional* | Push notification URL (e.g. `https://ntfy.sh/my-topic`) |
| `NTFY_TOKEN` | *Optional* | Bearer authentication token for protected ntfy topics |
| `NTFY_ERROR_THRESHOLD` | `3` | Consecutive failures before sending an ntfy notification |
| `CHECK_INTERVAL` | `600` | Frequency between cleanup runs in seconds |

---

## Building & Publishing

To build locally and publish the container image to GitHub Packages:

```bash
./publish.sh
# Or with a custom version tag:
./publish.sh v1.0.0
```
