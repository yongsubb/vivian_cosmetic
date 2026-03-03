"""Refund request model.

Refunds can be requested by cashiers and must be approved by a supervisor.
Supervisors can also perform an instant refund (recorded as an approved request).
"""

from __future__ import annotations

from datetime import datetime

from extensions import db


class RefundRequest(db.Model):
    __tablename__ = 'refund_requests'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)

    transaction_id = db.Column(
        db.Integer,
        db.ForeignKey('transactions.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )

    requested_by = db.Column(
        db.Integer,
        db.ForeignKey('users.id', ondelete='SET NULL'),
        nullable=True,
        index=True,
    )

    status = db.Column(db.String(20), nullable=False, default='pending', index=True)

    reason = db.Column(db.Text, nullable=True)

    approved_by = db.Column(
        db.Integer,
        db.ForeignKey('users.id', ondelete='SET NULL'),
        nullable=True,
        index=True,
    )
    approved_at = db.Column(db.DateTime, nullable=True)

    rejected_by = db.Column(
        db.Integer,
        db.ForeignKey('users.id', ondelete='SET NULL'),
        nullable=True,
        index=True,
    )
    rejected_at = db.Column(db.DateTime, nullable=True)

    created_at = db.Column(db.DateTime, default=datetime.now, index=True)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)

    # Relationships
    transaction = db.relationship('Transaction', backref=db.backref('refund_requests', lazy='dynamic'))

    def to_dict(self, include_transaction: bool = False) -> dict:
        data = {
            'id': self.id,
            'transaction_id': self.transaction_id,
            'requested_by': self.requested_by,
            'status': self.status,
            'reason': self.reason,
            'approved_by': self.approved_by,
            'approved_at': self.approved_at.isoformat() if self.approved_at else None,
            'rejected_by': self.rejected_by,
            'rejected_at': self.rejected_at.isoformat() if self.rejected_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_transaction and self.transaction:
            data['transaction'] = self.transaction.to_dict(include_items=True)
        return data
