"""
Flask extensions initialization
"""
from flask import jsonify
from flask_sqlalchemy import SQLAlchemy
from flask_jwt_extended import JWTManager
from flask_cors import CORS
from flask_migrate import Migrate

# Initialize extensions
db = SQLAlchemy()
jwt = JWTManager()
cors = CORS()
migrate = Migrate()


def init_extensions(app):
    """Initialize all Flask extensions"""
    db.init_app(app)
    jwt.init_app(app)
    cors.init_app(app, resources={r"/api/*": {"origins": "*"}})
    migrate.init_app(app, db)
    
    # JWT error handlers
    @jwt.expired_token_loader
    def expired_token_callback(jwt_header, jwt_payload):
        print(f"❌ JWT Error: Token expired - Header: {jwt_header}, Payload: {jwt_payload}")
        return jsonify({
            'success': False,
            'message': 'Token has expired. Please login again.',
            'error': 'token_expired'
        }), 401
    
    @jwt.invalid_token_loader
    def invalid_token_callback(error):
        print(f"❌ JWT Error: Invalid token - Error: {error}")
        return jsonify({
            'success': False,
            'message': 'Invalid token. Please login again.',
            'error': 'invalid_token'
        }), 401
    
    @jwt.unauthorized_loader
    def missing_token_callback(error):
        print(f"❌ JWT Error: Missing token - Error: {error}")
        return jsonify({
            'success': False,
            'message': 'Authorization token is missing. Please login.',
            'error': 'missing_token'
        }), 401
    
    @jwt.revoked_token_loader
    def revoked_token_callback(jwt_header, jwt_payload):
        print(f"❌ JWT Error: Token revoked - Header: {jwt_header}, Payload: {jwt_payload}")
        return jsonify({
            'success': False,
            'message': 'Token has been revoked. Please login again.',
            'error': 'token_revoked'
        }), 401
    
    return app
