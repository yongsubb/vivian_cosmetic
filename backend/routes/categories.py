"""
Categories routes
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
from extensions import db
from models.product import Category
from utils.activity_logger import log_activity
from utils.rbac import require_supervisor

categories_bp = Blueprint('categories', __name__)


@categories_bp.route('/', methods=['GET'])
@jwt_required()
def get_categories():
    """Get all categories"""
    try:
        categories = Category.query.filter_by(is_active=True).all()
        return jsonify({
            'success': True,
            'data': [c.to_dict() for c in categories]
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@categories_bp.route('/<int:category_id>', methods=['GET'])
@jwt_required()
def get_category(category_id):
    """Get specific category"""
    try:
        category = Category.query.get(category_id)
        if not category:
            return jsonify({
                'success': False,
                'message': 'Category not found'
            }), 404
        return jsonify({
            'success': True,
            'data': category.to_dict()
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@categories_bp.route('/', methods=['POST'])
@jwt_required()
@require_supervisor
def create_category():
    """Create new category (supervisor only)"""
    try:
        data = request.get_json()
        
        name = (data.get('name') or '').strip() if isinstance(data, dict) else ''
        if not name:
            return jsonify({
                'success': False,
                'message': 'Category name is required'
            }), 400

        # If a category with this name already exists, avoid a 500 from UNIQUE constraint.
        # If it exists but is inactive, we reactivate it.
        existing = Category.query.filter_by(name=name).first()
        if existing and existing.is_active:
            return jsonify({
                'success': False,
                'message': 'Category name already exists'
            }), 409
        if existing and not existing.is_active:
            existing.description = data.get('description')
            existing.icon = data.get('icon')
            existing.color = data.get('color')
            existing.is_active = True
            db.session.commit()

            # Audit log (best effort)
            try:
                log_activity(
                    user_id=get_jwt_identity(),
                    action='Reactivated category',
                    entity_type='category',
                    entity_id=existing.id,
                    details={'category_id': existing.id, 'name': existing.name},
                )
            except Exception:
                pass

            return jsonify({
                'success': True,
                'message': 'Category reactivated successfully',
                'data': existing.to_dict()
            }), 200
        
        category = Category(
            name=name,
            description=data.get('description'),
            icon=data.get('icon'),
            color=data.get('color')
        )
        
        db.session.add(category)
        db.session.commit()

        # Audit log (best effort)
        try:
            log_activity(
                user_id=get_jwt_identity(),
                action='Created category',
                entity_type='category',
                entity_id=category.id,
                details={'category_id': category.id, 'name': category.name},
            )
        except Exception:
            pass
        
        return jsonify({
            'success': True,
            'message': 'Category created successfully',
            'data': category.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@categories_bp.route('/<int:category_id>', methods=['PUT'])
@jwt_required()
@require_supervisor
def update_category(category_id):
    """Update category (supervisor only)"""
    try:
        category = Category.query.get(category_id)
        if not category:
            return jsonify({
                'success': False,
                'message': 'Category not found'
            }), 404
        
        data = request.get_json()
        
        if 'name' in data:
            category.name = data['name']
        if 'description' in data:
            category.description = data['description']
        if 'icon' in data:
            category.icon = data['icon']
        if 'color' in data:
            category.color = data['color']
        if 'is_active' in data:
            category.is_active = data['is_active']
        
        db.session.commit()

        # Audit log (best effort)
        try:
            log_activity(
                user_id=get_jwt_identity(),
                action='Updated category',
                entity_type='category',
                entity_id=category.id,
                details={'category_id': category.id, 'name': category.name},
            )
        except Exception:
            pass
        
        return jsonify({
            'success': True,
            'message': 'Category updated successfully',
            'data': category.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@categories_bp.route('/<int:category_id>', methods=['DELETE'])
@jwt_required()
@require_supervisor
def delete_category(category_id):
    """Remove (soft delete) a category (supervisor only)."""
    try:
        category = Category.query.get(category_id)
        if not category:
            return jsonify({
                'success': False,
                'message': 'Category not found'
            }), 404

        # Idempotent: deleting an inactive category is a no-op.
        if not category.is_active:
            return jsonify({
                'success': True,
                'message': 'Category removed successfully',
                'data': category.to_dict(),
            }), 200

        product_count = category.products.count() if category.products is not None else 0
        if product_count > 0:
            return jsonify({
                'success': False,
                'message': 'Cannot remove category with existing products',
                'data': {
                    'category_id': category.id,
                    'product_count': product_count,
                },
            }), 409

        category.is_active = False
        db.session.commit()

        # Audit log (best effort)
        try:
            log_activity(
                user_id=get_jwt_identity(),
                action='Removed category',
                entity_type='category',
                entity_id=category.id,
                details={'category_id': category.id, 'name': category.name},
            )
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': 'Category removed successfully',
            'data': category.to_dict()
        }), 200

    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500
