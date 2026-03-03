"""
Application settings and configuration
"""
import os
from datetime import timedelta
from dotenv import load_dotenv

_is_production = os.getenv('FLASK_ENV', 'development') == 'production'
load_dotenv(override=(not _is_production))


class Config:
    """Base configuration"""
    SECRET_KEY = os.getenv('SECRET_KEY', 'vivian-cosmetic-shop-secret-key-2024')
    JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'vivian-jwt-secret-key-2024')
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(hours=8)  # 8 hour shift
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(days=30)
    
    # CORS Settings
    CORS_ORIGINS = os.getenv('CORS_ORIGINS', '*')
    
    # Application Settings
    APP_NAME = 'Vivian Cosmetic Shop API'
    APP_VERSION = '1.0.0'
    DEBUG = False
    TESTING = False


class DevelopmentConfig(Config):
    """Development configuration"""
    DEBUG = True
    SQLALCHEMY_ECHO = True


class ProductionConfig(Config):
    """Production configuration"""
    DEBUG = False
    SQLALCHEMY_ECHO = False


class TestingConfig(Config):
    """Testing configuration"""
    TESTING = True
    DEBUG = True


# Configuration dictionary
config = {
    'development': DevelopmentConfig,
    'production': ProductionConfig,
    'testing': TestingConfig,
    'default': DevelopmentConfig
}


def get_config():
    """Get configuration based on environment"""
    env = os.getenv('FLASK_ENV', 'development')
    return config.get(env, config['default'])
