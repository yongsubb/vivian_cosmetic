"""
Customers routes
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from extensions import db
from models.customer import Customer

customers_bp = Blueprint('customers', __name__)


@customers_bp.route('/', methods=['GET'])
@jwt_required()
def get_customers():
    """Get all customers"""
    try:
        query = Customer.query.filter_by(is_active=True)
        
        # Search
        search = request.args.get('search')
        if search:
            query = query.filter(
                (Customer.name.ilike(f'%{search}%')) |
                (Customer.phone.ilike(f'%{search}%')) |
                (Customer.email.ilike(f'%{search}%'))
            )
        
        customers = query.all()
        return jsonify({
            'success': True,
            'data': [c.to_dict() for c in customers]
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@customers_bp.route('/<int:customer_id>', methods=['GET'])
@jwt_required()
def get_customer(customer_id):
    """Get specific customer"""
    try:
        customer = Customer.query.get(customer_id)
        if not customer:
            return jsonify({
                'success': False,
                'message': 'Customer not found'
            }), 404
        return jsonify({
            'success': True,
            'data': customer.to_dict()
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@customers_bp.route('/', methods=['POST'])
@jwt_required()
def create_customer():
    """Create new customer"""
    try:
        data = request.get_json()
        
        if not data.get('name'):
            return jsonify({
                'success': False,
                'message': 'Customer name is required'
            }), 400
        
        customer = Customer(
            name=data['name'],
            email=data.get('email'),
            phone=data.get('phone'),
            address=data.get('address')
        )
        
        db.session.add(customer)
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Customer created successfully',
            'data': customer.to_dict()
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@customers_bp.route('/<int:customer_id>', methods=['PUT'])
@jwt_required()
def update_customer(customer_id):
    """Update customer"""
    try:
        customer = Customer.query.get(customer_id)
        if not customer:
            return jsonify({
                'success': False,
                'message': 'Customer not found'
            }), 404
        
        data = request.get_json()
        
        if 'name' in data:
            customer.name = data['name']
        if 'email' in data:
            customer.email = data['email']
        if 'phone' in data:
            customer.phone = data['phone']
        if 'address' in data:
            customer.address = data['address']
        
        db.session.commit()
        
        return jsonify({
            'success': True,
            'message': 'Customer updated successfully',
            'data': customer.to_dict()
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500
