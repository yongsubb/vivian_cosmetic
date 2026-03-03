import base64
import json
import os
from typing import Any
from urllib import request
from urllib import error as urlerror
from urllib.parse import urlencode


def format_phone_e164(raw_phone: str) -> str:
    """Best-effort E.164 formatting for SMS providers.

    The app stores phones as digits-only (11-12 digits). Many SMS APIs expect E.164.

    Env vars:
      - OTP_SMS_COUNTRY_CODE (default: 63)

    Examples (PH defaults):
      - 09171234567 -> +639171234567
      - 639171234567 -> +639171234567
    """

    phone = (raw_phone or '').strip()
    if not phone:
        return phone

    # Remove common separators.
    phone = phone.replace(' ', '').replace('-', '').replace('(', '').replace(')', '')

    if phone.startswith('+'):
        return phone

    digits = ''.join(ch for ch in phone if ch.isdigit())
    cc = (os.getenv('OTP_SMS_COUNTRY_CODE') or '63').strip().lstrip('+')
    if not cc:
        return digits

    if len(digits) == 11 and digits.startswith('0'):
        return f'+{cc}{digits[1:]}'

    if len(digits) >= 11 and digits.startswith(cc):
        return f'+{digits}'

    # Fallback: if already looks like a national number, prefix country code.
    return f'+{cc}{digits}'


def format_sms_verify3_target(raw_phone: str) -> str:
    """Format target for RapidAPI sms-verify3.

    Their examples commonly use a space after the country code, like:
      +63 9xxxxxxxxx
    Some providers are picky about this formatting.

    Uses OTP_SMS_COUNTRY_CODE (default 63).
    """

    e164 = format_phone_e164(raw_phone)
    cc = (os.getenv('OTP_SMS_COUNTRY_CODE') or '63').strip().lstrip('+')
    if not cc:
        return e164

    prefix = f'+{cc}'
    if e164.startswith(prefix) and len(e164) > len(prefix):
        rest = e164[len(prefix):]
        if rest and rest[0] != ' ':
            return f'{prefix} {rest.lstrip()}'
    return e164


def _render_template(value: Any, *, phone: str, otp: str) -> Any:
    if isinstance(value, str):
        return value.replace('{phone}', phone).replace('{otp}', otp)
    if isinstance(value, list):
        return [_render_template(v, phone=phone, otp=otp) for v in value]
    if isinstance(value, dict):
        return {k: _render_template(v, phone=phone, otp=otp) for k, v in value.items()}
    return value


def _load_headers_json(env_var: str) -> tuple[dict[str, str], str | None]:
    headers_raw = (os.getenv(env_var) or '').strip()
    if not headers_raw:
        return {}, None

    try:
        parsed = json.loads(headers_raw)
        if not isinstance(parsed, dict):
            return {}, f'{env_var} must be a JSON object'
        return {str(k): str(v) for k, v in parsed.items()}, None
    except Exception:
        return {}, f'{env_var} is not valid JSON'


def _normalize_common_headers(headers: dict[str, str]) -> dict[str, str]:
    # Some providers behind RapidAPI/Cloudflare block requests with no User-Agent.
    headers.setdefault(
        'User-Agent',
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    )
    headers.setdefault('Accept', 'application/json,text/plain,*/*')

    # Canonicalize RapidAPI header casing (some gateways can be picky).
    lower_to_key = {k.lower(): k for k in list(headers.keys())}
    for low, canon in [
        ('x-rapidapi-key', 'X-RapidAPI-Key'),
        ('x-rapidapi-host', 'X-RapidAPI-Host'),
    ]:
        original_key = lower_to_key.get(low)
        if not original_key:
            continue
        value = headers.get(original_key)
        if value is None:
            continue
        headers[canon] = value
        if original_key != canon:
            headers.pop(original_key, None)

    return headers


def _do_json_request(
    *,
    url: str,
    method: str = 'POST',
    headers: dict[str, str] | None = None,
    body: Any | None = None,
) -> tuple[bool, str, str | None]:
    url = (url or '').strip()
    if not url:
        return False, '', 'URL is empty'

    hdrs = dict(headers or {})
    _normalize_common_headers(hdrs)

    data_bytes: bytes | None
    if body is None:
        data_bytes = None
    else:
        data_bytes = json.dumps(body).encode('utf-8')
        hdrs.setdefault('Content-Type', 'application/json')

    try:
        req = request.Request(url, data=data_bytes, method=(method or 'POST').strip().upper())
        for k, v in hdrs.items():
            req.add_header(k, v)

        with request.urlopen(req, timeout=15) as resp:
            status = getattr(resp, 'status', 0) or 0
            text = ''
            try:
                text = (resp.read() or b'').decode('utf-8', errors='replace')
            except Exception:
                text = ''

            if 200 <= int(status) < 300:
                return True, text, None

            snippet = (text or '').strip().replace('\r', ' ').replace('\n', ' ')
            if len(snippet) > 300:
                snippet = snippet[:300] + '…'
            detail = f'HTTP {status}'
            if snippet:
                detail = f'{detail}: {snippet}'
            return False, text, detail
    except urlerror.HTTPError as e:
        try:
            body_text = (e.read() or b'').decode('utf-8', errors='replace')
        except Exception:
            body_text = ''

        snippet = (body_text or '').strip().replace('\r', ' ').replace('\n', ' ')
        if len(snippet) > 300:
            snippet = snippet[:300] + '…'

        status = getattr(e, 'code', None)
        detail = f'HTTP Error {status}: {getattr(e, "reason", "")}'.strip()
        if snippet:
            detail = f'{detail} | {snippet}'
        return False, body_text, detail
    except Exception as e:
        return False, '', str(e)


def _do_form_request(
    *,
    url: str,
    method: str = 'POST',
    headers: dict[str, str] | None = None,
    form: dict[str, Any] | None = None,
) -> tuple[bool, str, str | None]:
    url = (url or '').strip()
    if not url:
        return False, '', 'URL is empty'

    hdrs = dict(headers or {})
    _normalize_common_headers(hdrs)
    hdrs.setdefault('Content-Type', 'application/x-www-form-urlencoded')

    data_bytes: bytes | None
    if form is None:
        data_bytes = None
    else:
        encoded = urlencode({k: '' if v is None else str(v) for k, v in form.items()})
        data_bytes = encoded.encode('utf-8')

    try:
        req = request.Request(url, data=data_bytes, method=(method or 'POST').strip().upper())
        for k, v in hdrs.items():
            req.add_header(k, v)

        with request.urlopen(req, timeout=15) as resp:
            status = getattr(resp, 'status', 0) or 0
            text = ''
            try:
                text = (resp.read() or b'').decode('utf-8', errors='replace')
            except Exception:
                text = ''

            if 200 <= int(status) < 300:
                return True, text, None

            snippet = (text or '').strip().replace('\r', ' ').replace('\n', ' ')
            if len(snippet) > 300:
                snippet = snippet[:300] + '…'
            detail = f'HTTP {status}'
            if snippet:
                detail = f'{detail}: {snippet}'
            return False, text, detail
    except urlerror.HTTPError as e:
        try:
            body_text = (e.read() or b'').decode('utf-8', errors='replace')
        except Exception:
            body_text = ''

        snippet = (body_text or '').strip().replace('\r', ' ').replace('\n', ' ')
        if len(snippet) > 300:
            snippet = snippet[:300] + '…'

        status = getattr(e, 'code', None)
        detail = f'HTTP Error {status}: {getattr(e, "reason", "")}'.strip()
        if snippet:
            detail = f'{detail} | {snippet}'
        return False, body_text, detail
    except Exception as e:
        return False, '', str(e)


def _digits_only(phone: str) -> str:
    raw = (phone or '').strip()
    return ''.join(ch for ch in raw if ch.isdigit())


def textbelt_send_otp_sms(*, phone: str, otp: str) -> tuple[bool, str | None]:
    """Send an OTP message via a self-hosted Textbelt server.

    Textbelt expects x-www-form-urlencoded fields: number, message, (optional) key.

    Env vars:
      - OTP_TEXTBELT_URL (default: http://localhost:9090/text)
      - OTP_TEXTBELT_KEY (optional)
      - OTP_TEXTBELT_MESSAGE_TEMPLATE (default: 'Your Vivian Loyalty OTP is {otp}')

    Notes:
      - Textbelt expects digits (no '+'). For PH we send e.g. 639xxxxxxxxx.
    """

    url = (os.getenv('OTP_TEXTBELT_URL') or 'http://localhost:9090/text').strip()
    if not url:
        return False, 'OTP_TEXTBELT_URL is not configured'

    key = (os.getenv('OTP_TEXTBELT_KEY') or '').strip()
    template = (os.getenv('OTP_TEXTBELT_MESSAGE_TEMPLATE') or 'Your Vivian Loyalty OTP is {otp}').strip()
    message = template.replace('{otp}', str(otp or '').strip())

    # Textbelt wants digits-only, typically country code + national number for /intl.
    number = _digits_only(phone)
    if not number:
        return False, 'Phone number is empty'

    # If configured to hit /text (US-only) but we have an international-looking number,
    # switch to /intl to avoid immediate "Invalid phone number" responses.
    if url.rstrip('/').endswith('/text') and (len(number) < 9 or len(number) > 10):
        url = url.rstrip('/')[:-5] + '/intl'

    headers: dict[str, str] = {}
    form: dict[str, Any] = {
        'number': number,
        'message': message,
    }
    if key:
        form['key'] = key

    ok, text, err = _do_form_request(url=url, method='POST', headers=headers, form=form)
    if not ok:
        return False, f'Failed to send SMS via Textbelt: {err or "Unknown error"}'

    # Textbelt returns JSON like: {"success": true} or {"success": false, "message": "..."}
    try:
        data = json.loads(text) if text else None
        if isinstance(data, dict) and data.get('success') is False:
            return False, f"Textbelt send failed: {data.get('message') or 'Unknown error'}"
    except Exception:
        # Non-JSON response: assume success if HTTP 2xx.
        pass

    return True, None


def _do_sms_request(*, phone: str, otp: str) -> tuple[bool, str, str | None]:
    url = (os.getenv('OTP_SMS_URL') or '').strip()
    if not url:
        return False, '', 'OTP_SMS_URL is not configured'

    method = (os.getenv('OTP_SMS_METHOD') or 'POST').strip().upper()

    headers, headers_err = _load_headers_json('OTP_SMS_HEADERS_JSON')
    if headers_err:
        return False, '', headers_err

    _normalize_common_headers(headers)

    body_template_raw = (os.getenv('OTP_SMS_BODY_TEMPLATE_JSON') or '').strip()
    body_bytes = b''
    if body_template_raw:
        try:
            template = json.loads(body_template_raw)
        except Exception:
            return False, '', 'OTP_SMS_BODY_TEMPLATE_JSON is not valid JSON'

        rendered = _render_template(template, phone=phone, otp=otp)
        body_bytes = json.dumps(rendered).encode('utf-8')
        headers.setdefault('Content-Type', 'application/json')

    try:
        req = request.Request(url, data=body_bytes or None, method=method)
        for k, v in headers.items():
            req.add_header(k, v)

        with request.urlopen(req, timeout=15) as resp:
            status = getattr(resp, 'status', 0) or 0
            text = ''
            try:
                text = (resp.read() or b'').decode('utf-8', errors='replace')
            except Exception:
                text = ''

            if 200 <= int(status) < 300:
                return True, text, None

            snippet = (text or '').strip().replace('\r', ' ').replace('\n', ' ')
            if len(snippet) > 300:
                snippet = snippet[:300] + '…'
            detail = f'SMS provider HTTP {status}'
            if snippet:
                detail = f'{detail}: {snippet}'
            return False, text, detail
    except urlerror.HTTPError as e:
        # HTTPError is file-like; capture any JSON/plain response body.
        try:
            body = (e.read() or b'').decode('utf-8', errors='replace')
        except Exception:
            body = ''

        snippet = (body or '').strip().replace('\r', ' ').replace('\n', ' ')
        if len(snippet) > 300:
            snippet = snippet[:300] + '…'

        status = getattr(e, 'code', None)
        detail = f'HTTP Error {status}: {getattr(e, "reason", "")}'.strip()
        if snippet:
            detail = f'{detail} | {snippet}'
        return False, body, f'Failed to send SMS: {detail}'
    except Exception as e:
        return False, '', f'Failed to send SMS: {e}'


def send_otp_sms(*, phone: str, otp: str) -> tuple[bool, str | None]:
    """Send OTP via an external SMS provider configured by env vars.

    This is intentionally generic so you can use RapidAPI/D7 or any provider.

    Required env vars:
      - OTP_SMS_URL

    Optional env vars:
      - OTP_SMS_METHOD (default: POST)
      - OTP_SMS_HEADERS_JSON (JSON string)
      - OTP_SMS_BODY_TEMPLATE_JSON (JSON string with placeholders {phone} and {otp})

    Returns:
      (success, error_message)
    """

    ok, _text, err = _do_sms_request(phone=phone, otp=otp)
    return ok, err


def request_provider_otp(*, phone: str) -> tuple[bool, str | None, str | None]:
    """Request an OTP from a provider that generates the code server-side.

    Some APIs (like RapidAPI sms-verify3) send an SMS and also return the
    verification code in the HTTP response. In this mode, we extract the code
    and store it server-side (hashed) without ever returning it to the client.

    Env vars:
      - OTP_SMS_RESPONSE_VERIFY_CODE_FIELD (default: verify_code)
    """

    ok, text, err = _do_sms_request(phone=phone, otp='')
    if not ok:
        return False, None, err

    if not text:
        return False, None, 'SMS provider response was empty'

    try:
        data = json.loads(text)
    except Exception:
        return False, None, 'SMS provider response was not valid JSON'

    field = (os.getenv('OTP_SMS_RESPONSE_VERIFY_CODE_FIELD') or 'verify_code').strip()
    if not field:
        field = 'verify_code'

    code = data.get(field) if isinstance(data, dict) else None
    if code is None:
        return False, None, f"SMS provider response missing '{field}'"

    code_str = str(code).strip()
    if not code_str:
        return False, None, f"SMS provider '{field}' was empty"

    return True, code_str, None


def textflow_send_otp_code(*, phone: str) -> tuple[bool, str | None]:
    """TextFlow RapidAPI: send OTP code to phone.

    Uses RapidAPI headers from OTP_SMS_HEADERS_JSON and these env vars:
      - OTP_TEXTFLOW_API_KEY (required)
      - OTP_TEXTFLOW_SERVICE_NAME (default: Vivian Loyalty)
      - OTP_TEXTFLOW_EXPIRATION_SECONDS (default: 300)
      - OTP_TEXTFLOW_SEND_URL (default: https://textflow-sms-api.p.rapidapi.com/send-code)
    """

    send_url = (
        os.getenv('OTP_TEXTFLOW_SEND_URL')
        or 'https://textflow-sms-api.p.rapidapi.com/send-code'
    ).strip()
    service_name = (os.getenv('OTP_TEXTFLOW_SERVICE_NAME') or 'Vivian Loyalty').strip()
    expiration_raw = (os.getenv('OTP_TEXTFLOW_EXPIRATION_SECONDS') or '60').strip()
    expiration = '60'
    try:
        expiration_int = int(expiration_raw)
        if expiration_int > 0:
            expiration = str(expiration_int)
    except Exception:
        expiration = '60'

    headers, headers_err = _load_headers_json('OTP_SMS_HEADERS_JSON')
    if headers_err:
        return False, headers_err

    # TextFlow docs show an `api_key` field in the JSON body.
    # Prefer OTP_TEXTFLOW_API_KEY, but fall back to the RapidAPI key if present.
    api_key = (os.getenv('OTP_TEXTFLOW_API_KEY') or '').strip()
    if not api_key:
        api_key = (
            headers.get('X-RapidAPI-Key')
            or headers.get('x-rapidapi-key')
            or headers.get('X-Rapidapi-Key')
            or ''
        ).strip()
    if not api_key:
        return False, 'OTP_TEXTFLOW_API_KEY is not configured (and RapidAPI key header missing)'

    body = {
        'data': {
            'phone_number': (phone or '').strip(),
            'service_name': service_name,
            'expiration_time': str(expiration),
            'api_key': api_key,
        }
    }

    ok, text, err = _do_json_request(url=send_url, method='POST', headers=headers, body=body)
    if not ok:
        return False, f'Failed to send OTP via TextFlow: {err or "Unknown error"}'

    # Some APIs return 2xx even on failure; try to detect common error shapes.
    try:
        data = json.loads(text) if text else None
        if isinstance(data, dict):
            if data.get('status') in {'failed', 'error'}:
                return False, f"TextFlow send failed: {data.get('message') or data.get('error') or data.get('status')}"
            if data.get('success') is False:
                return False, f"TextFlow send failed: {data.get('message') or 'Unknown error'}"
            if data.get('error'):
                return False, f"TextFlow send failed: {data.get('error')}"
    except Exception:
        pass

    return True, None


def textflow_verify_otp_code(*, phone: str, code: str) -> tuple[bool, str | None]:
    """TextFlow RapidAPI: verify OTP code for phone.

    Uses RapidAPI headers from OTP_SMS_HEADERS_JSON and these env vars:
      - OTP_TEXTFLOW_API_KEY (required)
      - OTP_TEXTFLOW_VERIFY_URL (default: https://textflow-sms-api.p.rapidapi.com/verify-code)
    """

    verify_url = (
        os.getenv('OTP_TEXTFLOW_VERIFY_URL')
        or 'https://textflow-sms-api.p.rapidapi.com/verify-code'
    ).strip()

    headers, headers_err = _load_headers_json('OTP_SMS_HEADERS_JSON')
    if headers_err:
        return False, headers_err

    api_key = (os.getenv('OTP_TEXTFLOW_API_KEY') or '').strip()
    if not api_key:
        api_key = (
            headers.get('X-RapidAPI-Key')
            or headers.get('x-rapidapi-key')
            or headers.get('X-Rapidapi-Key')
            or ''
        ).strip()
    if not api_key:
        return False, 'OTP_TEXTFLOW_API_KEY is not configured (and RapidAPI key header missing)'

    body = {
        'data': {
            'phone_number': (phone or '').strip(),
            'code': (code or '').strip(),
            'api_key': api_key,
        }
    }

    ok, text, err = _do_json_request(url=verify_url, method='POST', headers=headers, body=body)
    if not ok:
        return False, f'Failed to verify OTP via TextFlow: {err or "Unknown error"}'

    if not text:
        # If TextFlow returns an empty 2xx, treat as success.
        return True, None

    try:
        data = json.loads(text)
    except Exception:
        # Non-JSON 2xx; treat as success.
        return True, None

    # Try a few common response shapes.
    if isinstance(data, dict):
        if data.get('status') in {'failed', 'error'}:
            return False, str(data.get('message') or data.get('error') or 'Invalid OTP')
        if 'success' in data:
            return (bool(data.get('success')), None if data.get('success') else (str(data.get('message') or 'Invalid OTP')))

        inner = data.get('data') if isinstance(data.get('data'), dict) else None
        if inner is not None:
            for key in ['verified', 'valid', 'is_valid', 'ok']:
                if key in inner:
                    return (bool(inner.get(key)), None if inner.get(key) else 'Invalid OTP')

        message = str(data.get('message') or '')
        if message:
            low = message.lower()
            if 'invalid' in low or 'wrong' in low or 'failed' in low:
                return False, message
            if 'verified' in low or 'success' in low or 'valid' in low:
                return True, None

    # Default: assume 2xx means verified unless explicitly flagged otherwise.
    return True, None


def _twilio_basic_auth_header(*, account_sid: str, auth_token: str) -> str:
    token = f'{account_sid}:{auth_token}'.encode('utf-8')
    return 'Basic ' + base64.b64encode(token).decode('ascii')


def twilio_verify_send_code(*, phone: str, channel: str | None = None) -> tuple[bool, str | None]:
    """Twilio Verify: send an OTP code to the given phone number.

    Env vars:
      - TWILIO_ACCOUNT_SID (required)
      - TWILIO_AUTH_TOKEN (required)
      - TWILIO_VERIFY_SERVICE_SID (required)
      - TWILIO_VERIFY_CHANNEL (optional, default: sms)
    """

    account_sid = (os.getenv('TWILIO_ACCOUNT_SID') or '').strip()
    auth_token = (os.getenv('TWILIO_AUTH_TOKEN') or '').strip()
    service_sid = (os.getenv('TWILIO_VERIFY_SERVICE_SID') or '').strip()
    if not account_sid or not auth_token or not service_sid:
        return False, 'Twilio Verify is not configured (TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN/TWILIO_VERIFY_SERVICE_SID)'
    if not account_sid.startswith('AC'):
        return False, 'TWILIO_ACCOUNT_SID must be your Twilio Account SID (starts with "AC")'
    if not service_sid.startswith('VA'):
        return False, 'TWILIO_VERIFY_SERVICE_SID must be your Twilio Verify Service SID (starts with "VA")'

    to = (phone or '').strip()
    if not to:
        return False, 'Phone number is empty'
    if not to.startswith('+'):
        to = format_phone_e164(to)

    channel_value = (channel or os.getenv('TWILIO_VERIFY_CHANNEL') or 'sms').strip().lower()
    if not channel_value:
        channel_value = 'sms'

    url = f'https://verify.twilio.com/v2/Services/{service_sid}/Verifications'
    headers = {
        'Authorization': _twilio_basic_auth_header(account_sid=account_sid, auth_token=auth_token),
    }
    form = {
        'To': to,
        'Channel': channel_value,
    }

    ok, text, err = _do_form_request(url=url, method='POST', headers=headers, form=form)
    if not ok:
        return False, f'Twilio Verify send failed: {err or "Unknown error"}'

    # Best-effort detection of error payloads that still return 2xx.
    try:
        data = json.loads(text) if text else None
        if isinstance(data, dict):
            if data.get('error_code') or data.get('error_message'):
                return False, f"Twilio Verify send failed: {data.get('error_message') or data.get('error_code')}"
            status = str(data.get('status') or '').strip().lower()
            if status in {'canceled', 'failed'}:
                return False, f'Twilio Verify send failed: status={status}'
    except Exception:
        pass

    return True, None


def twilio_verify_check_code(*, phone: str, code: str) -> tuple[bool, str | None]:
    """Twilio Verify: check an OTP code for the given phone number.

    Returns:
      (verified, error_message)
    """

    account_sid = (os.getenv('TWILIO_ACCOUNT_SID') or '').strip()
    auth_token = (os.getenv('TWILIO_AUTH_TOKEN') or '').strip()
    service_sid = (os.getenv('TWILIO_VERIFY_SERVICE_SID') or '').strip()
    if not account_sid or not auth_token or not service_sid:
        return False, 'Twilio Verify is not configured (TWILIO_ACCOUNT_SID/TWILIO_AUTH_TOKEN/TWILIO_VERIFY_SERVICE_SID)'
    if not account_sid.startswith('AC'):
        return False, 'TWILIO_ACCOUNT_SID must be your Twilio Account SID (starts with "AC")'
    if not service_sid.startswith('VA'):
        return False, 'TWILIO_VERIFY_SERVICE_SID must be your Twilio Verify Service SID (starts with "VA")'

    to = (phone or '').strip()
    if not to:
        return False, 'Phone number is empty'
    if not to.startswith('+'):
        to = format_phone_e164(to)

    code_value = (code or '').strip()
    if not code_value:
        return False, 'OTP code is empty'

    url = f'https://verify.twilio.com/v2/Services/{service_sid}/VerificationCheck'
    headers = {
        'Authorization': _twilio_basic_auth_header(account_sid=account_sid, auth_token=auth_token),
    }
    form = {
        'To': to,
        'Code': code_value,
    }

    ok, text, err = _do_form_request(url=url, method='POST', headers=headers, form=form)
    if not ok:
        return False, f'Twilio Verify check failed: {err or "Unknown error"}'

    if not text:
        return False, 'Twilio Verify response was empty'

    try:
        data = json.loads(text)
    except Exception:
        return False, 'Twilio Verify response was not valid JSON'

    if not isinstance(data, dict):
        return False, 'Twilio Verify response was not an object'

    # Twilio commonly returns: {"status":"approved"|"pending", "valid": true|false, ...}
    status = str(data.get('status') or '').strip().lower()
    valid = data.get('valid')

    if status == 'approved' or valid is True:
        return True, None

    if data.get('error_code') or data.get('error_message'):
        return False, str(data.get('error_message') or data.get('error_code'))

    if status:
        return False, f'Not approved (status={status})'

    return False, 'Invalid OTP code'
