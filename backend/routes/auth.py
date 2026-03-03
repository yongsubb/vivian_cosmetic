"""
Authentication routes - Login, Logout, Token management
"""
from datetime import datetime
import hashlib
import hmac
import os
import re
import secrets
import time
import uuid
from typing import Optional
from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    jwt_required,
    get_jwt_identity,
    get_jwt
)
from sqlalchemy.exc import SQLAlchemyError
from extensions import db
from models.user import User
from utils.activity_logger import log_activity
from utils.otp_email import send_otp_email

auth_bp = Blueprint('auth', __name__)


_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _is_valid_email(value: str) -> bool:
    return bool(_EMAIL_RE.match((value or "").strip()))


# =============================================================================
# Password reset via Email OTP (in-memory store; no DB migrations)
# =============================================================================
# NOTE: This uses in-memory storage so it works without DB migrations.
# It will reset on server restart and won't work across multiple workers.
_PWD_OTP_TTL_SECONDS = int(os.getenv('PWD_RESET_OTP_TTL_SECONDS') or (5 * 60))
_PWD_OTP_MAX_ATTEMPTS = int(os.getenv('PWD_RESET_OTP_MAX_ATTEMPTS') or 5)
_PWD_OTP_MAX_REQUESTS_WINDOW_SECONDS = int(
    os.getenv('PWD_RESET_OTP_MAX_REQUESTS_WINDOW_SECONDS') or (10 * 60)
)
_PWD_OTP_MAX_REQUESTS_PER_WINDOW = int(
    os.getenv('PWD_RESET_OTP_MAX_REQUESTS_PER_WINDOW') or 3
)

# otp_ref -> dict(user_id, email, otp_hash, created_at, expires_at, attempts, rate_key)
_pwd_reset_otp_store: dict[str, dict] = {}


def _now_ts() -> int:
    return int(time.time())


def _otp_signing_key() -> bytes:
    secret = os.getenv('SECRET_KEY') or os.getenv('JWT_SECRET_KEY') or 'otp-dev-secret'
    return secret.encode('utf-8')


def _hash_otp(*, otp_ref: str, otp_code: str) -> str:
    msg = f'{otp_ref}:{otp_code}'.encode('utf-8')
    return hmac.new(_otp_signing_key(), msg, hashlib.sha256).hexdigest()


def _generate_otp_code() -> str:
    return f'{secrets.randbelow(1_000_000):06d}'


def _cleanup_pwd_otps() -> None:
    now = _now_ts()
    expired = [k for k, v in _pwd_reset_otp_store.items() if int(v.get('expires_at', 0)) <= now]
    for k in expired:
        _pwd_reset_otp_store.pop(k, None)


def _rate_limit_key(user_id: int, email: str) -> str:
    return f'{user_id}:{(email or "").strip().lower()}'


def _count_recent_requests(user_id: int, email: str) -> int:
    now = _now_ts()
    window_start = now - _PWD_OTP_MAX_REQUESTS_WINDOW_SECONDS
    key = _rate_limit_key(user_id, email)
    count = 0
    for v in _pwd_reset_otp_store.values():
        if v.get('rate_key') != key:
            continue
        if int(v.get('created_at', 0)) >= window_start:
            count += 1
    return count


def _validate_new_password(password: str) -> Optional[str]:
    pwd = (password or '').strip()
    if not pwd:
        return 'New password is required'
    if len(pwd) < 6:
        return 'Password must be at least 6 characters'
    return None


@auth_bp.route('/login', methods=['POST'])
def login():
    """
    Login endpoint
    Supports both password and PIN authentication
    
    Request body:
    {
        "username": "string",
        "password": "string" (optional),
        "pin": "string" (optional),
        "role": "cashier" | "supervisor" (optional, for validation)
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'message': 'No data provided'
            }), 400
        
        username = data.get('username', '').strip()
        password = data.get('password')
        pin = data.get('pin')
        requested_role = data.get('role')
        
        # Validate input
        if not username:
            return jsonify({
                'success': False,
                'message': 'Username is required'
            }), 400
        
        if not password and not pin:
            return jsonify({
                'success': False,
                'message': 'Password or PIN is required'
            }), 400
        
        # Find user
        user = User.query.filter_by(username=username).first()
        
        if not user:
            return jsonify({
                'success': False,
                'message': 'Invalid username or password'
            }), 401
        
        # Check if user is active
        if not user.is_active:
            return jsonify({
                'success': False,
                'message': 'Account is deactivated. Please contact supervisor.'
            }), 403
        
        # Authenticate
        authenticated = False
        auth_method = None
        
        if password:
            authenticated = user.check_password(password)
            auth_method = 'password'
        elif pin:
            authenticated = user.check_pin(pin)
            auth_method = 'pin'
        
        if not authenticated:
            return jsonify({
                'success': False,
                'message': 'Invalid credentials'
            }), 401
        
        # Validate role if specified
        if requested_role and user.role != requested_role:
            return jsonify({
                'success': False,
                'message': f'You do not have {requested_role} privileges'
            }), 403
        
        # Update login status
        user.is_logged_in = True
        user.last_login = datetime.now()
        db.session.commit()
        
        # Create tokens
        access_token = create_access_token(
            identity=str(user.id),
            additional_claims={
                'username': user.username,
                'role': user.role,
                'full_name': user.full_name,
                'nickname': user.nickname,
                'display_name': user.display_name,
            }
        )
        refresh_token = create_refresh_token(identity=str(user.id))
        
        return jsonify({
            'success': True,
            'message': 'Login successful',
            'data': {
                'access_token': access_token,
                'refresh_token': refresh_token,
                'user': user.to_dict(),
                'auth_method': auth_method
            }
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Login failed: {str(e)}'
        }), 500


@auth_bp.route('/password-reset/request', methods=['POST'])
def request_password_reset_otp():
    """Request a password reset OTP sent to the user's email.

    Body:
      {"username_or_email": "..."} OR {"username": "..."} OR {"email": "..."}

    Response always returns success=true to reduce user enumeration.
    When configured and the user has an email, includes: otp_ref, destination (masked).
    """

    try:
        _cleanup_pwd_otps()

        data = request.get_json() or {}
        raw = (
            data.get('username_or_email')
            or data.get('identifier')
            or data.get('username')
            or data.get('email')
            or ''
        )
        identifier = (raw or '').strip()
        if not identifier:
            return jsonify({'success': False, 'message': 'Username or email is required'}), 400

        user = None
        if '@' in identifier:
            # Email lookup
            email = identifier.lower()
            if not _is_valid_email(email):
                return jsonify({'success': False, 'message': 'Invalid email address'}), 400
            user = User.query.filter(db.func.lower(User.email) == email).first()
        else:
            # Username lookup
            user = User.query.filter_by(username=identifier).first()

        # Always respond with success to avoid account enumeration.
        if not user or not user.is_active:
            return jsonify({
                'success': True,
                'message': 'If the account exists, a verification code has been sent to the registered email.'
            }), 200

        email = (user.email or '').strip()
        if not email or not _is_valid_email(email):
            return jsonify({
                'success': True,
                'message': 'If the account exists, a verification code has been sent to the registered email.'
            }), 200

        # Rate limit per user/email
        recent = _count_recent_requests(user.id, email)
        if recent >= _PWD_OTP_MAX_REQUESTS_PER_WINDOW:
            return jsonify({
                'success': True,
                'message': 'If the account exists, a verification code has been sent to the registered email.'
            }), 200

        otp_ref = str(uuid.uuid4())
        otp_code = _generate_otp_code()

        ok, err, masked = send_otp_email(
            to_email=email,
            otp=otp_code,
            subject=(os.getenv('PWD_RESET_EMAIL_SUBJECT') or 'Vivian Cosmetic Shop Password Reset Code'),
            body_template=(
                os.getenv('PWD_RESET_EMAIL_BODY_TEMPLATE')
                or 'Your Vivian Cosmetic Shop password reset code is {otp}. It expires in 5 minutes.'
            ),
        )

        # Store OTP even if sending failed, but only if email config exists.
        # If sending fails due to config, behave like success without details.
        if not ok:
            # Best-effort log; don't leak internal SMTP details to clients.
            try:
                log_activity(
                    user_id=user.id,
                    action='Password reset OTP send failed',
                    entity_type='user',
                    entity_id=user.id,
                    details={'masked_email': masked, 'error': err},
                )
            except Exception:
                pass

            return jsonify({
                'success': True,
                'message': 'If the account exists, a verification code has been sent to the registered email.'
            }), 200

        now = _now_ts()
        _pwd_reset_otp_store[otp_ref] = {
            'user_id': user.id,
            'email': email,
            'otp_hash': _hash_otp(otp_ref=otp_ref, otp_code=otp_code),
            'created_at': now,
            'expires_at': now + _PWD_OTP_TTL_SECONDS,
            'attempts': 0,
            'rate_key': _rate_limit_key(user.id, email),
        }

        # Audit log (best effort)
        try:
            log_activity(
                user_id=user.id,
                action='Requested password reset OTP',
                entity_type='user',
                entity_id=user.id,
                details={'masked_email': masked},
            )
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': 'If the account exists, a verification code has been sent to the registered email.',
            'data': {
                'otp_ref': otp_ref,
                'destination': masked,
            }
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'message': f'Failed to request OTP: {str(e)}'}), 500


@auth_bp.route('/password-reset/confirm', methods=['POST'])
def confirm_password_reset_otp():
    """Confirm OTP and set a new password.

    Body:
      {"otp_ref": "...", "otp_code": "123456", "new_password": "..."}
    """

    try:
        _cleanup_pwd_otps()
        data = request.get_json() or {}
        otp_ref = (data.get('otp_ref') or '').strip()
        otp_code = (data.get('otp_code') or '').strip()
        new_password = data.get('new_password')

        if not otp_ref or not otp_code:
            return jsonify({
                'success': False,
                'message': 'OTP reference and code are required'
            }), 400

        pwd_err = _validate_new_password(new_password)
        if pwd_err:
            return jsonify({'success': False, 'message': pwd_err}), 400

        entry = _pwd_reset_otp_store.get(otp_ref)
        if not entry:
            return jsonify({
                'success': False,
                'message': 'OTP expired or invalid. Please request a new OTP.'
            }), 400

        now = _now_ts()
        if int(entry.get('expires_at', 0)) <= now:
            _pwd_reset_otp_store.pop(otp_ref, None)
            return jsonify({
                'success': False,
                'message': 'OTP expired or invalid. Please request a new OTP.'
            }), 400

        attempts = int(entry.get('attempts', 0) or 0)
        if attempts >= _PWD_OTP_MAX_ATTEMPTS:
            _pwd_reset_otp_store.pop(otp_ref, None)
            return jsonify({
                'success': False,
                'message': 'Too many attempts. Please request a new OTP.'
            }), 429

        expected_hash = str(entry.get('otp_hash') or '')
        actual_hash = _hash_otp(otp_ref=otp_ref, otp_code=otp_code)
        if not hmac.compare_digest(expected_hash, actual_hash):
            entry['attempts'] = attempts + 1
            return jsonify({
                'success': False,
                'message': 'Invalid OTP code'
            }), 400

        user_id = entry.get('user_id')
        user = User.query.get(user_id)
        if not user or not user.is_active:
            _pwd_reset_otp_store.pop(otp_ref, None)
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404

        user.set_password(new_password)
        db.session.commit()
        _pwd_reset_otp_store.pop(otp_ref, None)

        # Audit log (best effort)
        try:
            log_activity(
                user_id=user.id,
                action='Reset password via email OTP',
                entity_type='user',
                entity_id=user.id,
                details={'method': 'email_otp'},
            )
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': 'Password reset successfully'
        }), 200

    except SQLAlchemyError as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Password reset failed: {str(e)}'
        }), 500
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Password reset failed: {str(e)}'
        }), 500


@auth_bp.route('/logout', methods=['POST'])
@jwt_required()
def logout():
    """Logout endpoint - Updates user login status"""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        
        if user:
            user.is_logged_in = False
            db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Logout successful'
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Logout failed: {str(e)}'
        }), 500


@auth_bp.route('/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    """Refresh access token"""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        if not user.is_active:
            return jsonify({
                'success': False,
                'message': 'Account is deactivated'
            }), 403
        
        access_token = create_access_token(
            identity=str(user.id),
            additional_claims={
                'username': user.username,
                'role': user.role,
                'full_name': user.full_name,
                'nickname': user.nickname,
                'display_name': user.display_name,
            }
        )
        
        return jsonify({
            'success': True,
            'data': {
                'access_token': access_token
            }
        }), 200
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Token refresh failed: {str(e)}'
        }), 500


@auth_bp.route('/me', methods=['GET'])
@jwt_required()
def get_current_user():
    """Get current authenticated user"""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        return jsonify({
            'success': True,
            'data': user.to_dict(include_sensitive=True)
        }), 200
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Failed to get user: {str(e)}'
        }), 500


@auth_bp.route('/me', methods=['PUT'])
@jwt_required()
def update_current_user():
    """Update current authenticated user profile (nickname/full name/email/etc)."""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)

        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404

        data = request.get_json() or {}

        # Allow either full_name or first_name/last_name
        full_name = (data.get('full_name') or '').strip()
        if full_name:
            parts = [p for p in full_name.split(' ') if p.strip()]
            if len(parts) >= 2:
                user.first_name = parts[0]
                user.last_name = ' '.join(parts[1:])
            else:
                # Keep last_name unchanged to satisfy NOT NULL
                user.first_name = parts[0]

        if 'first_name' in data and (data.get('first_name') or '').strip():
            user.first_name = data['first_name'].strip()
        if 'last_name' in data and (data.get('last_name') or '').strip():
            user.last_name = data['last_name'].strip()

        if 'nickname' in data:
            nickname = (data.get('nickname') or '').strip()
            user.nickname = nickname if nickname else None

        if 'email' in data:
            email = (data.get('email') or '').strip()
            if email and not _is_valid_email(email):
                return jsonify({
                    'success': False,
                    'message': 'Invalid email address'
                }), 400
            user.email = email if email else None
        if 'phone' in data:
            phone = (data.get('phone') or '').strip()
            user.phone = phone if phone else None
        if 'avatar_url' in data:
            avatar_url = (data.get('avatar_url') or '').strip()
            user.avatar_url = avatar_url if avatar_url else None

        db.session.commit()
        return jsonify({
            'success': True,
            'message': 'Profile updated successfully',
            'data': user.to_dict(include_sensitive=True)
        }), 200

    except SQLAlchemyError as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Failed to update profile: {str(e)}'
        }), 500
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Failed to update profile: {str(e)}'
        }), 500


@auth_bp.route('/verify', methods=['GET'])
@jwt_required()
def verify_token():
    """Verify if the current token is valid"""
    try:
        user_id = get_jwt_identity()
        claims = get_jwt()
        
        return jsonify({
            'success': True,
            'data': {
                'user_id': user_id,
                'username': claims.get('username'),
                'role': claims.get('role'),
                'full_name': claims.get('full_name')
            }
        }), 200
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Token verification failed: {str(e)}'
        }), 500


@auth_bp.route('/change-password', methods=['POST'])
@jwt_required()
def change_password():
    """Change user password"""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        data = request.get_json()
        
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        current_password = data.get('current_password')
        new_password = data.get('new_password')
        
        if not current_password or not new_password:
            return jsonify({
                'success': False,
                'message': 'Current and new password are required'
            }), 400
        
        if not user.check_password(current_password):
            return jsonify({
                'success': False,
                'message': 'Current password is incorrect'
            }), 401
        
        if len(new_password) < 6:
            return jsonify({
                'success': False,
                'message': 'Password must be at least 6 characters'
            }), 400
        
        user.set_password(new_password)
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Password changed successfully'
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Password change failed: {str(e)}'
        }), 500


@auth_bp.route('/set-pin', methods=['POST'])
@jwt_required()
def set_pin():
    """Set or update user PIN"""
    try:
        user_id = get_jwt_identity()
        user = User.query.get(user_id)
        data = request.get_json()
        
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        password = data.get('password')
        new_pin = data.get('pin')
        
        if not password:
            return jsonify({
                'success': False,
                'message': 'Password is required to set PIN'
            }), 400
        
        if not user.check_password(password):
            return jsonify({
                'success': False,
                'message': 'Password is incorrect'
            }), 401
        
        try:
            user.set_pin(new_pin)
            db.session.commit()
        except ValueError as e:
            return jsonify({
                'success': False,
                'message': str(e)
            }), 400
        
        return jsonify({
            'success': True,
            'message': 'PIN set successfully'
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Failed to set PIN: {str(e)}'
        }), 500


@auth_bp.route('/register', methods=['POST'])
def register():
    """
    Register a new cashier account (pending approval)
    
    Request body:
    {
        "username": "string",
        "password": "string",
        "first_name": "string",
        "last_name": "string",
        "email": "string" (optional),
        "phone": "string" (optional)
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({
                'success': False,
                'message': 'No data provided'
            }), 400
        
        # Validate required fields
        required = ['username', 'password', 'first_name', 'last_name']
        for field in required:
            if not data.get(field, '').strip():
                return jsonify({
                    'success': False,
                    'message': f'{field.replace("_", " ").title()} is required'
                }), 400
        
        username = data['username'].strip()
        password = data['password']
        first_name = data['first_name'].strip()
        last_name = data['last_name'].strip()

        email = (data.get('email') or '').strip()
        if email:
            # Basic email format validation (kept intentionally simple)
            if len(email) > 254 or not re.match(r'^[^@\s]+@[^@\s]+\.[^@\s]+$', email, re.IGNORECASE):
                return jsonify({
                    'success': False,
                    'message': 'Invalid email address'
                }), 400
        
        # Validate username length
        if len(username) < 3:
            return jsonify({
                'success': False,
                'message': 'Username must be at least 3 characters'
            }), 400
        
        # Validate password length
        if len(password) < 8:
            return jsonify({
                'success': False,
                'message': 'Password must be at least 8 characters'
            }), 400

        # Validate password strength: uppercase, number, special character
        if not re.search(r'[A-Z]', password):
            return jsonify({
                'success': False,
                'message': 'Password must contain at least 1 uppercase letter'
            }), 400
        if not re.search(r'\d', password):
            return jsonify({
                'success': False,
                'message': 'Password must contain at least 1 number'
            }), 400
        if not re.search(r'[^A-Za-z0-9]', password):
            return jsonify({
                'success': False,
                'message': 'Password must contain at least 1 special character'
            }), 400
        
        # Check if username already exists
        existing_user = User.query.filter_by(username=username).first()
        if existing_user:
            return jsonify({
                'success': False,
                'message': 'Username already exists'
            }), 409
        
        # Validate phone number (optional): digits only, length 11-12
        phone = (data.get('phone') or '').strip()
        if phone:
            if not re.fullmatch(r'\d{11,12}', phone):
                return jsonify({
                    'success': False,
                    'message': 'Invalid phone number'
                }), 400

        # Create new user with pending status (is_active=False)
        user = User(
            username=username,
            first_name=first_name,
            last_name=last_name,
            password=password,
            role='cashier',  # Always register as cashier
            email=email or None,
            phone=phone or None,
            address=data.get('address', '').strip() or None,
            is_active=False  # Pending approval - cannot login until approved
        )
        
        db.session.add(user)
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Account created successfully. Waiting for supervisor approval.',
            'data': {
                'user_id': user.id,
                'username': user.username,
                'status': 'pending'
            }
        }), 201
        
    except SQLAlchemyError as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Registration failed: {str(e)}'
        }), 500
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Registration failed: {str(e)}'
        }), 500


@auth_bp.route('/pending-accounts', methods=['GET'])
@jwt_required()
def get_pending_accounts():
    """Get all pending account approvals (supervisor only)"""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403
        
        # Get all inactive users (pending approval)
        pending_users = User.query.filter_by(is_active=False, role='cashier').all()
        
        return jsonify({
            'success': True,
            'data': [{
                'id': user.id,
                'username': user.username,
                'first_name': user.first_name,
                'last_name': user.last_name,
                'full_name': user.full_name,
                'email': user.email,
                'phone': user.phone,
                'address': user.address,
                'created_at': user.created_at.isoformat() if user.created_at else None
            } for user in pending_users],
            'count': len(pending_users)
        }), 200
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': f'Failed to get pending accounts: {str(e)}'
        }), 500


@auth_bp.route('/approve-account/<int:user_id>', methods=['POST'])
@jwt_required()
def approve_account(user_id):
    """Approve a pending account (supervisor only)"""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403
        
        user = User.query.get(user_id)
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        if user.is_active:
            return jsonify({
                'success': False,
                'message': 'Account is already active'
            }), 400
        
        user.is_active = True
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': f'Account for {user.full_name} has been approved',
            'data': user.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Failed to approve account: {str(e)}'
        }), 500


@auth_bp.route('/reject-account/<int:user_id>', methods=['POST'])
@jwt_required()
def reject_account(user_id):
    """Reject and delete a pending account (supervisor only)"""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403
        
        user = User.query.get(user_id)
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        if user.is_active:
            return jsonify({
                'success': False,
                'message': 'Cannot reject an active account. Deactivate instead.'
            }), 400
        
        username = user.username
        full_name = user.full_name
        db.session.delete(user)
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': f'Account request for {full_name} ({username}) has been rejected'
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': f'Failed to reject account: {str(e)}'
        }), 500
