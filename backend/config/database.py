"""
Database configuration for MySQL (XAMPP)
"""
import os
from dotenv import load_dotenv

_is_production = os.getenv('FLASK_ENV', 'development') == 'production'
load_dotenv(override=(not _is_production))

# MySQL Database Configuration (XAMPP)
DATABASE_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'port': int(os.getenv('DB_PORT', 3306)),
    'user': os.getenv('DB_USER', 'root'),
    'password': os.getenv('DB_PASSWORD', ''),  # Default XAMPP has no password
    'database': os.getenv('DB_NAME', 'vivian_cosmetic_shop'),
    'charset': 'utf8mb4'
}

# SQLAlchemy Database URI
SQLALCHEMY_DATABASE_URI = (
    f"mysql+pymysql://{DATABASE_CONFIG['user']}:{DATABASE_CONFIG['password']}"
    f"@{DATABASE_CONFIG['host']}:{DATABASE_CONFIG['port']}/{DATABASE_CONFIG['database']}"
    f"?charset={DATABASE_CONFIG['charset']}"
)

SQLALCHEMY_TRACK_MODIFICATIONS = False
SQLALCHEMY_ECHO = os.getenv('DEBUG', 'False').lower() == 'true'
