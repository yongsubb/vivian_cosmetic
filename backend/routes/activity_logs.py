"""Activity Logs routes - Audit trail.

Provides read access for authenticated users and delete access for supervisors.
"""

from flask import Blueprint, jsonify, request
from flask_jwt_extended import get_jwt, jwt_required

from extensions import db
from models.user import ActivityLog, User

activity_logs_bp = Blueprint('activity_logs', __name__)


@activity_logs_bp.route('/', methods=['GET'])
@jwt_required()
def get_activity_logs():
    """Get recent activity logs."""
    try:
        limit = request.args.get('limit', 50, type=int)
        limit = max(1, min(limit, 200))

        # archived=1 -> archived logs, archived=0 -> active logs (default)
        archived = request.args.get('archived', 0, type=int)
        show_archived = bool(archived)

        logs_query = ActivityLog.query
        logs_query = logs_query.filter(ActivityLog.is_archived.is_(show_archived))
        logs = logs_query.order_by(ActivityLog.created_at.desc()).limit(limit).all()

        data = []
        for log in logs:
            user_name = 'System'
            if log.user_id:
                user = User.query.get(log.user_id)
                if user:
                    user_name = getattr(user, 'display_name', None) or user.full_name

            data.append({
                'id': log.id,
                'user_id': log.user_id,
                'user_name': user_name,
                'action': log.action,
                'entity_type': log.entity_type,
                'entity_id': log.entity_id,
                'details': log.details,
                'is_archived': bool(getattr(log, 'is_archived', False)),
                'created_at': log.created_at.isoformat() if log.created_at else None,
            })

        return jsonify({'success': True, 'data': data}), 200
    except Exception as e:
        return jsonify({'success': False, 'message': str(e)}), 500


@activity_logs_bp.route('/<int:log_id>', methods=['DELETE'])
@jwt_required()
def delete_activity_log(log_id: int):
    """Archive a single activity log entry (supervisor only).

    Use ?hard=true for permanent deletion.
    """
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({'success': False, 'message': 'Supervisor access required'}), 403

        hard = request.args.get('hard', 'false').lower() in {'1', 'true', 'yes', 'on'}

        log = ActivityLog.query.get(log_id)
        if not log:
            return jsonify({'success': False, 'message': 'Activity log not found'}), 404

        if hard:
            db.session.delete(log)
            db.session.commit()
            return jsonify({'success': True, 'message': 'Activity log deleted'}), 200

        log.is_archived = True
        db.session.commit()
        return jsonify({'success': True, 'message': 'Activity log archived'}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500


@activity_logs_bp.route('/<int:log_id>/restore', methods=['PATCH'])
@jwt_required()
def restore_activity_log(log_id: int):
    """Restore an archived activity log entry (supervisor only)."""
    try:
        claims = get_jwt()
        if claims.get('role') != 'supervisor':
            return jsonify({'success': False, 'message': 'Supervisor access required'}), 403

        log = ActivityLog.query.get(log_id)
        if not log:
            return jsonify({'success': False, 'message': 'Activity log not found'}), 404

        log.is_archived = False
        db.session.commit()
        return jsonify({'success': True, 'message': 'Activity log restored'}), 200
    except Exception as e:
        db.session.rollback()
        return jsonify({'success': False, 'message': str(e)}), 500
