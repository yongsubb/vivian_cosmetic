import 'package:flutter/material.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_typography.dart';
import '../services/api_service.dart';

/// Widget for showing pending account approvals to supervisors
class PendingApprovalsWidget extends StatefulWidget {
  final VoidCallback? onApprovalChanged;

  const PendingApprovalsWidget({super.key, this.onApprovalChanged});

  @override
  State<PendingApprovalsWidget> createState() => _PendingApprovalsWidgetState();
}

class _PendingApprovalsWidgetState extends State<PendingApprovalsWidget> {
  List<Map<String, dynamic>> _pendingAccounts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPendingAccounts();
  }

  Future<void> _loadPendingAccounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ApiService();
      final response = await apiService.get<List<dynamic>>(
        '/auth/pending-accounts',
        fromJsonT: (data) => data as List<dynamic>,
      );

      if (!mounted) return;

      if (response.success) {
        setState(() {
          _pendingAccounts = List<Map<String, dynamic>>.from(
            response.data ?? const [],
          );
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Failed to load pending accounts';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Error loading pending accounts';
        _isLoading = false;
      });
    }
  }

  Future<void> _approveAccount(int userId, String fullName) async {
    try {
      final apiService = ApiService();
      final response = await apiService.post<Map<String, dynamic>>(
        '/auth/approve-account/$userId',
      );

      if (!mounted) return;

      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fullName has been approved'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadPendingAccounts();
        widget.onApprovalChanged?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Failed to approve account'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _rejectAccount(int userId, String fullName) async {
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject Account'),
        content: Text(
          'Are you sure you want to reject the account request for $fullName? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final apiService = ApiService();
      final response = await apiService.post<Map<String, dynamic>>(
        '/auth/reject-account/$userId',
      );

      if (!mounted) return;

      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Account request for $fullName has been rejected'),
            backgroundColor: AppColors.warning,
          ),
        );
        _loadPendingAccounts();
        widget.onApprovalChanged?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message ?? 'Failed to reject account'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: AppTypography.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadPendingAccounts,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_pendingAccounts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.person_add,
                    color: AppColors.warning,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Account Approvals',
                        style: AppTypography.heading4,
                      ),
                      Text(
                        '${_pendingAccounts.length} account(s) waiting for approval',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _loadPendingAccounts,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            ...List.generate(_pendingAccounts.length, (index) {
              final account = _pendingAccounts[index];
              return _buildAccountItem(account);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountItem(Map<String, dynamic> account) {
    final fullName = account['full_name'] ?? 'Unknown';
    final username = account['username'] ?? '';
    final email = account['email'];
    final phone = account['phone'];
    final address = account['address'];
    final userId = account['id'] as int;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Text(
              fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
              style: AppTypography.heading4.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 16),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fullName, style: AppTypography.labelLarge),
                const SizedBox(height: 4),
                Text(
                  '@$username',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textLight,
                  ),
                ),
                if (email != null && email.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      email,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                if (phone != null && phone.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      phone,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
                if (address != null && address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      address,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textLight,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Reject button
              IconButton(
                onPressed: () => _rejectAccount(userId, fullName),
                icon: const Icon(Icons.close),
                color: AppColors.error,
                tooltip: 'Reject',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.error.withValues(alpha: 0.1),
                ),
              ),
              const SizedBox(width: 8),
              // Approve button
              IconButton(
                onPressed: () => _approveAccount(userId, fullName),
                icon: const Icon(Icons.check),
                color: AppColors.success,
                tooltip: 'Approve',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.success.withValues(alpha: 0.1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Notification badge for pending approvals
class PendingApprovalsBadge extends StatefulWidget {
  final Widget child;

  const PendingApprovalsBadge({super.key, required this.child});

  @override
  State<PendingApprovalsBadge> createState() => _PendingApprovalsBadgeState();
}

class _PendingApprovalsBadgeState extends State<PendingApprovalsBadge> {
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _loadPendingCount();
  }

  Future<void> _loadPendingCount() async {
    try {
      final apiService = ApiService();
      final response = await apiService.get<List<dynamic>>(
        '/auth/pending-accounts',
        fromJsonT: (data) => data as List<dynamic>,
      );

      if (!mounted) return;

      if (response.success) {
        setState(() {
          _pendingCount = (response.data ?? const []).length;
        });
      }
    } catch (e) {
      // Silently fail - badge just won't show
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingCount == 0) {
      return widget.child;
    }

    return Badge(
      label: Text(_pendingCount.toString()),
      backgroundColor: AppColors.warning,
      child: widget.child,
    );
  }
}
