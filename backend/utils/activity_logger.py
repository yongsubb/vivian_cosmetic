"""Activity logging helpers.

Best-effort audit trail: failures should not break the main request.
"""

from __future__ import annotations

from typing import Any, Optional

from flask import request

from extensions import db


def log_activity(
    *,
    user_id: Optional[int],
    action: str,
    entity_type: Optional[str] = None,
    entity_id: Optional[int] = None,
    details: Optional[dict[str, Any]] = None,
) -> None:
    try:
        from models.user import ActivityLog

        log = ActivityLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            details=details,
            ip_address=(request.remote_addr if request else None),
            user_agent=(request.user_agent.string[:255] if request and request.user_agent else None),
        )
        db.session.add(log)
        db.session.commit()
    except Exception:
        try:
            db.session.rollback()
        except Exception:
            pass
