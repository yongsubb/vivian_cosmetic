"""Loyalty member maintenance job.

Designed to be run daily via Windows Task Scheduler / cron.

Rules implemented:
- If a member is inactive for 1 year (based on last_active_at), archive+deactivate.
- If an archived member has never activated within 30 days of creation, delete.

This job is idempotent and safe to run multiple times.
"""

from __future__ import annotations

from datetime import datetime, timedelta

from sqlalchemy import func

from app import app
from extensions import db
from models.loyalty import LoyaltyMember


def run() -> dict[str, int]:
    now = datetime.now()
    one_year_ago = now - timedelta(days=365)
    thirty_days_ago = now - timedelta(days=30)

    archived_count = 0
    deleted_count = 0

    with app.app_context():
        # 1) Auto-deactivate/archive members inactive for 1 year.
        # Only applies to members that have activated at least once.
        if hasattr(LoyaltyMember, 'last_active_at') and hasattr(LoyaltyMember, 'is_archived'):
            last_seen = func.coalesce(
                LoyaltyMember.last_active_at,
                LoyaltyMember.activated_at,
                LoyaltyMember.created_at,
            )

            q = LoyaltyMember.query.filter(
                LoyaltyMember.is_active.is_(True),
                LoyaltyMember.is_archived.is_(False),
                LoyaltyMember.activated_at.isnot(None),
                last_seen <= one_year_ago,
            )

            rows = q.all()
            for m in rows:
                m.is_active = False
                m.is_archived = True
                if hasattr(m, 'archived_at'):
                    m.archived_at = now
                if hasattr(m, 'deactivated_at'):
                    m.deactivated_at = now
            archived_count = len(rows)

        # 2) Auto-delete archived accounts that never activated within 30 days.
        if hasattr(LoyaltyMember, 'is_archived') and hasattr(LoyaltyMember, 'activated_at'):
            q_del = LoyaltyMember.query.filter(
                LoyaltyMember.is_archived.is_(True),
                LoyaltyMember.activated_at.is_(None),
                LoyaltyMember.created_at <= thirty_days_ago,
            )
            rows_del = q_del.all()
            for m in rows_del:
                db.session.delete(m)
            deleted_count = len(rows_del)

        db.session.commit()

    return {
        'archived': archived_count,
        'deleted': deleted_count,
    }


if __name__ == '__main__':
    result = run()
    print(f"Archived (inactive>=1y): {result['archived']}")
    print(f"Deleted (archived+unactivated>=30d): {result['deleted']}")
