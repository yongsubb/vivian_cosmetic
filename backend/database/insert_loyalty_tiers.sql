-- Insert default loyalty tiers for Vivian Cosmetic Shop
-- Four tiers with 5%, 10%, 15%, and 20% discounts

INSERT INTO `loyalty_tiers` (`id`, `name`, `min_points`, `max_points`, `discount_percent`, `points_multiplier`, `color`, `icon`, `benefits`, `is_active`, `created_at`, `updated_at`) VALUES
(1, 'Bronze', 1, 99, 5.00, 1.00, '#CD7F32', 'stars', '5% discount on purchases', 1, NOW(), NOW()),
(2, 'Silver', 100, 499, 10.00, 1.50, '#C0C0C0', 'star', '10% discount on purchases', 1, NOW(), NOW()),
(3, 'Gold', 500, 999, 15.00, 2.00, '#FFD700', 'workspace_premium', '15% discount on purchases', 1, NOW(), NOW()),
(4, 'Platinum', 1000, NULL, 20.00, 2.00, '#E5E4E2', 'workspace_premium', '20% discount on purchases', 1, NOW(), NOW());
