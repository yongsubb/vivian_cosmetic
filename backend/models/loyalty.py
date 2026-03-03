"""
Loyalty models for membership management
"""
from datetime import datetime
from extensions import db


class LoyaltyTier(db.Model):
    """Loyalty tier levels (Bronze, Silver, Gold, Platinum)"""
    __tablename__ = 'loyalty_tiers'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String(50), unique=True, nullable=False)
    min_points = db.Column(db.Integer, default=0, nullable=False)
    max_points = db.Column(db.Integer, nullable=True)
    discount_percent = db.Column(db.Numeric(5, 2), default=0.00)
    points_multiplier = db.Column(db.Numeric(3, 2), default=1.00)
    color = db.Column(db.String(7), default='#808080')
    icon = db.Column(db.String(50))
    benefits = db.Column(db.Text)
    is_active = db.Column(db.Boolean, default=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    members = db.relationship('LoyaltyMember', backref='tier', lazy='dynamic')
    
    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'min_points': self.min_points,
            'max_points': self.max_points,
            'discount_percent': float(self.discount_percent) if self.discount_percent else 0,
            'points_multiplier': float(self.points_multiplier) if self.points_multiplier else 1,
            'color': self.color,
            'icon': self.icon,
            'benefits': self.benefits,
            'is_active': self.is_active,
            'member_count': self.members.count(),
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
    
    def __repr__(self):
        return f'<LoyaltyTier {self.name}>'


class LoyaltyMember(db.Model):
    """Loyalty program member linked to customer"""
    __tablename__ = 'loyalty_members'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    customer_id = db.Column(db.Integer, db.ForeignKey('customers.id', ondelete='CASCADE'), unique=True, nullable=False)
    member_number = db.Column(db.String(20), unique=True, nullable=False)
    card_barcode = db.Column(db.String(50), unique=True, nullable=False)
    
    # Member info
    tier_id = db.Column(db.Integer, db.ForeignKey('loyalty_tiers.id', ondelete='SET NULL'), default=1)
    join_date = db.Column(db.DateTime, default=datetime.now)
    expiry_date = db.Column(db.DateTime, nullable=True)
    
    # Points tracking
    current_points = db.Column(db.Integer, default=0)
    lifetime_points = db.Column(db.Integer, default=0)
    
    # Card status
    card_issued = db.Column(db.Boolean, default=False)
    card_issued_date = db.Column(db.DateTime, nullable=True)
    card_status = db.Column(db.String(20), default='active')  # active, suspended, expired, lost
    
    # Status
    is_active = db.Column(db.Boolean, default=True)

    # Archive / lifecycle (used by loyalty app + staff tooling)
    is_archived = db.Column(db.Boolean, default=False, nullable=False)
    archived_at = db.Column(db.DateTime, nullable=True)
    deactivated_at = db.Column(db.DateTime, nullable=True)

    # Member app activity
    activated_at = db.Column(db.DateTime, nullable=True)
    last_active_at = db.Column(db.DateTime, nullable=True)

    # Limited self-reactivation count for the member app.
    # Each transition from inactive->active consumes 1.
    reactivation_remaining = db.Column(db.Integer, default=3, nullable=False)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    customer = db.relationship('Customer', backref=db.backref('loyalty_member', uselist=False))
    point_transactions = db.relationship('LoyaltyTransaction', backref='member', lazy='dynamic', cascade='all, delete-orphan')
    
    def to_dict(self, include_customer=True, include_tier=True):
        data = {
            'id': self.id,
            'customer_id': self.customer_id,
            'member_number': self.member_number,
            'card_barcode': self.card_barcode,
            'tier_id': self.tier_id,
            'join_date': self.join_date.isoformat() if self.join_date else None,
            'expiry_date': self.expiry_date.isoformat() if self.expiry_date else None,
            'current_points': self.current_points,
            'lifetime_points': self.lifetime_points,
            'card_issued': self.card_issued,
            'card_issued_date': self.card_issued_date.isoformat() if self.card_issued_date else None,
            'card_status': self.card_status,
            'is_active': self.is_active,
            'is_archived': bool(getattr(self, 'is_archived', False)),
            'archived_at': self.archived_at.isoformat() if self.archived_at else None,
            'deactivated_at': self.deactivated_at.isoformat() if self.deactivated_at else None,
            'activated_at': self.activated_at.isoformat() if self.activated_at else None,
            'last_active_at': self.last_active_at.isoformat() if self.last_active_at else None,
            'reactivation_remaining': int(getattr(self, 'reactivation_remaining', 3) or 0),
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }
        
        if include_customer and self.customer:
            data['customer'] = {
                'id': self.customer.id,
                'name': self.customer.name,
                'email': self.customer.email,
                'phone': self.customer.phone,
                'address': self.customer.address,
                'total_purchases': float(self.customer.total_purchases) if self.customer.total_purchases else 0,
            }
        
        if include_tier and self.tier:
            data['tier'] = {
                'id': self.tier.id,
                'name': self.tier.name,
                'discount_percent': float(self.tier.discount_percent) if self.tier.discount_percent else 0,
                'points_multiplier': float(self.tier.points_multiplier) if self.tier.points_multiplier else 1,
                'color': self.tier.color,
                'icon': self.tier.icon,
            }
        
        return data
    
    @staticmethod
    def generate_member_number():
        """Generate a unique member number"""
        import random
        import string
        prefix = 'VCS'
        year = datetime.now().strftime('%y')
        random_part = ''.join(random.choices(string.digits, k=6))
        return f'{prefix}{year}{random_part}'
    
    @staticmethod
    def generate_barcode():
        """Generate a unique barcode for the loyalty card"""
        import random
        # EAN-13 compatible format: 13 digits starting with custom prefix
        prefix = '200'  # Internal use prefix
        random_part = ''.join([str(random.randint(0, 9)) for _ in range(9)])
        # Calculate check digit for EAN-13
        code = prefix + random_part
        total = 0
        for i, digit in enumerate(code):
            if i % 2 == 0:
                total += int(digit)
            else:
                total += int(digit) * 3
        check_digit = (10 - (total % 10)) % 10
        return code + str(check_digit)
    
    def __repr__(self):
        return f'<LoyaltyMember {self.member_number}>'


class LoyaltyTransaction(db.Model):
    """Points transaction history"""
    __tablename__ = 'loyalty_transactions'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    member_id = db.Column(db.Integer, db.ForeignKey('loyalty_members.id', ondelete='CASCADE'), nullable=False)
    transaction_id = db.Column(db.Integer, db.ForeignKey('transactions.id', ondelete='SET NULL'), nullable=True)
    
    # Transaction type
    transaction_type = db.Column(db.String(20), nullable=False)  # earn, redeem, adjust, expire, bonus
    points = db.Column(db.Integer, nullable=False)  # Positive for earn, negative for redeem
    balance_after = db.Column(db.Integer, nullable=False)
    
    # Reference
    description = db.Column(db.String(255))
    reference_code = db.Column(db.String(50))
    
    # User who made adjustment
    adjusted_by = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    
    # Relationships
    sale_transaction = db.relationship('Transaction', backref='loyalty_transactions')
    adjuster = db.relationship('User', backref='loyalty_adjustments')
    
    def to_dict(self):
        return {
            'id': self.id,
            'member_id': self.member_id,
            'transaction_id': self.transaction_id,
            'transaction_type': self.transaction_type,
            'points': self.points,
            'balance_after': self.balance_after,
            'description': self.description,
            'reference_code': self.reference_code,
            'adjusted_by': self.adjusted_by,
            'adjuster_name': f'{self.adjuster.first_name} {self.adjuster.last_name}' if self.adjuster else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
    
    def __repr__(self):
        return f'<LoyaltyTransaction {self.id} - {self.transaction_type}: {self.points}>'


class LoyaltySetting(db.Model):
    """Loyalty program settings with admin control"""
    __tablename__ = 'loyalty_settings'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    setting_key = db.Column(db.String(100), unique=True, nullable=False)
    setting_value = db.Column(db.Text)
    setting_type = db.Column(db.String(20), default='string')
    min_value = db.Column(db.Numeric(10, 2), nullable=True)
    max_value = db.Column(db.Numeric(10, 2), nullable=True)
    description = db.Column(db.String(255))
    
    # Audit
    last_modified_by = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    modifier = db.relationship('User', backref='loyalty_setting_changes')
    
    def get_value(self):
        """Get typed value based on setting_type"""
        if self.setting_type == 'number':
            try:
                return float(self.setting_value)
            except (ValueError, TypeError):
                return 0
        elif self.setting_type == 'boolean':
            return self.setting_value.lower() in ('true', '1', 'yes')
        elif self.setting_type == 'json':
            import json
            try:
                return json.loads(self.setting_value)
            except (ValueError, TypeError):
                return {}
        return self.setting_value
    
    def to_dict(self):
        return {
            'id': self.id,
            'setting_key': self.setting_key,
            'setting_value': self.setting_value,
            'typed_value': self.get_value(),
            'setting_type': self.setting_type,
            'min_value': float(self.min_value) if self.min_value else None,
            'max_value': float(self.max_value) if self.max_value else None,
            'description': self.description,
            'last_modified_by': self.last_modified_by,
            'modifier_name': f'{self.modifier.first_name} {self.modifier.last_name}' if self.modifier else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }
    
    def __repr__(self):
        return f'<LoyaltySetting {self.setting_key}>'
