"""
API Routes package
"""
from .auth import auth_bp
from .users import users_bp
from .products import products_bp
from .categories import categories_bp
from .transactions import transactions_bp
from .customers import customers_bp
from .reports import reports_bp
from .settings import settings_bp
from .vouchers import vouchers_bp
from .loyalty import loyalty_bp
from .activity_logs import activity_logs_bp
from .promotions import promotions_bp
from .refunds import refunds_bp
from .payments import payments_bp

__all__ = [
    'auth_bp',
    'users_bp',
    'products_bp',
    'categories_bp',
    'transactions_bp',
    'customers_bp',
    'reports_bp',
    'settings_bp',
    'vouchers_bp',
    'loyalty_bp',
    'activity_logs_bp',
    'promotions_bp',
    'refunds_bp',
    'payments_bp'
]


def register_blueprints(app):
    """Register all API blueprints"""
    app.register_blueprint(auth_bp, url_prefix='/api/auth')
    app.register_blueprint(users_bp, url_prefix='/api/users')
    app.register_blueprint(products_bp, url_prefix='/api/products')
    app.register_blueprint(categories_bp, url_prefix='/api/categories')
    app.register_blueprint(transactions_bp, url_prefix='/api/transactions')
    app.register_blueprint(customers_bp, url_prefix='/api/customers')
    app.register_blueprint(reports_bp, url_prefix='/api/reports')
    app.register_blueprint(settings_bp, url_prefix='/api/settings')
    app.register_blueprint(vouchers_bp, url_prefix='/api/vouchers')
    app.register_blueprint(loyalty_bp, url_prefix='/api/loyalty')
    app.register_blueprint(activity_logs_bp, url_prefix='/api/activity-logs')
    app.register_blueprint(promotions_bp, url_prefix='/api/promotions')
    app.register_blueprint(refunds_bp, url_prefix='/api/refunds')
    app.register_blueprint(payments_bp, url_prefix='/api/payments')
    
    return app
