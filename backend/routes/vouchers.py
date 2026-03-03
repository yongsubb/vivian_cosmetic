"""
Voucher routes
"""
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required

vouchers_bp = Blueprint('vouchers', __name__)

# Mock data for vouchers
# In a real app, this would be in the database
_vouchers = {
    'WELCOME10': {'type': 'percentage', 'value': 10, 'min_spend': 0, 'description': '10% off welcome bonus'},
    'SAVE50': {'type': 'fixed', 'value': 50, 'min_spend': 500, 'description': '₱50 off on orders over ₱500'},
    'VIP20': {'type': 'percentage', 'value': 20, 'min_spend': 1000, 'description': '20% off for VIPs'},
    'SUMMER': {'type': 'percentage', 'value': 15, 'min_spend': 0, 'description': 'Summer sale 15% off'},
}

@vouchers_bp.route('/validate', methods=['POST'])
@jwt_required()
def validate_voucher():
    """Validate a voucher code"""
    try:
        data = request.get_json()
        code = data.get('code')
        amount = data.get('amount', 0)
        
        if not code:
            return jsonify({'success': False, 'message': 'Code is required'}), 400
            
        voucher = _vouchers.get(code.upper())
        if not voucher:
            return jsonify({'success': False, 'message': 'Invalid voucher code'}), 404
            
        if amount < voucher['min_spend']:
            return jsonify({
                'success': False, 
                'message': f'Minimum spend of ₱{voucher["min_spend"]} required'
            }), 400
            
        discount = 0
        if voucher['type'] == 'percentage':
            discount = amount * (voucher['value'] / 100)
        else:
            discount = voucher['value']
            
        # Cap discount at amount
        if discount > amount:
            discount = amount
            
        return jsonify({
            'success': True,
            'data': {
                'code': code.upper(),
                'discount': float(discount),
                'type': voucher['type'],
                'value': voucher['value'],
                'description': voucher['description']
            }
        }), 200
        
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500

@vouchers_bp.route('/', methods=['GET'])
@jwt_required()
def get_vouchers():
    """Get all active vouchers"""
    try:
        return jsonify({
            'success': True,
            'data': [{'code': k, **v} for k, v in _vouchers.items()]
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500
