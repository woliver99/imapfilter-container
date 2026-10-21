# imapfilter-container

A lightweight, local-first, self-hosted Dockerized email cleanup service powered by [`imapfilter`](https://github.com/lefcha/imapfilter). It supports multiple email accounts simultaneously, connecting over secure IMAP (SSL/TLS) to automatically organize newsletters into dedicated folders and purge stale junk mail on a recurring schedule.

Container images are published to [GitHub Packages](https://github.com/woliver99/imapfilter-container/pkgs/container/imapfilter-container) (`ghcr.io/woliver99/imapfilter-container`).

---

## Features

- **Multi-Account Support**: Cleanly processes multiple independent email accounts (`ACCOUNT1_*`, `ACCOUNT2_*`, etc.) sequentially.
- **Automated Newsletter Organization**: Routes incoming messages matching `List-Unsubscribe` or `List-Id` headers from `INBOX` to `Newsletters`.
- **Junk Mail Retention Management**: Permanently purges messages in `Junk` older than 14 days (`options.expunge = true`).
- **Failure Isolation**: Employs protected calls (`pcall`) per account so a transient network timeout on one account will not block remaining accounts.
- **Configurable Daemon Loop**: Runs on a background schedule (default: 600 seconds / 10 minutes) with ISO/UTC timestamped logs.
- **Lean Multi-Stage Container**: Based on Debian Bookworm Slim with minimal runtime dependencies.
- **Graceful Termination**: Intercepts `SIGTERM`/`SIGINT` signals for immediate, clean shutdown with Docker Compose.

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) & [Docker Compose](https://docs.docker.com/compose/) (or [Podman](https://podman.io/) with `podman-compose`)
- [Git](https://git-scm.com/)

---

## Getting Started

### 1. Clone Repository (with Submodules)

Clone the repository and its `imapfilter` source submodule:

```bash
git clone --recurse-submodules git@github.com:woliver99/imapfilter-container.git
cd imapfilter-container
```

If you previously cloned without `--recurse-submodules`, initialize the submodule:

```bash
git submodule update --init --recursive
```

---

### 2. Generate Microsoft App Passwords

If Two-Step Verification (2FA) is enabled on your Microsoft / Hotmail / Outlook account, standard account passwords will not work for IMAP. You must create a dedicated App Password for each account:

1. Sign in to your Microsoft Account security dashboard: [https://account.live.com/proofs/manage/additional](https://account.live.com/proofs/manage/additional).
2. Scroll to the **App passwords** section.
3. Click **Create a new app password**.
4. Copy the generated 16-character password (remove spaces when pasting).

---

### 3. Configure Environment (`.env`)

Copy the example environment file:

```bash
cp .env.example .env
```

Configure your accounts in `.env`:

```env
# Primary Account
ACCOUNT1_USER=personal_email@hotmail.com
ACCOUNT1_PASS=your_app_password_here

# Secondary Account (optional)
ACCOUNT2_USER=work_email@outlook.com
ACCOUNT2_PASS=your_second_app_password_here

# Service Check Interval (in seconds, default: 600s = 10 minutes)
CHECK_INTERVAL=600
```

#### Optional Per-Account Overrides

You can customize individual account parameters if needed:

```env
# Custom display name in logs
ACCOUNT1_NAME="Personal Hotmail"

# Custom IMAP host and port (defaults to outlook.office365.com:993)
ACCOUNT1_SERVER=outlook.office365.com
ACCOUNT1_PORT=993
ACCOUNT1_SSL=auto

# Custom folder targets and retention days
ACCOUNT1_NEWSLETTERS_FOLDER=Newsletters
ACCOUNT1_JUNK_FOLDER=Junk
ACCOUNT1_JUNK_DAYS=14
```

> [!CAUTION]
> Never commit your `.env` file to version control. The included `.gitignore` protects secrets from being staged.

---

### 4. Build and Start Service

Build the Docker image and start the container:

```bash
docker compose up -d --build
```

Alternatively, to run using the prebuilt image published on GitHub Packages without local compilation:

```bash
docker compose pull
docker compose up -d
```

---

### 5. Verify Operation

Follow the container logs to monitor cleanup runs:

```bash
docker compose logs -f
```

Sample output:
```text
2026-10-21 19:40:00 UTC [imapfilter] Starting email cleanup loop (interval: 600s)...
2026-10-21 19:40:00 UTC [imapfilter] Running imapfilter...
==> Processing Account 1 (personal@hotmail.com) [personal@hotmail.com@outlook.office365.com:993]...
==> Completed processing Account 1 (personal@hotmail.com).
==> Processing Account 2 (work@outlook.com) [work@outlook.com@outlook.office365.com:993]...
==> Completed processing Account 2 (work@outlook.com).
2026-10-21 19:40:05 UTC [imapfilter] imapfilter run completed successfully.
2026-10-21 19:40:05 UTC [imapfilter] Sleeping for 600s until next check...
```

To stop the service:

```bash
docker compose down
```

---

## Publishing to GitHub Packages

A dedicated script [`publish.sh`](publish.sh) is provided to build the container image and publish it directly to GitHub Packages (`ghcr.io`):

```bash
# Build and publish 'latest' tag
./publish.sh

# Or publish with a specific version tag as well
./publish.sh v1.0.0
```

The script will:
1. Build the container image tagged as `ghcr.io/woliver99/imapfilter-container:latest` (and `v1.0.0` if specified).
2. Authenticate to `ghcr.io` (via GitHub CLI if logged in, or prompting for a GitHub Personal Access Token with `write:packages` scope).
3. Push the image to GitHub Packages.

---

## Pushing Code to GitHub

To push your repository commits and branches to GitHub over SSH:

```bash
git push -u origin main
```

---

## Project Structure

```text
imapfilter-container/
├── .dockerignore              # Docker build context exclusions
├── .gitignore                 # Git ignore rules (.env, logs, swap files)
├── .gitmodules                # Submodule tracking for imapfilter
├── Dockerfile                 # Multi-stage build with OCI metadata labels
├── docker-compose.yml         # Container deployment configuration
├── entrypoint.sh              # Loop runner with signal handling
├── config.lua                 # Multi-account imapfilter logic
├── publish.sh                 # Builds and publishes container to GitHub Packages
├── .env.example               # Multi-account credentials template
├── README.md                  # Documentation and setup guide
└── src/
    └── imapfilter/            # Upstream imapfilter submodule (Git)
```
