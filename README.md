# imapfilter-container

A lightweight, self-hosted email cleanup daemon powered by `imapfilter`. Connects to multiple IMAP email accounts over SSL, automatically routes newsletter and promotional mail to a `Newsletters` folder, and purges stale messages from `Junk`.

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
      - ./config.lua:/config/config.lua:ro
```

### 2. Configure Accounts (`.env`)

Create a `.env` file from the provided example:

```bash
cp .env.example .env
```

Define your credentials:

```env
# Primary Account (Required)
ACCOUNT1_USER=your_first_email@example.com
ACCOUNT1_PASS=your_secret_password

# Secondary Account (Optional)
ACCOUNT2_USER=your_second_email@example.com
ACCOUNT2_PASS=your_second_password

# Cleanup run interval in seconds (default: 600 = 10 minutes)
CHECK_INTERVAL=600
```

### 3. Launch Service

```bash
docker compose up -d
docker compose logs -f
```

---

## Configuration Reference

Each account (`ACCOUNT1_*`, `ACCOUNT2_*`, up to `ACCOUNT<N>_*`) supports the following environment variables:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `ACCOUNT<N>_USER` | *Required* | Email username or address |
| `ACCOUNT<N>_PASS` | *Required* | Account password or App Password |
| `ACCOUNT<N>_SERVER` | `outlook.office365.com` | IMAP server hostname |
| `ACCOUNT<N>_PORT` | `993` | IMAP port (SSL/TLS) |
| `ACCOUNT<N>_SSL` | `auto` | SSL/TLS protocol version (`auto`, `tls1.2`, etc.) |
| `ACCOUNT<N>_NEWSLETTERS_FOLDER` | `Newsletters` | Folder to move matched newsletters to |
| `ACCOUNT<N>_JUNK_FOLDER` | `Junk` | Junk/Spam folder to purge |
| `ACCOUNT<N>_JUNK_DAYS` | `14` | Delete junk messages older than this many days |
| `CHECK_INTERVAL` | `600` | Frequency between cleanup runs in seconds |

---

## Building & Publishing

To build locally and publish the container image to GitHub Packages:

```bash
./publish.sh
# Or with a custom version tag:
./publish.sh v1.0.0
```
