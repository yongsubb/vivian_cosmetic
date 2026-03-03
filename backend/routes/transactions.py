"""
Transactions routes - Sales transactions
"""
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity, get_jwt
from extensions import db
from sqlalchemy import or_, desc
from models.loyalty import LoyaltyMember, LoyaltyTransaction, LoyaltyTier, LoyaltySetting
from models.transaction import Transaction, TransactionItem
from models.product import Product
from models.customer import Customer
from models.refund_request import RefundRequest
from utils.activity_logger import log_activity

transactions_bp = Blueprint('transactions', __name__)


def _current_user_id_int():
    """JWT identity is stored as string(user.id); normalize to int for DB comparisons."""
    raw = get_jwt_identity()
    try:
        return int(raw)
    except Exception:
        return None


@transactions_bp.route('/', methods=['GET'])
@jwt_required()
def get_transactions():
    """Get transactions with optional filtering"""
    try:
        query = Transaction.query

        user_id = _current_user_id_int()

        # Non-privileged users can only view their own transactions.
        claims = get_jwt()
        role = (claims.get('role') or '').lower()
        is_privileged = role in {'supervisor', 'admin', 'superadmin'}
        if not is_privileged:
            if user_id is None:
                return jsonify({'success': False, 'message': 'Invalid user identity'}), 401
            query = query.filter(Transaction.user_id == user_id)
        
        # Filter by status
        status = request.args.get('status')

        # Filter by date range.
        # IMPORTANT: For refunded transactions, use the refund approval date (RefundRequest.approved_at)
        # so refunds approved today appear under Today/This Week/This Month even if the original sale
        # happened earlier.
        start_date_str = request.args.get('start_date')
        end_date_str = request.args.get('end_date')

        start_dt = None
        end_dt = None
        if start_date_str:
            start_dt = datetime.strptime(start_date_str, '%Y-%m-%d')
        if end_date_str:
            end_dt = datetime.strptime(end_date_str, '%Y-%m-%d')
            end_dt = end_dt.replace(hour=23, minute=59, second=59)

        use_refund_dates = (
            (status or '').lower().strip() == 'refunded'
            and (start_dt is not None or end_dt is not None)
        )

        if use_refund_dates:
            # If end_dt is not provided, default to end of today.
            if end_dt is None:
                end_dt = datetime.now().replace(hour=23, minute=59, second=59)

            query = query.join(
                RefundRequest,
                RefundRequest.transaction_id == Transaction.id,
            ).filter(
                RefundRequest.status == 'approved',
                RefundRequest.approved_at.isnot(None),
            )

            if start_dt is not None:
                query = query.filter(RefundRequest.approved_at >= start_dt)
            if end_dt is not None:
                query = query.filter(RefundRequest.approved_at <= end_dt)
        else:
            if start_dt is not None:
                query = query.filter(Transaction.created_at >= start_dt)
            if end_dt is not None:
                query = query.filter(Transaction.created_at <= end_dt)

        if status:
            query = query.filter(Transaction.status == status)
        
        # Filter by payment method
        payment_method = request.args.get('payment_method')
        if payment_method:
            query = query.filter_by(payment_method=payment_method)

        # Search (transaction code, customer name/phone, payment method, voucher)
        search = (request.args.get('search') or '').strip()
        if search:
            query = query.outerjoin(Customer)

            clauses = [
                Transaction.transaction_id.ilike(f'%{search}%'),
                Transaction.payment_method.ilike(f'%{search}%'),
                Transaction.voucher_code.ilike(f'%{search}%'),
                Customer.name.ilike(f'%{search}%'),
                Customer.phone.ilike(f'%{search}%'),
            ]

            # If the search looks like an internal numeric id, include it.
            try:
                search_id = int(search)
                clauses.append(Transaction.id == search_id)
            except Exception:
                pass

            query = query.filter(or_(*clauses))
        
        # Order by newest first
        if use_refund_dates:
            query = query.order_by(
                desc(RefundRequest.approved_at),
                desc(Transaction.created_at),
            ).distinct(Transaction.id)
        else:
            query = query.order_by(Transaction.created_at.desc())
        
        # Pagination
        page = request.args.get('page', 1, type=int)
        per_page = request.args.get('per_page', 50, type=int)
        
        pagination = query.paginate(page=page, per_page=per_page, error_out=False)
        
        return jsonify({
            'success': True,
            'data': [t.to_dict() for t in pagination.items],
            'pagination': {
                'page': page,
                'per_page': per_page,
                'total': pagination.total,
                'pages': pagination.pages
            }
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@transactions_bp.route('/<int:transaction_id>', methods=['GET'])
@jwt_required()
def get_transaction(transaction_id):
    """Get specific transaction"""
    try:
        transaction = Transaction.query.get(transaction_id)
        if not transaction:
            return jsonify({
                'success': False,
                'message': 'Transaction not found'
            }), 404

        # Non-privileged users can only view their own transactions.
        user_id = _current_user_id_int()
        claims = get_jwt()
        role = (claims.get('role') or '').lower()
        is_privileged = role in {'supervisor', 'admin', 'superadmin'}
        if not is_privileged:
            if user_id is None:
                return jsonify({'success': False, 'message': 'Invalid user identity'}), 401

            if transaction.user_id != user_id:
                return jsonify({
                    'success': False,
                    'message': 'Access denied'
                }), 403
        return jsonify({
            'success': True,
            'data': transaction.to_dict(include_items=True)
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@transactions_bp.route('/by-code/<string:transaction_code>', methods=['GET'])
@jwt_required()
def get_transaction_by_code(transaction_code):
    """Get specific transaction by its transaction_id code (e.g., TXN-20250101123000)."""
    try:
        transaction = Transaction.query.filter_by(
            transaction_id=transaction_code,
        ).first()
        if not transaction:
            return jsonify({
                'success': False,
                'message': 'Transaction not found'
            }), 404

        # Non-privileged users can only view their own transactions.
        user_id = _current_user_id_int()
        claims = get_jwt()
        role = (claims.get('role') or '').lower()
        is_privileged = role in {'supervisor', 'admin', 'superadmin'}
        if not is_privileged:
            if user_id is None:
                return jsonify({'success': False, 'message': 'Invalid user identity'}), 401

            if transaction.user_id != user_id:
                return jsonify({
                    'success': False,
                    'message': 'Access denied'
                }), 403
        return jsonify({
            'success': True,
            'data': transaction.to_dict(include_items=True)
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@transactions_bp.route('/', methods=['POST'])
@jwt_required()
def create_transaction():
    """Create new transaction (checkout)"""
    try:
        user_id = _current_user_id_int()
        if user_id is None:
            return jsonify({'success': False, 'message': 'Invalid user identity'}), 401
        data = request.get_json()
        
        # Validate items
        items = data.get('items', [])
        if not items:
            return jsonify({
                'success': False,
                'message': 'Transaction must have at least one item'
            }), 400
        
        # Generate transaction ID
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        transaction_id = f"TXN-{timestamp}"
        
        # Create transaction
        transaction = Transaction(
            transaction_id=transaction_id,
            user_id=user_id,
            customer_id=data.get('customer_id'),
            subtotal=data['subtotal'],
            discount_amount=data.get('discount_amount', 0),
            tax_amount=data.get('tax_amount', 0),
            total_amount=data['total_amount'],
            payment_method=data['payment_method'],
            amount_received=data['amount_received'],
            change_amount=data.get('change_amount', 0),
            voucher_code=data.get('voucher_code'),
            voucher_discount=data.get('voucher_discount', 0),
            notes=data.get('notes'),
            status='completed'
        )
        
        db.session.add(transaction)
        db.session.flush()  # Get transaction ID
        
        # Add transaction items and update stock
        for item in items:
            product = Product.query.get(item['product_id'])
            if not product:
                db.session.rollback()
                return jsonify({
                    'success': False,
                    'message': f'Product {item["product_id"]} not found'
                }), 400

            skip_stock = bool(item.get('skip_stock'))

            # Check stock (skip for redeemed reward items that already decremented stock at redeem time)
            if not skip_stock:
                if product.stock_quantity < item['quantity']:
                    db.session.rollback()
                    return jsonify({
                        'success': False,
                        'message': f'Insufficient stock for {product.name}'
                    }), 400
            
            # Create transaction item
            trans_item = TransactionItem(
                transaction_id=transaction.id,
                product_id=product.id,
                product_name=product.name,
                product_sku=product.sku,
                unit_price=item['unit_price'],
                quantity=item['quantity'],
                discount_percent=item.get('discount_percent', 0),
                subtotal=item['subtotal']
            )
            db.session.add(trans_item)

            # Update stock (skip for redeemed reward items)
            if not skip_stock:
                product.stock_quantity -= item['quantity']
        
        db.session.commit()

        # Loyalty: award points to member and auto-upgrade tier
        try:
            if transaction.customer_id:
                member = LoyaltyMember.query.filter_by(customer_id=transaction.customer_id).first()
                if member:
                    # Determine pesos-per-point from settings (default 10)
                    setting = LoyaltySetting.query.filter_by(setting_key='pesos_per_point').first()
                    try:
                        pesos_per_point = int(float(setting.get_value())) if setting else 10
                    except Exception:
                        pesos_per_point = 10

                    # Calculate points (use total_amount after discounts)
                    total = float(transaction.total_amount or 0)
                    points = int(total // float(pesos_per_point))

                    if points > 0:
                        member.current_points = (member.current_points or 0) + points
                        member.lifetime_points = (member.lifetime_points or 0) + points

                        # Recalculate tier based on lifetime_points thresholds
                        new_tier = LoyaltyTier.query.filter(
                            LoyaltyTier.is_active == True,
                            LoyaltyTier.min_points <= member.lifetime_points,
                        ).filter(
                            or_(
                                LoyaltyTier.max_points.is_(None),
                                LoyaltyTier.max_points >= member.lifetime_points,
                            )
                        ).order_by(LoyaltyTier.min_points.desc()).first()

                        if new_tier and member.tier_id != new_tier.id:
                            member.tier_id = new_tier.id

                        # Record loyalty transaction
                        lt = LoyaltyTransaction(
                            member_id=member.id,
                            transaction_id=transaction.id,
                            transaction_type='earn',
                            points=points,
                            balance_after=member.current_points,
                            description=f'Earned {points} points for purchase {transaction.transaction_id}',
                            reference_code=transaction.transaction_id,
                            adjusted_by=user_id,
                        )
                        db.session.add(lt)
                        db.session.commit()
        except Exception:
            # Best effort; do not fail entire checkout on loyalty errors
            db.session.rollback()

        # Audit log (best effort)
        try:
            log_activity(
                user_id=user_id,
                action=f'Completed sale {transaction.transaction_id}',
                entity_type='transaction',
                entity_id=transaction.id,
                details={'transaction_id': transaction.transaction_id, 'total': float(transaction.total_amount)},
            )
        except Exception:
            pass
        
        return jsonify({
            'success': True,
            'message': 'Transaction completed successfully',
            'data': transaction.to_dict(include_items=True)
        }), 201
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@transactions_bp.route('/<int:transaction_id>/void', methods=['POST'])
@jwt_required()
def void_transaction(transaction_id):
    """Void a transaction (supervisor only)"""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({
                'success': False,
                'message': 'Supervisor access required'
            }), 403
        
        transaction = Transaction.query.get(transaction_id)
        if not transaction:
            return jsonify({
                'success': False,
                'message': 'Transaction not found'
            }), 404
        
        if transaction.status == 'voided':
            return jsonify({
                'success': False,
                'message': 'Transaction is already voided'
            }), 400
        
        # Restore stock
        for item in transaction.items:
            product = Product.query.get(item.product_id)
            if product:
                product.stock_quantity += item.quantity
        
        transaction.status = 'voided'
        data = request.get_json() or {}
        transaction.notes = data.get('reason', 'Transaction voided')
        
        db.session.commit()

        # Audit log (best effort)
        try:
            void_user_id = get_jwt_identity()
            log_activity(
                user_id=void_user_id,
                action=f'Voided transaction {transaction.transaction_id}',
                entity_type='transaction',
                entity_id=transaction.id,
                details={'transaction_id': transaction.transaction_id, 'reason': transaction.notes},
            )
        except Exception:
            pass
        
        return jsonify({
            'success': True,
            'message': 'Transaction voided successfully'
        }), 200
        
    except Exception as e:
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500
