import os
import json
import smtplib
import ssl
import urllib.request
import urllib.error
from email.message import EmailMessage


def _mask_email(email: str) -> str:
    e = (email or '').strip()
    if not e or '@' not in e:
        return ''
    name, domain = e.split('@', 1)
    if len(name) <= 2:
        masked_name = name[:1] + '*'
    else:
        masked_name = name[:1] + ('*' * (len(name) - 2)) + name[-1:]
    return f'{masked_name}@{domain}'


def _get_timeout_seconds() -> float:
    raw = (os.getenv('EMAIL_SEND_TIMEOUT_SECONDS') or os.getenv('SMTP_TIMEOUT_SECONDS') or '8').strip()
    try:
        value = float(raw)
    except Exception:
        value = 8.0
    if value <= 0:
        return 8.0
    return min(value, 20.0)


def _send_via_sendgrid_http(
    *,
    to_email: str,
    subject: str,
    body: str,
) -> tuple[bool, str | None]:
    api_key = (os.getenv('SENDGRID_API_KEY') or '').strip()
    if not api_key:
        return False, 'SENDGRID_API_KEY is not configured'

    from_email = (os.getenv('SENDGRID_FROM') or os.getenv('SMTP_FROM') or '').strip()
    if not from_email:
        return False, 'SENDGRID_FROM is not configured'

    payload = {
        'personalizations': [{'to': [{'email': to_email}]}],
        'from': {'email': from_email},
        'subject': subject,
        'content': [{'type': 'text/plain', 'value': body}],
    }

    req = urllib.request.Request(
        url='https://api.sendgrid.com/v3/mail/send',
        data=json.dumps(payload).encode('utf-8'),
        method='POST',
        headers={
            'Authorization': f'Bearer {api_key}',
            'Content-Type': 'application/json',
        },
    )

    timeout = _get_timeout_seconds()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            if int(getattr(resp, 'status', 0) or 0) in {200, 202}:
                return True, None
            return False, f'SendGrid API unexpected status: {getattr(resp, "status", None)}'
    except urllib.error.HTTPError as e:
        try:
            body_bytes = e.read(512)
            extra = body_bytes.decode('utf-8', errors='ignore').strip()
        except Exception:
            extra = ''
        msg = f'SendGrid API error: {getattr(e, "code", None)}'
        if extra:
            msg = f'{msg} {extra[:200]}'
        return False, msg
    except Exception as e:
        return False, f'SendGrid request failed: {e}'


def send_otp_email(
    *,
    to_email: str,
    otp: str,
    subject: str | None = None,
    body_template: str | None = None,
) -> tuple[bool, str | None, str | None]:
    """Send a 6-digit OTP to an email address via SendGrid or SMTP.

    Provider selection:
        - If `SENDGRID_API_KEY` is set, use SendGrid HTTP API (recommended on Render).
        - Otherwise fall back to SMTP.

    Env vars (SendGrid HTTP API):
        - SENDGRID_API_KEY (required)
        - SENDGRID_FROM (required)

    Env vars (SMTP fallback):
        - SMTP_HOST (required)
        - SMTP_PORT (default: 587)
        - SMTP_USERNAME (required)
        - SMTP_PASSWORD (required)
        - SMTP_FROM (default: SMTP_USERNAME)
        - OTP_EMAIL_SUBJECT (default: Vivian Loyalty Verification Code)
        - OTP_EMAIL_BODY_TEMPLATE (default: Your Vivian Loyalty verification code is {otp})
        - SMTP_USE_TLS (default: true)

    Timeouts:
        - EMAIL_SEND_TIMEOUT_SECONDS (default: 8; max: 20)
        - SMTP_TIMEOUT_SECONDS (alias for EMAIL_SEND_TIMEOUT_SECONDS)

    Returns:
        (success, error_message, masked_destination)
    """
    to = (to_email or '').strip()
    if not to:
        return False, 'Customer email is missing', None

    subject = (subject or os.getenv('OTP_EMAIL_SUBJECT') or 'Vivian Loyalty Verification Code').strip()
    effective_body_template = (
        body_template
        or os.getenv('OTP_EMAIL_BODY_TEMPLATE')
        or 'Your Vivian Loyalty verification code is {otp}. It expires in 5 minutes.'
    )
    body = (effective_body_template or '').replace('{otp}', str(otp or '').strip())

    # Prefer SendGrid HTTP API when configured.
    if (os.getenv('SENDGRID_API_KEY') or '').strip():
        ok, err = _send_via_sendgrid_http(to_email=to, subject=subject, body=body)
        if ok:
            return True, None, _mask_email(to)
        return False, err or 'Failed to send email via SendGrid', _mask_email(to)

    host = (os.getenv('SMTP_HOST') or '').strip()
    user = (os.getenv('SMTP_USERNAME') or '').strip()
    password = (os.getenv('SMTP_PASSWORD') or '').strip()

    if not host or not user or not password:
        return False, 'Email OTP is not configured (SENDGRID_API_KEY or SMTP_HOST/SMTP_USERNAME/SMTP_PASSWORD)', None

    port_raw = (os.getenv('SMTP_PORT') or '587').strip()
    try:
        port = int(port_raw)
    except Exception:
        port = 587

    from_email = (os.getenv('SMTP_FROM') or user).strip()

    msg = EmailMessage()
    msg['From'] = from_email
    msg['To'] = to
    msg['Subject'] = subject
    msg.set_content(body)

    use_tls = (os.getenv('SMTP_USE_TLS') or 'true').strip().lower() in {'1', 'true', 'yes', 'on'}
    timeout = _get_timeout_seconds()

    try:
        if use_tls:
            context = ssl.create_default_context()
            with smtplib.SMTP(host=host, port=port, timeout=timeout) as server:
                server.ehlo()
                server.starttls(context=context)
                server.ehlo()
                server.login(user, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP(host=host, port=port, timeout=timeout) as server:
                server.ehlo()
                server.login(user, password)
                server.send_message(msg)
        return True, None, _mask_email(to)
    except Exception as e:
        return False, f'Failed to send email: {e}', _mask_email(to)
