"""Application settings model (DB-backed)."""

from datetime import datetime

from extensions import db


class Setting(db.Model):
    __tablename__ = 'settings'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    setting_key = db.Column(db.String(100), unique=True, nullable=False, index=True)
    setting_value = db.Column(db.Text)
    setting_type = db.Column(db.String(20), default='string')
    description = db.Column(db.String(255))

    created_at = db.Column(db.DateTime, default=datetime.now)
    updated_at = db.Column(
        db.DateTime,
        default=datetime.now,
        onupdate=datetime.now,
    )

    def get_value(self):
        if self.setting_type == 'number':
            try:
                return float(self.setting_value)
            except (ValueError, TypeError):
                return 0
        if self.setting_type == 'boolean':
            return str(self.setting_value).lower() in ('true', '1', 'yes')
        if self.setting_type == 'json':
            import json

            try:
                return json.loads(self.setting_value or '{}')
            except (ValueError, TypeError):
                return {}
        return self.setting_value

    def set_value(self, value):
        # Store as string (DB schema uses TEXT)
        self.setting_value = 'null' if value is None else str(value)

    def to_dict(self):
        return {
            'id': self.id,
            'setting_key': self.setting_key,
            'setting_value': self.setting_value,
            'typed_value': self.get_value(),
            'setting_type': self.setting_type,
            'description': self.description,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }
