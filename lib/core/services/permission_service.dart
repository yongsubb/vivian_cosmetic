import 'package:flutter/material.dart';

/// Role-based access control utilities
class PermissionService {
  // Role constants
  static const String roleSupervisor = 'supervisor';
  static const String roleCashier = 'cashier';

  /// Check if user has supervisor role
  static bool isSupervisor(String? role) {
    return role?.toLowerCase() == roleSupervisor;
  }

  /// Check if user has cashier role
  static bool isCashier(String? role) {
    return role?.toLowerCase() == roleCashier;
  }

  /// Check if user can access a specific feature
  static bool canAccess(String? role, PermissionFeature feature) {
    if (role == null) return false;

    switch (feature) {
      // Supervisor-only features
      case PermissionFeature.manageUsers:
      case PermissionFeature.viewReports:
      case PermissionFeature.manageSettings:
      case PermissionFeature.manageLoyalty:
      case PermissionFeature.manageProducts:
      case PermissionFeature.deleteActivityLog:
      case PermissionFeature.viewAllTransactions:
        return isSupervisor(role);

      // Cashier and supervisor features
      case PermissionFeature.createTransaction:
      case PermissionFeature.viewOwnTransactions:
      case PermissionFeature.scanBarcode:
        return isCashier(role) || isSupervisor(role);

      // Public features (both roles)
      case PermissionFeature.viewDashboard:
      case PermissionFeature.viewProfile:
        return true;
    }
  }

  /// Show unauthorized access dialog
  static void showUnauthorizedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Access Denied'),
        content: const Text(
          'You do not have permission to access this feature. '
          'Please contact your supervisor.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Permission features that can be checked
enum PermissionFeature {
  // Supervisor only
  manageUsers,
  viewReports,
  manageSettings,
  manageLoyalty,
  manageProducts,
  deleteActivityLog,
  viewAllTransactions,

  // Cashier and supervisor
  createTransaction,
  viewOwnTransactions,
  scanBarcode,

  // All users
  viewDashboard,
  viewProfile,
}
