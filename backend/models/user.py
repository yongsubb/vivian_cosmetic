"""
User model for authentication and user management
"""
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash
from extensions import db


class User(db.Model):
    """User model for cashiers and supervisors"""
    __tablename__ = 'users'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    username = db.Column(db.String(50), unique=True, nullable=False, index=True)
    email = db.Column(db.String(100), unique=True, nullable=True)
    password_hash = db.Column(db.String(255), nullable=False)
    pin_hash = db.Column(db.String(255), nullable=True)  # 4-digit PIN for quick login
    
    # User info
    first_name = db.Column(db.String(50), nullable=False)
    last_name = db.Column(db.String(50), nullable=False)
    nickname = db.Column(db.String(50), nullable=True)
    phone = db.Column(db.String(20), nullable=True)
    address = db.Column(db.String(500), nullable=True)  # Home address for security
    avatar_url = db.Column(db.String(255), nullable=True)
    
    # Role: 'cashier' or 'supervisor'
    role = db.Column(db.String(20), nullable=False, default='cashier')
    
    # Status
    is_active = db.Column(db.Boolean, default=True)
    is_logged_in = db.Column(db.Boolean, default=False)
    last_login = db.Column(db.DateTime, nullable=True)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(db.DateTime, default=datetime.now, onupdate=datetime.now)
    
    # Relationships
    transactions = db.relationship('Transaction', backref='cashier', lazy='dynamic')
    
    def __init__(self, username, first_name, last_name, password, role='cashier', **kwargs):
        self.username = username
        self.first_name = first_name
        self.last_name = last_name
        self.set_password(password)
        self.role = role
        for key, value in kwargs.items():
            if hasattr(self, key):
                setattr(self, key, value)
    
    def set_password(self, password):
        """Hash and set password"""
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        """Verify password"""
        return check_password_hash(self.password_hash, password)
    
    def set_pin(self, pin):
        """Hash and set PIN"""
        if pin and len(pin) == 4 and pin.isdigit():
            self.pin_hash = generate_password_hash(pin)
        else:
            raise ValueError("PIN must be a 4-digit number")
    
    def check_pin(self, pin):
        """Verify PIN"""
        if self.pin_hash:
            return check_password_hash(self.pin_hash, pin)
        return False
    
    @property
    def full_name(self):
        """Get full name"""
        return f"{self.first_name} {self.last_name}"

    @property
    def display_name(self):
        """Preferred display name for UI/receipts"""
        if self.nickname and self.nickname.strip():
            return self.nickname.strip()
        return self.full_name
    
    @property
    def is_supervisor(self):
        """Check if user is supervisor"""
        return self.role == 'supervisor'
    
    def to_dict(self, include_sensitive=False):
        """Convert to dictionary"""
        data = {
            'id': self.id,
            'username': self.username,
            'email': self.email,
            'first_name': self.first_name,
            'last_name': self.last_name,
            'full_name': self.full_name,
            'nickname': self.nickname,
            'display_name': self.display_name,
            'phone': self.phone,
            'address': self.address,
            'avatar_url': self.avatar_url,
            'role': self.role,
            'is_active': self.is_active,
            'is_logged_in': self.is_logged_in,
            'last_login': self.last_login.isoformat() if self.last_login else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
        if include_sensitive:
            data['has_pin'] = self.pin_hash is not None
        return data
    
    def __repr__(self):
        return f'<User {self.username} ({self.role})>'


class ActivityLog(db.Model):
    """Activity log for audit trail"""
    __tablename__ = 'activity_logs'
    
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id', ondelete='SET NULL'), nullable=True)
    action = db.Column(db.String(100), nullable=False)
    entity_type = db.Column(db.String(50), nullable=True)
    entity_id = db.Column(db.Integer, nullable=True)
    details = db.Column(db.JSON, nullable=True)
    ip_address = db.Column(db.String(45), nullable=True)
    user_agent = db.Column(db.String(255), nullable=True)

    # Soft-delete / archive flag
    is_archived = db.Column(db.Boolean, default=False, nullable=False)
    
    # Timestamps
    created_at = db.Column(db.DateTime, default=datetime.now)
    
    # Relationships
    user = db.relationship('User', backref='activity_logs')
    
    def to_dict(self):
        return {
            'id': self.id,
            'user_id': self.user_id,
            'action': self.action,
            'entity_type': self.entity_type,
            'entity_id': self.entity_id,
            'details': self.details,
            'ip_address': self.ip_address,
            'user_agent': self.user_agent,
            'is_archived': bool(self.is_archived),
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }
    
    def __repr__(self):
        return f'<ActivityLog {self.action}>'
