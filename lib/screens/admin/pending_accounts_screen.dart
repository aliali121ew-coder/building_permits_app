import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../models/user_model.dart';
import '../../services/cloudflare_api_service.dart';
import '../../widgets/professional_back_button.dart';
import '../../widgets/user_avatar.dart';

/// طلبات الحسابات الجديدة بانتظار موافقة المدير
class PendingAccountsScreen extends StatefulWidget {
  const PendingAccountsScreen({super.key});

  @override
  State<PendingAccountsScreen> createState() => _PendingAccountsScreenState();
}

class _PendingAccountsScreenState extends State<PendingAccountsScreen> {
  final _api = CloudflareApiService.instance;
  late Future<List<UserModel>> _future;
  final _busy = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _future = _api.fetchAllProfiles().then((all) => all.where((u) => u.approvalStatus == 'pending').toList());
    });
  }

  Future<void> _act(UserModel u, Future<void> Function() action, String done) async {
    setState(() => _busy.add(u.id));
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(done, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.secondary,
      ));
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString(), style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _busy.remove(u.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const ProfessionalBackButton(),
        title: const Text('طلبات الحسابات الجديدة'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: FutureBuilder<List<UserModel>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final users = snap.data ?? const [];
          if (users.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.verified_rounded, size: 56, color: AppColors.secondary),
                  SizedBox(height: 10),
                  Text('لا توجد طلبات بانتظار الموافقة', style: TextStyle(fontFamily: 'Cairo')),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => _load(),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: users.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final u = users[i];
                final busy = _busy.contains(u.id);
                return Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            UserAvatar(path: u.avatarPath, name: u.fullName),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text(u.email ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  if (u.licenseStartAt != null)
                                    Text('طلب في ${AppDateUtils.formatDate(u.licenseStartAt!)}',
                                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.secondary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: busy
                                    ? null
                                    : () => _act(u, () => _api.approveUser(u.id), 'تمت الموافقة على ${u.fullName}'),
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('موافقة'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.danger,
                                  side: const BorderSide(color: AppColors.danger),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                                onPressed: busy
                                    ? null
                                    : () => _act(u, () => _api.pauseLicense(userId: u.id, paused: true),
                                        'تم رفض حساب ${u.fullName}'),
                                icon: const Icon(Icons.block_rounded, size: 18),
                                label: const Text('رفض'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
