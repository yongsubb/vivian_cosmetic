"""Settings routes."""

import re
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt
from extensions import db

from models.setting import Setting

settings_bp = Blueprint('settings', __name__)


_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _is_valid_email(value: str) -> bool:
    return bool(_EMAIL_RE.match((value or "").strip()))

DEFAULT_SETTINGS = {
    'store_name': ('Vivian Cosmetic Shop', 'string', 'Store display name'),
    'store_address': ('123 Beauty Street, Manila, Philippines', 'string', 'Store address'),
    'store_phone': ('+63 912 345 6789', 'string', 'Store contact number'),
    'store_email': ('info@viviancosmetics.com', 'string', 'Store email'),
    # Requested: default is 0 so tax does not come back as 12% after relogin/restart.
    'tax_rate': (0, 'number', 'Tax rate percentage'),
    'currency': ('PHP', 'string', 'Currency code'),
    'currency_symbol': ('₱', 'string', 'Currency symbol'),
    'receipt_footer': ('Thank you for shopping at Vivian Cosmetic Shop!', 'string', 'Receipt footer message'),
    'low_stock_threshold': (10, 'number', 'Low stock threshold'),
    'low_stock_notification': (True, 'boolean', 'Enable low stock notifications'),
}


_defaults_initialized = False


def _ensure_defaults():
    global _defaults_initialized
    if _defaults_initialized:
        return

    # Best-effort: ensure table exists for environments created via SQLAlchemy.
    # If the DB is created via schema.sql, this is effectively a no-op.
    try:
        db.create_all()
    except Exception:
        pass

    try:
        for key, (default_value, setting_type, description) in DEFAULT_SETTINGS.items():
            row = Setting.query.filter_by(setting_key=key).with_for_update(skip_locked=True).first()
            
            if row is None:
                try:
                    row = Setting(
                        setting_key=key,
                        setting_type=setting_type,
                        description=description,
                    )
                    row.set_value(default_value)
                    db.session.add(row)
                    db.session.commit()
                except Exception:
                    # Another process already inserted it, ignore
                    db.session.rollback()
            else:
                changed = False
                # One-time migration: old default tax_rate was 12. If it is still 12,
                # flip it to the new default 0 so it doesn't reappear after relogin.
                if key == 'tax_rate' and str(row.setting_value).strip() == '12':
                    row.setting_type = 'number'
                    row.set_value(0)
                    changed = True

                # Keep the stored value, but ensure metadata is present.
                if not row.setting_type:
                    row.setting_type = setting_type
                    changed = True
                if row.description is None and description is not None:
                    row.description = description
                    changed = True
                
                if changed:
                    db.session.commit()

        _defaults_initialized = True
    except Exception:
        db.session.rollback()
        # If we hit any error, still mark as initialized to avoid repeated attempts
        _defaults_initialized = True


def get_setting_value(key, default=None):
    """Get a typed setting value from DB with a default fallback."""
    _ensure_defaults()
    row = Setting.query.filter_by(setting_key=key).first()
    if row is None:
        return DEFAULT_SETTINGS.get(key, (default, 'string', None))[0]
    return row.get_value()


def _all_settings_dict():
    _ensure_defaults()
    rows = Setting.query.all()
    return {r.setting_key: r.get_value() for r in rows}


@settings_bp.route('/', methods=['GET'])
@jwt_required()
def get_settings():
    """Get all settings"""
    try:
        return jsonify({
            'success': True,
            'data': _all_settings_dict()
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@settings_bp.route('/<key>', methods=['GET'])
@jwt_required()
def get_setting(key):
    """Get specific setting"""
    try:
        return jsonify({
            'success': True,
            'data': {key: get_setting_value(key)}
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@settings_bp.route('/', methods=['PUT'])
@jwt_required()
def update_settings():
    """Update settings (supervisor only)"""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403
        
        data = request.get_json()
        if not data:
            return jsonify({
                'success': False,
                'message': 'No data provided'
            }), 400

        _ensure_defaults()
        updated = {}
        
        for key, value in data.items():
            if key in ('email', 'store_email', 'storeEmail'):
                email = str(value or '').strip()
                if email and not _is_valid_email(email):
                    return jsonify({
                        'success': False,
                        'message': f'Invalid email address for {key}'
                    }), 400

            row = Setting.query.filter_by(setting_key=key).first()
            if row is None:
                default_value, setting_type, description = DEFAULT_SETTINGS.get(
                    key,
                    ('', 'string', None),
                )
                row = Setting(
                    setting_key=key,
                    setting_type=setting_type,
                    description=description,
                )
                row.set_value(default_value)
                db.session.add(row)

            # Light type enforcement based on known defaults
            expected_type = DEFAULT_SETTINGS.get(key, (None, row.setting_type, None))[1] or row.setting_type
            row.setting_type = expected_type

            if expected_type == 'number':
                try:
                    value = float(value)
                except (ValueError, TypeError):
                    return jsonify({
                        'success': False,
                        'message': f'Invalid number for {key}'
                    }), 400
            elif expected_type == 'boolean':
                if isinstance(value, str):
                    value = value.lower() in ('true', '1', 'yes')
                else:
                    value = bool(value)

            row.set_value(value)
            updated[key] = row.get_value()

        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Settings updated successfully',
            'data': _all_settings_dict(),
            'updated': updated
        }), 200
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500
