# imapfilter-container

A lightweight, local-first, self-hosted Dockerized email cleanup service powered by [`imapfilter`](https://github.com/lefcha/imapfilter). It connects to Microsoft Hotmail / Outlook over secure IMAP (SSL/TLS) and automatically organizes newsletters into a dedicated folder while purging stale junk mail every 10 minutes.

---

## Features

- **Automated Newsletter Organization**: Routes incoming messages with `List-Unsubscribe` or `List-Id` headers from `INBOX` to `Newsletters`.
- **Junk Mail Retention Management**: Permanently purges messages in `Junk` older than 14 days (`options.expunge = true`).
- **Foreground Daemon Loop**: Runs checks on a configurable schedule (default: 600 seconds / 10 minutes) with timestamped logs.
- **Lean Multi-Stage Container**: Builds directly from the `imapfilter` source submodule on Debian Bookworm Slim with minimal runtime dependencies.
- **Graceful Termination**: Handles `SIGTERM`/`SIGINT` signals for clean shutdown with Docker Compose.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/) (or [Podman](https://podman.io/) with `podman-compose`)
- [Git](https://git-scm.com/)

---

## Getting Started

### 1. Clone Repository (with Submodules)

Clone the repository and its `imapfilter` submodule in a single command:

```bash
git clone --recurse-submodules https://github.com/your-username/imapfilter-container.git
cd imapfilter-container
```

If you previously cloned the repository without `--recurse-submodules`, initialize and update the submodule:

```bash
git submodule update --init --recursive
```

---

### 2. Generate a Microsoft App Password

If Two-Step Verification (2FA) is enabled on your Microsoft / Hotmail / Outlook account, standard account passwords will not work for IMAP. You must create a dedicated App Password:

1. Sign in to your Microsoft Account security dashboard: [https://account.live.com/proofs/manage/additional](https://account.live.com/proofs/manage/additional).
2. Scroll to the **App passwords** section.
3. Click **Create a new app password**.
4. Copy the generated 16-character password (e.g., `abcd efgh ijkl mnop`). Remove spaces when pasting it into your configuration.

---

### 3. Configure Environment

Copy the example environment file:

```bash
cp .env.example .env
```

Edit `.env` with your email and generated App Password:

```env
HOTMAIL_USER=your_email@hotmail.com
HOTMAIL_PASS=your_app_password_here
```

> [!CAUTION]
> Never commit your `.env` file to version control. The included `.gitignore` already ignores `.env`.

---

### 4. Build and Start Service

Build the Docker image and start the container in detached mode:

```bash
docker compose up -d --build
```

---

### 5. Verify Operation

Inspect the container logs to monitor execution and verify scheduled runs:

```bash
docker compose logs -f
```

Sample output:
```text
2026-10-21 19:25:00 UTC [imapfilter] Starting email cleanup loop (interval: 600s)...
2026-10-21 19:25:00 UTC [imapfilter] Running imapfilter...
2026-10-21 19:25:02 UTC [imapfilter] imapfilter run completed successfully.
2026-10-21 19:25:02 UTC [imapfilter] Sleeping for 600s until next check...
```

To stop the container:

```bash
docker compose down
```

---

## Customizing Filter Rules

The filtering rules reside in [`config.lua`](config.lua) and are mounted read-only into `/config/config.lua:ro`.

### Default Rules

```lua
-- Move newsletters/promotions to "Newsletters" folder
local newsletters = account.INBOX:contain_field('List-Unsubscribe', '') +
                    account.INBOX:contain_field('List-Id', '')
newsletters:move_messages(account['Newsletters'])

-- Delete junk older than 14 days
local old_junk = account['Junk']:is_older(14)
old_junk:delete_messages()
```

After modifying [`config.lua`](config.lua), restart the container to apply your changes:

```bash
docker compose restart
```

---

## Project Structure

```text
imapfilter-container/
├── .dockerignore              # Docker build context exclusions
├── .gitignore                 # Git ignore patterns (.env, logs, temp files)
├── .gitmodules                # Git submodule configuration for imapfilter
├── Dockerfile                 # Multi-stage Debian Bookworm build
├── docker-compose.yml         # Container deployment specification
├── entrypoint.sh              # Foreground loop runner with signal handling
├── config.lua                 # imapfilter Lua configuration and filtering rules
├── .env.example               # Example credentials template
├── README.md                  # Documentation and setup guide
└── src/
    └── imapfilter/            # Upstream imapfilter submodule (Git)
```
