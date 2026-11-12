import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/cloudflare_api_service.dart';
import '../../widgets/professional_back_button.dart';

/// سجل نشاط النظام للمدير: كل تسجيل حساب، دخول، تغيير كلمة مرور، تعديل ملف،
/// صلاحيات، قفل/إيقاف، وكل إضافة/تعديل/حذف للإجازات من جميع الموظفين.
class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final _api = CloudflareApiService.instance;
  final _items = <Map<String, dynamic>>[];
  bool _loading = false;
  bool _hasMore = true;
  String? _error;
  String _filter = 'all'; // all / account / permit

  static const _actions = <String, (String, IconData, Color)>{
    'register': ('إنشاء حساب جديد', Icons.person_add_alt_1_rounded, AppColors.info),
    'login': ('تسجيل دخول', Icons.login_rounded, Colors.blueGrey),
    'password_change': ('تغيير كلمة المرور', Icons.password_rounded, Colors.orange),
    'password_reset': ('إعادة تعيين كلمة مرور', Icons.lock_reset_rounded, Colors.deepOrange),
    'profile_update': ('تعديل الملف الشخصي', Icons.badge_rounded, AppColors.primary),
    'permissions_update': ('تعديل الصلاحيات', Icons.admin_panel_settings_rounded, AppColors.accent),
    'approve': ('موافقة على حساب', Icons.verified_rounded, AppColors.secondary),
    'suspend': ('إيقاف حساب', Icons.block_rounded, AppColors.danger),
    'activate': ('تفعيل حساب', Icons.check_circle_rounded, AppColors.secondary),
    'lock': ('قفل حساب', Icons.lock_rounded, AppColors.danger),
    'unlock': ('فك قفل حساب', Icons.lock_open_rounded, AppColors.secondary),
    'permit_insert': ('إضافة إجازة', Icons.add_circle_rounded, AppColors.secondary),
    'permit_update': ('تعديل إجازة', Icons.edit_rounded, AppColors.info),
    'permit_delete': ('حذف إجازة', Icons.delete_rounded, AppColors.danger),
    'permit_restore': ('استعادة إجازة', Icons.restore_rounded, AppColors.secondary),
  };

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _hasMore = true;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _api.fetchActivity(before: _items.isEmpty ? null : _items.last['created_at']?.toString());
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length >= 50;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _time(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _filter == 'all' ? _items : _items.where((e) => e['kind'] == _filter).toList();

    return Scaffold(
      appBar: AppBar(
        leading: const ProfessionalBackButton(),
        title: const Text('سجل النشاط'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh_rounded))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'all', label: Text('الكل')),
                ButtonSegment(value: 'account', label: Text('الحسابات')),
                ButtonSegment(value: 'permit', label: Text('الإجازات')),
              ],
              selected: {_filter},
              onSelectionChanged: (s) => setState(() => _filter = s.first),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.pixels > n.metrics.maxScrollExtent - 300) _loadMore();
                  return false;
                },
                child: ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: visible.length + 1,
                  itemBuilder: (context, i) {
                    if (i == visible.length) {
                      if (_error != null) {
                        return Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_error!,
                              textAlign: TextAlign.center, style: const TextStyle(color: AppColors.danger)),
                        );
                      }
                      if (_loading) {
                        return const Padding(
                            padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                      }
                      if (visible.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(40),
                          child: Center(child: Text('لا يوجد نشاط بعد')),
                        );
                      }
                      return const SizedBox.shrink();
                    }
                    final e = visible[i];
                    final (label, icon, color) = _actions[e['action']] ??
                        (e['action']?.toString() ?? '', Icons.info_outline_rounded, Colors.grey);
                    final actor = (e['actor_name'] ?? '').toString();
                    final target = (e['target_name'] ?? '').toString();
                    final details = (e['details'] ?? '').toString();
                    final isPermit = e['kind'] == 'permit';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.14),
                          child: Icon(icon, color: color, size: 20),
                        ),
                        title: Text(
                          isPermit ? '$label ${details.isNotEmpty ? details : ''}' : label,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (actor.isNotEmpty) 'بواسطة: $actor',
                                if (target.isNotEmpty && target != actor)
                                  (isPermit ? 'الإجازة: $target' : 'الحساب: $target'),
                              ].join(' • '),
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (!isPermit && details.isNotEmpty)
                              Text(details, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            Text(_time(e['created_at']?.toString()),
                                style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
