"""
Vivian Cosmetic Shop - Flask Backend Application
Main entry point
"""
import os
import socket
from pathlib import Path

from flask import Flask, abort, jsonify, request, send_from_directory
from dotenv import load_dotenv
from sqlalchemy import text
from flask_cors import CORS

# Load environment variables
# Always load `backend/.env` regardless of the current working directory.
# Prefer values from `.env` even if the process environment already contains
# older values (common when switching SMS providers locally).
_dotenv_path = Path(__file__).resolve().parent / '.env'
load_dotenv(dotenv_path=_dotenv_path, override=True)

# Import extensions and routes
from extensions import init_extensions, db
from config.database import SQLALCHEMY_DATABASE_URI, SQLALCHEMY_TRACK_MODIFICATIONS
from config.settings import get_config
from routes import register_blueprints


def _get_lan_ip() -> str | None:
    """Best-effort LAN IP discovery for printing a clickable URL."""
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        # Doesn't need to be reachable; no packets are sent.
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return None


def _resolve_flutter_web_build_dir() -> Path:
    """Resolve Flutter web build output directory.

    Defaults to `<projectRoot>/build/web`.
    Can be overridden with FLUTTER_WEB_BUILD_DIR.
    """
    override = os.getenv("FLUTTER_WEB_BUILD_DIR")
    if override:
        return Path(override).expanduser().resolve()

    # backend/app.py -> backend/ -> project root
    project_root = Path(__file__).resolve().parent.parent
    return (project_root / "build" / "web").resolve()


def create_app(config_class=None):
    """Application factory pattern"""
    app = Flask(__name__)
    
    # Disable strict slashes to prevent 308 redirects
    app.url_map.strict_slashes = False
    
    # Load configuration
    if config_class is None:
        config_class = get_config()
    
    app.config.from_object(config_class)
    app.config['SQLALCHEMY_DATABASE_URI'] = SQLALCHEMY_DATABASE_URI
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = SQLALCHEMY_TRACK_MODIFICATIONS
    
    # Initialize extensions
    init_extensions(app)

    # Allow browser-based clients (Flutter web) to call the API.
    # Note: tighten `origins` for production.
    CORS(
        app,
        resources={r"/api/*": {"origins": "*"}},
        allow_headers=["Content-Type", "Authorization"],
        methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    )

    # Optional one-off schema patch.
    # Disabled by default because it forces an immediate DB connection on startup
    # and can contribute to MySQL/MariaDB instability on some XAMPP installs.
    run_schema_patch = os.getenv("RUN_SCHEMA_PATCH_ON_STARTUP", "false").lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    if run_schema_patch:
        try:
            with app.app_context():
                if db.engine.dialect.name == "mysql":
                    # Create promotions table if missing (safe, one-off).
                    promos_table_exists = db.session.execute(
                        text(
                            """
                            SELECT COUNT(*)
                            FROM information_schema.TABLES
                            WHERE TABLE_SCHEMA = DATABASE()
                              AND TABLE_NAME = 'promotions'
                            """
                        )
                    ).scalar()
                    if int(promos_table_exists or 0) == 0:
                        from models.promotion import Promotion

                        Promotion.__table__.create(db.engine)

                    # Create refund_requests table if missing (safe, one-off).
                    refund_table_exists = db.session.execute(
                        text(
                            """
                            SELECT COUNT(*)
                            FROM information_schema.TABLES
                            WHERE TABLE_SCHEMA = DATABASE()
                              AND TABLE_NAME = 'refund_requests'
                            """
                        )
                    ).scalar()
                    if int(refund_table_exists or 0) == 0:
                        from models.refund_request import RefundRequest

                        RefundRequest.__table__.create(db.engine)

                    # Add nickname column if not exists
                    exists = db.session.execute(
                        text(
                            """
                            SELECT COUNT(*)
                            FROM information_schema.COLUMNS
                            WHERE TABLE_SCHEMA = DATABASE()
                              AND TABLE_NAME = 'users'
                              AND COLUMN_NAME = 'nickname'
                            """
                        )
                    ).scalar()
                    if int(exists or 0) == 0:
                        db.session.execute(
                            text(
                                "ALTER TABLE users ADD COLUMN nickname VARCHAR(50) NULL AFTER last_name"
                            )
                        )
                        db.session.commit()

                    # Add address column if not exists
                    address_exists = db.session.execute(
                        text(
                            """
                            SELECT COUNT(*)
                            FROM information_schema.COLUMNS
                            WHERE TABLE_SCHEMA = DATABASE()
                              AND TABLE_NAME = 'users'
                              AND COLUMN_NAME = 'address'
                            """
                        )
                    ).scalar()
                    if int(address_exists or 0) == 0:
                        db.session.execute(
                            text(
                                "ALTER TABLE users ADD COLUMN address VARCHAR(500) NULL AFTER phone"
                            )
                        )
                        db.session.commit()

                    # Add is_archived column to activity_logs if not exists
                    activity_archived_exists = db.session.execute(
                        text(
                            """
                            SELECT COUNT(*)
                            FROM information_schema.COLUMNS
                            WHERE TABLE_SCHEMA = DATABASE()
                              AND TABLE_NAME = 'activity_logs'
                              AND COLUMN_NAME = 'is_archived'
                            """
                        )
                    ).scalar()
                    if int(activity_archived_exists or 0) == 0:
                        db.session.execute(
                            text(
                                "ALTER TABLE activity_logs ADD COLUMN is_archived TINYINT(1) NOT NULL DEFAULT 0 AFTER user_agent"
                            )
                        )
                        db.session.commit()

                    # Add points_cost column to products if not exists
                    points_cost_exists = db.session.execute(
                        text(
                            """
                            SELECT COUNT(*)
                            FROM information_schema.COLUMNS
                            WHERE TABLE_SCHEMA = DATABASE()
                              AND TABLE_NAME = 'products'
                              AND COLUMN_NAME = 'points_cost'
                            """
                        )
                    ).scalar()
                    if int(points_cost_exists or 0) == 0:
                        db.session.execute(
                            text(
                                "ALTER TABLE products ADD COLUMN points_cost INT NOT NULL DEFAULT 0 AFTER discount_percent"
                            )
                        )
                        db.session.commit()

                    # Loyalty member lifecycle fields (archive + activity)
                    try:
                        def _col_exists(col: str) -> int:
                            return int(
                                (
                                    db.session.execute(
                                        text(
                                            """
                                            SELECT COUNT(*)
                                            FROM information_schema.COLUMNS
                                            WHERE TABLE_SCHEMA = DATABASE()
                                              AND TABLE_NAME = 'loyalty_members'
                                              AND COLUMN_NAME = :col
                                            """
                                        ),
                                        {'col': col},
                                    ).scalar()
                                )
                                or 0
                            )

                        if _col_exists('is_archived') == 0:
                            db.session.execute(
                                text(
                                    "ALTER TABLE loyalty_members ADD COLUMN is_archived TINYINT(1) NOT NULL DEFAULT 0 AFTER is_active"
                                )
                            )
                            db.session.commit()

                        if _col_exists('archived_at') == 0:
                            db.session.execute(
                                text(
                                    "ALTER TABLE loyalty_members ADD COLUMN archived_at DATETIME NULL AFTER is_archived"
                                )
                            )
                            db.session.commit()

                        if _col_exists('deactivated_at') == 0:
                            db.session.execute(
                                text(
                                    "ALTER TABLE loyalty_members ADD COLUMN deactivated_at DATETIME NULL AFTER archived_at"
                                )
                            )
                            db.session.commit()

                        if _col_exists('activated_at') == 0:
                            db.session.execute(
                                text(
                                    "ALTER TABLE loyalty_members ADD COLUMN activated_at DATETIME NULL AFTER deactivated_at"
                                )
                            )
                            db.session.commit()

                        if _col_exists('last_active_at') == 0:
                            db.session.execute(
                                text(
                                    "ALTER TABLE loyalty_members ADD COLUMN last_active_at DATETIME NULL AFTER activated_at"
                                )
                            )
                            db.session.commit()

                        if _col_exists('reactivation_remaining') == 0:
                            db.session.execute(
                                text(
                                    "ALTER TABLE loyalty_members ADD COLUMN reactivation_remaining INT NOT NULL DEFAULT 3 AFTER last_active_at"
                                )
                            )
                            db.session.commit()
                    except Exception as e:
                        try:
                            db.session.rollback()
                        except Exception:
                            pass
                        print(f"⚠️ Loyalty member schema patch failed: {e}")

                    # Upsert default loyalty tiers (safe, idempotent).
                    try:
                        from models.loyalty import LoyaltyTier
                        from sqlalchemy import func

                        desired = [
                            {
                                "id": 1,
                                "name": "Bronze",
                                "min_points": 1,
                                "max_points": 99,
                                "discount_percent": 5.00,
                                "points_multiplier": 1.00,
                                "color": "#CD7F32",
                                "icon": "stars",
                                "benefits": "5% discount on purchases",
                                "is_active": True,
                            },
                            {
                                "id": 2,
                                "name": "Silver",
                                "min_points": 100,
                                "max_points": 499,
                                "discount_percent": 10.00,
                                "points_multiplier": 1.50,
                                "color": "#C0C0C0",
                                "icon": "star",
                                "benefits": "10% discount on purchases",
                                "is_active": True,
                            },
                            {
                                "id": 3,
                                "name": "Gold",
                                "min_points": 500,
                                "max_points": 999,
                                "discount_percent": 15.00,
                                "points_multiplier": 2.00,
                                "color": "#FFD700",
                                "icon": "workspace_premium",
                                "benefits": "15% discount on purchases",
                                "is_active": True,
                            },
                            {
                                "id": 4,
                                "name": "Platinum",
                                "min_points": 1000,
                                "max_points": None,
                                "discount_percent": 20.00,
                                "points_multiplier": 2.00,
                                "color": "#E5E4E2",
                                "icon": "workspace_premium",
                                "benefits": "20% discount on purchases",
                                "is_active": True,
                            },
                        ]

                        for d in desired:
                            tier = LoyaltyTier.query.filter_by(id=d["id"]).first()
                            if not tier:
                                tier = LoyaltyTier.query.filter(
                                    func.lower(LoyaltyTier.name)
                                    == d["name"].lower()
                                ).first()
                            if not tier:
                                tier = LoyaltyTier(name=d["name"])
                                db.session.add(tier)

                            # Normalize stored name.
                            tier.name = d["name"]

                            tier.min_points = d["min_points"]
                            tier.max_points = d["max_points"]
                            tier.discount_percent = d["discount_percent"]
                            tier.points_multiplier = d["points_multiplier"]
                            tier.color = d["color"]
                            tier.icon = d["icon"]
                            tier.benefits = d["benefits"]
                            tier.is_active = d["is_active"]

                        db.session.commit()
                    except Exception as e:
                        db.session.rollback()
                        print(f"⚠️ Loyalty tier upsert failed: {e}")
        except Exception as e:
            try:
                db.session.rollback()
            except Exception:
                pass
            print(f"⚠️ Schema patch skipped/failed: {e}")
    
    # Register blueprints
    register_blueprints(app)

    # ------------------------------------------------------------
    # Optional: Serve Flutter Web build from this Flask server.
    # This makes the app reachable at: http://<LAN-IP>:5000/
    # ------------------------------------------------------------
    flutter_web_dir = _resolve_flutter_web_build_dir()
    serve_web = os.getenv("SERVE_FLUTTER_WEB", "true").lower() in {
        "1",
        "true",
        "yes",
        "on",
    }
    flutter_index = flutter_web_dir / "index.html"
    web_enabled = serve_web and flutter_index.exists()

    app.config["FLUTTER_WEB_BUILD_DIR"] = str(flutter_web_dir)
    app.config["FLUTTER_WEB_ENABLED"] = bool(web_enabled)

    if web_enabled:

        @app.route("/", defaults={"path": ""})
        @app.route("/<path:path>")
        def flutter_web(path: str):
            # Never intercept API routes.
            if path.startswith("api"):
                abort(404)

            # Serve exact asset files if they exist.
            file_path = flutter_web_dir / path
            if path and file_path.exists() and file_path.is_file():
                return send_from_directory(flutter_web_dir, path)

            # Otherwise serve the SPA entrypoint.
            return send_from_directory(flutter_web_dir, "index.html")
    
    # Health check endpoint
    @app.route('/api/health', methods=['GET'])
    def health_check():
        return jsonify({
            'success': True,
            'message': 'Vivian Cosmetic Shop API is running',
            'version': '1.0.0'
        }), 200
    
    # Root endpoint (API info). If Flutter web hosting is enabled, this moves to /api.
    @app.route('/api', methods=['GET'])
    def api_index():
        return jsonify({
            'name': 'Vivian Cosmetic Shop API',
            'version': '1.0.0',
            'description': 'POS and Inventory Management System API',
            'endpoints': {
                'auth': '/api/auth',
                'users': '/api/users',
                'products': '/api/products',
                'categories': '/api/categories',
                'transactions': '/api/transactions',
                'customers': '/api/customers',
                'reports': '/api/reports',
                'settings': '/api/settings',
                'loyalty': '/api/loyalty'
            }
        }), 200
    
    # Error handlers
    @app.errorhandler(404)
    def not_found(error):
        # If Flutter web hosting is enabled, let the SPA handle client-side routes.
        if app.config.get("FLUTTER_WEB_ENABLED") and not request.path.startswith(
            "/api"
        ):
            flutter_web_dir_local = Path(app.config["FLUTTER_WEB_BUILD_DIR"])
            index_file = flutter_web_dir_local / "index.html"
            if index_file.exists():
                return send_from_directory(flutter_web_dir_local, "index.html")

        return jsonify({'success': False, 'message': 'Resource not found'}), 404

    @app.errorhandler(405)
    def method_not_allowed(error):
        allowed = getattr(error, 'valid_methods', None)
        allowed_str = ''
        if allowed:
            try:
                allowed_str = f" Allowed: {', '.join(sorted(set(allowed)))}"
            except Exception:
                allowed_str = f" Allowed: {allowed}"

        # Include method/path so client snackbars/logs immediately reveal
        # what endpoint was actually called.
        msg = f"Method not allowed ({request.method} {request.path}).{allowed_str}".strip()
        return jsonify({'success': False, 'message': msg}), 405
    
    @app.errorhandler(500)
    def internal_error(error):
        db.session.rollback()
        return jsonify({
            'success': False,
            'message': 'Internal server error'
        }), 500
    
    return app


# Create application instance
app = create_app()


if __name__ == '__main__':
    # Development server
    port = int(os.getenv('PORT', 5000))
    debug = os.getenv('DEBUG', 'False').lower() == 'true'

    web_enabled = bool(app.config.get("FLUTTER_WEB_ENABLED"))
    lan_ip = _get_lan_ip()
    lan_base = f"http://{lan_ip}:{port}" if lan_ip else None
    local_base = f"http://localhost:{port}"
    
    print(f"""
    ╔══════════════════════════════════════════════════════════╗
    ║         Vivian Cosmetic Shop - Backend Server            ║
    ╠══════════════════════════════════════════════════════════╣
    ║  Local: {local_base:<46}║
    ║  LAN:   {(lan_base or 'Unavailable'):<46}║
    ║  Debug mode: {debug}                                       ║
    ║                                                          ║
    ║  UI:   {'/' if web_enabled else '(disabled - run flutter build web)'}
    ║  API:  /api/*  (health: /api/health)                      ║
    ║  Endpoints:                                              ║
    ║  • POST /api/auth/login      - Login                     ║
    ║  • POST /api/auth/logout     - Logout                    ║
    ║  • GET  /api/auth/me         - Get current user          ║
    ║  • GET  /api/products        - List products             ║
    ║  • GET  /api/categories      - List categories           ║
    ║  • POST /api/transactions    - Create transaction        ║
    ║  • GET  /api/reports/daily   - Daily report              ║
    ╚══════════════════════════════════════════════════════════╝
    """)
    
    app.run(host='0.0.0.0', port=port, debug=debug, use_reloader=False)
