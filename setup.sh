#!/bin/bash

# Define paths
SERVICE_PATH="/etc/systemd/system/alert_monitor.service"
SCRIPT_PATH="/opt/alert_monitor.py"

# Create Python monitoring script
cat << 'EOF' > "$SCRIPT_PATH"
#!/usr/bin/env python3

#!/usr/bin/env python3

import os
import time
import socket
import subprocess
from datetime import datetime
from email.message import EmailMessage
import smtplib

# ------------------------- CONFIG -------------------------
SMTP_SERVER = 'smtp.gmail.com'
SMTP_PORT = 587
SMTP_USER = 'babafarooq001@gmail.com'       # <-- Replace with your email
SMTP_PASS = 'hulu pver rsvv rmpk'          # <-- Use App Password
TO_EMAIL = 'babafarooq@gmail.com'   # <-- Replace with destination
LAST_POS_FILE = '/var/tmp/.sshlog_pos'   # Make sure this is writable
HOSTNAME = socket.gethostname()

# ------------------------- UTILS -------------------------
def get_ip_address():
    try:
        return subprocess.check_output(["curl", "-s", "https://api.ipify.org"], text=True).strip()
    except:
        return "Unavailable"

def get_command_output(command):
    try:
        return subprocess.check_output(command, text=True).strip()
    except Exception as e:
        return f"Error: {e}"

def format_disk_usage(disk_info):
    disk_lines = disk_info.splitlines()
    table = """
    <table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: 100%; border: 1px solid #0000FF;">
        <tr style="background-color: #B0C4DE;">
            <th>Filesystem</th><th>Size</th><th>Used</th><th>Avail</th><th>Use%</th><th>Mounted on</th>
        </tr>
    """
    for line in disk_lines[1:]:
        columns = line.split()
        if len(columns) >= 6:
            table += f"<tr><td>{columns[0]}</td><td>{columns[1]}</td><td>{columns[2]}</td><td>{columns[3]}</td><td>{columns[4]}</td><td>{columns[5]}</td></tr>"
    table += "</table>"
    return table

def format_memory_usage(mem_info):
    lines = mem_info.splitlines()
    if len(lines) < 3:
        return "<p>Memory data unavailable</p>"

    mem = lines[1].split()
    swap = lines[2].split()
    table = """
    <table border="1" cellpadding="5" cellspacing="0" style="border-collapse: collapse; width: auto; border: 1px solid #0000FF;">
        <tr style="background-color: #B0C4DE;">
            <th>CPU</th><th>Total</th><th>Used</th><th>Free</th><th>Shared</th><th>Buff/Cache</th><th>Available</th>
        </tr>
        <tr>
            <td>Mem</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td><td>{}</td>
        </tr>
    """.format(*mem[1:8])

    if len(swap) >= 4:
        table += f"<tr><td>Swap</td><td>{swap[1]}</td><td>{swap[2]}</td><td>{swap[3]}</td><td colspan='3'>No Swap Space</td></tr>"
    table += "</table>"
    return table

def get_uptime_seconds():
    try:
        with open("/proc/uptime", "r") as f:
            return int(float(f.readline().split()[0]))
    except:
        return -1

def send_email(subject, html_body):
    msg = EmailMessage()
    msg['Subject'] = subject
    msg['From'] = SMTP_USER
    msg['To'] = TO_EMAIL
    msg.set_content("HTML format required. Please view in email client.")
    msg.add_alternative(html_body, subtype='html')

    with smtplib.SMTP(SMTP_SERVER, SMTP_PORT) as smtp:
        smtp.starttls()
        smtp.login(SMTP_USER, SMTP_PASS)
        smtp.send_message(msg)

# ---------------------- ALERTS --------------------------
def notify_boot():
    uptime = get_uptime_seconds()
    if uptime > 60:  # Skip if system has been up more than 1 minute
        return

    ip = get_ip_address()
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    disk = get_command_output(['df', '-h'])
    mem = get_command_output(['free', '-h'])
    cpu_cores = os.cpu_count()

    body = f"""
    <html><body>
    <h2>🔔 System Boot Detected - {HOSTNAME}</h2>
    <p><b>🖥️ System Info:</b><br>
       <b>🕒 Time:</b> {now}<br>
       <b>🧭 Hostname:</b> {HOSTNAME}<br>
       <b>🌐 IP Address:</b> {ip}<br>
       <b>⚙️ CPU Cores:</b> {cpu_cores}</p>
    <p><b>🧠 Memory:</b></p>{format_memory_usage(mem)}
    <p><b>📀 Disk:</b></p>{format_disk_usage(disk)}
    </body></html>
    """
    send_email(f"🔌 System UP: {HOSTNAME}", body)

def monitor_ssh():
    log_file = "/var/log/auth.log" if os.path.exists("/var/log/auth.log") else "/var/log/secure"
    last_pos = 0
    if os.path.exists(LAST_POS_FILE):
        with open(LAST_POS_FILE, 'r') as f:
            try:
                last_pos = int(f.read().strip())
            except:
                last_pos = 0

    with open(log_file, 'r') as f:
        f.seek(last_pos)
        lines = f.readlines()
        last_pos = f.tell()

    with open(LAST_POS_FILE, 'w') as f:
        f.write(str(last_pos))

    for line in lines:
        if 'Failed password' in line:
            send_email(f"🚫 SSH Login Failed - {HOSTNAME}", f"<pre>{line}</pre>")
        elif 'Accepted password' in line or 'Accepted publickey' in line:
            send_email(f"✅ SSH Login Success - {HOSTNAME}", f"<pre>{line}</pre>")

# ------------------------ MAIN --------------------------
if __name__ == '__main__':
    notify_boot()
    while True:
        monitor_ssh()
        time.sleep(30)  # Check every 30 seconds


EOF

# Make the Python script executable
chmod +x "$SCRIPT_PATH"

# Create systemd service file
cat << EOF > "$SERVICE_PATH"
[Unit]
Description=Alert Monitor Script
After=network.target

[Service]
ExecStart=/usr/bin/python3 $SCRIPT_PATH
WorkingDirectory=/opt
User=root
Group=root
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd daemon and enable/start the service
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable alert_monitor.service
systemctl start alert_monitor.service

echo "Alert monitor service created and started."
