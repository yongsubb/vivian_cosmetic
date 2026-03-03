"""
Promotion routes for creating, managing, and viewing loyalty promotions.
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from extensions import db
from models.promotion import Promotion
from utils.rbac import require_admin
from datetime import datetime

promotions_bp = Blueprint('promotions', __name__)

# [GET] /api/promotions - Get all active promotions (for members)
@promotions_bp.route('', methods=['GET'])
@jwt_required()
def get_active_promotions():
    """Returns all active promotions."""
    try:
        promos = Promotion.query.filter_by(is_active=True).order_by(Promotion.created_at.desc()).all()
        return jsonify({
            'success': True,
            'data': [p.to_dict() for p in promos]
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

# [GET] /api/promotions/all - Get all promotions (for admin)
@promotions_bp.route('/all', methods=['GET'])
@jwt_required()
@require_admin
def get_all_promotions():
    """Returns all promotions, active or inactive."""
    try:
        promos = Promotion.query.order_by(Promotion.created_at.desc()).all()
        return jsonify({
            'success': True,
            'data': [p.to_dict() for p in promos]
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500

# [POST] /api/promotions - Create a new promotion
@promotions_bp.route('', methods=['POST'])
@jwt_required()
@require_admin
def create_promotion():
    """Creates a new promotion."""
    try:
        data = request.get_json()
        if not data or not data.get('title'):
            return jsonify({'success': False, 'message': 'Title is required.'}), 400

        new_promo = Promotion(
            title=data['title'],
            description=data.get('description'),
            image_url=data.get('image_url'),
            start_date=datetime.fromisoformat(data['start_date']) if data.get('start_date') else None,
            end_date=datetime.fromisoformat(data['end_date']) if data.get('end_date') else None,
            is_active=data.get('is_active', False)
        )
        db.session.add(new_promo)
        db.session.commit()
        return jsonify({
            'success': True,
            'message': 'Promotion created successfully.',
            'data': new_promo.to_dict()
        }), 201
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500

# [PUT] /api/promotions/<int:promo_id> - Update a promotion
@promotions_bp.route('/<int:promo_id>', methods=['PUT'])
@jwt_required()
@require_admin
def update_promotion(promo_id):
    """Updates an existing promotion."""
    try:
        promo = Promotion.query.get_or_404(promo_id)
        data = request.get_json()

        promo.title = data.get('title', promo.title)
        promo.description = data.get('description', promo.description)
        promo.image_url = data.get('image_url', promo.image_url)
        promo.start_date = datetime.fromisoformat(data['start_date']) if data.get('start_date') else promo.start_date
        promo.end_date = datetime.fromisoformat(data['end_date']) if data.get('end_date') else promo.end_date
        promo.is_active = data.get('is_active', promo.is_active)
        
        db.session.commit()
        return jsonify({
            'success': True,
            'message': 'Promotion updated successfully.',
            'data': promo.to_dict()
        }), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500

# [DELETE] /api/promotions/<int:promo_id> - Delete a promotion
@promotions_bp.route('/<int:promo_id>', methods=['DELETE'])
@jwt_required()
@require_admin
def delete_promotion(promo_id):
    """Deletes a promotion."""
    try:
        promo = Promotion.query.get_or_404(promo_id)
        db.session.delete(promo)
        db.session.commit()
        return jsonify({
            'success': True,
            'message': 'Promotion deleted successfully.'
        }), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500
