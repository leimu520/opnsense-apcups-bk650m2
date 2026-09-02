#!/usr/local/bin/python3
"""
APC BK650M2 UPS notification dispatcher.
Reads /usr/local/opnsense/scripts/apcupsbk650m2/notify.conf and sends
notifications through enabled channels.

Test usage:
    notify.py --config /tmp/test.conf --channel email "subject" "body"
"""

import argparse
import base64
import hashlib
import hmac
import json
import smtplib
import ssl
import sys
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timezone
from email.mime.text import MIMEText
from pathlib import Path

CONFIG_PATH = "/usr/local/opnsense/scripts/apcupsbk650m2/notify.conf"


def log(msg):
    sys.stderr.write(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {msg}\n")


def load_config(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as e:
        log(f"Failed to load config: {e}")
        return {"enabled": False}


def send_email(cfg, subject, body):
    host = cfg.get("email_smtp_host", "").strip()
    port = int(cfg.get("email_smtp_port", 587))
    username = cfg.get("email_smtp_username", "").strip()
    password = cfg.get("email_smtp_password", "")
    from_addr = cfg.get("email_from", "").strip()
    to_addrs = [a.strip() for a in cfg.get("email_to", "").split(",") if a.strip()]
    use_tls = bool(cfg.get("email_use_tls", True))

    if not host or not from_addr or not to_addrs:
        log("Email config incomplete")
        return False

    # 163/QQ/Gmail 等通常要求发件人与登录账号一致
    if username and from_addr != username:
        log(f"Warning: email from address ({from_addr}) does not match SMTP username ({username}). "
            "Some providers such as 163 require them to be identical.")

    msg = MIMEText(body, "plain", "utf-8")
    msg["Subject"] = subject
    msg["From"] = from_addr
    msg["To"] = ", ".join(to_addrs)

    try:
        context = ssl.create_default_context()
        # Port 465 is conventionally SSL-wrapped SMTP (SMTPS).
        if port == 465:
            log("Using SMTP_SSL for port 465")
            server = smtplib.SMTP_SSL(host, port, timeout=15, context=context)
        else:
            server = smtplib.SMTP(host, port, timeout=15)
            # Establish TLS if requested (STARTTLS, typical for port 587/25).
            if use_tls:
                server.starttls(context=context)
        if username and password:
            server.login(username, password)
        server.sendmail(from_addr, to_addrs, msg.as_string())
        server.quit()
        log("Email sent")
        return True
    except Exception as e:
        log(f"Email failed: {e}")
        return False


def send_wechat_bot(cfg, subject, body):
    webhook = cfg.get("wechat_bot_webhook", "").strip()
    if not webhook:
        log("WeChat bot webhook not configured")
        return False

    payload = {
        "msgtype": "text",
        "text": {"content": f"{subject}\n{body}"}
    }

    try:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(
            webhook,
            data=data,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = resp.read().decode("utf-8")
            log(f"WeChat bot result: {result}")
            return True
    except Exception as e:
        log(f"WeChat bot failed: {e}")
        return False


def get_wechat_app_token(corp_id, corp_secret):
    url = f"https://qyapi.weixin.qq.com/cgi-bin/gettoken?corpid={corp_id}&corpsecret={corp_secret}"
    try:
        with urllib.request.urlopen(url, timeout=15) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data.get("access_token")
    except Exception as e:
        log(f"WeChat app token failed: {e}")
        return None


def send_wechat_app(cfg, subject, body):
    corp_id = cfg.get("wechat_app_corp_id", "").strip()
    corp_secret = cfg.get("wechat_app_corp_secret", "").strip()
    agent_id = cfg.get("wechat_app_agent_id", "").strip()
    to_user = cfg.get("wechat_app_to_user", "@all").strip()

    if not corp_id or not corp_secret or not agent_id:
        log("WeChat app config incomplete")
        return False

    token = get_wechat_app_token(corp_id, corp_secret)
    if not token:
        return False

    payload = {
        "touser": to_user,
        "msgtype": "text",
        "agentid": agent_id,
        "text": {"content": f"{subject}\n{body}"}
    }

    url = f"https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token={token}"
    try:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = resp.read().decode("utf-8")
            log(f"WeChat app result: {result}")
            return True
    except Exception as e:
        log(f"WeChat app failed: {e}")
        return False


def send_aliyun_sms(cfg, subject, body):
    access_key = cfg.get("sms_api_key", "").strip()
    access_secret = cfg.get("sms_api_secret", "").strip()
    phone_numbers = cfg.get("sms_phone_number", "").strip()
    sign_name = cfg.get("sms_sign_name", "").strip()
    template_code = cfg.get("sms_template_code", "").strip()

    if not access_key or not access_secret or not phone_numbers or not sign_name or not template_code:
        log("Aliyun SMS config incomplete")
        return False

    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    params = {
        "AccessKeyId": access_key,
        "Action": "SendSms",
        "Format": "JSON",
        "PhoneNumbers": phone_numbers,
        "RegionId": "cn-hangzhou",
        "SignName": sign_name,
        "SignatureMethod": "HMAC-SHA1",
        "SignatureNonce": str(uuid.uuid4()),
        "SignatureVersion": "1.0",
        "TemplateCode": template_code,
        "TemplateParam": json.dumps({"subject": subject, "body": body}, ensure_ascii=False),
        "Timestamp": timestamp,
        "Version": "2017-05-25"
    }

    sorted_params = sorted(params.items())
    canonical = urllib.parse.urlencode(sorted_params)
    string_to_sign = f"GET&%2F&{urllib.parse.quote(canonical, safe='')}"
    sign_key = f"{access_secret}&"
    signature = base64.b64encode(
        hmac.new(sign_key.encode(), string_to_sign.encode(), hashlib.sha1).digest()
    ).decode()

    query = urllib.parse.urlencode({**params, "Signature": signature})
    url = f"https://dysmsapi.aliyuncs.com/?{query}"

    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            result = resp.read().decode("utf-8")
            log(f"Aliyun SMS result: {result}")
            return True
    except Exception as e:
        log(f"Aliyun SMS failed: {e}")
        return False


def send_custom_sms(cfg, subject, body):
    api_url = cfg.get("sms_api_url", "").strip()
    api_key = cfg.get("sms_api_key", "").strip()
    api_secret = cfg.get("sms_api_secret", "").strip()
    phone_numbers = cfg.get("sms_phone_number", "").strip()

    if not api_url:
        log("Custom SMS API URL not configured")
        return False

    payload = {
        "key": api_key,
        "secret": api_secret,
        "phone": phone_numbers,
        "subject": subject,
        "body": body,
        "message": f"{subject} {body}"
    }

    try:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        req = urllib.request.Request(
            api_url,
            data=data,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST"
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            result = resp.read().decode("utf-8")
            log(f"Custom SMS result: {result}")
            return True
    except Exception as e:
        log(f"Custom SMS failed: {e}")
        return False


def send_sms(cfg, subject, body):
    provider = cfg.get("sms_provider", "aliyun")
    if provider == "aliyun":
        return send_aliyun_sms(cfg, subject, body)
    elif provider == "custom":
        return send_custom_sms(cfg, subject, body)
    else:
        log(f"Unknown SMS provider: {provider}")
        return False


CHANNELS = {
    "email": send_email,
    "wechat_bot": send_wechat_bot,
    "wechat_app": send_wechat_app,
    "sms": send_sms,
}


def parse_args():
    parser = argparse.ArgumentParser(description="APC BK650M2 notification dispatcher")
    parser.add_argument("--config", default=CONFIG_PATH, help="path to notify.conf")
    parser.add_argument("--channel", choices=list(CHANNELS.keys()), help="send only to this channel (test mode)")
    parser.add_argument("subject", help="message subject")
    parser.add_argument("body", help="message body")
    return parser.parse_args()


def main():
    args = parse_args()
    cfg = load_config(args.config)

    if args.channel:
        # Test mode: always attempt the selected channel, regardless of global/channel enable flags.
        sender = CHANNELS.get(args.channel)
        ok = sender(cfg, args.subject, args.body)
        sys.exit(0 if ok else 1)

    if not cfg.get("enabled"):
        log("Notifications disabled")
        sys.exit(0)

    results = []
    if cfg.get("email_enabled"):
        results.append(send_email(cfg, args.subject, args.body))
    if cfg.get("wechat_bot_enabled"):
        results.append(send_wechat_bot(cfg, args.subject, args.body))
    if cfg.get("wechat_app_enabled"):
        results.append(send_wechat_app(cfg, args.subject, args.body))
    if cfg.get("sms_enabled"):
        results.append(send_sms(cfg, args.subject, args.body))

    if results and not all(results):
        sys.exit(1)


if __name__ == "__main__":
    main()
