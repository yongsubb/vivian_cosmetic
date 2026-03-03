"""
Reports routes - Sales analytics and reports
"""
from datetime import datetime, timedelta
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required
from sqlalchemy import func, desc
from extensions import db
from models.transaction import Transaction, TransactionItem
from models.product import Product, Category
from models.refund_request import RefundRequest
from utils.rbac import require_supervisor

reports_bp = Blueprint('reports', __name__)


@reports_bp.route('/daily', methods=['GET'])
@jwt_required()
@require_supervisor
def get_daily_report():
    """Get daily sales report"""
    try:
        date_str = request.args.get('date')
        if date_str:
            report_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        else:
            # Use local time instead of UTC
            report_date = datetime.now().date()
        
        # Get transactions for the day
        transactions = Transaction.query.filter(
            func.date(Transaction.created_at) == report_date,
            Transaction.status == 'completed'
        ).all()
        
        # Calculate totals
        total_sales = sum(float(t.total_amount) for t in transactions)
        total_transactions = len(transactions)
        total_items = sum(t.item_count for t in transactions)
        average_sale = total_sales / total_transactions if total_transactions > 0 else 0

        # Refunded products (based on refund approval date)
        refunded_products = (
            db.session.query(func.coalesce(func.sum(TransactionItem.quantity), 0))
            .join(Transaction, Transaction.id == TransactionItem.transaction_id)
            .join(RefundRequest, RefundRequest.transaction_id == Transaction.id)
            .filter(
                RefundRequest.status == 'approved',
                RefundRequest.approved_at.isnot(None),
                func.date(RefundRequest.approved_at) == report_date,
                Transaction.status == 'refunded',
            )
            .scalar()
        )
        try:
            refunded_products = int(refunded_products or 0)
        except Exception:
            refunded_products = 0
        
        # Payment method breakdown
        payment_breakdown = {}
        for t in transactions:
            method = t.payment_method
            if method not in payment_breakdown:
                payment_breakdown[method] = {'count': 0, 'total': 0}
            payment_breakdown[method]['count'] += 1
            payment_breakdown[method]['total'] += float(t.total_amount)
        
        # Calculate trend percentage (compare with previous day)
        previous_date = report_date - timedelta(days=1)
        previous_transactions = Transaction.query.filter(
            func.date(Transaction.created_at) == previous_date,
            Transaction.status == 'completed'
        ).all()
        previous_sales = sum(float(t.total_amount) for t in previous_transactions)
        
        if previous_sales > 0:
            trend_percentage = ((total_sales - previous_sales) / previous_sales) * 100
        elif total_sales > 0:
            trend_percentage = 100.0  # 100% increase from 0
        else:
            trend_percentage = 0.0
        
        # Create hourly breakdown for the single day
        hourly_breakdown = {}
        for hour in range(24):
            hourly_breakdown[str(hour)] = {'sales': 0, 'transactions': 0}
        
        # Fill in actual hourly sales data
        for t in transactions:
            hour = t.created_at.hour
            hourly_breakdown[str(hour)]['sales'] += float(t.total_amount)
            hourly_breakdown[str(hour)]['transactions'] += 1
        
        return jsonify({
            'success': True,
            'data': {
                'date': report_date.isoformat(),
                'total_sales': total_sales,
                'total_transactions': total_transactions,
                'total_items_sold': total_items,
                'refunded_products': refunded_products,
                'average_sale': average_sale,
                'trend_percentage': round(trend_percentage, 1),
                'hourly_breakdown': hourly_breakdown,
                'payment_breakdown': payment_breakdown,
                'transactions': [t.to_dict(include_items=False) for t in transactions]
            }
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@reports_bp.route('/weekly', methods=['GET'])
@jwt_required()
@require_supervisor
def get_weekly_report():
    """Get weekly sales report"""
    try:
        date_str = request.args.get('date')
        if date_str:
            end_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        else:
            end_date = datetime.now().date()
        
        start_date = end_date - timedelta(days=6)
        
        # Get transactions for the week
        transactions = Transaction.query.filter(
            func.date(Transaction.created_at) >= start_date,
            func.date(Transaction.created_at) <= end_date,
            Transaction.status == 'completed'
        ).all()
        
        # Daily breakdown
        daily_breakdown = {}
        for i in range(7):
            day = start_date + timedelta(days=i)
            daily_breakdown[day.isoformat()] = {'sales': 0, 'transactions': 0}
        
        for t in transactions:
            day = t.created_at.date().isoformat()
            if day in daily_breakdown:
                daily_breakdown[day]['sales'] += float(t.total_amount)
                daily_breakdown[day]['transactions'] += 1
        
        total_sales = sum(float(t.total_amount) for t in transactions)
        total_transactions = len(transactions)
        total_items = sum(t.item_count for t in transactions)
        average_sale = total_sales / total_transactions if total_transactions > 0 else 0

        # Refunded products (based on refund approval date, inclusive range)
        refunded_products = (
            db.session.query(func.coalesce(func.sum(TransactionItem.quantity), 0))
            .join(Transaction, Transaction.id == TransactionItem.transaction_id)
            .join(RefundRequest, RefundRequest.transaction_id == Transaction.id)
            .filter(
                RefundRequest.status == 'approved',
                RefundRequest.approved_at.isnot(None),
                func.date(RefundRequest.approved_at) >= start_date,
                func.date(RefundRequest.approved_at) <= end_date,
                Transaction.status == 'refunded',
            )
            .scalar()
        )
        try:
            refunded_products = int(refunded_products or 0)
        except Exception:
            refunded_products = 0
        
        # Calculate trend percentage (compare with previous week)
        previous_end_date = start_date - timedelta(days=1)
        previous_start_date = previous_end_date - timedelta(days=6)
        previous_transactions = Transaction.query.filter(
            func.date(Transaction.created_at) >= previous_start_date,
            func.date(Transaction.created_at) <= previous_end_date,
            Transaction.status == 'completed'
        ).all()
        previous_sales = sum(float(t.total_amount) for t in previous_transactions)
        
        if previous_sales > 0:
            trend_percentage = ((total_sales - previous_sales) / previous_sales) * 100
        elif total_sales > 0:
            trend_percentage = 100.0
        else:
            trend_percentage = 0.0
        
        return jsonify({
            'success': True,
            'data': {
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'total_sales': total_sales,
                'total_transactions': total_transactions,
                'total_items_sold': total_items,
                'refunded_products': refunded_products,
                'refunded_items': refunded_products,
                'average_sale': average_sale,
                'trend_percentage': round(trend_percentage, 1),
                'daily_breakdown': daily_breakdown
            }
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@reports_bp.route('/monthly', methods=['GET'])
@jwt_required()
@require_supervisor
def get_monthly_report():
    """Get monthly sales report"""
    try:
        year = request.args.get('year', datetime.now().year, type=int)
        month = request.args.get('month', datetime.now().month, type=int)

        start_date = datetime(year, month, 1).date()
        if month == 12:
            end_date = (datetime(year + 1, 1, 1) - timedelta(days=1)).date()
        else:
            end_date = (datetime(year, month + 1, 1) - timedelta(days=1)).date()
        
        # Get transactions for the month
        transactions = Transaction.query.filter(
            func.year(Transaction.created_at) == year,
            func.month(Transaction.created_at) == month,
            Transaction.status == 'completed'
        ).all()
        
        total_sales = sum(float(t.total_amount) for t in transactions)
        total_transactions = len(transactions)
        total_items = sum(t.item_count for t in transactions)
        average_sale = total_sales / total_transactions if total_transactions > 0 else 0

        # Refunded products (based on refund approval date)
        refunded_products = (
            db.session.query(func.coalesce(func.sum(TransactionItem.quantity), 0))
            .join(Transaction, Transaction.id == TransactionItem.transaction_id)
            .join(RefundRequest, RefundRequest.transaction_id == Transaction.id)
            .filter(
                RefundRequest.status == 'approved',
                RefundRequest.approved_at.isnot(None),
                func.date(RefundRequest.approved_at) >= start_date,
                func.date(RefundRequest.approved_at) <= end_date,
                Transaction.status == 'refunded',
            )
            .scalar()
        )
        try:
            refunded_products = int(refunded_products or 0)
        except Exception:
            refunded_products = 0
        
        # Create daily breakdown for each day of the month
        from calendar import monthrange
        days_in_month = monthrange(year, month)[1]
        daily_breakdown = {}
        
        for day in range(1, days_in_month + 1):
            date_obj = datetime(year, month, day).date()
            daily_breakdown[date_obj.isoformat()] = {'sales': 0, 'transactions': 0}
        
        # Fill in actual sales data
        for t in transactions:
            day_key = t.created_at.date().isoformat()
            if day_key in daily_breakdown:
                daily_breakdown[day_key]['sales'] += float(t.total_amount)
                daily_breakdown[day_key]['transactions'] += 1
        
        # Calculate trend percentage (compare with previous month)
        if month == 1:
            previous_year = year - 1
            previous_month = 12
        else:
            previous_year = year
            previous_month = month - 1
        
        previous_transactions = Transaction.query.filter(
            func.year(Transaction.created_at) == previous_year,
            func.month(Transaction.created_at) == previous_month,
            Transaction.status == 'completed'
        ).all()
        previous_sales = sum(float(t.total_amount) for t in previous_transactions)
        
        if previous_sales > 0:
            trend_percentage = ((total_sales - previous_sales) / previous_sales) * 100
        elif total_sales > 0:
            trend_percentage = 100.0
        else:
            trend_percentage = 0.0
        
        return jsonify({
            'success': True,
            'data': {
                'year': year,
                'month': month,
                'total_sales': total_sales,
                'total_transactions': total_transactions,
                'total_items_sold': total_items,
                'refunded_products': refunded_products,
                'refunded_items': refunded_products,
                'average_sale': average_sale,
                'trend_percentage': round(trend_percentage, 1),
                'daily_breakdown': daily_breakdown
            }
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@reports_bp.route('/yearly', methods=['GET'])
@jwt_required()
@require_supervisor
def get_yearly_report():
    """Get yearly sales report"""
    try:
        year = request.args.get('year', datetime.now().year, type=int)

        start_date = datetime(year, 1, 1).date()
        end_date = datetime(year, 12, 31).date()
        
        # Get transactions for the year
        transactions = Transaction.query.filter(
            func.year(Transaction.created_at) == year,
            Transaction.status == 'completed'
        ).all()
        
        total_sales = sum(float(t.total_amount) for t in transactions)
        total_transactions = len(transactions)
        total_items = sum(t.item_count for t in transactions)
        average_sale = total_sales / total_transactions if total_transactions > 0 else 0

        # Refunded products (based on refund approval date)
        refunded_products = (
            db.session.query(func.coalesce(func.sum(TransactionItem.quantity), 0))
            .join(Transaction, Transaction.id == TransactionItem.transaction_id)
            .join(RefundRequest, RefundRequest.transaction_id == Transaction.id)
            .filter(
                RefundRequest.status == 'approved',
                RefundRequest.approved_at.isnot(None),
                func.date(RefundRequest.approved_at) >= start_date,
                func.date(RefundRequest.approved_at) <= end_date,
                Transaction.status == 'refunded',
            )
            .scalar()
        )
        try:
            refunded_products = int(refunded_products or 0)
        except Exception:
            refunded_products = 0
        
        # Create monthly breakdown for each month of the year
        monthly_breakdown = {}
        for month_num in range(1, 13):
            month_key = f'{year}-{month_num:02d}'
            monthly_breakdown[month_key] = {'sales': 0, 'transactions': 0}
        
        # Fill in actual monthly sales data
        for t in transactions:
            month_key = t.created_at.strftime('%Y-%m')
            if month_key in monthly_breakdown:
                monthly_breakdown[month_key]['sales'] += float(t.total_amount)
                monthly_breakdown[month_key]['transactions'] += 1
        
        # Calculate trend percentage (compare with previous year)
        previous_year = year - 1
        previous_transactions = Transaction.query.filter(
            func.year(Transaction.created_at) == previous_year,
            Transaction.status == 'completed'
        ).all()
        previous_sales = sum(float(t.total_amount) for t in previous_transactions)
        
        if previous_sales > 0:
            trend_percentage = ((total_sales - previous_sales) / previous_sales) * 100
        elif total_sales > 0:
            trend_percentage = 100.0
        else:
            trend_percentage = 0.0
        
        return jsonify({
            'success': True,
            'data': {
                'year': year,
                'total_sales': total_sales,
                'total_transactions': total_transactions,
                'total_items_sold': total_items,
                'refunded_products': refunded_products,
                'refunded_items': refunded_products,
                'average_sale': average_sale,
                'trend_percentage': round(trend_percentage, 1),
                'monthly_breakdown': monthly_breakdown
            }
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@reports_bp.route('/top-products', methods=['GET'])
@jwt_required()
@require_supervisor
def get_top_products():
    """Get top selling products"""
    try:
        limit = request.args.get('limit', 10, type=int)

        # Optional timeframe filter (kept consistent with /category-breakdown)
        timeframe = request.args.get('timeframe', None, type=str)
        timeframe = (timeframe or '').lower().strip()

        now = datetime.now()
        year = request.args.get('year', now.year, type=int)
        month = request.args.get('month', now.month, type=int)
        date_str = request.args.get('date', None, type=str)

        start_dt = None
        end_dt = None

        if timeframe in ('', 'all'):
            start_dt = None
            end_dt = None
        elif timeframe == 'day':
            if date_str:
                try:
                    d = datetime.strptime(date_str, '%Y-%m-%d')
                except Exception:
                    return jsonify(
                        {
                            'success': False,
                            'message': 'Invalid date format. Use YYYY-MM-DD.',
                        }
                    ), 400
            else:
                d = now

            start_dt = datetime(d.year, d.month, d.day, 0, 0, 0)
            end_dt = start_dt + timedelta(days=1)
        elif timeframe == 'week':
            if date_str:
                try:
                    d = datetime.strptime(date_str, '%Y-%m-%d')
                except Exception:
                    return jsonify(
                        {
                            'success': False,
                            'message': 'Invalid date format. Use YYYY-MM-DD.',
                        }
                    ), 400
            else:
                d = now

            week_start = datetime(d.year, d.month, d.day, 0, 0, 0) - timedelta(
                days=d.weekday()
            )
            start_dt = week_start
            end_dt = start_dt + timedelta(days=7)
        elif timeframe == 'year':
            start_dt = datetime(year, 1, 1, 0, 0, 0)
            end_dt = datetime(year + 1, 1, 1, 0, 0, 0)
        else:
            # Default: month
            start_dt = datetime(year, month, 1, 0, 0, 0)
            if month == 12:
                end_dt = datetime(year + 1, 1, 1, 0, 0, 0)
            else:
                end_dt = datetime(year, month + 1, 1, 0, 0, 0)

        # Query top products by revenue (still includes quantity)
        query = (
            db.session.query(
                TransactionItem.product_id,
                TransactionItem.product_name,
                func.sum(TransactionItem.quantity).label('total_quantity'),
                func.sum(TransactionItem.subtotal).label('total_sales'),
            )
            .join(Transaction)
            .filter(Transaction.status == 'completed')
        )

        if start_dt is not None and end_dt is not None:
            query = query.filter(
                Transaction.created_at >= start_dt,
                Transaction.created_at < end_dt,
            )

        top_products = (
            query.group_by(
                TransactionItem.product_id,
                TransactionItem.product_name,
            )
            .order_by(desc('total_sales'))
            .limit(limit)
            .all()
        )
        
        return jsonify({
            'success': True,
            'data': [{
                'product_id': p.product_id,
                'product_name': p.product_name,
                'total_quantity': int(p.total_quantity or 0),
                'total_sales': float(p.total_sales or 0.0),
                # Aliases for frontend compatibility (some views expect these)
                'quantity_sold': int(p.total_quantity or 0),
                'total_revenue': float(p.total_sales or 0.0),
            } for p in top_products]
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@reports_bp.route('/low-stock', methods=['GET'])
@jwt_required()
@require_supervisor
def get_low_stock():
    """Get low stock products"""
    try:
        # Import here to avoid circular imports
        from routes.settings import get_setting_value
        
        # Get threshold from DB-backed settings
        threshold = get_setting_value('low_stock_threshold', 10)
        
        products = Product.query.filter(
            Product.is_active == True,
            Product.stock_quantity <= threshold
        ).all()
        
        return jsonify({
            'success': True,
            'data': [p.to_dict() for p in products]
        }), 200
    except Exception as e:
        return jsonify({
            'success': False,
            'message': str(e)
        }), 500


@reports_bp.route('/category-breakdown', methods=['GET'])
@jwt_required()
@require_supervisor
def get_category_breakdown():
    """Get sales by category for day/week/month/year (used for dashboard analytics)."""
    try:
        timeframe = request.args.get('timeframe', 'month', type=str)
        timeframe = (timeframe or 'month').lower().strip()

        now = datetime.now()
        year = request.args.get('year', now.year, type=int)
        month = request.args.get('month', now.month, type=int)
        date_str = request.args.get('date', None, type=str)

        # Build date filters
        start_dt = None
        end_dt = None

        if timeframe == 'day':
            # Use explicit date if provided, else today.
            if date_str:
                try:
                    d = datetime.strptime(date_str, '%Y-%m-%d')
                except Exception:
                    return jsonify({'success': False, 'message': 'Invalid date format. Use YYYY-MM-DD.'}), 400
            else:
                d = now

            start_dt = datetime(d.year, d.month, d.day, 0, 0, 0)
            end_dt = start_dt + timedelta(days=1)
            year = d.year
            month = d.month
        elif timeframe == 'week':
            # Monday-based week (Mon..Sun). Anchor using explicit date if provided, else today.
            if date_str:
                try:
                    d = datetime.strptime(date_str, '%Y-%m-%d')
                except Exception:
                    return jsonify({'success': False, 'message': 'Invalid date format. Use YYYY-MM-DD.'}), 400
            else:
                d = now

            # datetime.weekday(): Monday=0..Sunday=6
            week_start = datetime(d.year, d.month, d.day, 0, 0, 0) - timedelta(days=d.weekday())
            start_dt = week_start
            end_dt = start_dt + timedelta(days=7)
            year = start_dt.year
            month = start_dt.month
            date_str = date_str or week_start.strftime('%Y-%m-%d')
        elif timeframe == 'year':
            # Whole year
            start_dt = datetime(year, 1, 1, 0, 0, 0)
            end_dt = datetime(year + 1, 1, 1, 0, 0, 0)
        else:
            # Default: month
            start_dt = datetime(year, month, 1, 0, 0, 0)
            # Next month boundary
            if month == 12:
                end_dt = datetime(year + 1, 1, 1, 0, 0, 0)
            else:
                end_dt = datetime(year, month + 1, 1, 0, 0, 0)

        rows = (
            db.session.query(
                func.coalesce(Category.name, 'Other').label('category'),
                func.sum(TransactionItem.subtotal).label('total_sales'),
            )
            .join(Transaction, TransactionItem.transaction_id == Transaction.id)
            .outerjoin(Product, TransactionItem.product_id == Product.id)
            .outerjoin(Category, Product.category_id == Category.id)
            .filter(
                Transaction.status == 'completed',
                Transaction.created_at >= start_dt,
                Transaction.created_at < end_dt,
            )
            .group_by('category')
            .order_by(desc('total_sales'))
            .all()
        )

        data = [
            {
                'category': r.category,
                'total_sales': float(r.total_sales) if r.total_sales else 0.0,
            }
            for r in rows
        ]

        return jsonify(
            {
                'success': True,
                'data': {
                    'timeframe': timeframe,
                    'year': year,
                    'month': month,
                    'date': date_str,
                    'categories': data,
                },
            }
        ), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500
