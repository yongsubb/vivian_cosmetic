"""Role-based access control helpers.

This project uses simple roles embedded in JWT claims (e.g. 'cashier', 'supervisor').
These helpers standardize authorization checks across routes.
"""

from __future__ import annotations

from functools import wraps

from flask import jsonify
from flask_jwt_extended import get_jwt


def current_role() -> str:
    claims = get_jwt() or {}
    role = claims.get("role")
    return str(role or "").lower()


def require_roles(*roles: str):
    """Decorator to require one of the allowed roles.

    Must be used with @jwt_required() on the route.
    """

    allowed = {str(r).lower() for r in roles if str(r).strip()}

    def decorator(fn):
        @wraps(fn)
        def wrapper(*args, **kwargs):
            role = current_role()
            if role not in allowed:
                # Keep message consistent with existing code.
                if allowed == {"supervisor"}:
                    msg = "Supervisor access required"
                else:
                    msg = "Access denied"
                return jsonify({"success": False, "message": msg}), 403
            return fn(*args, **kwargs)

        return wrapper

    return decorator


def require_supervisor(fn):
    return require_roles("supervisor")(fn)


def require_admin(fn):
    """Decorator to require an admin-like role.

    Note: In this codebase, the default "admin" user is often created with the
    role "supervisor". We therefore allow supervisor/admin/superadmin.
    """

    return require_roles("supervisor", "admin", "superadmin")(fn)
