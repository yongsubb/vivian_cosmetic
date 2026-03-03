"""
Transaction and TransactionItem models
"""
from datetime import datetime
from extensions import db


class Transaction(db.Model):
    """Transaction model for sales records"""
    __tablename__ = 'transactions'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    transaction_id = db.Column(db.String(50), unique=True, nullable=False, index=True)
    
    # Customer (optional)
    customer_id = db.Column(db.Integer, db.ForeignKey('customers.id'), nullable=True)
    
    # Cashier
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    
    # Amounts
    subtotal = db.Column(db.Numeric(12, 2), nullable=False)
    discount_amount = db.Column(db.Numeric(12, 2), default=0)
    tax_amount = db.Column(db.Numeric(12, 2), default=0)
    total_amount = db.Column(db.Numeric(12, 2), nullable=False)
    
    # Payment
    payment_method = db.Column(db.String(20), nullable=False)  # cash, card, gcash, maya
    amount_received = db.Column(db.Numeric(12, 2), nullable=False)
    change_amount = db.Column(db.Numeric(12, 2), default=0)
    
    # Voucher
    voucher_code = db.Column(db.String(50), nullable=True)
    voucher_discount = db.Column(db.Numeric(12, 2), default=0)
    
    # Status: pending, completed, voided, refunded
    status = db.Column(db.String(20), default='completed')
    
    # Notes
    notes = db.Column(db.Text, nullable=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    items = db.relationship('TransactionItem', backref='transaction', lazy='joined', cascade='all, delete-orphan')
    
    def generate_transaction_id(self):
        """Generate unique transaction ID"""
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        return f"TXN-{timestamp}-{self.id or 0:04d}"
    
    @property
    def item_count(self):
        """Get total number of items"""
        return sum(item.quantity for item in self.items)
    
    def to_dict(self, include_items=True):
        data = {
            'id': self.id,
            'transaction_id': self.transaction_id,
            'customer_id': self.customer_id,
            'customer_name': self.customer.name if self.customer else None,
            'user_id': self.user_id,
            'cashier_name': self.cashier.display_name if self.cashier else None,
            'subtotal': float(self.subtotal),
            'discount_amount': float(self.discount_amount) if self.discount_amount else 0,
            'tax_amount': float(self.tax_amount) if self.tax_amount else 0,
            'total_amount': float(self.total_amount),
            'payment_method': self.payment_method,
            'amount_received': float(self.amount_received),
            'change_amount': float(self.change_amount) if self.change_amount else 0,
            'voucher_code': self.voucher_code,
            'voucher_discount': float(self.voucher_discount) if self.voucher_discount else 0,
            'status': self.status,
            'notes': self.notes,
            'item_count': self.item_count,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
        if include_items:
            data['items'] = [item.to_dict() for item in self.items]
        return data
    
    def __repr__(self):
        return f'<Transaction {self.transaction_id}>'


class TransactionItem(db.Model):
    """TransactionItem model for individual items in a transaction"""
    __tablename__ = 'transaction_items'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    transaction_id = db.Column(db.Integer, db.ForeignKey('transactions.id'), nullable=False)
    product_id = db.Column(db.Integer, db.ForeignKey('products.id'), nullable=False)
    
    # Product snapshot (in case product details change later)
    product_name = db.Column(db.String(200), nullable=False)
    product_sku = db.Column(db.String(50), nullable=False)
    
    # Pricing at time of sale
    unit_price = db.Column(db.Numeric(10, 2), nullable=False)
    quantity = db.Column(db.Integer, nullable=False, default=1)
    discount_percent = db.Column(db.Numeric(5, 2), default=0)
    subtotal = db.Column(db.Numeric(12, 2), nullable=False)
    
    def to_dict(self):
        return {
            'id': self.id,
            'product_id': self.product_id,
            'product_name': self.product_name,
            'product_sku': self.product_sku,
            'unit_price': float(self.unit_price),
            'quantity': self.quantity,
            'discount_percent': float(self.discount_percent) if self.discount_percent else 0,
            'subtotal': float(self.subtotal)
        }
    
    def __repr__(self):
        return f'<TransactionItem {self.product_name} x{self.quantity}>'
