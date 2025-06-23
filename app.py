import imaplib
import pikepdf
import email
import os
import yaml
import schedule
import time
import requests
import logging
from datetime import datetime, timedelta
from email.header import decode_header
from threading import Lock, Thread
import re
from fastapi import FastAPI, Request, Form
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from contextlib import asynccontextmanager

account_locks = {}


# Setup logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

def sanitize_filename(text, max_length=64):
    # Only allow letters, numbers, underscore, @, and dot
    # First, decode MIME words if present
    if isinstance(text, str):
        text = decode_mime_words(text)
    # Remove quotes first
    text = text.replace('"', '').replace("'", '')
    # Replace spaces and invalid chars with underscore
    sanitized = re.sub(r'[^a-zA-Z0-9@._]', '_', text)
    # Replace multiple underscores with single underscore
    sanitized = re.sub(r'_+', '_', sanitized)
    # Truncate to max length if needed
    if len(sanitized) > max_length:
        name_parts = sanitized.rsplit('.', 1)
        if len(name_parts) > 1:
            # If there's an extension, preserve it
            ext_len = len(name_parts[1]) + 1  # +1 for the dot
            max_name_len = max_length - ext_len
            sanitized = f"{name_parts[0][:max_name_len]}.{name_parts[1]}"
        else:
            sanitized = sanitized[:max_length]
    return sanitized

CONFIG_PATH = "/app/configs/config.yaml"
app = FastAPI()
templates = Jinja2Templates(directory="templates")

# Load config
def load_config(path=CONFIG_PATH):
    logging.info(f"Loading config from {path}...")
    with open(path, 'r') as f:
        config = yaml.safe_load(f)
    logging.info("Config loaded successfully.")
    return config

# Notify via webhook
def notify(config, event, details):
    if config.get("notifications_enabled", True) and config.get("notify_url"):
        try:
            logging.info(f"Sending notification for event: {event}")
            requests.post(config["notify_url"], json={"event": event, "details": details})
        except Exception as e:
            logging.error("Notification failed: %s", e)

def unlock_pdf(input_path, output_path, passwords):
    logging.info(f"Attempting to unlock PDF: {input_path}")
    for pwd in passwords:
        try:
            logging.info(f"Trying password: {pwd}")
            with pikepdf.open(input_path, password=pwd) as pdf:
                pdf.save(output_path)
            logging.info(f"PDF unlocked and saved to: {output_path}")
            return True
        except Exception as e:
            logging.error(f"Error unlocking PDF: {e}")
            continue
    logging.warning("Failed to unlock PDF with all passwords.")
    return False



# Decode MIME-encoded headers
def decode_mime_words(s):
    if not s:
        return ""
    decoded_fragments = decode_header(s)
    return ''.join([
        frag.decode(enc or 'utf-8') if isinstance(frag, bytes) else frag
        for frag, enc in decoded_fragments
    ])

def create_email_filename(from_, subject, date_str):
    date_str = date_str.split(",")[-1].strip().split()[0]  # Extract date part only
    parts = [
        decode_mime_words(from_),
        decode_mime_words(subject),
        date_str
    ]
    base_filename = "_".join(filter(None, parts))
    return sanitize_filename(base_filename)

# Process and save emails
def process_emails(account, global_config):
    user = account['imap']['user']
    if user not in account_locks:
        account_locks[user] = Lock()

    if not account_locks[user].acquire(blocking=False):
        logging.info(f"Skipping {user} – job already running.")
        return
    try:
        logging.info(f"Connecting to IMAP server: {account['imap']['host']}")
        imap = imaplib.IMAP4_SSL(account['imap']['host'], account['imap']['port'])
        imap.login(account['imap']['user'], account['imap']['password'])
        imap.select("INBOX")

        # Get allowed senders and prepare base search criteria
        allowed_senders = account.get("filter_from", [])
        if not allowed_senders:
            logging.warning(f"No filter_from addresses configured for {user}, skipping account.")
            return

        days = account.get("search_last_days")
        date_criteria = ""
        if days:
            date_since = (datetime.now() - timedelta(days=days)).strftime("%d-%b-%Y")
            date_criteria = f"SINCE {date_since}"
            logging.info(f"Filtering emails since: {date_since}")


        # Search for each sender separately
        for sender in allowed_senders:
            total_messages = 0
            search_criteria = f'(FROM "{sender}")'
            if date_criteria:
                search_criteria = f'({date_criteria} {search_criteria})'
            
            logging.info(f"Searching for emails from: {sender}")
            status, messages = imap.search(None, search_criteria)
            messages = messages[0].split()
            sender_count = len(messages)
            total_messages += sender_count
            logging.info(f"Found {sender_count} email(s) from {sender}")

            for mail_id in messages:
                try:
                    status, data = imap.fetch(mail_id, '(RFC822)')
                    if status != 'OK' or not data or not data[0]:
                        logging.error(f"Failed to fetch email {mail_id}")
                        continue
                        
                    raw_email = data[0][1]
                    msg = email.message_from_bytes(raw_email)
                    
                    logging.info(f"Processing email: {msg['Subject']}")

                    # Create directory if it doesn't exist
                    os.makedirs(account["save_eml_to"], exist_ok=True)

                    # Save .eml file
                    filename = create_email_filename(msg['From'], msg['Subject'], msg['Date'])
                    eml_path = os.path.join(account["save_eml_to"], filename + ".eml")
                    logging.info(f"Saving email to: {eml_path}")
                    
                    with open(eml_path, "wb") as f:
                        f.write(raw_email)
                    
                    notify(global_config, "email_saved", {
                        "subject": msg['Subject'],
                        "from": msg['From'],
                        "path": eml_path
                    })
                except Exception as e:
                    logging.error(f"Error processing email {mail_id}: {str(e)}")
                    continue

                # Save attachments
                for part in msg.walk():
                    if part.get_content_maintype() == 'multipart' or part.get('Content-Disposition') is None:
                        continue
                    attachment_name = part.get_filename()
                    if attachment_name:
                        attachment_name = attachment_name.replace(" ", "_")
                        att_path = os.path.join(account["save_attachments_to"], attachment_name)
                        logging.info(f"Saving attachment to: {att_path}")
                        with open(att_path, 'wb') as af:
                            af.write(part.get_payload(decode=True))

                        # Handle PDF unlock
                        if att_path.endswith(".pdf"):
                            unlocked_path = os.path.join(account["save_attachments_to"], "unlocked_" + attachment_name)
                            logging.info(f"Attempting to unlock PDF attachment: {att_path}")
                            if unlock_pdf(att_path, unlocked_path, global_config["pdf_passwords"]):
                                logging.info(f"Removing original encrypted PDF: {att_path}")
                                os.remove(att_path)

                # Move email to backup folder
                logging.info(f"Moving email {mail_id} to backup folder.")
                imap.copy(mail_id, 'backup')
                imap.store(mail_id, '+FLAGS', '\\Deleted')

                notify(global_config, "email_saved", {"subject": msg['Subject']})

        imap.expunge()
        imap.logout()
        logging.info("IMAP session closed.")
    except Exception as e:
        logging.error("Error during email processing: %s", e)
        notify(global_config, "error", str(e))
    finally:
        account_locks[user].release()

# Schedule job
def run_schedule(config):
    logging.info("Scheduling email processing jobs...")
    for acct in config['accounts']:
        schedule.every(config['schedule_minutes']).minutes.do(process_emails, acct, config)
        logging.info(f"Scheduled job for account: {acct['imap']['user']}")

    while True:
        schedule.run_pending()
        time.sleep(10)

def background_scheduler():
    while True:
        config = load_config(CONFIG_PATH)
        schedule_minutes = config.get("schedule_minutes", 30)
        for acct in config['accounts']:
            process_emails(acct, config)
        time.sleep(schedule_minutes * 60)

@asynccontextmanager
async def lifespan(app: FastAPI):
    thread = Thread(target=background_scheduler, daemon=True)
    thread.start()
    yield
    # No cleanup needed

app = FastAPI(lifespan=lifespan)

@app.get("/", response_class=HTMLResponse)
def read_config(request: Request):
    with open(CONFIG_PATH, "r") as f:
        config_text = f.read()
    return templates.TemplateResponse("editor.html", {"request": request, "config_text": config_text})

@app.post("/save", response_class=RedirectResponse)
def save_config(request: Request, config_text: str = Form(...)):
    with open(CONFIG_PATH, "w") as f:
        f.write(config_text)
    return RedirectResponse("/", status_code=303)

if __name__ == "__main__":
    import uvicorn
    if not os.path.exists("templates"):
        os.makedirs("templates")
    template_path = os.path.join("templates", "editor.html")
    if not os.path.exists(template_path):
        with open(template_path, "w") as f:
            f.write("""
<!DOCTYPE html>
<html>
<head>
    <title>Edit Config</title>
</head>
<body>
    <h1>Edit config.yaml</h1>
    <form method=\"post\" action=\"/save\">
        <textarea name=\"config_text\" rows=\"30\" cols=\"100\">{{ config_text }}</textarea><br>
        <button type=\"submit\">Save</button>
    </form>
</body>
</html>
""")
    uvicorn.run(app, host="0.0.0.0", port=8004)
