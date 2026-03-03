"""
Insert default loyalty tiers into the database
"""
import sys
import os
# Add backend directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app import app, db
from models.loyalty import LoyaltyTier
from datetime import datetime

with app.app_context():
    # Check if tiers already exist
    existing_tiers = LoyaltyTier.query.count()
    
    if existing_tiers > 0:
        print(f"⚠️ {existing_tiers} tiers already exist in database.")
        response = input("Delete existing tiers and recreate? (yes/no): ")
        if response.lower() != 'yes':
            print("Cancelled.")
            exit()
        
        # Delete existing tiers
        LoyaltyTier.query.delete()
        db.session.commit()
        print("✅ Deleted existing tiers")
    
    # Create default tiers
    tiers = [
        LoyaltyTier(
            id=1,
            name='Bronze',
            min_points=1,
            max_points=99,
            discount_percent=5.00,
            points_multiplier=1.00,
            color='#CD7F32',
            icon='stars',
            benefits='5% discount on purchases',
            is_active=True
        ),
        LoyaltyTier(
            id=2,
            name='Silver',
            min_points=100,
            max_points=499,
            discount_percent=10.00,
            points_multiplier=1.50,
            color='#C0C0C0',
            icon='star',
            benefits='10% discount on purchases',
            is_active=True
        ),
        LoyaltyTier(
            id=3,
            name='Gold',
            min_points=500,
            max_points=999,
            discount_percent=15.00,
            points_multiplier=2.00,
            color='#FFD700',
            icon='workspace_premium',
            benefits='15% discount on purchases',
            is_active=True
        ),
        LoyaltyTier(
            id=4,
            name='Platinum',
            min_points=1000,
            max_points=None,
            discount_percent=20.00,
            points_multiplier=2.00,
            color='#E5E4E2',
            icon='workspace_premium',
            benefits='20% discount on purchases',
            is_active=True
        )
    ]
    
    for tier in tiers:
        db.session.add(tier)
    
    db.session.commit()
    
    print("\n✅ Successfully inserted loyalty tiers!")
    print("\nTiers in database:")
    for tier in LoyaltyTier.query.all():
        print(f"  - {tier.name}: {tier.min_points}-{tier.max_points or '∞'} points, {tier.discount_percent}% discount")
