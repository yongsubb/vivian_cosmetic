"""Refund routes - Refund request + approval workflow.

Workflow:
- Cashier: creates a refund request (pending).
- Supervisor: approves/rejects requests.
- Supervisor can also perform an instant refund (recorded as an approved request).

Refund processing:
- Restore product stock for all items in the transaction.
- Reverse loyalty points that were earned for the transaction (if any).
"""

from __future__ import annotations

from datetime import datetime

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, get_jwt_identity, jwt_required
from sqlalchemy import func

from extensions import db
from models.loyalty import LoyaltyMember, LoyaltyTier, LoyaltyTransaction
from models.product import Product
from models.refund_request import RefundRequest
from models.transaction import Transaction
from utils.activity_logger import log_activity
from utils.rbac import require_admin


refunds_bp = Blueprint('refunds', __name__)


def _current_user_id_int():
    raw = get_jwt_identity()
    try:
        return int(raw)
    except Exception:
        return None


def _is_privileged_role() -> bool:
    claims = get_jwt() or {}
    role = (claims.get('role') or '').lower()
    return role in {'supervisor', 'admin', 'superadmin'}


def _append_transaction_note(transaction: Transaction, note: str | None):
    note = (note or '').strip()
    if not note:
        return
    existing = (transaction.notes or '').strip()
    if not existing:
        transaction.notes = note
        return
    transaction.notes = f"{existing}\n{note}"


def _recalculate_member_tier(member: LoyaltyMember):
    # Same logic pattern as checkout.
    new_tier = (
        LoyaltyTier.query.filter(
            LoyaltyTier.is_active == True,  # noqa: E712
            LoyaltyTier.min_points <= (member.lifetime_points or 0),
        )
        .filter(
            (LoyaltyTier.max_points.is_(None))
            | (LoyaltyTier.max_points >= (member.lifetime_points or 0))
        )
        .order_by(LoyaltyTier.min_points.desc())
        .first()
    )
    if new_tier and member.tier_id != new_tier.id:
        member.tier_id = new_tier.id


def _reverse_loyalty_points_for_transaction(
    *,
    transaction: Transaction,
    actor_user_id: int | None,
):
    if not transaction.customer_id:
        return

    member = LoyaltyMember.query.filter_by(customer_id=transaction.customer_id).first()
    if not member:
        return

    # Find the original earn record for this sale.
    earn = LoyaltyTransaction.query.filter_by(
        member_id=member.id,
        transaction_id=transaction.id,
        transaction_type='earn',
    ).order_by(LoyaltyTransaction.id.desc()).first()

    if not earn:
        return

    points = int(earn.points or 0)
    if points <= 0:
        return

    # Idempotency guard: don't reverse twice.
    existing_refund = LoyaltyTransaction.query.filter_by(
        member_id=member.id,
        transaction_id=transaction.id,
        transaction_type='refund',
    ).first()
    if existing_refund:
        return

    member.current_points = max(0, int(member.current_points or 0) - points)
    member.lifetime_points = max(0, int(member.lifetime_points or 0) - points)

    _recalculate_member_tier(member)

    lt = LoyaltyTransaction(
        member_id=member.id,
        transaction_id=transaction.id,
        transaction_type='refund',
        points=-points,
        balance_after=member.current_points,
        description=f'Refund reversal: -{points} points for {transaction.transaction_id}',
        reference_code=transaction.transaction_id,
        adjusted_by=actor_user_id,
    )
    db.session.add(lt)


def _restore_redeemed_reward_points_for_transaction(
    *,
    transaction: Transaction,
    actor_user_id: int | None,
    member_card_hint: str | None = None,
):
    """Restore points spent on redeemed reward products.

    Redeemed reward items are represented in checkout as ₱0 line items.
    We infer them by:
    - product.points_cost > 0
    - unit_price <= 0 and line subtotal <= 0

    This keeps behavior compatible with the existing DB schema (no extra flags).
    """

    member = None
    if transaction.customer_id:
        member = LoyaltyMember.query.filter_by(customer_id=transaction.customer_id).first()
    elif member_card_hint:
        hint = (member_card_hint or '').strip()
        if hint:
            member = LoyaltyMember.query.filter_by(card_barcode=hint).first()
            if not member:
                member = LoyaltyMember.query.filter_by(member_number=hint).first()
    if not member:
        return

    # Idempotency: don't restore twice.
    existing_restore = LoyaltyTransaction.query.filter_by(
        member_id=member.id,
        transaction_id=transaction.id,
        transaction_type='refund_redeem_product',
    ).first()
    if existing_restore:
        return

    points_to_restore = 0
    restored_lines = 0
    for item in (transaction.items or []):
        try:
            unit_price = float(item.unit_price or 0)
            line_total = float(item.subtotal or 0)
        except Exception:
            unit_price = 0.0
            line_total = 0.0

        if unit_price > 0 or line_total > 0:
            continue

        product = Product.query.get(item.product_id)
        if not product:
            continue

        points_cost = int(getattr(product, 'points_cost', 0) or 0)
        if points_cost <= 0:
            continue

        qty = int(item.quantity or 0)
        if qty <= 0:
            continue

        points_to_restore += points_cost * qty
        restored_lines += 1

    if points_to_restore <= 0:
        return

    member.current_points = int(member.current_points or 0) + int(points_to_restore)

    # Sync with customer (best effort)
    if member.customer:
        try:
            member.customer.loyalty_points = member.current_points
        except Exception:
            pass

    db.session.add(
        LoyaltyTransaction(
            member_id=member.id,
            transaction_id=transaction.id,
            transaction_type='refund_redeem_product',
            points=int(points_to_restore),
            balance_after=member.current_points,
            description=(
                f'Refund restore: +{points_to_restore} points (redeemed rewards) '
                f'for {transaction.transaction_id} ({restored_lines} line(s))'
            ),
            reference_code=transaction.transaction_id,
            adjusted_by=actor_user_id,
        )
    )


def _process_refund(
    *,
    transaction: Transaction,
    actor_user_id: int | None,
    reason: str | None,
    member_card_hint: str | None = None,
):
    if transaction.status == 'refunded':
        raise ValueError('Transaction is already refunded')
    if transaction.status == 'voided':
        raise ValueError('Voided transactions cannot be refunded')
    if transaction.status != 'completed':
        raise ValueError('Only completed transactions can be refunded')

    # Restore stock
    for item in transaction.items:
        product = Product.query.get(item.product_id)
        if product:
            product.stock_quantity += int(item.quantity or 0)

    # Reverse loyalty points (best effort)
    _reverse_loyalty_points_for_transaction(
        transaction=transaction,
        actor_user_id=actor_user_id,
    )

    # Restore points spent on redeemed reward items (best effort)
    _restore_redeemed_reward_points_for_transaction(
        transaction=transaction,
        actor_user_id=actor_user_id,
        member_card_hint=member_card_hint,
    )

    transaction.status = 'refunded'
    _append_transaction_note(transaction, reason)


@refunds_bp.route('/transactions/<int:transaction_id>', methods=['POST'])
@jwt_required()
def request_or_refund_transaction(transaction_id: int):
    """Create a refund request (cashier) or instantly refund (supervisor)."""
    try:
        user_id = _current_user_id_int()
        if user_id is None:
            return jsonify({'success': False, 'message': 'Invalid user identity'}), 401

        transaction = Transaction.query.get(transaction_id)
        if not transaction:
            return jsonify({'success': False, 'message': 'Transaction not found'}), 404

        data = request.get_json() or {}
        reason = (data.get('reason') or '').strip() or None
        member_card_hint = (
            (data.get('member_card') or data.get('member_card_barcode') or data.get('member_number') or '')
        ).strip() or None

        if member_card_hint:
            # Persist the hint for later approvals (without schema changes).
            # This also keeps the reason human-readable for supervisors.
            hint_line = f"Member card: {member_card_hint}"
            reason = f"{reason}\n{hint_line}" if reason else hint_line

        # Prevent duplicate pending requests.
        pending = RefundRequest.query.filter_by(
            transaction_id=transaction.id,
            status='pending',
        ).first()
        if pending and not _is_privileged_role():
            return jsonify({
                'success': False,
                'message': 'Refund request is already pending approval',
                'data': pending.to_dict(include_transaction=True),
            }), 400

        if _is_privileged_role():
            # Instant refund
            rr = RefundRequest(
                transaction_id=transaction.id,
                requested_by=user_id,
                status='approved',
                reason=reason,
                approved_by=user_id,
                approved_at=datetime.now(),
            )
            db.session.add(rr)

            _process_refund(
                transaction=transaction,
                actor_user_id=user_id,
                reason=reason,
                member_card_hint=member_card_hint,
            )

            db.session.commit()

            try:
                log_activity(
                    user_id=user_id,
                    action=f'Refunded transaction {transaction.transaction_id}',
                    entity_type='transaction',
                    entity_id=transaction.id,
                    details={'transaction_id': transaction.transaction_id, 'refund_request_id': rr.id},
                )
            except Exception:
                pass

            return jsonify({
                'success': True,
                'message': 'Transaction refunded successfully',
                'data': {
                    'refund_request': rr.to_dict(include_transaction=True),
                },
            }), 200

        # Cashier: create request
        rr = RefundRequest(
            transaction_id=transaction.id,
            requested_by=user_id,
            status='pending',
            reason=reason,
        )
        db.session.add(rr)
        db.session.commit()

        try:
            log_activity(
                user_id=user_id,
                action=f'Requested refund for {transaction.transaction_id}',
                entity_type='transaction',
                entity_id=transaction.id,
                details={'transaction_id': transaction.transaction_id, 'refund_request_id': rr.id},
            )
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': 'Refund request submitted for approval',
            'data': {
                'refund_request': rr.to_dict(include_transaction=True),
            },
        }), 201

    except ValueError as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 400
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@refunds_bp.route('/pending', methods=['GET'])
@jwt_required()
@require_admin
def get_pending_refunds():
    try:
        pending = (
            RefundRequest.query.filter_by(status='pending')
            .order_by(RefundRequest.created_at.asc())
            .limit(200)
            .all()
        )
        return jsonify({
            'success': True,
            'data': [r.to_dict(include_transaction=True) for r in pending],
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@refunds_bp.route('/mine', methods=['GET'])
@jwt_required()
def get_my_refund_requests():
    try:
        user_id = _current_user_id_int()
        if user_id is None:
            return jsonify({'success': False, 'message': 'Invalid user identity'}), 401

        limit = request.args.get('limit', 50, type=int)
        if limit < 1:
            limit = 1
        if limit > 200:
            limit = 200

        q = RefundRequest.query.filter_by(requested_by=user_id)

        status = (request.args.get('status') or '').strip().lower()
        if status:
            # supports comma-separated
            allowed = {s.strip() for s in status.split(',') if s.strip()}
            if allowed:
                q = q.filter(RefundRequest.status.in_(allowed))

        rows = q.order_by(RefundRequest.created_at.desc()).limit(limit).all()

        return jsonify({
            'success': True,
            'data': [r.to_dict(include_transaction=True) for r in rows],
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@refunds_bp.route('/<int:request_id>/approve', methods=['POST'])
@jwt_required()
@require_admin
def approve_refund_request(request_id: int):
    try:
        user_id = _current_user_id_int()
        if user_id is None:
            return jsonify({'success': False, 'message': 'Invalid user identity'}), 401

        rr = RefundRequest.query.get(request_id)
        if not rr:
            return jsonify({'success': False, 'message': 'Refund request not found'}), 404

        if rr.status != 'pending':
            return jsonify({'success': False, 'message': 'Refund request is not pending'}), 400

        transaction = Transaction.query.get(rr.transaction_id)
        if not transaction:
            return jsonify({'success': False, 'message': 'Transaction not found'}), 404

        rr.status = 'approved'
        rr.approved_by = user_id
        rr.approved_at = datetime.now()

        # Extract optional member card hint from the stored reason.
        member_card_hint = None
        if rr.reason:
            for line in str(rr.reason).splitlines():
                if line.strip().lower().startswith('member card:'):
                    member_card_hint = line.split(':', 1)[1].strip() or None
                    break

        # Process
        _process_refund(
            transaction=transaction,
            actor_user_id=user_id,
            reason=rr.reason,
            member_card_hint=member_card_hint,
        )

        db.session.commit()

        try:
            log_activity(
                user_id=user_id,
                action=f'Approved refund for {transaction.transaction_id}',
                entity_type='refund_request',
                entity_id=rr.id,
                details={'transaction_id': transaction.transaction_id, 'refund_request_id': rr.id},
            )
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': 'Refund approved and processed',
            'data': rr.to_dict(include_transaction=True),
        }), 200

    except ValueError as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 400
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@refunds_bp.route('/<int:request_id>/reject', methods=['POST'])
@jwt_required()
@require_admin
def reject_refund_request(request_id: int):
    try:
        user_id = _current_user_id_int()
        if user_id is None:
            return jsonify({'success': False, 'message': 'Invalid user identity'}), 401

        rr = RefundRequest.query.get(request_id)
        if not rr:
            return jsonify({'success': False, 'message': 'Refund request not found'}), 404

        if rr.status != 'pending':
            return jsonify({'success': False, 'message': 'Refund request is not pending'}), 400

        rr.status = 'rejected'
        rr.rejected_by = user_id
        rr.rejected_at = datetime.now()

        db.session.commit()

        try:
            log_activity(
                user_id=user_id,
                action=f'Rejected refund request {rr.id}',
                entity_type='refund_request',
                entity_id=rr.id,
                details={'refund_request_id': rr.id, 'transaction_id': rr.transaction_id},
            )
        except Exception:
            pass

        return jsonify({
            'success': True,
            'message': 'Refund request rejected',
            'data': rr.to_dict(include_transaction=True),
        }), 200

    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@refunds_bp.route('/stats/daily', methods=['GET'])
@jwt_required()
@require_admin
def get_daily_refund_stats():
    """Helper endpoint (optional) for dashboards. Returns refunded products count for a date."""
    try:
        date_str = request.args.get('date')
        if date_str:
            report_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        else:
            report_date = datetime.now().date()

        refunded_requests = RefundRequest.query.filter(
            RefundRequest.status == 'approved',
            RefundRequest.approved_at.isnot(None),
            func.date(RefundRequest.approved_at) == report_date,
        ).all()

        refunded_products = 0
        for rr in refunded_requests:
            txn = Transaction.query.get(rr.transaction_id)
            if txn:
                refunded_products += int(txn.item_count or 0)

        return jsonify({
            'success': True,
            'data': {
                'date': report_date.isoformat(),
                'refunded_products': refunded_products,
                'refunded_requests': len(refunded_requests),
            },
        }), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500
