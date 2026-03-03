import base64
import hashlib
import hmac
import http.client
import json
import os
import re
import threading
import time
import urllib.error
import urllib.request
import uuid

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, jwt_required


payments_bp = Blueprint('payments', __name__)


_QRPH_SESSION_TTL_SECONDS = 60 * 60  # keep some buffer beyond 30m expiry
_qrph_lock = threading.Lock()
_qrph_sessions: dict[str, dict] = {}
_qrph_ref_index: dict[str, str] = {}
_qrph_code_index: dict[str, str] = {}


# PayMongo Checkout Session tracking (for fixed-amount GCash flow)
_checkout_lock = threading.Lock()
_checkout_sessions: dict[str, dict] = {}
_checkout_id_index: dict[str, str] = {}


def _now_ts() -> int:
    return int(time.time())


def _cleanup_sessions(*, now: int | None = None):
    now_ts = now if now is not None else _now_ts()
    to_delete: list[str] = []
    for session_id, session in _qrph_sessions.items():
        created_at = int(session.get('created_at') or 0)
        if created_at and (now_ts - created_at) > _QRPH_SESSION_TTL_SECONDS:
            to_delete.append(session_id)

    for session_id in to_delete:
        session = _qrph_sessions.pop(session_id, None) or {}
        ref = session.get('reference_id')
        code_id = session.get('paymongo_code_id')
        if isinstance(ref, str) and ref:
            _qrph_ref_index.pop(ref, None)
        if isinstance(code_id, str) and code_id:
            _qrph_code_index.pop(code_id, None)


def _cleanup_checkout_sessions(*, now: int | None = None):
    now_ts = now if now is not None else _now_ts()
    to_delete: list[str] = []
    for session_id, session in _checkout_sessions.items():
        created_at = int(session.get('created_at') or 0)
        if created_at and (now_ts - created_at) > _QRPH_SESSION_TTL_SECONDS:
            to_delete.append(session_id)

    for session_id in to_delete:
        session = _checkout_sessions.pop(session_id, None) or {}
        checkout_id = session.get('paymongo_checkout_id')
        if isinstance(checkout_id, str) and checkout_id:
            _checkout_id_index.pop(checkout_id, None)


def _parse_paymongo_signature_header(header_value: str | None) -> dict[str, str]:
    if not header_value or not isinstance(header_value, str):
        return {}
    parts = [p.strip() for p in header_value.split(',') if p.strip()]
    out: dict[str, str] = {}
    for part in parts:
        if '=' not in part:
            continue
        k, v = part.split('=', 1)
        k = k.strip()
        v = v.strip()
        if k and v:
            out[k] = v
    return out


def _verify_paymongo_webhook(raw_body: bytes, *, signature_header: str | None, secret: str) -> tuple[bool, str | None]:
    if not secret:
        return False, 'missing_webhook_secret'

    parsed = _parse_paymongo_signature_header(signature_header)
    timestamp = parsed.get('t')
    if not timestamp:
        return False, 'missing_signature_timestamp'

    # Signature string: "{t}.{raw_json_payload}" (raw body, not parsed JSON)
    signed_payload = f"{timestamp}.".encode('utf-8') + (raw_body or b'')
    computed = hmac.new(secret.encode('utf-8'), signed_payload, hashlib.sha256).hexdigest()

    # Accept either test or live signature; event indicates livemode but we may not be able to parse safely
    provided_live = parsed.get('li')
    provided_test = parsed.get('te')

    if provided_live and hmac.compare_digest(computed, provided_live):
        return True, None
    if provided_test and hmac.compare_digest(computed, provided_test):
        return True, None

    return False, 'invalid_signature'


def _collect_string_values(obj, *, max_items: int = 2000) -> list[str]:
    """Collect string values from nested dict/list payloads.

    This is used to match PayMongo webhook payloads back to our in-memory
    QRPh sessions even when the identifying ids are nested (e.g. source.id).
    """
    out: list[str] = []
    if obj is None:
        return out

    stack = [obj]
    seen = set()
    while stack and len(out) < max_items:
        cur = stack.pop()
        try:
            cur_id = id(cur)
            if cur_id in seen:
                continue
            seen.add(cur_id)
        except Exception:
            pass

        if isinstance(cur, str):
            s = cur.strip()
            if not s:
                continue
            # Avoid huge strings (e.g. QR image data URIs, base64 blobs, EMV payloads)
            if len(s) > 256:
                continue
            low = s.lower()
            if low.startswith('data:image/'):
                continue
            if s.startswith('000201'):
                continue
            out.append(s)
            continue

        if isinstance(cur, dict):
            for v in cur.values():
                stack.append(v)
            continue

        if isinstance(cur, list):
            for v in cur:
                stack.append(v)
            continue

    return out


def _find_session_id_from_event_obj(event_obj: dict) -> str | None:
    if not isinstance(event_obj, dict):
        return None

    attrs = event_obj.get('attributes') if isinstance(event_obj.get('attributes'), dict) else {}

    # Candidates we can match against our indices.
    candidates: list[str] = []

    # Direct id of the object in the event.
    obj_id = event_obj.get('id')
    if isinstance(obj_id, str) and obj_id:
        candidates.append(obj_id)

    # Reference id (commonly present in QRPh objects).
    ref = attrs.get('reference_id')
    if isinstance(ref, str) and ref:
        candidates.append(ref)

    # Payments often include external_reference_number.
    ext_ref = attrs.get('external_reference_number')
    if isinstance(ext_ref, str) and ext_ref:
        candidates.append(ext_ref)

    # Metadata may contain your own reference numbers.
    metadata = attrs.get('metadata') if isinstance(attrs.get('metadata'), dict) else {}
    if isinstance(metadata, dict):
        for key in ('pm_reference_number', 'reference_id', 'external_reference_number'):
            val = metadata.get(key)
            if isinstance(val, str) and val:
                candidates.append(val)

    # Some event types (notably payment events) can contain the QRPh code id or
    # reference id nested inside attributes.source / relationships, etc.
    # Collect all small-ish string values and try them against our indices.
    try:
        candidates.extend(_collect_string_values(event_obj))
    except Exception:
        pass

    # De-dupe while preserving order.
    seen_values: set[str] = set()
    unique_candidates: list[str] = []
    for v in candidates:
        if not isinstance(v, str):
            continue
        if v in seen_values:
            continue
        seen_values.add(v)
        unique_candidates.append(v)

    with _qrph_lock:
        _cleanup_sessions()
        for value in unique_candidates:
            if value in _qrph_ref_index:
                return _qrph_ref_index.get(value)
            if value in _qrph_code_index:
                return _qrph_code_index.get(value)
    return None


def _find_checkout_session_id_from_event_obj(event_obj: dict) -> str | None:
    if not isinstance(event_obj, dict):
        return None

    # Collect all small string values and try to match:
    # - our own generated session_id (stored in metadata/description)
    # - PayMongo checkout session id
    candidates: list[str] = []
    try:
        candidates.extend(_collect_string_values(event_obj))
    except Exception:
        candidates = []

    # De-dupe while preserving order.
    seen_values: set[str] = set()
    unique_candidates: list[str] = []
    for v in candidates:
        if not isinstance(v, str):
            continue
        if v in seen_values:
            continue
        seen_values.add(v)
        unique_candidates.append(v)

    with _checkout_lock:
        _cleanup_checkout_sessions()

        for value in unique_candidates:
            if value in _checkout_sessions:
                return value
            if value in _checkout_id_index:
                return _checkout_id_index.get(value)

    return None


def _get_ngrok_https_base_url() -> str | None:
    """Best-effort: read ngrok's local API to get the current HTTPS public URL."""
    try:
        conn = http.client.HTTPConnection('127.0.0.1', 4040, timeout=2)
        conn.request('GET', '/api/tunnels')
        resp = conn.getresponse()
        body = resp.read().decode('utf-8')
        conn.close()
        if resp.status != 200:
            return None
        parsed = json.loads(body or '{}')
        tunnels = parsed.get('tunnels') if isinstance(parsed, dict) else None
        if not isinstance(tunnels, list):
            return None
        for t in tunnels:
            if not isinstance(t, dict):
                continue
            public_url = t.get('public_url')
            if isinstance(public_url, str) and public_url.startswith('https://'):
                return public_url.rstrip('/')
    except Exception:
        return None
    return None


def _public_https_base_url() -> str | None:
    """Resolve a public HTTPS base URL for redirect links.

    Priority:
    1) PUBLIC_HTTPS_BASE_URL env var
    2) ngrok local API (127.0.0.1:4040)
    """
    env_base = (os.getenv('PUBLIC_HTTPS_BASE_URL', '') or '').strip().rstrip('/')
    if env_base.startswith('https://'):
        return env_base

    ngrok_base = _get_ngrok_https_base_url()
    if ngrok_base and ngrok_base.startswith('https://'):
        return ngrok_base

    return None


def _json_error(status: int, message: str, *, error: str | None = None):
    payload = {
        'success': False,
        'message': message,
    }
    if error:
        payload['error'] = error
    return jsonify(payload), status


def _extract_first_string(obj, keys):
    if not isinstance(obj, dict):
        return None
    for key in keys:
        val = obj.get(key)
        if isinstance(val, str) and val.strip():
            return val.strip()
    return None


def _deep_find_first_string(obj, predicate):
    """Depth-first search for the first string that matches [predicate]."""
    try:
        if isinstance(obj, str):
            return obj if predicate(obj) else None
        if isinstance(obj, dict):
            for v in obj.values():
                found = _deep_find_first_string(v, predicate)
                if found:
                    return found
            return None
        if isinstance(obj, list):
            for v in obj:
                found = _deep_find_first_string(v, predicate)
                if found:
                    return found
            return None
    except Exception:
        return None
    return None


_BASE64_RE = re.compile(r'^[A-Za-z0-9+/=\s]+$')


def _looks_like_base64_image(s: str) -> bool:
    if not isinstance(s, str):
        return False
    v = s.strip()
    if len(v) < 200:
        return False
    if v.lower().startswith(('http://', 'https://', 'data:image/')):
        return False
    return bool(_BASE64_RE.match(v))


def _as_data_uri_if_base64(s: str | None) -> str | None:
    if not s:
        return None
    v = s.strip()
    if v.lower().startswith(('http://', 'https://', 'data:image/')):
        return v
    if _looks_like_base64_image(v):
        # Assume PNG; if PayMongo returns another type, Flutter will still try to decode.
        return f'data:image/png;base64,{v}'
    return v


def _paymongo_request(secret_key: str, path: str, *, payload: dict | None = None):
    url = f'https://api.paymongo.com{path}'
    auth = base64.b64encode(f'{secret_key}:'.encode('utf-8')).decode('ascii')
    data = None
    if payload is not None:
        data = json.dumps(payload).encode('utf-8')

    req = urllib.request.Request(
        url,
        method='POST',
        data=data,
        headers={
            'accept': 'application/json',
            'content-type': 'application/json',
            'authorization': f'Basic {auth}',
        },
    )

    with urllib.request.urlopen(req, timeout=30) as resp:
        body = resp.read().decode('utf-8')
        parsed = json.loads(body) if body else {}
        return resp.status, parsed


def _parse_checkout_url(pm_obj: dict) -> str | None:
    if not isinstance(pm_obj, dict):
        return None
    attrs = pm_obj.get('attributes') if isinstance(pm_obj.get('attributes'), dict) else {}
    for k in ('checkout_url', 'url', 'redirect_url'):
        v = attrs.get(k)
        if isinstance(v, str) and v.strip().startswith(('http://', 'https://')):
            return v.strip()
    return None


def _require_cashier_role() -> tuple[bool, tuple] | tuple[bool, None]:
    claims = get_jwt() or {}
    role = (claims.get('role') or '').lower()
    if not role:
        return False, _json_error(403, 'Unauthorized', error='missing_role')
    return True, None


@payments_bp.get('/qrph/static')
@jwt_required()
def generate_static_qrph():
    """Generate a static QRPh code via PayMongo.

    This endpoint is intended for POS cashiers to display a QR that customers
    can scan using GCash (and other QRPh-capable wallets).

    IMPORTANT: PayMongo secret keys MUST stay on the backend.
    """

    ok, err_resp = _require_cashier_role()
    if not ok:
        return err_resp

    secret_key = os.getenv('PAYMONGO_SECRET_KEY', '').strip()
    if not secret_key:
        return _json_error(
            501,
            'PayMongo is not configured (missing PAYMONGO_SECRET_KEY).',
            error='paymongo_not_configured',
        )

    # According to PayMongo docs, QRPh generate expects a JSON:API-ish payload.
    # Example:
    # { "data": { "attributes": { "kind": "instore", "mobile_number": "...", "notes": "..." } } }
    mobile_number = (request.args.get('mobile_number') or '').strip()
    notes = (request.args.get('notes') or '').strip()
    if not mobile_number:
        mobile_number = (os.getenv('PAYMONGO_QRPH_MOBILE_NUMBER', '') or '').strip()
    if not notes:
        notes = (os.getenv('PAYMONGO_QRPH_NOTES', '') or '').strip()

    session_id = uuid.uuid4().hex

    # Optional: store expected amount on our side so we can validate the webhook payment.
    expected_amount_centavos = None
    amount_str = (request.args.get('amount') or '').strip()
    amount_centavos_str = (request.args.get('amount_centavos') or '').strip()
    try:
        if amount_centavos_str:
            expected_amount_centavos = int(amount_centavos_str)
        elif amount_str:
            # amount is in PHP (e.g. 123.45) -> centavos
            expected_amount_centavos = int(round(float(amount_str) * 100))
    except Exception:
        expected_amount_centavos = None

    # Include our session id in notes to help with reconciliation/debugging.
    session_note = f"session:{session_id}"
    if notes:
        notes = f"{notes} | {session_note}"
    else:
        notes = session_note

    attributes = {'kind': 'instore'}
    if mobile_number:
        attributes['mobile_number'] = mobile_number
    if notes:
        attributes['notes'] = notes

    paymongo_payload = {'data': {'attributes': attributes}}

    try:
        status, data = _paymongo_request(
            secret_key,
            '/v1/qrph/generate',
            payload=paymongo_payload,
        )
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode('utf-8')
            err_json = json.loads(err_body) if err_body else {}
        except Exception:
            err_json = {}
        return _json_error(
            502,
            'Failed to generate QRPh via PayMongo.',
            error=err_json.get('errors') or 'paymongo_error',
        )
    except Exception as e:
        return _json_error(502, f'Failed to generate QRPh via PayMongo: {e}')

    if not isinstance(data, dict) or 'data' not in data:
        return _json_error(502, 'Invalid PayMongo response', error='invalid_response')

    payload = None
    image_url = None
    paymongo_code_id = None
    reference_id = None

    pm_data = data.get('data')
    pm_obj = None
    if isinstance(pm_data, dict):
        pm_obj = pm_data
    elif isinstance(pm_data, list) and pm_data:
        # Some APIs return JSON:API arrays: { data: [ ... ] }
        first = pm_data[0]
        if isinstance(first, dict):
            pm_obj = first

    if isinstance(pm_obj, dict):
        paymongo_code_id = pm_obj.get('id') if isinstance(pm_obj.get('id'), str) else None
        attrs = (
            (pm_obj.get('attributes') or {})
            if isinstance(pm_obj.get('attributes'), dict)
            else {}
        )

        reference_id = attrs.get('reference_id') if isinstance(attrs.get('reference_id'), str) else None

        # Common/expected keys
        payload = _extract_first_string(
            attrs,
            [
                'qr_string',
                'qr_payload',
                'qr_content',
                'payload',
                'qrph_string',
                'qrph_payload',
                'qr',
            ],
        ) or _extract_first_string(
            pm_obj,
            [
                'qr_string',
                'qr_payload',
                'payload',
                'qrph_string',
                'qrph_payload',
            ],
        )

        image_url = _extract_first_string(
            attrs,
            [
                'qr_image_url',
                'qr_code_url',
                'image_url',
                'qr_url',
                'qrph_url',
                'qr_image',
                'qr_image_data',
                'qr_image_data_uri',
            ],
        ) or _extract_first_string(
            pm_obj,
            [
                'qr_image_url',
                'qr_code_url',
                'image_url',
                'qr_url',
                'qrph_url',
                'qr_image',
                'qr_image_data',
                'qr_image_data_uri',
            ],
        )

        image_url = _as_data_uri_if_base64(image_url)

        # Heuristic fallback:
        # - EMVCo QR payloads usually start with "000201"
        # - Images can be http(s) URLs or data URIs
        payload = payload or _deep_find_first_string(
            pm_obj,
            lambda s: isinstance(s, str) and s.strip().startswith('000201'),
        )
        image_url = image_url or _deep_find_first_string(
            pm_obj,
            lambda s: isinstance(s, str)
            and s.strip().lower().startswith(('http://', 'https://', 'data:image/')),
        )

        if not image_url:
            img_b64 = _deep_find_first_string(pm_obj, lambda s: isinstance(s, str) and _looks_like_base64_image(s))
            image_url = _as_data_uri_if_base64(img_b64)

    if not payload and not image_url:
        # Log the raw response for local debugging.
        try:
            print('⚠️ PayMongo QRPh response missing QR fields:', data)
        except Exception:
            pass
        return _json_error(
            502,
            'PayMongo response did not include QR data.',
            error='missing_qr_data',
        )

    response = {
        'success': True,
        'message': 'QRPh generated',
        'data': {
            'provider': 'paymongo',
            'session_id': session_id,
            'paymongo_code_id': paymongo_code_id,
            'reference_id': reference_id,
            'expected_amount_centavos': expected_amount_centavos,
            'qr_payload': payload,
            'qr_image_url': image_url,
        },
    }

    with _qrph_lock:
        _cleanup_sessions()
        _qrph_sessions[session_id] = {
            'session_id': session_id,
            'status': 'pending',
            'created_at': _now_ts(),
            'expected_amount_centavos': expected_amount_centavos,
            'paymongo_code_id': paymongo_code_id,
            'reference_id': reference_id,
            'last_payment': None,
            'expired': False,
        }
        if isinstance(reference_id, str) and reference_id:
            _qrph_ref_index[reference_id] = session_id
        if isinstance(paymongo_code_id, str) and paymongo_code_id:
            _qrph_code_index[paymongo_code_id] = session_id

    # Helpful for debugging, but can be very large (qr_image is a data URI).
    if os.getenv('PAYMONGO_DEBUG_RESPONSE', 'false').lower() in {'1', 'true', 'yes', 'on'}:
        response['data']['provider_response'] = data

    return jsonify(response), 200


@payments_bp.get('/qrph/session/<session_id>')
@jwt_required()
def get_qrph_session_status(session_id: str):
    with _qrph_lock:
        _cleanup_sessions()
        session = _qrph_sessions.get(session_id)

        if not session:
            return _json_error(404, 'QRPh session not found', error='session_not_found')

        return (
            jsonify(
                {
                    'success': True,
                    'message': 'OK',
                    'data': session,
                }
            ),
            200,
        )


@payments_bp.post('/gcash/checkout')
@jwt_required()
def create_gcash_checkout():
    """Create a PayMongo Checkout Session locked to a specific amount.

    This produces a hosted checkout URL. The POS can display the URL as a QR code
    so customers can scan and pay without manually typing the amount.
    """

    ok, err_resp = _require_cashier_role()
    if not ok:
        return err_resp

    secret_key = os.getenv('PAYMONGO_SECRET_KEY', '').strip()
    if not secret_key:
        return _json_error(
            501,
            'PayMongo is not configured (missing PAYMONGO_SECRET_KEY).',
            error='paymongo_not_configured',
        )

    try:
        body = request.get_json(silent=True) or {}
    except Exception:
        body = {}

    expected_amount_centavos = None
    try:
        amount_centavos_raw = body.get('amount_centavos')
        amount_raw = body.get('amount')
        if isinstance(amount_centavos_raw, (int, float)):
            expected_amount_centavos = int(amount_centavos_raw)
        elif isinstance(amount_centavos_raw, str) and amount_centavos_raw.strip():
            expected_amount_centavos = int(amount_centavos_raw.strip())
        elif isinstance(amount_raw, (int, float)):
            expected_amount_centavos = int(round(float(amount_raw) * 100))
        elif isinstance(amount_raw, str) and amount_raw.strip():
            expected_amount_centavos = int(round(float(amount_raw.strip()) * 100))
    except Exception:
        expected_amount_centavos = None

    if expected_amount_centavos is None or expected_amount_centavos <= 0:
        return _json_error(400, 'Missing or invalid amount', error='invalid_amount')

    public_base = _public_https_base_url()
    if not public_base:
        return _json_error(
            501,
            'Missing public HTTPS base URL for PayMongo redirects. Start ngrok or set PUBLIC_HTTPS_BASE_URL.',
            error='missing_public_https_base_url',
        )

    session_id = uuid.uuid4().hex

    # Use our session id in multiple places for robust webhook matching.
    reference_number = f'vcs-{session_id[:16]}'
    description = f'Vivian POS GCash Checkout | session:{session_id}'

    success_url = f'{public_base}/api/payments/paymongo/checkout/success?sid={session_id}'
    cancel_url = f'{public_base}/api/payments/paymongo/checkout/cancel?sid={session_id}'

    payload = {
        'data': {
            'attributes': {
                'description': description,
                'reference_number': reference_number,
                'success_url': success_url,
                'cancel_url': cancel_url,
                'payment_method_types': ['gcash'],
                'metadata': {
                    'vcs_session_id': session_id,
                    'vcs_expected_amount_centavos': expected_amount_centavos,
                },
                'line_items': [
                    {
                        'name': 'Order payment',
                        'quantity': 1,
                        'amount': expected_amount_centavos,
                        'currency': 'PHP',
                    }
                ],
            }
        }
    }

    try:
        status, data = _paymongo_request(secret_key, '/v1/checkout_sessions', payload=payload)
    except urllib.error.HTTPError as e:
        try:
            err_body = e.read().decode('utf-8')
            err_json = json.loads(err_body) if err_body else {}
        except Exception:
            err_json = {}
        return _json_error(
            502,
            'Failed to create PayMongo checkout session.',
            error=err_json.get('errors') or 'paymongo_error',
        )
    except Exception as e:
        return _json_error(502, f'Failed to create PayMongo checkout session: {e}')

    pm_data = data.get('data') if isinstance(data, dict) else None
    pm_obj = None
    if isinstance(pm_data, dict):
        pm_obj = pm_data
    elif isinstance(pm_data, list) and pm_data:
        first = pm_data[0]
        if isinstance(first, dict):
            pm_obj = first

    if not isinstance(pm_obj, dict):
        return _json_error(502, 'Invalid PayMongo response', error='invalid_response')

    paymongo_checkout_id = pm_obj.get('id') if isinstance(pm_obj.get('id'), str) else None
    checkout_url = _parse_checkout_url(pm_obj)

    if not checkout_url:
        try:
            print('⚠️ PayMongo checkout response missing checkout_url:', data)
        except Exception:
            pass
        return _json_error(502, 'PayMongo response missing checkout URL', error='missing_checkout_url')

    with _checkout_lock:
        _cleanup_checkout_sessions()
        _checkout_sessions[session_id] = {
            'session_id': session_id,
            'status': 'pending',
            'created_at': _now_ts(),
            'expected_amount_centavos': expected_amount_centavos,
            'paymongo_checkout_id': paymongo_checkout_id,
            'checkout_url': checkout_url,
            'last_payment': None,
        }
        if isinstance(paymongo_checkout_id, str) and paymongo_checkout_id:
            _checkout_id_index[paymongo_checkout_id] = session_id

    return (
        jsonify(
            {
                'success': True,
                'message': 'Checkout session created',
                'data': {
                    'provider': 'paymongo',
                    'session_id': session_id,
                    'expected_amount_centavos': expected_amount_centavos,
                    'paymongo_checkout_id': paymongo_checkout_id,
                    'checkout_url': checkout_url,
                },
            }
        ),
        200,
    )


@payments_bp.get('/gcash/session/<session_id>')
@jwt_required()
def get_gcash_checkout_session_status(session_id: str):
    with _checkout_lock:
        _cleanup_checkout_sessions()
        session = _checkout_sessions.get(session_id)
        if not session:
            return _json_error(404, 'Checkout session not found', error='session_not_found')
        return (
            jsonify({'success': True, 'message': 'OK', 'data': session}),
            200,
        )


@payments_bp.post('/paymongo/webhook')
def paymongo_webhook():
    # NOTE: This endpoint must be publicly reachable via HTTPS for PayMongo to deliver events.
    secret = (os.getenv('PAYMONGO_WEBHOOK_SECRET', '') or '').strip()

    raw_body = request.get_data(cache=False) or b''
    sig_header = request.headers.get('Paymongo-Signature')

    ok, err = _verify_paymongo_webhook(raw_body, signature_header=sig_header, secret=secret)
    if not ok:
        # Respond 4xx so PayMongo retries if misconfigured; during setup you want to see this.
        return _json_error(400, 'Invalid webhook signature', error=err or 'invalid_signature')

    try:
        payload = json.loads(raw_body.decode('utf-8') or '{}')
    except Exception:
        payload = {}

    event = payload.get('data') if isinstance(payload, dict) else None
    if not isinstance(event, dict):
        return jsonify({'success': True, 'message': 'ignored'}), 200

    event_attrs = event.get('attributes') if isinstance(event.get('attributes'), dict) else {}
    event_type = event_attrs.get('type') if isinstance(event_attrs.get('type'), str) else None
    event_data = event_attrs.get('data') if isinstance(event_attrs.get('data'), dict) else None

    if not event_type or not isinstance(event_data, dict):
        return jsonify({'success': True, 'message': 'ignored'}), 200

    # Update our in-memory session store.
    qrph_session_id = _find_session_id_from_event_obj(event_data) or _find_session_id_from_event_obj(event)
    checkout_session_id = _find_checkout_session_id_from_event_obj(event_data) or _find_checkout_session_id_from_event_obj(event)

    if not qrph_session_id and not checkout_session_id:
        try:
            print('ℹ️ PayMongo webhook not matched to session:', event_type, event_data.get('type'), event_data.get('id'))
        except Exception:
            pass

    payment_attrs = event_data.get('attributes') if isinstance(event_data.get('attributes'), dict) else {}
    amount = payment_attrs.get('amount')
    currency = payment_attrs.get('currency')
    pay_status = payment_attrs.get('status')
    payment_id = event_data.get('id') if isinstance(event_data.get('id'), str) else None

    if qrph_session_id:
        with _qrph_lock:
            _cleanup_sessions()
            if qrph_session_id in _qrph_sessions:
                session = _qrph_sessions[qrph_session_id]

                if event_type == 'payment.paid':
                    expected_amount = session.get('expected_amount_centavos')
                    paid_amount = None
                    try:
                        if isinstance(amount, (int, float)):
                            paid_amount = int(amount)
                        elif isinstance(amount, str) and amount.strip():
                            paid_amount = int(float(amount.strip()))
                    except Exception:
                        paid_amount = None

                    if isinstance(expected_amount, int) and paid_amount is not None and expected_amount != paid_amount:
                        session['status'] = 'amount_mismatch'
                    else:
                        session['status'] = 'paid'

                    session['last_payment'] = {
                        'payment_id': payment_id,
                        'amount': amount,
                        'currency': currency,
                        'status': pay_status,
                        'paid_at': payment_attrs.get('paid_at'),
                        'external_reference_number': payment_attrs.get('external_reference_number'),
                    }
                    session['expired'] = False
                elif event_type == 'qrph.expired':
                    session['status'] = 'expired'
                    session['expired'] = True

    if checkout_session_id and event_type == 'payment.paid':
        with _checkout_lock:
            _cleanup_checkout_sessions()
            if checkout_session_id in _checkout_sessions:
                session = _checkout_sessions[checkout_session_id]
                session['status'] = 'paid'
                session['last_payment'] = {
                    'payment_id': payment_id,
                    'amount': amount,
                    'currency': currency,
                    'status': pay_status,
                    'paid_at': payment_attrs.get('paid_at'),
                    'external_reference_number': payment_attrs.get('external_reference_number'),
                }

    # Always acknowledge quickly with 2xx.
    return jsonify({'success': True, 'message': 'received'}), 200


@payments_bp.get('/paymongo/webhook')
def paymongo_webhook_probe():
    # Browser probe / manual verification endpoint.
    # PayMongo will send POST requests to this same path.
    return (
        jsonify(
            {
                'success': True,
                'message': 'PayMongo webhook endpoint is reachable. Send a POST request to deliver events.',
                'data': {
                    'method': 'POST',
                    'path': '/api/payments/paymongo/webhook',
                },
            }
        ),
        200,
    )


@payments_bp.get('/paymongo/checkout/success')
def paymongo_checkout_success():
    # Minimal redirect target for PayMongo hosted checkout.
    sid = (request.args.get('sid') or '').strip()
    return (
        f'Payment successful. You can return to the cashier. (session: {sid})',
        200,
        {'content-type': 'text/plain; charset=utf-8'},
    )


@payments_bp.get('/paymongo/checkout/cancel')
def paymongo_checkout_cancel():
    sid = (request.args.get('sid') or '').strip()
    return (
        f'Payment cancelled. You can return to the cashier. (session: {sid})',
        200,
        {'content-type': 'text/plain; charset=utf-8'},
    )
