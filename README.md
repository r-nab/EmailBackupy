# EmailBackupy

A super simple, containerized email backup tool with a FastAPI web frontend for editing configuration and scheduling email downloads.

## Features
- Download emails and attachments from IMAP servers
- Unlock password-protected PDFs
- Web UI to edit and preview `config.yaml` (with YAML syntax highlighting)
- Background job runs at a configurable interval
- Container-ready (Unraid compatible)

---

## Quick Start (Local with Podman)

### 1. Build the Container
```sh
podman build -t emailbackupy .
```

### 2. Prepare Data Directories
Create local directories to persist emails and attachments:
```sh
mkdir -p ~/emailbackupy-data/eml ~/emailbackupy-data/attachments
```

### 3. Run the Container
Mount your config and data directories:
```sh
podman run --rm -p 8004:8004 \
  -v $(pwd)/config.yaml:/app/configs/config.yaml:Z \
  -v ~/emailbackupy-data/eml:/data/eml:Z \
  -v ~/emailbackupy-data/attachments:/data/attachments:Z \
  localhost/emailbackupy
```
- The web UI will be available at: http://localhost:8004/
- Edit and save the config from the browser.

#### Config Structure
- `pdf_passwords`: List of passwords to try for unlocking PDF attachments.
- `schedule_minutes`: How often (in minutes) to run the backup job.
- `notifications_enabled`: Enable/disable webhook notifications.
- `notify_url`: Webhook URL for notifications (optional).
- `accounts`: List of email accounts to fetch from.
  - `imap`: IMAP connection details (`host`, `port`, `user`, `password`)
  - `search_last_days`: Only fetch emails from the last N days.
  - `filter_from`: List of sender addresses to filter.
  - `save_eml_to`: Directory to save .eml files (should be `/data/eml` for container mount).
  - `save_attachments_to`: Directory to save attachments (should be `/data/attachments`).
  - `filename_format`: Format for saved email filenames.

---

## Notes
- The config editor is available at the root web page.
- All changes to `config.yaml` take effect on the next scheduled run.
- Data is persisted in the mounted volumes.
- For production, use secure passwords and restrict access to the web UI.

---

## License
MIT
