import os
import smtplib
import ssl
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


def send_otp_email(
    *,
    to_email: str,
    otp: str,
    subject: str | None = None,
    body_template: str | None = None,
) -> tuple[bool, str | None, str | None]:
    """Send a 6-digit OTP to an email address via SMTP.

    Env vars:
      - SMTP_HOST (required)
      - SMTP_PORT (default: 587)
      - SMTP_USERNAME (required)
      - SMTP_PASSWORD (required)  # for Gmail use an App Password
      - SMTP_FROM (default: SMTP_USERNAME)
      - OTP_EMAIL_SUBJECT (default: Vivian Loyalty Verification Code)
      - OTP_EMAIL_BODY_TEMPLATE (default: Your Vivian Loyalty verification code is {otp})
      - SMTP_USE_TLS (default: true)

    Returns:
      (success, error_message, masked_destination)
    """

    host = (os.getenv('SMTP_HOST') or '').strip()
    user = (os.getenv('SMTP_USERNAME') or '').strip()
    password = (os.getenv('SMTP_PASSWORD') or '').strip()

    if not host or not user or not password:
        return False, 'Email OTP is not configured (SMTP_HOST/SMTP_USERNAME/SMTP_PASSWORD)', None

    port_raw = (os.getenv('SMTP_PORT') or '587').strip()
    try:
        port = int(port_raw)
    except Exception:
        port = 587

    from_email = (os.getenv('SMTP_FROM') or user).strip()
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

    msg = EmailMessage()
    msg['From'] = from_email
    msg['To'] = to
    msg['Subject'] = subject
    msg.set_content(body)

    use_tls = (os.getenv('SMTP_USE_TLS') or 'true').strip().lower() in {'1', 'true', 'yes', 'on'}

    try:
        if use_tls:
            context = ssl.create_default_context()
            with smtplib.SMTP(host=host, port=port, timeout=20) as server:
                server.ehlo()
                server.starttls(context=context)
                server.ehlo()
                server.login(user, password)
                server.send_message(msg)
        else:
            with smtplib.SMTP(host=host, port=port, timeout=20) as server:
                server.ehlo()
                server.login(user, password)
                server.send_message(msg)
        return True, None, _mask_email(to)
    except Exception as e:
        return False, f'Failed to send email: {e}', _mask_email(to)
