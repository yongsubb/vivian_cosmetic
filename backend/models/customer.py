"""
Customer model
"""
from datetime import datetime
from extensions import db


class Customer(db.Model):
    """Customer model for loyalty and tracking"""
    __tablename__ = 'customers'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(100), nullable=False)
    email = db.Column(db.String(100), unique=True, nullable=True, index=True)
    phone = db.Column(db.String(20), unique=True, nullable=True, index=True)
    address = db.Column(db.Text, nullable=True)
    
    # Loyalty
    loyalty_points = db.Column(db.Integer, default=0)
    total_purchases = db.Column(db.Numeric(12, 2), default=0)
    
    # Status
    is_active = db.Column(db.Boolean, default=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    transactions = db.relationship('Transaction', backref='customer', lazy='dynamic')
    
    @property
    def transaction_count(self):
        """Get total number of transactions"""
        return self.transactions.count()
    
    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'email': self.email,
            'phone': self.phone,
            'address': self.address,
            'loyalty_points': self.loyalty_points,
            'total_purchases': float(self.total_purchases) if self.total_purchases else 0,
            'transaction_count': self.transaction_count,
            'is_active': self.is_active,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
    
    def __repr__(self):
        return f'<Customer {self.name}>'
