"""Users routes - User management (admin only)."""

import re
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt
from extensions import db
from models.user import User
from utils.rbac import require_supervisor

users_bp = Blueprint('users', __name__)


_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _is_valid_email(value: str) -> bool:
    return bool(_EMAIL_RE.match((value or "").strip()))
@users_bp.route('/', methods=['GET'])
@jwt_required()
@require_supervisor
def get_users():
    """Get all users (supervisor only)"""
    try:
        users = User.query.all()
        return jsonify({
            'success': True,
            'data': [user.to_dict() for user in users]
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@users_bp.route('/<int:user_id>', methods=['GET'])
@jwt_required()
@require_supervisor
def get_user(user_id):
    """Get specific user"""
    try:
        user = User.query.get(user_id)
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        return jsonify({
            'success': True,
            'data': user.to_dict()
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@users_bp.route('/', methods=['POST'])
@jwt_required()
@require_supervisor
def create_user():
    """Create new user"""
    try:
        data = request.get_json()
        
        # Validate required fields
        required = ['username', 'password', 'first_name', 'last_name']
        for field in required:
            if not data.get(field):
                return jsonify({
                    'success': False,
                    'message': f'{field} is required'
                }), 400
        
        # Check if username exists
        if User.query.filter_by(username=data['username']).first():
            return jsonify({
                'success': False,
                'message': 'Username already exists'
            }), 409
        
        email = (data.get('email') or '').strip()
        if email and not _is_valid_email(email):
            return jsonify({
                'success': False,
                'message': 'Invalid email address'
            }), 400

        user = User(
            username=data['username'],
            first_name=data['first_name'],
            last_name=data['last_name'],
            password=data['password'],
            role=data.get('role', 'cashier'),
            email=email if email else None,
            phone=data.get('phone')
        )
        
        if data.get('pin'):
            user.set_pin(data['pin'])
        
        db.session.add(user)
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'User created successfully',
            'data': user.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@users_bp.route('/<int:user_id>', methods=['PUT'])
@jwt_required()
@require_supervisor
def update_user(user_id):
    """Update user"""
    try:
        user = User.query.get(user_id)
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        data = request.get_json()
        
        # Update fields
        if 'first_name' in data:
            user.first_name = data['first_name']
        if 'last_name' in data:
            user.last_name = data['last_name']
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
            user.phone = data['phone']
        if 'role' in data:
            user.role = data['role']
        if 'is_active' in data:
            user.is_active = data['is_active']
        if 'password' in data and data['password']:
            user.set_password(data['password'])
        if 'pin' in data and data['pin']:
            user.set_pin(data['pin'])
        
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'User updated successfully',
            'data': user.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@users_bp.route('/<int:user_id>', methods=['DELETE'])
@jwt_required()
@require_supervisor
def delete_user(user_id):
    """Delete (deactivate) user"""
    try:
        user = User.query.get(user_id)
        if not user:
            return jsonify({
                'success': False,
                'message': 'User not found'
            }), 404
        
        # Soft delete - deactivate instead of removing
        user.is_active = False
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'User deactivated successfully'
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500
