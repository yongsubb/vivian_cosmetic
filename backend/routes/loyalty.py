"""
Loyalty Management API Routes
Handles member registration, card generation, points, and admin discount control
"""
from datetime import datetime, timedelta
import hashlib
import hmac
import os
import secrets
import time
import uuid
import re
from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    jwt_required,
    get_jwt_identity,
    get_jwt,
    create_access_token,
)
from sqlalchemy import or_, func
from extensions import db
from models import Customer, User
from models.loyalty import LoyaltyMember, LoyaltyTier, LoyaltyTransaction, LoyaltySetting
from models.product import Product
from utils.otp_sms import (
    format_phone_e164,
    format_sms_verify3_target,
    request_provider_otp,
    send_otp_sms,
    textbelt_send_otp_sms,
    textflow_send_otp_code,
    textflow_verify_otp_code,
    twilio_verify_check_code,
    twilio_verify_send_code,
)
from utils.otp_email import send_otp_email

loyalty_bp = Blueprint('loyalty', __name__)


_STAFF_ROLES = {'admin', 'superadmin', 'supervisor', 'cashier'}
_MEMBER_ROLE = 'loyalty_member'


# =============================================================================
# Loyalty App OTP (in-memory) storage
# =============================================================================
# NOTE: This uses in-memory storage so it works without DB migrations.
# It will reset on server restart and won't work across multiple workers.
_OTP_TTL_SECONDS = 5 * 60
_OTP_MAX_ATTEMPTS = 5
_OTP_MAX_REQUESTS_WINDOW_SECONDS = 10 * 60
_OTP_MAX_REQUESTS_PER_WINDOW = 3

# otp_ref -> dict(member_id, member_number, phone, otp_hash, created_at, expires_at, attempts)
_otp_store: dict[str, dict] = {}


def _now_ts() -> int:
    return int(time.time())


def _normalize_phone(raw: str) -> str:
    raw = (raw or '').strip()
    if not raw:
        return ''
    # Keep digits only so inputs like "+63 917-123-4567" match DB entries.
    return ''.join(ch for ch in raw if ch.isdigit())


def _phone_variants_for_lookup(phone_digits: str) -> list[str]:
    """Generate common DB variants for a phone number.

    We store/accept digits-only numbers from the app, but the DB may contain:
      - local format: 09xxxxxxxxx
      - country format: 63xxxxxxxxxx
      - E.164 with plus: +63xxxxxxxxxx

    This avoids false 'Invalid member credentials' when formats differ.
    """

    digits = _normalize_phone(phone_digits)
    if not digits:
        return []

    cc = (os.getenv('OTP_SMS_COUNTRY_CODE') or '63').strip().lstrip('+')
    variants: set[str] = {digits}

    if cc:
        # 09xxxxxxxxx -> 63 + 9xxxxxxxxx
        if len(digits) == 11 and digits.startswith('0'):
            variants.add(f'{cc}{digits[1:]}')

        # 63 + 9xxxxxxxxx -> 09xxxxxxxxx
        if len(digits) >= len(cc) + 10 and digits.startswith(cc):
            national = digits[len(cc):]
            if len(national) == 10:
                variants.add(f'0{national}')

    # Add optional plus-prefixed variants (only for country-code numbers).
    if cc:
        variants |= {
            f'+{v}'
            for v in list(variants)
            if v and (not v.startswith('+')) and v.isdigit() and v.startswith(cc)
        }
    return sorted(variants)


def _format_phone_for_sms(phone: str) -> str:
    """Format phone for external SMS provider without affecting login matching.

    Some providers expect E.164 (e.g. +639xxxxxxxxx) instead of local formats.
    Controlled by env vars so you can adapt to your SMS provider:
      - OTP_SMS_COUNTRY_CODE (e.g. 63)
      - OTP_SMS_E164_PLUS (true/false)

    If OTP_SMS_COUNTRY_CODE is set and the phone starts with '0' and has
    length 11 (e.g. 09xxxxxxxxx), it will be converted to 63 + 9xxxxxxxxx.
    """
    raw = (phone or '').strip()
    cc = (os.getenv('OTP_SMS_COUNTRY_CODE') or '').strip()
    if not cc:
        return raw

    # Convert PH-style local number 09xxxxxxxxx -> 63 + 9xxxxxxxxx
    if raw.startswith('0') and len(raw) == 11 and raw[1:].isdigit():
        raw = f'{cc}{raw[1:]}'

    plus = (os.getenv('OTP_SMS_E164_PLUS') or 'false').lower() in {
        '1',
        'true',
        'yes',
        'on',
    }
    if plus and raw and not raw.startswith('+'):
        raw = f'+{raw}'
    return raw


def _otp_signing_key() -> bytes:
    # Prefer SECRET_KEY; fall back to JWT secret.
    secret = os.getenv('SECRET_KEY') or os.getenv('JWT_SECRET_KEY') or 'otp-dev-secret'
    return secret.encode('utf-8')


def _hash_otp(otp_ref: str, otp_code: str) -> str:
    # Bind OTP to its reference so reused codes cannot be replayed.
    msg = f'{otp_ref}:{otp_code}'.encode('utf-8')
    return hmac.new(_otp_signing_key(), msg, hashlib.sha256).hexdigest()


def _generate_otp_code() -> str:
    # 6-digit numeric code.
    return f'{secrets.randbelow(1_000_000):06d}'


def _cleanup_otps() -> None:
    now = _now_ts()
    expired = [k for k, v in _otp_store.items() if int(v.get('expires_at', 0)) <= now]
    for k in expired:
        _otp_store.pop(k, None)


def _rate_limit_key(member_id: int, phone: str) -> str:
    return f'{member_id}:{phone}'


def _count_recent_requests(member_id: int, phone: str) -> int:
    now = _now_ts()
    window_start = now - _OTP_MAX_REQUESTS_WINDOW_SECONDS
    key = _rate_limit_key(member_id, phone)
    count = 0
    for v in _otp_store.values():
        if v.get('rate_key') != key:
            continue
        if int(v.get('created_at', 0)) >= window_start:
            count += 1
    return count


def _get_jwt_role():
    try:
        return (get_jwt() or {}).get('role')
    except Exception:
        return None


def _require_roles(roles):
    role = _get_jwt_role()
    if role not in roles:
        return (
            jsonify({'success': False, 'message': 'Forbidden'}),
            403,
        )
    return None


# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

def get_loyalty_setting(key, default=None):
    """Get a loyalty setting value by key"""
    setting = LoyaltySetting.query.filter_by(setting_key=key).first()
    if setting:
        return setting.get_value()
    return default


def log_activity(user_id, action, entity_type, entity_id, details=None):
    """Log activity for audit trail"""
    from models.user import ActivityLog
    try:
        log = ActivityLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            details=details
        )
        db.session.add(log)
        db.session.commit()
    except Exception:
        pass  # Don't fail if logging fails


def calculate_tier(lifetime_points):
    """Calculate the appropriate tier based on lifetime points"""
    tier = LoyaltyTier.query.filter(
        LoyaltyTier.is_active == True,
        LoyaltyTier.min_points <= lifetime_points
    ).filter(
        or_(
            LoyaltyTier.max_points.is_(None),
            LoyaltyTier.max_points >= lifetime_points
        )
    ).order_by(LoyaltyTier.min_points.desc()).first()
    
    if not tier:
        # Fallback to the lowest active tier. This keeps new members with
        # lifetime_points=0 mapped to Bronze even if Bronze starts at 1.
        tier = LoyaltyTier.query.filter(
            LoyaltyTier.is_active == True
        ).order_by(LoyaltyTier.min_points.asc()).first()
    
    return tier


# =============================================================================
# MEMBER ENDPOINTS
# =============================================================================

@loyalty_bp.route('/members', methods=['GET'])
@jwt_required()
def get_members():
    """Get all loyalty members with optional filters"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        search = request.args.get('search', '')
        tier_id = request.args.get('tier_id', type=int)
        status = request.args.get('status', '')
        
        query = LoyaltyMember.query.join(Customer)

        # By default, hide archived members from the main list.
        if hasattr(LoyaltyMember, 'is_archived'):
            query = query.filter(LoyaltyMember.is_archived.is_(False))
        
        # Apply filters
        if search:
            query = query.filter(
                or_(
                    Customer.name.ilike(f'%{search}%'),
                    Customer.phone.ilike(f'%{search}%'),
                    Customer.email.ilike(f'%{search}%'),
                    LoyaltyMember.member_number.ilike(f'%{search}%'),
                    LoyaltyMember.card_barcode.ilike(f'%{search}%')
                )
            )
        
        if tier_id:
            query = query.filter(LoyaltyMember.tier_id == tier_id)
        
        if status:
            query = query.filter(LoyaltyMember.card_status == status)
        
        # Paginate
        pagination = query.order_by(LoyaltyMember.created_at.desc()).paginate(
            page=page, per_page=per_page, error_out=False
        )
        
        return jsonify({
            'success': True,
            'data': {
                'members': [m.to_dict() for m in pagination.items],
                'total': pagination.total,
                'pages': pagination.pages,
                'current_page': page
            }
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/archived', methods=['GET'])
@jwt_required()
def get_archived_members():
    """Get archived loyalty members (staff only)."""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        search = request.args.get('search', '')

        query = LoyaltyMember.query.join(Customer)
        if hasattr(LoyaltyMember, 'is_archived'):
            query = query.filter(LoyaltyMember.is_archived.is_(True))
        else:
            # If schema doesn't support it, treat as empty.
            return jsonify({'success': True, 'data': {'members': [], 'total': 0, 'pages': 0, 'current_page': page}}), 200

        if search:
            query = query.filter(
                or_(
                    Customer.name.ilike(f'%{search}%'),
                    Customer.phone.ilike(f'%{search}%'),
                    Customer.email.ilike(f'%{search}%'),
                    LoyaltyMember.member_number.ilike(f'%{search}%'),
                    LoyaltyMember.card_barcode.ilike(f'%{search}%'),
                )
            )

        # MariaDB/MySQL don't support `NULLS LAST`. Use an `IS NULL` sort key.
        pagination = query.order_by(
            LoyaltyMember.archived_at.is_(None).asc(),
            LoyaltyMember.archived_at.desc(),
            LoyaltyMember.created_at.desc(),
        ).paginate(
            page=page, per_page=per_page, error_out=False
        )

        return jsonify({
            'success': True,
            'data': {
                'members': [m.to_dict() for m in pagination.items],
                'total': pagination.total,
                'pages': pagination.pages,
                'current_page': page,
            },
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/archive', methods=['POST'])
@jwt_required()
def archive_member(member_id: int):
    """Archive (soft-delete) a loyalty member (staff only)."""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        current_user_id = get_jwt_identity()
        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404

        if hasattr(member, 'is_archived'):
            member.is_archived = True
        member.is_active = False
        if hasattr(member, 'archived_at'):
            member.archived_at = datetime.now()
        if hasattr(member, 'deactivated_at'):
            member.deactivated_at = datetime.now()

        db.session.commit()

        log_activity(
            current_user_id,
            'LOYALTY_MEMBER_ARCHIVED',
            'loyalty_member',
            member_id,
            {'member_number': member.member_number},
        )

        return jsonify({'success': True, 'message': 'Member archived successfully', 'data': member.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/restore', methods=['POST'])
@jwt_required()
def restore_member(member_id: int):
    """Restore an archived loyalty member (staff only)."""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        current_user_id = get_jwt_identity()
        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404

        if hasattr(member, 'is_archived'):
            member.is_archived = False
        member.is_active = True
        if hasattr(member, 'archived_at'):
            member.archived_at = None
        if hasattr(member, 'deactivated_at'):
            member.deactivated_at = None

        db.session.commit()

        log_activity(
            current_user_id,
            'LOYALTY_MEMBER_RESTORED',
            'loyalty_member',
            member_id,
            {'member_number': member.member_number},
        )

        return jsonify({'success': True, 'message': 'Member restored successfully', 'data': member.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>', methods=['GET'])
@jwt_required()
def get_member(member_id):
    """Get a single member by ID"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        return jsonify({
            'success': True,
            'data': member.to_dict()
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/scan/<barcode>', methods=['GET'])
@jwt_required()
def scan_member_card(barcode):
    """Find member by scanning their card barcode"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        member = LoyaltyMember.query.filter_by(card_barcode=barcode).first()
        
        if not member:
            return jsonify({
                'success': False, 
                'message': 'No member found with this card'
            }), 404
        
        if member.card_status != 'active':
            return jsonify({
                'success': False,
                'message': f'Card is {member.card_status}',
                'data': member.to_dict()
            }), 400
        
        if not member.is_active:
            return jsonify({
                'success': False,
                'message': 'Member account is inactive',
                'data': member.to_dict()
            }), 400
        
        return jsonify({
            'success': True,
            'data': member.to_dict()
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/search', methods=['GET'])
@jwt_required()
def search_member():
    """Search member by phone, email, or member number"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        query = request.args.get('q', '')
        
        if not query or len(query) < 3:
            return jsonify({
                'success': False,
                'message': 'Search query must be at least 3 characters'
            }), 400
        
        members = LoyaltyMember.query.join(Customer).filter(
            or_(
                Customer.phone.ilike(f'%{query}%'),
                Customer.email.ilike(f'%{query}%'),
                Customer.name.ilike(f'%{query}%'),
                LoyaltyMember.member_number.ilike(f'%{query}%')
            )
        ).limit(10).all()
        
        return jsonify({
            'success': True,
            'data': [m.to_dict() for m in members]
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members', methods=['POST'])
@jwt_required()
def register_member():
    """Register a new loyalty member"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        current_user_id = get_jwt_identity()
        data = request.get_json()
        
        # Check if customer_id is provided or create new customer
        customer_id = data.get('customer_id')
        
        if customer_id:
            customer = Customer.query.get(customer_id)
            if not customer:
                return jsonify({'success': False, 'message': 'Customer not found'}), 404
            
            # Check if customer already has a loyalty membership
            existing = LoyaltyMember.query.filter_by(customer_id=customer_id).first()
            if existing:
                return jsonify({
                    'success': False,
                    'message': 'Customer is already a loyalty member',
                    'data': existing.to_dict()
                }), 400
        else:
            # Create new customer
            name = data.get('name')
            phone = _normalize_phone(data.get('phone') or '')
            email = (data.get('email') or '').strip()
            
            if not name:
                return jsonify({'success': False, 'message': 'Customer name is required'}), 400

            # Validate phone number (optional): digits only, length 11-12
            if phone:
                if not re.fullmatch(r'\d{11,12}', phone):
                    return jsonify({'success': False, 'message': 'Invalid phone number'}), 400

            # If phone/email already exist as a Customer, reuse that customer.
            # This avoids blocking loyalty registration when a customer record
            # was created earlier (e.g. from POS sales) but has no loyalty member yet.
            existing_by_phone = None
            existing_by_email = None

            if phone:
                phone_variants = _phone_variants_for_lookup(phone)
                if phone_variants:
                    existing_by_phone = (
                        Customer.query
                        .filter(Customer.phone.in_(phone_variants))
                        .first()
                    )

            if email:
                existing_by_email = (
                    Customer.query
                    .filter(func.lower(Customer.email) == email.lower())
                    .first()
                )

            if existing_by_phone and existing_by_email and existing_by_phone.id != existing_by_email.id:
                return jsonify({
                    'success': False,
                    'message': 'Phone and email belong to different existing customers',
                }), 400

            customer = existing_by_phone or existing_by_email

            if customer:
                # Check if this customer already has a loyalty membership
                existing = LoyaltyMember.query.filter_by(customer_id=customer.id).first()
                if existing:
                    return jsonify({
                        'success': False,
                        'message': 'Customer is already a loyalty member',
                        'data': existing.to_dict(),
                    }), 400

                # Fill missing fields (do not overwrite non-empty values)
                if name and not (customer.name or '').strip():
                    customer.name = name
                if phone and not (customer.phone or '').strip():
                    customer.phone = phone
                if email and not (customer.email or '').strip():
                    customer.email = email
                addr = (data.get('address') or '').strip()
                if addr and not (customer.address or '').strip():
                    customer.address = addr
            else:
                customer = Customer(
                    name=name,
                    phone=phone,
                    email=email,
                    address=data.get('address', ''),
                    loyalty_points=0
                )
                db.session.add(customer)
                db.session.flush()  # Get the customer ID
        
        # Generate unique member number and barcode
        member_number = LoyaltyMember.generate_member_number()
        while LoyaltyMember.query.filter_by(member_number=member_number).first():
            member_number = LoyaltyMember.generate_member_number()
        
        card_barcode = LoyaltyMember.generate_barcode()
        while LoyaltyMember.query.filter_by(card_barcode=card_barcode).first():
            card_barcode = LoyaltyMember.generate_barcode()
        
        # Calculate expiry date (1 year from now)
        expiry_date = datetime.now() + timedelta(days=365)
        
        # Resolve initial tier (defaults to Bronze if configured)
        # If no tiers exist, leave tier_id as NULL to satisfy FK constraint.
        initial_tier = calculate_tier(0)
        initial_tier_id = initial_tier.id if initial_tier else None

        # Create loyalty member
        member = LoyaltyMember(
            customer_id=customer.id,
            member_number=member_number,
            card_barcode=card_barcode,
            tier_id=initial_tier_id,
            join_date=datetime.now(),
            expiry_date=expiry_date,
            current_points=0,
            lifetime_points=0,
            card_issued=False,
            card_status='active',
            is_active=True
        )
        db.session.add(member)
        db.session.flush()
        
        db.session.commit()
        
        log_activity(
            current_user_id, 
            'LOYALTY_MEMBER_REGISTERED', 
            'loyalty_member', 
            member.id,
            {'member_number': member_number, 'customer_name': customer.name}
        )
        
        return jsonify({
            'success': True,
            'message': 'Loyalty member registered successfully',
            'data': member.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>', methods=['PUT'])
@jwt_required()
def update_member(member_id):
    """Update member information"""
    try:
        current_user_id = get_jwt_identity()
        member = LoyaltyMember.query.get(member_id)
        
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        data = request.get_json() or {}

        # Allow updating linked customer fields
        customer_updates = data.get('customer') if isinstance(data.get('customer'), dict) else {}
        name = customer_updates.get('name') if customer_updates else data.get('name')
        phone = customer_updates.get('phone') if customer_updates else data.get('phone')
        email = customer_updates.get('email') if customer_updates else data.get('email')
        address = customer_updates.get('address') if customer_updates else data.get('address')

        customer = member.customer
        if customer:
            if phone is not None and phone != customer.phone and phone != '':
                existing_phone = Customer.query.filter(Customer.phone == phone, Customer.id != customer.id).first()
                if existing_phone:
                    return jsonify({'success': False, 'message': 'Phone number already registered'}), 400

            if email is not None and email != customer.email and email != '':
                existing_email = Customer.query.filter(Customer.email == email, Customer.id != customer.id).first()
                if existing_email:
                    return jsonify({'success': False, 'message': 'Email already registered'}), 400

            if name is not None:
                customer.name = name
            if phone is not None:
                customer.phone = phone
            if email is not None:
                customer.email = email
            if address is not None:
                customer.address = address
        
        # Update allowed fields
        if 'tier_id' in data and data['tier_id'] is not None:
            member.tier_id = data['tier_id']

        if 'card_status' in data:
            member.card_status = data['card_status']
        
        if 'is_active' in data:
            member.is_active = data['is_active']
        
        if 'card_issued' in data:
            issued = bool(data['card_issued'])
            if issued and not member.card_issued:
                member.card_issued = True
                member.card_issued_date = datetime.now()
            elif not issued and member.card_issued:
                member.card_issued = False
                member.card_issued_date = None

        if 'expiry_date' in data:
            if not data['expiry_date']:
                member.expiry_date = None
            else:
                member.expiry_date = datetime.fromisoformat(data['expiry_date'].replace('Z', '+00:00'))
        
        db.session.commit()
        
        log_activity(
            current_user_id,
            'LOYALTY_MEMBER_UPDATED',
            'loyalty_member',
            member.id,
            data
        )
        
        return jsonify({
            'success': True,
            'message': 'Member updated successfully',
            'data': member.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>', methods=['DELETE'])
@jwt_required()
def delete_member(member_id):
    """Permanently delete an archived loyalty member and its linked customer."""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        current_user_id = get_jwt_identity()
        member = LoyaltyMember.query.get(member_id)

        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404

        # The UI exposes permanent delete from the Archived Members screen.
        # Require archived state as a safety rail.
        if not bool(getattr(member, 'is_archived', False)):
            return (
                jsonify(
                    {
                        'success': False,
                        'message': 'Member must be archived before deletion',
                    }
                ),
                400,
            )

        customer_id = member.customer_id
        customer = getattr(member, 'customer', None)

        member_number = member.member_number

        # If the customer has sales history, detach it (customer_id is nullable)
        # so we can delete the customer record without breaking FK constraints.
        try:
            from models.transaction import Transaction

            Transaction.query.filter(Transaction.customer_id == customer_id).update(
                {'customer_id': None}, synchronize_session=False
            )
        except Exception:
            # If transactions table/model is unavailable for some reason, proceed
            # with loyalty deletion only; customer delete may fail and will be
            # surfaced below.
            pass

        db.session.delete(member)

        if customer is not None:
            db.session.delete(customer)

        db.session.commit()

        log_activity(
            current_user_id,
            'LOYALTY_MEMBER_DELETED',
            'loyalty_member',
            member_id,
            {'member_number': member_number},
        )

        return (
            jsonify(
                {
                    'success': True,
                    'message': 'Member and customer deleted successfully',
                }
            ),
            200,
        )

    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/renew', methods=['POST'])
@jwt_required()
def renew_membership(member_id):
    """Renew membership validity for 1 year."""
    try:
        current_user_id = get_jwt_identity()
        member = LoyaltyMember.query.get(member_id)

        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404

        now = datetime.now()
        base_date = member.expiry_date if member.expiry_date and member.expiry_date > now else now
        member.expiry_date = base_date + timedelta(days=365)
        if member.card_status == 'expired':
            member.card_status = 'active'

        db.session.commit()

        log_activity(
            current_user_id,
            'LOYALTY_MEMBERSHIP_RENEWED',
            'loyalty_member',
            member.id,
            {'expiry_date': member.expiry_date.isoformat() if member.expiry_date else None},
        )

        return jsonify({
            'success': True,
            'message': 'Membership renewed successfully',
            'data': member.to_dict()
        }), 200

    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/issue-card', methods=['POST'])
@jwt_required()
def issue_card(member_id):
    """Mark physical card as issued"""
    try:
        current_user_id = get_jwt_identity()
        member = LoyaltyMember.query.get(member_id)
        
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        member.card_issued = True
        member.card_issued_date = datetime.now()
        
        db.session.commit()
        
        log_activity(
            current_user_id,
            'LOYALTY_CARD_ISSUED',
            'loyalty_member',
            member.id,
            {'member_number': member.member_number}
        )
        
        return jsonify({
            'success': True,
            'message': 'Card marked as issued',
            'data': member.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/card-data', methods=['GET'])
@jwt_required()
def get_card_data(member_id):
    """Get data needed for generating physical card"""
    try:
        member = LoyaltyMember.query.get(member_id)
        
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        # Get store info for card
        store_name = 'Vivian Cosmetic Shop'
        
        card_data = {
            'member_number': member.member_number,
            'card_barcode': member.card_barcode,
            'customer_name': member.customer.name if member.customer else '',
            'tier_name': member.tier.name if member.tier else 'Bronze',
            'tier_color': member.tier.color if member.tier else '#CD7F32',
            'join_date': member.join_date.strftime('%Y-%m-%d') if member.join_date else '',
            'expiry_date': member.expiry_date.strftime('%Y-%m-%d') if member.expiry_date else '',
            'store_name': store_name
        }
        
        return jsonify({
            'success': True,
            'data': card_data
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# =============================================================================
# POINTS MANAGEMENT
# =============================================================================

@loyalty_bp.route('/members/<int:member_id>/points', methods=['POST'])
@jwt_required()
def add_points(member_id):
    """Add or deduct points manually"""
    try:
        return jsonify({
            'success': False,
            'message': 'Points system has been removed'
        }), 410
        current_user_id = get_jwt_identity()
        
        # Verify user is supervisor
        user = User.query.get(current_user_id)
        if not user or user.role != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Only supervisors can adjust points manually'
            }), 403
        
        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        data = request.get_json()
        points = data.get('points', 0)
        reason = data.get('reason', 'Manual adjustment')
        transaction_type = data.get('type', 'adjust')
        
        if points == 0:
            return jsonify({'success': False, 'message': 'Points cannot be zero'}), 400
        
        # Check for sufficient points on deduction
        if points < 0 and member.current_points + points < 0:
            return jsonify({
                'success': False,
                'message': 'Insufficient points balance'
            }), 400
        
        # Update member points
        member.current_points += points
        if points > 0:
            member.lifetime_points += points
        
        # Check for tier upgrade
        new_tier = calculate_tier(member.lifetime_points)
        if new_tier and new_tier.id != member.tier_id:
            member.tier_id = new_tier.id
        
        # Record transaction
        transaction = LoyaltyTransaction(
            member_id=member.id,
            transaction_type=transaction_type,
            points=points,
            balance_after=member.current_points,
            description=reason,
            reference_code=f'ADJ-{datetime.now().strftime("%Y%m%d%H%M%S")}',
            adjusted_by=current_user_id
        )
        db.session.add(transaction)
        
        # Sync with customer loyalty_points
        if member.customer:
            member.customer.loyalty_points = member.current_points
        
        db.session.commit()
        
        log_activity(
            current_user_id,
            'LOYALTY_POINTS_ADJUSTED',
            'loyalty_member',
            member.id,
            {'points': points, 'reason': reason, 'new_balance': member.current_points}
        )
        
        return jsonify({
            'success': True,
            'message': f'Points {"added" if points > 0 else "deducted"} successfully',
            'data': member.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/transactions', methods=['GET'])
@jwt_required()
def get_member_transactions(member_id):
    """Get point transaction history for a member"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)
        
        pagination = LoyaltyTransaction.query.filter_by(member_id=member_id)\
            .order_by(LoyaltyTransaction.created_at.desc())\
            .paginate(page=page, per_page=per_page, error_out=False)
        
        return jsonify({
            'success': True,
            'data': {
                'transactions': [t.to_dict() for t in pagination.items],
                'total': pagination.total,
                'pages': pagination.pages,
                'current_page': page
            }
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/redeem', methods=['POST'])
@jwt_required()
def redeem_points(member_id):
    """Redeem points for discount"""
    try:
        return jsonify({
            'success': False,
            'message': 'Points system has been removed'
        }), 410
        current_user_id = get_jwt_identity()
        member = LoyaltyMember.query.get(member_id)
        
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        # Check if redemption is allowed
        if not get_loyalty_setting('allow_points_redemption', True):
            return jsonify({
                'success': False,
                'message': 'Points redemption is currently disabled'
            }), 400
        
        data = request.get_json()
        points_to_redeem = data.get('points', 0)
        
        if points_to_redeem <= 0:
            return jsonify({'success': False, 'message': 'Invalid points amount'}), 400
        
        if points_to_redeem > member.current_points:
            return jsonify({
                'success': False,
                'message': 'Insufficient points balance'
            }), 400
        
        # Calculate peso value
        points_to_peso = get_loyalty_setting('points_to_peso_rate', 100)
        peso_value = points_to_redeem / points_to_peso
        
        # Deduct points
        member.current_points -= points_to_redeem
        
        # Record transaction
        transaction = LoyaltyTransaction(
            member_id=member.id,
            transaction_type='redeem',
            points=-points_to_redeem,
            balance_after=member.current_points,
            description=f'Redeemed for ₱{peso_value:.2f} discount',
            reference_code=f'RDM-{datetime.now().strftime("%Y%m%d%H%M%S")}',
            adjusted_by=current_user_id
        )
        db.session.add(transaction)
        
        # Sync with customer
        if member.customer:
            member.customer.loyalty_points = member.current_points
        
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Points redeemed successfully',
            'data': {
                'points_redeemed': points_to_redeem,
                'peso_value': peso_value,
                'remaining_points': member.current_points
            }
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/members/<int:member_id>/redeem-product', methods=['POST'])
@jwt_required()
def redeem_product_for_member(member_id: int):
    """Redeem a product using points for a specific member (staff only)."""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        staff_user_id = get_jwt_identity()

        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404

        data = request.get_json() or {}
        product_id = data.get('product_id')
        quantity = data.get('quantity', 1)

        try:
            product_id = int(product_id)
        except Exception:
            return jsonify({'success': False, 'message': 'product_id is required'}), 400

        try:
            quantity = int(quantity)
        except Exception:
            return jsonify({'success': False, 'message': 'Invalid quantity'}), 400

        if quantity <= 0:
            return jsonify({'success': False, 'message': 'Quantity must be at least 1'}), 400

        product = Product.query.get(product_id)
        if not product or not product.is_active:
            return jsonify({'success': False, 'message': 'Product not found'}), 404

        points_cost = int(getattr(product, 'points_cost', 0) or 0)
        if points_cost <= 0:
            return jsonify({'success': False, 'message': 'This product is not redeemable'}), 400

        if int(product.stock_quantity or 0) < quantity:
            return jsonify({'success': False, 'message': 'Insufficient stock'}), 400

        points_needed = points_cost * quantity
        if int(member.current_points or 0) < points_needed:
            return jsonify({'success': False, 'message': 'Insufficient points balance'}), 400

        # Apply redemption
        member.current_points = int(member.current_points or 0) - points_needed

        # Decrement stock at redemption time.
        # Redeemed rewards may be completed as a ₱0 checkout in the POS without
        # posting a normal sale transaction, so relying on checkout to decrement
        # stock can leave inventory unchanged.
        product.stock_quantity = int(product.stock_quantity or 0) - quantity

        # Record transaction
        ref = f"RWP-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        tx = LoyaltyTransaction(
            member_id=member.id,
            transaction_type='redeem_product',
            points=-points_needed,
            balance_after=member.current_points,
            description=f"Redeemed {quantity}x {product.name}",
            reference_code=ref,
            adjusted_by=staff_user_id,
        )
        db.session.add(tx)

        # Sync with customer (best effort)
        if member.customer:
            try:
                member.customer.loyalty_points = member.current_points
            except Exception:
                pass

        db.session.commit()

        return jsonify({
            'success': True,
            'message': 'Reward redeemed successfully',
            'data': {
                'member': member.to_dict(),
                'product': product.to_dict(),
                'quantity': quantity,
                'points_spent': points_needed,
                'remaining_points': member.current_points,
                'reference_code': ref,
            }
        }), 200

    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


# =============================================================================
# TIERS MANAGEMENT
# =============================================================================

@loyalty_bp.route('/tiers', methods=['GET'])
@jwt_required()
def get_tiers():
    """Get all loyalty tiers"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        tiers = LoyaltyTier.query.order_by(LoyaltyTier.min_points).all()
        
        return jsonify({
            'success': True,
            'data': [t.to_dict() for t in tiers]
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/tiers/<int:tier_id>', methods=['PUT'])
@jwt_required()
def update_tier(tier_id):
    """Update tier settings (supervisor only)"""
    try:
        current_user_id = get_jwt_identity()
        
        user = User.query.get(current_user_id)
        if not user or user.role != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Only supervisors can update tier settings'
            }), 403
        
        tier = LoyaltyTier.query.get(tier_id)
        if not tier:
            return jsonify({'success': False, 'message': 'Tier not found'}), 404
        
        data = request.get_json()
        
        # Validate discount percent limits
        max_discount = get_loyalty_setting('max_discount_percent', 20)
        if 'discount_percent' in data:
            discount = float(data['discount_percent'])
            if discount < 0 or discount > max_discount:
                return jsonify({
                    'success': False,
                    'message': f'Discount must be between 0 and {max_discount}%'
                }), 400
            tier.discount_percent = discount
        
        if 'points_multiplier' in data:
            multiplier = float(data['points_multiplier'])
            if multiplier < 1 or multiplier > 5:
                return jsonify({
                    'success': False,
                    'message': 'Points multiplier must be between 1 and 5'
                }), 400
            tier.points_multiplier = multiplier
        
        if 'benefits' in data:
            tier.benefits = data['benefits']
        
        if 'min_points' in data:
            tier.min_points = int(data['min_points'])
        
        if 'max_points' in data:
            tier.max_points = int(data['max_points']) if data['max_points'] else None
        
        db.session.commit()
        
        log_activity(
            current_user_id,
            'LOYALTY_TIER_UPDATED',
            'loyalty_tier',
            tier.id,
            data
        )
        
        return jsonify({
            'success': True,
            'message': 'Tier updated successfully',
            'data': tier.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


# =============================================================================
# SETTINGS MANAGEMENT (ADMIN DISCOUNT CONTROL)
# =============================================================================

@loyalty_bp.route('/settings', methods=['GET'])
@jwt_required()
def get_loyalty_settings():
    """Get all loyalty settings"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        settings = LoyaltySetting.query.all()
        
        # Convert to dict format
        settings_dict = {}
        settings_list = []
        for s in settings:
            settings_dict[s.setting_key] = s.get_value()
            settings_list.append(s.to_dict())
        
        return jsonify({
            'success': True,
            'data': {
                'settings': settings_dict,
                'details': settings_list
            }
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/settings', methods=['PUT'])
@jwt_required()
def update_loyalty_settings():
    """Update loyalty settings (supervisor only)"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        current_user_id = get_jwt_identity()
        
        user = User.query.get(current_user_id)
        if not user or user.role != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Only supervisors can update loyalty settings'
            }), 403
        
        data = request.get_json()
        updated = []
        
        for key, value in data.items():
            setting = LoyaltySetting.query.filter_by(setting_key=key).first()
            if setting:
                # Validate within limits if defined
                if setting.setting_type == 'number':
                    try:
                        num_value = float(value)
                        if setting.min_value is not None and num_value < float(setting.min_value):
                            return jsonify({
                                'success': False,
                                'message': f'{key} cannot be less than {setting.min_value}'
                            }), 400
                        if setting.max_value is not None and num_value > float(setting.max_value):
                            return jsonify({
                                'success': False,
                                'message': f'{key} cannot be greater than {setting.max_value}'
                            }), 400
                    except ValueError:
                        return jsonify({
                            'success': False,
                            'message': f'{key} must be a number'
                        }), 400
                
                setting.setting_value = str(value)
                setting.last_modified_by = current_user_id
                updated.append(key)
        
        db.session.commit()
        
        log_activity(
            current_user_id,
            'LOYALTY_SETTINGS_UPDATED',
            'loyalty_settings',
            None,
            {'updated_keys': updated, 'values': data}
        )
        
        return jsonify({
            'success': True,
            'message': f'Updated {len(updated)} setting(s)',
            'data': {'updated': updated}
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/settings/<key>', methods=['GET'])
@jwt_required()
def get_loyalty_setting_by_key(key):
    """Get a single loyalty setting by key"""
    try:
        denied = _require_roles(_STAFF_ROLES)
        if denied:
            return denied

        setting = LoyaltySetting.query.filter_by(setting_key=key).first()

        if not setting:
            return jsonify({'success': False, 'message': 'Setting not found'}), 404

        return jsonify({
            'success': True,
            'data': setting.to_dict()
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# =============================================================================
# LOYALTY MEMBER APP ENDPOINTS
# =============================================================================


@loyalty_bp.route('/app/login', methods=['POST'])
def loyalty_member_app_login():
    """Login endpoint for loyalty members (mobile app)."""
    try:
        _cleanup_otps()
        data = request.get_json() or {}
        member_number = (data.get('member_number') or '').strip()
        phone = _normalize_phone(data.get('phone') or '')
        barcode = (data.get('barcode') or '').strip()
        otp_ref = (data.get('otp_ref') or '').strip()
        otp_code = (data.get('otp_code') or '').strip()

        if barcode:
            member = LoyaltyMember.query.filter_by(card_barcode=barcode).first()
        else:
            if not member_number or not phone:
                return jsonify({
                    'success': False,
                    'message': 'member_number and phone are required'
                }), 400

            # Strict phone format: digits only 11-12 (matches cashier registration rules)
            if not re.fullmatch(r'\d{11,12}', phone):
                return jsonify({'success': False, 'message': 'Invalid phone number'}), 400

            phone_variants = _phone_variants_for_lookup(phone)

            member = (
                LoyaltyMember.query.join(Customer)
                .filter(
                    LoyaltyMember.member_number == member_number,
                    Customer.phone.in_(phone_variants),
                )
                .first()
            )

        if not member:
            return jsonify({'success': False, 'message': 'Invalid member credentials'}), 401

        if member.card_status != 'active':
            return jsonify({'success': False, 'message': 'Member account is inactive'}), 403

        is_archived = bool(getattr(member, 'is_archived', False))
        if (not member.is_active) or is_archived:
            remaining = int(getattr(member, 'reactivation_remaining', 3) or 0)
            if remaining <= 0:
                return jsonify({
                    'success': False,
                    'message': 'Account is deactivated and can no longer be reactivated.',
                    'error': 'activation_limit_reached',
                }), 403

            # Self-reactivation on login.
            member.is_active = True
            if hasattr(member, 'is_archived'):
                member.is_archived = False
            if hasattr(member, 'archived_at'):
                member.archived_at = None
            if hasattr(member, 'deactivated_at'):
                member.deactivated_at = None
            if hasattr(member, 'reactivation_remaining'):
                member.reactivation_remaining = remaining - 1

        # Enforce OTP only for member_number + phone logins.
        # Barcode logins are left unchanged (no phone provided).
        if not barcode:
            if not otp_ref or not otp_code:
                return jsonify({
                    'success': False,
                    'message': 'OTP required. Please request an OTP and try again.',
                    'error': 'otp_required',
                }), 400

            entry = _otp_store.get(otp_ref)
            if not entry:
                return jsonify({
                    'success': False,
                    'message': 'OTP expired or invalid. Please request a new OTP.',
                    'error': 'otp_invalid',
                }), 400

            if int(entry.get('expires_at', 0)) <= _now_ts():
                _otp_store.pop(otp_ref, None)
                return jsonify({
                    'success': False,
                    'message': 'OTP expired. Please request a new OTP.',
                    'error': 'otp_expired',
                }), 400

            if int(entry.get('attempts', 0)) >= _OTP_MAX_ATTEMPTS:
                _otp_store.pop(otp_ref, None)
                return jsonify({
                    'success': False,
                    'message': 'Too many failed attempts. Please request a new OTP.',
                    'error': 'otp_locked',
                }), 429

            # Ensure otp_ref matches this member + phone.
            if (
                int(entry.get('member_id', -1)) != int(member.id)
                or str(entry.get('member_number', '')).strip() != member_number
                or str(entry.get('phone', '')).strip() != phone
            ):
                return jsonify({
                    'success': False,
                    'message': 'OTP does not match this account. Please request a new OTP.',
                    'error': 'otp_mismatch',
                }), 400

            provider_mode = str(entry.get('provider_mode') or '').strip().lower()
            if provider_mode == 'textflow':
                provider_phone = str(entry.get('provider_phone') or '').strip() or format_phone_e164(phone)
                verified, verify_error = textflow_verify_otp_code(phone=provider_phone, code=otp_code)
                if not verified:
                    entry['attempts'] = int(entry.get('attempts', 0)) + 1
                    return jsonify({
                        'success': False,
                        'message': 'Invalid OTP code',
                        'error': 'otp_invalid',
                        'details': verify_error or 'TextFlow verification failed',
                    }), 401
            elif provider_mode in {'twilio', 'twilio_verify', 'twilio-verify'}:
                provider_phone = str(entry.get('provider_phone') or '').strip() or format_phone_e164(phone)
                verified, verify_error = twilio_verify_check_code(phone=provider_phone, code=otp_code)
                if not verified:
                    entry['attempts'] = int(entry.get('attempts', 0)) + 1
                    return jsonify({
                        'success': False,
                        'message': 'Invalid OTP code',
                        'error': 'otp_invalid',
                        'details': verify_error or 'Twilio verification failed',
                    }), 401
            else:
                expected_hash = str(entry.get('otp_hash', ''))
                provided_hash = _hash_otp(otp_ref, otp_code)
                if not hmac.compare_digest(expected_hash, provided_hash):
                    entry['attempts'] = int(entry.get('attempts', 0)) + 1
                    return jsonify({
                        'success': False,
                        'message': 'Invalid OTP code',
                        'error': 'otp_invalid',
                    }), 401

            # One-time use OTP.
            _otp_store.pop(otp_ref, None)

        access_token = create_access_token(
            identity=str(member.id),
            additional_claims={
                'role': _MEMBER_ROLE,
                'member_id': member.id,
                'customer_id': member.customer_id,
            },
            expires_delta=timedelta(days=30),
        )

        # Mark activity (activated_at on first successful login)
        try:
            now = datetime.now()
            if hasattr(member, 'activated_at') and not member.activated_at:
                member.activated_at = now
            if hasattr(member, 'last_active_at'):
                member.last_active_at = now
            db.session.commit()
        except Exception:
            db.session.rollback()

        return jsonify({
            'success': True,
            'message': 'Login successful',
            'data': {
                'access_token': access_token,
                'member': member.to_dict(),
            }
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/app/request-otp', methods=['POST'])
def loyalty_member_app_request_otp():
    """Request a one-time password (OTP) for loyalty member login."""
    try:
        _cleanup_otps()
        data = request.get_json() or {}
        member_number = (data.get('member_number') or '').strip()
        phone = _normalize_phone(data.get('phone') or '')
        channel = (data.get('channel') or 'email').strip().lower()

        # Backward compatible aliases
        if channel in {'sms', 'phone'}:
            channel = 'sms'
        if channel in {'mail', 'gmail'}:
            channel = 'email'

        if not member_number or not phone:
            return jsonify({
                'success': False,
                'message': 'member_number and phone are required'
            }), 400

        if not re.fullmatch(r'\d{11,12}', phone):
            return jsonify({'success': False, 'message': 'Invalid phone number'}), 400

        phone_variants = _phone_variants_for_lookup(phone)

        member = (
            LoyaltyMember.query.join(Customer)
            .filter(
                LoyaltyMember.member_number == member_number,
                Customer.phone.in_(phone_variants),
            )
            .first()
        )

        if not member:
            # Avoid leaking whether member exists: use a generic message.
            return jsonify({'success': False, 'message': 'Invalid member credentials'}), 401

        if member.card_status != 'active':
            return jsonify({'success': False, 'message': 'Member account is inactive'}), 403

        is_archived = bool(getattr(member, 'is_archived', False))
        if (not member.is_active) or is_archived:
            remaining = int(getattr(member, 'reactivation_remaining', 3) or 0)
            if remaining <= 0:
                return jsonify({
                    'success': False,
                    'message': 'Account is deactivated and can no longer be reactivated.',
                    'error': 'activation_limit_reached',
                }), 403

        # Basic rate limiting per member+phone.
        if _count_recent_requests(member.id, phone) >= _OTP_MAX_REQUESTS_PER_WINDOW:
            return jsonify({
                'success': False,
                'message': 'Too many OTP requests. Please wait and try again.',
                'error': 'otp_rate_limited',
            }), 429

        otp_ref = uuid.uuid4().hex
        otp_code: str
        created_at = _now_ts()
        expires_at = created_at + _OTP_TTL_SECONDS

        sms_phone = _format_phone_for_sms(phone)
        provider_mode = (os.getenv('OTP_SMS_PROVIDER_MODE') or '').strip().lower()
        sent = False
        send_error: str | None = None
        provider_fallback_to_dev = False

        is_dev_local = os.getenv('FLASK_ENV', 'development') != 'production'
        echo_local = os.getenv('OTP_DEV_ECHO', 'true').lower() in {
            '1',
            'true',
            'yes',
            'on',
        }

        provider_entry: dict[str, object] | None = None

        # Primary: Email OTP (preferred)
        if channel == 'email':
            otp_code = _generate_otp_code()
            customer_email = (getattr(member, 'customer', None) and getattr(member.customer, 'email', None))
            customer_email = (customer_email or '').strip()

            sent, send_error, masked = send_otp_email(to_email=customer_email, otp=otp_code)
            if sent:
                provider_entry = {
                    'provider_mode': 'email',
                    'provider_email': masked or '',
                }
            else:
                if is_dev_local and echo_local:
                    provider_fallback_to_dev = True
                    sent = False
                else:
                    return jsonify({
                        'success': False,
                        'message': 'Failed to request OTP from email provider',
                        'error': 'otp_email_failed',
                        'details': send_error or 'Unknown error',
                    }), 502

        # Alternative: SMS OTP
        elif channel == 'sms':
            if provider_mode == 'textflow':
                textflow_phone = format_phone_e164(phone)
                sent, send_error = textflow_send_otp_code(phone=textflow_phone)
                if sent:
                    provider_entry = {
                        'provider_mode': 'textflow',
                        'provider_phone': textflow_phone,
                    }
                    otp_code = ''
                else:
                    if is_dev_local and echo_local:
                        provider_fallback_to_dev = True
                        otp_code = _generate_otp_code()
                        sent = False
                    else:
                        return jsonify({
                            'success': False,
                            'message': 'Failed to request OTP from SMS provider',
                            'error': 'otp_provider_failed',
                            'details': send_error or 'Unknown error',
                        }), 502

            elif provider_mode in {'twilio', 'twilio_verify', 'twilio-verify'}:
                twilio_phone = format_phone_e164(phone)
                sent, send_error = twilio_verify_send_code(phone=twilio_phone)
                if sent:
                    provider_entry = {
                        'provider_mode': 'twilio_verify',
                        'provider_phone': twilio_phone,
                    }
                    otp_code = ''
                else:
                    if is_dev_local and echo_local:
                        provider_fallback_to_dev = True
                        otp_code = _generate_otp_code()
                        sent = False
                    else:
                        return jsonify({
                            'success': False,
                            'message': 'Failed to request OTP from SMS provider',
                            'error': 'otp_provider_failed',
                            'details': send_error or 'Unknown error',
                        }), 502

            elif provider_mode == 'textbelt':
                otp_code = _generate_otp_code()
                textbelt_number = _normalize_phone(format_phone_e164(phone))
                sent, send_error = textbelt_send_otp_sms(phone=textbelt_number, otp=otp_code)
                if not sent:
                    if is_dev_local and echo_local:
                        provider_fallback_to_dev = True
                        sent = False
                    else:
                        return jsonify({
                            'success': False,
                            'message': 'Failed to request OTP from SMS provider',
                            'error': 'otp_provider_failed',
                            'details': send_error or 'Unknown error',
                        }), 502

            elif provider_mode in {'sms-verify3', 'provider'}:
                sms_target = format_sms_verify3_target(sms_phone)
                sent, provider_code, send_error = request_provider_otp(phone=sms_target)
                if sent and provider_code:
                    otp_code = provider_code
                else:
                    if is_dev_local and echo_local:
                        provider_fallback_to_dev = True
                        otp_code = _generate_otp_code()
                        sent = False
                    else:
                        return jsonify({
                            'success': False,
                            'message': 'Failed to request OTP from SMS provider',
                            'error': 'otp_provider_failed',
                            'details': send_error or 'Unknown error',
                        }), 502
            else:
                otp_code = _generate_otp_code()
                sent, send_error = send_otp_sms(phone=sms_phone, otp=otp_code)

        else:
            return jsonify({
                'success': False,
                'message': 'Invalid channel. Use email or sms.',
                'error': 'otp_channel_invalid',
            }), 400

        entry: dict[str, object] = {
            'member_id': int(member.id),
            'member_number': member_number,
            'phone': phone,
            'created_at': created_at,
            'expires_at': expires_at,
            'attempts': 0,
            'rate_key': _rate_limit_key(member.id, phone),
        }

        if provider_entry and (not provider_fallback_to_dev):
            entry.update(provider_entry)
            pm = str(entry.get('provider_mode') or '').strip().lower()
            # External providers (Verify/TextFlow) generate the code; we don't store a hash.
            if pm in {'textflow', 'twilio', 'twilio_verify', 'twilio-verify'}:
                entry['otp_hash'] = ''
            else:
                # Email and local modes must store the hash for later verification.
                entry['otp_hash'] = _hash_otp(otp_ref, otp_code)
        else:
            entry['otp_hash'] = _hash_otp(otp_ref, otp_code)

        entry['channel'] = channel

        _otp_store[otp_ref] = entry

        payload: dict[str, object] = {
            'otp_ref': otp_ref,
            'expires_in_seconds': _OTP_TTL_SECONDS,
            'channel': channel,
        }

        # Provide a masked destination for UI display (email only).
        if channel == 'email':
            provider_email = str(entry.get('provider_email') or '').strip()
            if provider_email:
                payload['destination'] = provider_email

        is_dev = os.getenv('FLASK_ENV', 'development') != 'production'
        echo = os.getenv('OTP_DEV_ECHO', 'true').lower() in {'1', 'true', 'yes', 'on'}
        if (not sent) and is_dev and echo and (
            provider_mode not in {'sms-verify3', 'provider', 'textflow'} or provider_fallback_to_dev
        ):
            payload['dev_otp'] = otp_code
            payload['dev_note'] = send_error or 'SMS provider not configured'

        return jsonify({
            'success': True,
            'message': ('Code sent' if sent else 'Code generated') if channel == 'email' else ('OTP sent' if sent else 'OTP generated'),
            'data': payload,
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/app/me', methods=['GET'])
@jwt_required()
def loyalty_member_app_me():
    """Return the authenticated member profile + points balance."""
    try:
        denied = _require_roles({_MEMBER_ROLE})
        if denied:
            return denied

        raw_id = get_jwt_identity()
        try:
            member_id = int(raw_id)
        except Exception:
            return jsonify({'success': False, 'message': 'Invalid token identity'}), 401

        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404

        if member.card_status != 'active' or (not member.is_active) or bool(getattr(member, 'is_archived', False)):
            return jsonify({'success': False, 'message': 'Member account is inactive'}), 403

        # Touch activity
        try:
            if hasattr(member, 'last_active_at'):
                member.last_active_at = datetime.now()
                db.session.commit()
        except Exception:
            db.session.rollback()

        return jsonify({'success': True, 'data': member.to_dict()}), 200

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/app/transactions', methods=['GET'])
@jwt_required()
def loyalty_member_app_transactions():
    """Point transaction history for the authenticated member."""
    try:
        denied = _require_roles({_MEMBER_ROLE})
        if denied:
            return denied

        raw_id = get_jwt_identity()
        try:
            member_id = int(raw_id)
        except Exception:
            return jsonify({'success': False, 'message': 'Invalid token identity'}), 401

        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 20, type=int)

        pagination = (
            LoyaltyTransaction.query.filter_by(member_id=member_id)
            .order_by(LoyaltyTransaction.created_at.desc())
            .paginate(page=page, per_page=per_page, error_out=False)
        )

        return jsonify({
            'success': True,
            'data': {
                'transactions': [t.to_dict() for t in pagination.items],
                'total': pagination.total,
                'pages': pagination.pages,
                'current_page': page,
            }
        }), 200

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/app/rewards', methods=['GET'])
@jwt_required()
def loyalty_member_app_rewards():
    """List redeemable reward products for the member app."""
    try:
        denied = _require_roles({_MEMBER_ROLE})
        if denied:
            return denied

        # Show products that are active and have a points cost.
        # Stock can be 0 (the app will disable redemption).
        products = (
            Product.query
            .filter(Product.is_active == True)
            .filter(Product.points_cost > 0)
            .order_by(Product.name.asc())
            .all()
        )

        def _reward_dict(p: Product) -> dict:
            return {
                'id': p.id,
                'name': p.name,
                'description': p.description,
                'image_url': p.image_url,
                'points_cost': int(p.points_cost or 0),
                'stock_quantity': int(p.stock_quantity or 0),
                'unit': p.unit,
                'category_name': p.category.name if p.category else None,
            }

        return jsonify({'success': True, 'data': [_reward_dict(p) for p in products]}), 200

    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@loyalty_bp.route('/app/rewards/redeem', methods=['POST'])
@jwt_required()
def loyalty_member_app_redeem_reward():
    """Redeem a reward product using points (member-initiated)."""
    try:
        denied = _require_roles({_MEMBER_ROLE})
        if denied:
            return denied

        raw_id = get_jwt_identity()
        try:
            member_id = int(raw_id)
        except Exception:
            return jsonify({'success': False, 'message': 'Invalid token identity'}), 401

        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404

        data = request.get_json() or {}
        product_id = data.get('product_id')
        quantity = data.get('quantity', 1)

        try:
            product_id = int(product_id)
        except Exception:
            return jsonify({'success': False, 'message': 'product_id is required'}), 400

        try:
            quantity = int(quantity)
        except Exception:
            return jsonify({'success': False, 'message': 'Invalid quantity'}), 400

        if quantity <= 0:
            return jsonify({'success': False, 'message': 'Quantity must be at least 1'}), 400

        product = Product.query.get(product_id)
        if not product or not product.is_active:
            return jsonify({'success': False, 'message': 'Product not found'}), 404

        points_cost = int(getattr(product, 'points_cost', 0) or 0)
        if points_cost <= 0:
            return jsonify({'success': False, 'message': 'This product is not redeemable'}), 400

        if int(product.stock_quantity or 0) < quantity:
            return jsonify({'success': False, 'message': 'Insufficient stock'}), 400

        points_needed = points_cost * quantity
        if int(member.current_points or 0) < points_needed:
            return jsonify({'success': False, 'message': 'Insufficient points balance'}), 400

        member.current_points = int(member.current_points or 0) - points_needed
        product.stock_quantity = int(product.stock_quantity or 0) - quantity

        ref = f"RWP-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        tx = LoyaltyTransaction(
            member_id=member.id,
            transaction_type='redeem_product',
            points=-points_needed,
            balance_after=member.current_points,
            description=f"Redeemed {quantity}x {product.name}",
            reference_code=ref,
            adjusted_by=None,
        )
        db.session.add(tx)

        if member.customer:
            try:
                member.customer.loyalty_points = member.current_points
            except Exception:
                pass

        db.session.commit()

        return jsonify({
            'success': True,
            'message': 'Reward redeemed successfully',
            'data': {
                'member': member.to_dict(),
                'product': {
                    'id': product.id,
                    'name': product.name,
                    'points_cost': int(product.points_cost or 0),
                    'stock_quantity': int(product.stock_quantity or 0),
                },
                'quantity': quantity,
                'points_spent': points_needed,
                'remaining_points': member.current_points,
                'reference_code': ref,
            }
        }), 200

    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500
        
        if not setting:
            return jsonify({'success': False, 'message': 'Setting not found'}), 404
        
        return jsonify({
            'success': True,
            'data': setting.to_dict()
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# =============================================================================
# DASHBOARD / STATISTICS
# =============================================================================

@loyalty_bp.route('/dashboard', methods=['GET'])
@jwt_required()
def get_loyalty_dashboard():
    """Get loyalty program statistics"""
    try:
        # Total members
        total_members = LoyaltyMember.query.filter_by(is_active=True).count()
        
        # Members by tier
        tier_counts = db.session.query(
            LoyaltyTier.name,
            LoyaltyTier.color,
            func.count(LoyaltyMember.id)
        ).outerjoin(LoyaltyMember).filter(
            LoyaltyMember.is_active == True
        ).group_by(LoyaltyTier.id).all()
        
        # Expiring / expired memberships
        now = datetime.now()
        expiring_threshold = now + timedelta(days=30)

        expiring_soon = LoyaltyMember.query.filter(
            LoyaltyMember.is_active == True,
            LoyaltyMember.expiry_date.isnot(None),
            LoyaltyMember.expiry_date >= now,
            LoyaltyMember.expiry_date <= expiring_threshold,
        ).count()

        expired_members = LoyaltyMember.query.filter(
            LoyaltyMember.is_active == True,
            LoyaltyMember.expiry_date.isnot(None),
            LoyaltyMember.expiry_date < now,
        ).count()
        
        # Recent signups (last 30 days)
        thirty_days_ago = datetime.now() - timedelta(days=30)
        recent_signups = LoyaltyMember.query.filter(
            LoyaltyMember.created_at >= thirty_days_ago
        ).count()
        
        # Cards pending issuance
        cards_pending = LoyaltyMember.query.filter_by(
            is_active=True,
            card_issued=False
        ).count()

        archived_members = 0
        if hasattr(LoyaltyMember, 'is_archived'):
            archived_members = LoyaltyMember.query.filter(
                LoyaltyMember.is_archived.is_(True)
            ).count()
        
        return jsonify({
            'success': True,
            'data': {
                'total_members': total_members,
                'tier_distribution': [
                    {'tier': name, 'color': color, 'count': count}
                    for name, color, count in tier_counts
                ],
                'expiring_soon': expiring_soon,
                'expired_members': expired_members,
                'recent_signups': recent_signups,
                'cards_pending_issuance': cards_pending,
                'archived_members': archived_members,
            }
        }), 200
        
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# =============================================================================
# RECENT MEMBERS LIST
# =============================================================================

@loyalty_bp.route('/members/recent', methods=['GET'])
@jwt_required()
def get_recent_members():
    """Return recently signed-up loyalty members.

    Query params:
    - days: window in days (default 30)
    - limit: number of records (default 20)
    """
    try:
        days = request.args.get('days', 30, type=int)
        limit = request.args.get('limit', 20, type=int)
        since = datetime.now() - timedelta(days=days)

        members = (
            LoyaltyMember.query
            .filter(LoyaltyMember.created_at >= since)
            .order_by(LoyaltyMember.created_at.desc())
            .limit(limit)
            .all()
        )

        return jsonify({
            'success': True,
            'data': [m.to_dict() for m in members],
            'count': len(members),
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


# =============================================================================
# EARN POINTS ON TRANSACTION
# =============================================================================

@loyalty_bp.route('/earn-points', methods=['POST'])
@jwt_required()
def earn_points_on_purchase():
    """Award points based on purchase amount (called after transaction)"""
    try:
        return jsonify({
            'success': False,
            'message': 'Points system has been removed'
        }), 410
        current_user_id = get_jwt_identity()
        data = request.get_json()
        
        member_id = data.get('member_id')
        transaction_id = data.get('transaction_id')
        purchase_amount = data.get('amount', 0)
        
        if not member_id or purchase_amount <= 0:
            return jsonify({
                'success': False,
                'message': 'Member ID and positive amount required'
            }), 400
        
        member = LoyaltyMember.query.get(member_id)
        if not member:
            return jsonify({'success': False, 'message': 'Member not found'}), 404
        
        # Check minimum purchase
        min_purchase = get_loyalty_setting('min_purchase_for_points', 100)
        if purchase_amount < min_purchase:
            return jsonify({
                'success': True,
                'message': f'Purchase below minimum ₱{min_purchase} for earning points',
                'data': {'points_earned': 0}
            }), 200
        
        # Calculate points
        points_per_peso = get_loyalty_setting('points_per_peso', 1)
        tier_multiplier = float(member.tier.points_multiplier) if member.tier else 1
        
        base_points = int(purchase_amount * points_per_peso)
        total_points = int(base_points * tier_multiplier)
        
        # Update member points
        member.current_points += total_points
        member.lifetime_points += total_points
        
        # Check for tier upgrade
        new_tier = calculate_tier(member.lifetime_points)
        tier_upgraded = False
        if new_tier and new_tier.id != member.tier_id:
            member.tier_id = new_tier.id
            tier_upgraded = True
        
        # Record transaction
        loyalty_trans = LoyaltyTransaction(
            member_id=member.id,
            transaction_id=transaction_id,
            transaction_type='earn',
            points=total_points,
            balance_after=member.current_points,
            description=f'Earned from ₱{purchase_amount:.2f} purchase ({tier_multiplier}x multiplier)',
            reference_code=f'EARN-{datetime.now().strftime("%Y%m%d%H%M%S")}'
        )
        db.session.add(loyalty_trans)
        
        # Sync with customer
        if member.customer:
            member.customer.loyalty_points = member.current_points
        
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Points awarded successfully',
            'data': {
                'points_earned': total_points,
                'current_points': member.current_points,
                'tier_upgraded': tier_upgraded,
                'new_tier': new_tier.name if tier_upgraded else None
            }
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500
