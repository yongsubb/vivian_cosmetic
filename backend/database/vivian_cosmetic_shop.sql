-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Feb 07, 2026 at 09:16 AM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `vivian_cosmetic_shop`
--

-- --------------------------------------------------------

--
-- Table structure for table `activity_logs`
--

CREATE TABLE `activity_logs` (
  `id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL,
  `action` varchar(100) NOT NULL,
  `entity_type` varchar(50) DEFAULT NULL,
  `entity_id` int(11) DEFAULT NULL,
  `details` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`details`)),
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `is_archived` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `activity_logs`
--

INSERT INTO `activity_logs` (`id`, `user_id`, `action`, `entity_type`, `entity_id`, `details`, `ip_address`, `user_agent`, `is_archived`, `created_at`) VALUES
(1, 1, 'Added new product', 'product', 13, '{\"product_id\": 13, \"name\": \"vincent masarap\"}', '127.0.0.1', NULL, 0, '2025-12-22 05:09:49'),
(2, 1, 'Completed sale TXN-20251222051007', 'transaction', 1, '{\"transaction_id\": \"TXN-20251222051007\", \"total\": 1233.0}', '127.0.0.1', NULL, 0, '2025-12-22 05:10:07'),
(3, 1, 'Completed sale TXN-20251222052117', 'transaction', 2, '{\"transaction_id\": \"TXN-20251222052117\", \"total\": 13563.0}', '127.0.0.1', NULL, 0, '2025-12-22 05:21:17'),
(4, 1, 'Added new product', 'product', 14, '{\"product_id\": 14, \"name\": \"dsds\"}', '127.0.0.1', NULL, 0, '2025-12-23 18:32:33'),
(5, 1, 'Updated product', 'product', 14, '{\"product_id\": 14, \"name\": \"dsds\"}', '127.0.0.1', NULL, 0, '2025-12-23 18:33:16'),
(6, 1, 'Completed sale TXN-20251223184316', 'transaction', 3, '{\"transaction_id\": \"TXN-20251223184316\", \"total\": 1233.0}', '127.0.0.1', NULL, 0, '2025-12-23 18:43:16');

-- --------------------------------------------------------

--
-- Table structure for table `categories`
--

CREATE TABLE `categories` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` text DEFAULT NULL,
  `icon` varchar(50) DEFAULT NULL,
  `color` varchar(7) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `categories`
--

INSERT INTO `categories` (`id`, `name`, `description`, `icon`, `color`, `is_active`, `created_at`, `updated_at`) VALUES
(1, 'Cosmetics', 'Beauty products', NULL, NULL, 1, '2025-12-22 03:45:05', '2025-12-22 03:45:05'),
(29, 'Test Category', NULL, '????', NULL, 1, '2025-12-22 03:47:45', '2025-12-22 03:47:45'),
(33, 'Lipstick', 'Lipsticks and lip products', 'lips', '#E91E63', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11'),
(34, 'Foundation', 'Foundation and base makeup', 'face', '#F5E6DA', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11'),
(35, 'Skincare', 'Skincare products and treatments', 'spa', '#4CAF50', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11'),
(36, 'Eyeshadow', 'Eye makeup products', 'visibility', '#9C27B0', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11'),
(37, 'Mascara', 'Mascara and eye products', 'remove_red_eye', '#2196F3', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11'),
(38, 'Blush', 'Blush and cheek products', 'favorite', '#FF5722', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11'),
(39, 'Perfume', 'Fragrances and perfumes', 'air', '#C9A24D', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11'),
(40, 'Tools', 'Makeup brushes and tools', 'brush', '#607D8B', 1, '2025-12-22 05:03:11', '2025-12-22 05:03:11');

-- --------------------------------------------------------

--
-- Table structure for table `customers`
--

CREATE TABLE `customers` (
  `id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `address` text DEFAULT NULL,
  `loyalty_points` int(11) DEFAULT NULL,
  `total_purchases` decimal(12,2) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `loyalty_members`
--

CREATE TABLE `loyalty_members` (
  `id` int(11) NOT NULL,
  `customer_id` int(11) NOT NULL,
  `member_number` varchar(20) NOT NULL,
  `card_barcode` varchar(50) NOT NULL,
  `tier_id` int(11) DEFAULT NULL,
  `join_date` datetime DEFAULT NULL,
  `expiry_date` datetime DEFAULT NULL,
  `current_points` int(11) DEFAULT NULL,
  `lifetime_points` int(11) DEFAULT NULL,
  `card_issued` tinyint(1) DEFAULT NULL,
  `card_issued_date` datetime DEFAULT NULL,
  `card_status` varchar(20) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `loyalty_settings`
--

CREATE TABLE `loyalty_settings` (
  `id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `setting_type` varchar(20) DEFAULT NULL,
  `min_value` decimal(10,2) DEFAULT NULL,
  `max_value` decimal(10,2) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `last_modified_by` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `loyalty_tiers`
--

CREATE TABLE `loyalty_tiers` (
  `id` int(11) NOT NULL,
  `name` varchar(50) NOT NULL,
  `min_points` int(11) NOT NULL,
  `max_points` int(11) DEFAULT NULL,
  `discount_percent` decimal(5,2) DEFAULT NULL,
  `points_multiplier` decimal(3,2) DEFAULT NULL,
  `color` varchar(7) DEFAULT NULL,
  `icon` varchar(50) DEFAULT NULL,
  `benefits` text DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `loyalty_transactions`
--

CREATE TABLE `loyalty_transactions` (
  `id` int(11) NOT NULL,
  `member_id` int(11) NOT NULL,
  `transaction_id` int(11) DEFAULT NULL,
  `transaction_type` varchar(20) NOT NULL,
  `points` int(11) NOT NULL,
  `balance_after` int(11) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `reference_code` varchar(50) DEFAULT NULL,
  `adjusted_by` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `products`
--

CREATE TABLE `products` (
  `id` int(11) NOT NULL,
  `sku` varchar(50) NOT NULL,
  `barcode` varchar(50) DEFAULT NULL,
  `name` varchar(200) NOT NULL,
  `description` text DEFAULT NULL,
  `cost_price` decimal(10,2) NOT NULL,
  `selling_price` decimal(10,2) NOT NULL,
  `discount_percent` decimal(5,2) DEFAULT NULL,
  `stock_quantity` int(11) NOT NULL,
  `low_stock_threshold` int(11) DEFAULT NULL,
  `unit` varchar(20) DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `image_url` varchar(255) DEFAULT NULL,
  `is_active` tinyint(1) DEFAULT NULL,
  `is_featured` tinyint(1) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `products`
--

INSERT INTO `products` (`id`, `sku`, `barcode`, `name`, `description`, `cost_price`, `selling_price`, `discount_percent`, `stock_quantity`, `low_stock_threshold`, `unit`, `category_id`, `image_url`, `is_active`, `is_featured`, `created_at`, `updated_at`) VALUES
(13, 'PRD-0001', '2323232', 'vincent masarap', 'wala lng', 0.00, 1233.00, 0.00, 10, 10, 'pcs', 33, NULL, 1, 0, '2025-12-22 05:09:49', '2025-12-23 18:43:16'),
(14, 'PRD-0002', '32323222', 'dsds', NULL, 0.00, 232.00, 0.00, 11, 10, 'pcs', 33, NULL, 0, 0, '2025-12-23 18:32:33', '2025-12-23 18:33:16');

-- --------------------------------------------------------

--
-- Table structure for table `settings`
--

CREATE TABLE `settings` (
  `id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `setting_type` varchar(20) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `settings`
--

INSERT INTO `settings` (`id`, `setting_key`, `setting_value`, `setting_type`, `description`, `created_at`, `updated_at`) VALUES
(1, 'store_name', 'Vivian Cosmetic Shop', 'string', 'Store display name', '2025-12-22 04:35:56', '2025-12-22 04:35:56'),
(3, 'store_address', '123 Beauty Street, Manila, Philippines', 'string', 'Store address', '2025-12-22 04:35:56', '2025-12-22 04:35:56'),
(4, 'store_phone', '+63 912 345 6789', 'string', 'Store contact number', '2025-12-22 04:35:57', '2025-12-22 04:35:57'),
(6, 'store_email', 'info@viviancosmetics.com', 'string', 'Store email', '2025-12-22 04:35:57', '2025-12-22 04:35:57'),
(7, 'tax_rate', '0', 'number', 'Tax rate percentage', '2025-12-22 04:35:57', '2025-12-22 04:35:57'),
(8, 'currency', 'PHP', 'string', 'Currency code', '2025-12-22 04:35:57', '2025-12-22 04:35:57'),
(10, 'currency_symbol', '???', 'string', 'Currency symbol', '2025-12-22 04:35:57', '2025-12-22 04:35:57'),
(13, 'receipt_footer', 'Thank you for shopping at Vivian Cosmetic Shop!', 'string', 'Receipt footer message', '2025-12-22 04:35:57', '2025-12-22 04:35:57'),
(16, 'low_stock_threshold', '10', 'number', 'Low stock threshold', '2025-12-22 04:35:57', '2025-12-22 04:35:57'),
(18, 'low_stock_notification', 'True', 'boolean', 'Enable low stock notifications', '2025-12-22 04:35:57', '2025-12-22 04:35:57');

-- --------------------------------------------------------

--
-- Table structure for table `transactions`
--

CREATE TABLE `transactions` (
  `id` int(11) NOT NULL,
  `transaction_id` varchar(50) NOT NULL,
  `customer_id` int(11) DEFAULT NULL,
  `user_id` int(11) NOT NULL,
  `subtotal` decimal(12,2) NOT NULL,
  `discount_amount` decimal(12,2) DEFAULT NULL,
  `tax_amount` decimal(12,2) DEFAULT NULL,
  `total_amount` decimal(12,2) NOT NULL,
  `payment_method` varchar(20) NOT NULL,
  `amount_received` decimal(12,2) NOT NULL,
  `change_amount` decimal(12,2) DEFAULT NULL,
  `voucher_code` varchar(50) DEFAULT NULL,
  `voucher_discount` decimal(12,2) DEFAULT NULL,
  `status` varchar(20) DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `transactions`
--

INSERT INTO `transactions` (`id`, `transaction_id`, `customer_id`, `user_id`, `subtotal`, `discount_amount`, `tax_amount`, `total_amount`, `payment_method`, `amount_received`, `change_amount`, `voucher_code`, `voucher_discount`, `status`, `notes`, `created_at`, `updated_at`) VALUES
(1, 'TXN-20251222051007', NULL, 1, 1233.00, 0.00, 0.00, 1233.00, 'maya', 1233.00, 0.00, NULL, 0.00, 'completed', NULL, '2025-12-22 05:10:07', '2025-12-22 05:10:07'),
(2, 'TXN-20251222052117', NULL, 1, 13563.00, 0.00, 0.00, 13563.00, 'card', 13563.00, 0.00, NULL, 0.00, 'completed', NULL, '2025-12-22 05:21:17', '2025-12-22 05:21:17'),
(3, 'TXN-20251223184316', NULL, 1, 1233.00, 0.00, 0.00, 1233.00, 'cash', 1233.00, 0.00, NULL, 0.00, 'completed', NULL, '2025-12-23 18:43:16', '2025-12-23 18:43:16');

-- --------------------------------------------------------

--
-- Table structure for table `transaction_items`
--

CREATE TABLE `transaction_items` (
  `id` int(11) NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `product_name` varchar(200) NOT NULL,
  `product_sku` varchar(50) NOT NULL,
  `unit_price` decimal(10,2) NOT NULL,
  `quantity` int(11) NOT NULL,
  `discount_percent` decimal(5,2) DEFAULT NULL,
  `subtotal` decimal(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `transaction_items`
--

INSERT INTO `transaction_items` (`id`, `transaction_id`, `product_id`, `product_name`, `product_sku`, `unit_price`, `quantity`, `discount_percent`, `subtotal`) VALUES
(1, 1, 13, 'vincent masarap', 'PRD-0001', 1233.00, 1, 0.00, 1233.00),
(2, 2, 13, 'vincent masarap', 'PRD-0001', 1233.00, 11, 0.00, 13563.00),
(3, 3, 13, 'vincent masarap', 'PRD-0001', 1233.00, 1, 0.00, 1233.00);

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `password_hash` varchar(255) NOT NULL,
  `pin_hash` varchar(255) DEFAULT NULL,
  `first_name` varchar(50) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `nickname` varchar(50) DEFAULT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `address` varchar(500) DEFAULT NULL,
  `avatar_url` varchar(255) DEFAULT NULL,
  `role` varchar(20) NOT NULL,
  `is_active` tinyint(1) DEFAULT NULL,
  `is_logged_in` tinyint(1) DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `username`, `email`, `password_hash`, `pin_hash`, `first_name`, `last_name`, `nickname`, `phone`, `address`, `avatar_url`, `role`, `is_active`, `is_logged_in`, `last_login`, `created_at`, `updated_at`) VALUES
(1, 'admin', 'admin@test.com', 'scrypt:32768:8:1$RAA5WzMQnOjJNK0F$5afe4883f280a750df61bc3585c23b081f69d82d45baa4b0d7ea0f175ba66de73c666530f60046d2e650a3cb7be5d49818596b74aa1b460f9e75faac775bbbcc', 'scrypt:32768:8:1$KCx2Mx3N3bVyyQmJ$6e52e1cabde2da8443aedd9951c100b2dbba32d0d3cb8f100ed1e34c3084ff30fbdb9573b06b71b0a357ca59686711aaa0073bb44e996ed9d79dae36392926a1', 'Admin', 'Vincent', 'Vincent Kupal', NULL, NULL, NULL, 'supervisor', 1, 1, '2026-02-07 16:03:00', '2025-12-22 03:45:05', '2026-02-07 16:03:00'),
(2, 'cashier', 'cashier@test.com', 'scrypt:32768:8:1$1qugCYvMpPASkiqV$adbc1be6d94ca6e93d60ae3593bcf07d063870cae42887109050d5b069be2b2c3cd281c2b8413a55476122c1c38fdfb5c71617b115c8efb88965746dead2b38b', 'scrypt:32768:8:1$TMXKbeqWYA9CmrmX$c7b9677e9bc7c27ba8dcc8ec32b617bbcef4118572923f09b2996adc16f3b5d494421271012c73ac92cdbf05399830a1304f61a4d42abe241b9a8a0355a433b1', 'Test', 'Cashier', NULL, NULL, NULL, NULL, 'cashier', 0, 0, NULL, '2025-12-22 03:45:05', '2025-12-23 18:26:55'),
(3, 'cashier1', 'cashier1@viviancosmetics.com', 'scrypt:32768:8:1$9IqMfZH6CBqfBuUH$2a97a53fe2dd2d37fbef6aac1af768c81abd5d19617c37dc9aab4090ce8bfd38a64a865b2fe4811f35b9b20848c7aea743b4d553f010fba308f6f031d810aa4e', NULL, 'Maria', 'Santos', NULL, NULL, NULL, NULL, 'cashier', 0, 0, NULL, '2025-12-22 05:03:11', '2025-12-23 18:28:44');

-- --------------------------------------------------------

--
-- Table structure for table `vouchers`
--

CREATE TABLE `vouchers` (
  `id` int(11) NOT NULL,
  `code` varchar(50) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `discount_type` varchar(20) NOT NULL DEFAULT 'percentage',
  `discount_value` decimal(10,2) NOT NULL,
  `min_purchase` decimal(10,2) DEFAULT 0.00,
  `max_discount` decimal(10,2) DEFAULT NULL,
  `usage_limit` int(11) DEFAULT NULL,
  `used_count` int(11) DEFAULT 0,
  `is_active` tinyint(1) DEFAULT 1,
  `valid_from` datetime DEFAULT NULL,
  `valid_until` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `vouchers`
--

INSERT INTO `vouchers` (`id`, `code`, `description`, `discount_type`, `discount_value`, `min_purchase`, `max_discount`, `usage_limit`, `used_count`, `is_active`, `valid_from`, `valid_until`, `created_at`, `updated_at`) VALUES
(1, 'BEAUTY10', '10% off on all purchases', 'percentage', 10.00, 500.00, NULL, NULL, 0, 1, '2025-12-19 03:23:51', '2026-12-19 03:23:51', '2025-12-19 03:23:51', '2025-12-19 03:23:51'),
(2, 'WELCOME20', '20% off for new customers', 'percentage', 20.00, 1000.00, NULL, NULL, 0, 1, '2025-12-19 03:23:51', '2026-06-19 03:23:51', '2025-12-19 03:23:51', '2025-12-19 03:23:51'),
(3, 'SAVE100', 'PHP 100 off on orders over 1500', 'fixed', 100.00, 1500.00, NULL, NULL, 0, 1, '2025-12-19 03:23:51', '2026-03-19 03:23:51', '2025-12-19 03:23:51', '2025-12-19 03:23:51');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `user_id` (`user_id`);

--
-- Indexes for table `categories`
--
ALTER TABLE `categories`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `customers`
--
ALTER TABLE `customers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ix_customers_phone` (`phone`),
  ADD UNIQUE KEY `ix_customers_email` (`email`);

--
-- Indexes for table `loyalty_members`
--
ALTER TABLE `loyalty_members`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `customer_id` (`customer_id`),
  ADD UNIQUE KEY `member_number` (`member_number`),
  ADD UNIQUE KEY `card_barcode` (`card_barcode`),
  ADD KEY `tier_id` (`tier_id`);

--
-- Indexes for table `loyalty_settings`
--
ALTER TABLE `loyalty_settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `setting_key` (`setting_key`),
  ADD KEY `last_modified_by` (`last_modified_by`);

--
-- Indexes for table `loyalty_tiers`
--
ALTER TABLE `loyalty_tiers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `loyalty_transactions`
--
ALTER TABLE `loyalty_transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `member_id` (`member_id`),
  ADD KEY `transaction_id` (`transaction_id`),
  ADD KEY `adjusted_by` (`adjusted_by`);

--
-- Indexes for table `products`
--
ALTER TABLE `products`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ix_products_sku` (`sku`),
  ADD UNIQUE KEY `ix_products_barcode` (`barcode`),
  ADD KEY `category_id` (`category_id`);

--
-- Indexes for table `settings`
--
ALTER TABLE `settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ix_settings_setting_key` (`setting_key`);

--
-- Indexes for table `transactions`
--
ALTER TABLE `transactions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ix_transactions_transaction_id` (`transaction_id`),
  ADD KEY `customer_id` (`customer_id`),
  ADD KEY `user_id` (`user_id`);

--
-- Indexes for table `transaction_items`
--
ALTER TABLE `transaction_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `transaction_id` (`transaction_id`),
  ADD KEY `product_id` (`product_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `ix_users_username` (`username`),
  ADD UNIQUE KEY `email` (`email`);

--
-- Indexes for table `vouchers`
--
ALTER TABLE `vouchers`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `idx_code` (`code`),
  ADD KEY `idx_is_active` (`is_active`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `activity_logs`
--
ALTER TABLE `activity_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `categories`
--
ALTER TABLE `categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=41;

--
-- AUTO_INCREMENT for table `customers`
--
ALTER TABLE `customers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `loyalty_members`
--
ALTER TABLE `loyalty_members`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `loyalty_settings`
--
ALTER TABLE `loyalty_settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `loyalty_tiers`
--
ALTER TABLE `loyalty_tiers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `loyalty_transactions`
--
ALTER TABLE `loyalty_transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `products`
--
ALTER TABLE `products`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=15;

--
-- AUTO_INCREMENT for table `settings`
--
ALTER TABLE `settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT for table `transactions`
--
ALTER TABLE `transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `transaction_items`
--
ALTER TABLE `transaction_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `vouchers`
--
ALTER TABLE `vouchers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD CONSTRAINT `activity_logs_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `loyalty_members`
--
ALTER TABLE `loyalty_members`
  ADD CONSTRAINT `loyalty_members_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `loyalty_members_ibfk_2` FOREIGN KEY (`tier_id`) REFERENCES `loyalty_tiers` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `loyalty_settings`
--
ALTER TABLE `loyalty_settings`
  ADD CONSTRAINT `loyalty_settings_ibfk_1` FOREIGN KEY (`last_modified_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `loyalty_transactions`
--
ALTER TABLE `loyalty_transactions`
  ADD CONSTRAINT `loyalty_transactions_ibfk_1` FOREIGN KEY (`member_id`) REFERENCES `loyalty_members` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `loyalty_transactions_ibfk_2` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `loyalty_transactions_ibfk_3` FOREIGN KEY (`adjusted_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `products`
--
ALTER TABLE `products`
  ADD CONSTRAINT `products_ibfk_1` FOREIGN KEY (`category_id`) REFERENCES `categories` (`id`);

--
-- Constraints for table `transactions`
--
ALTER TABLE `transactions`
  ADD CONSTRAINT `transactions_ibfk_1` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`),
  ADD CONSTRAINT `transactions_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`);

--
-- Constraints for table `transaction_items`
--
ALTER TABLE `transaction_items`
  ADD CONSTRAINT `transaction_items_ibfk_1` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`id`),
  ADD CONSTRAINT `transaction_items_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`id`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
