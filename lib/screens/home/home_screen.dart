import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permit_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/sync_indicator.dart';
import '../../widgets/tab_switch_notification.dart';
import '../admin/user_management_screen.dart';
import '../admin/licensing_screen.dart';
import '../auth/login_screen.dart';
import '../permits/permit_form_screen.dart';
import '../permits/permit_list_screen.dart';
import '../reports/reports_screen.dart';
import '../search/search_screen.dart';
import '../search/search_history_screen.dart';
import '../settings/settings_screen.dart';
import '../settings/profile_screen.dart';
import '../../widgets/update_dialog.dart';
import 'widgets/glass_stat_card.dart';

/// الشاشة الرئيسية الرسمية لمديرية بلدية الهاشمية - قسم الإجازات
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  Future<void> _showNotifications() async {
    final user = context.read<AuthProvider>().user;
    if (user == null) return;
    final notifications = await SupabaseService.instance.fetchNotifications(user.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 420,
          child: notifications.isEmpty
              ? const Center(child: Text('لا توجد إشعارات جديدة', style: TextStyle(fontFamily: 'Cairo')))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (_, __) => const Divider(),
                  itemBuilder: (_, index) {
                    final item = notifications[index];
                    return ListTile(
                      leading: Icon(item['is_read'] == true ? Icons.notifications_none_rounded : Icons.notifications_active_rounded, color: AppColors.primary),
                      title: Text(item['title']?.toString() ?? 'إشعار', style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                      subtitle: Text(item['message']?.toString() ?? '', style: const TextStyle(fontFamily: 'Cairo')),
                      onTap: () => SupabaseService.instance.markNotificationAsRead(item['id'].toString()),
                    );
                  },
                ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<PermitProvider>().init();
        // فحص تلقائي لوجود تحديث للتطبيق (صامت إن لم يوجد)
        checkAndPromptUpdate(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = context.watch<AuthProvider>();
    final hasView = auth.user?.canView ?? true;

    final pages = [
      hasView ? _buildHomeDashboard(context) : _buildLockedView(context, auth), // 0: الرئيسية
      (hasView && (auth.user?.canAdd ?? true))
          ? const PermitFormScreen()
          : _buildLockedView(context, auth, isAddOnly: true), // 1: إضافة
      hasView ? const SearchScreen() : _buildLockedView(context, auth), // 2: علامة البحث
      hasView ? const ReportsScreen() : _buildLockedView(context, auth), // 3: تقارير
      const SettingsScreen(), // 4: الإعدادات
    ];

    return Scaffold(
      body: NotificationListener<TabSwitchNotification>(
        onNotification: (notification) {
          setState(() {
            _currentIndex = notification.index;
          });
          return true;
        },
        child: IndexedStack(
          index: _currentIndex,
          children: pages,
        ),
      ),

      // ---- الشريط السفلي العائم الزجاجي الفاخر ----
      bottomNavigationBar: SafeArea(
        child: Container(
          height: 68,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          decoration: BoxDecoration(
            color: isDark 
                ? const Color(0xFF1E293B).withValues(alpha: 0.85) 
                : Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: isDark 
                  ? Colors.white.withValues(alpha: 0.08) 
                  : AppColors.primary.withValues(alpha: 0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark 
                    ? Colors.black.withValues(alpha: 0.35) 
                    : Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: -2,
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'الرئيسية', isDark),
                    _buildNavItem(1, Icons.add_circle_rounded, Icons.add_circle_outline_rounded, 'إضافة', isDark),
                    _buildNavItem(2, Icons.search_rounded, Icons.search_rounded, 'البحث', isDark),
                    _buildNavItem(3, Icons.analytics_rounded, Icons.analytics_outlined, 'تقارير', isDark),
                    _buildNavItem(4, Icons.settings_rounded, Icons.settings_outlined, 'الإعدادات', isDark),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // 1. الواجهة الرئيسية الرسمية لـ مديرية بلدية الهاشمية
  // =========================================================
  Widget _buildHomeDashboard(BuildContext context) {
    final permitProvider = context.watch<PermitProvider>();
    final auth = context.watch<AuthProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final hasView = auth.user?.canView ?? true;
    final hasAdd = auth.user?.canAdd ?? true;
    final hasEdit = auth.user?.canEdit ?? true;

    // كارتات الخدمة الـ 4 الكبيرة الفاخرة
    final cards = <GlassStatCard>[
      GlassStatCard(
        icon: Icons.folder_special_rounded,
        title: 'الاجازات',
        gradientColors: hasView
            ? AppColors.cardGradients[0]
            : [Colors.grey.shade700, Colors.grey.shade600],
        onTap: () {
          if (!hasView) {
            _showNoPermissionSnackBar(context, 'مشاهدة البيانات');
          } else {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermitListScreen()));
          }
        },
      ),
      GlassStatCard(
        icon: Icons.search_rounded,
        title: 'بحث',
        gradientColors: hasView
            ? AppColors.cardGradients[1]
            : [Colors.grey.shade700, Colors.grey.shade600],
        onTap: () {
          if (!hasView) {
            _showNoPermissionSnackBar(context, 'مشاهدة البيانات');
          } else {
            setState(() => _currentIndex = 2);
          }
        },
      ),
      GlassStatCard(
        icon: Icons.add_circle_rounded,
        title: 'اضافة',
        gradientColors: (hasView && hasAdd)
            ? AppColors.cardGradients[2]
            : [Colors.grey.shade700, Colors.grey.shade600],
        onTap: () {
          if (!hasView) {
            _showNoPermissionSnackBar(context, 'مشاهدة البيانات');
          } else if (!hasAdd) {
            _showNoPermissionSnackBar(context, 'إضافة إجازات جديدة');
          } else {
            setState(() => _currentIndex = 1);
          }
        },
      ),
      GlassStatCard(
        icon: Icons.edit_note_rounded,
        title: 'تعديل',
        gradientColors: (hasView && hasEdit)
            ? AppColors.cardGradients[3]
            : [Colors.grey.shade700, Colors.grey.shade600],
        onTap: () {
          if (!hasView) {
            _showNoPermissionSnackBar(context, 'مشاهدة البيانات');
          } else if (!hasEdit) {
            _showNoPermissionSnackBar(context, 'تعديل البيانات');
          } else {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PermitListScreen(sortByRecentEdits: true)));
          }
        },
      ),
    ];

    final isWide = MediaQuery.of(context).size.width > 600;
    final ratio = isWide ? 1.2 : 0.95; // زيادة ارتفاع الكارتات لتبرز 3d

    return Scaffold(
      // ---- الشريط العلوي الرسمي والرائع ----
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: null,
        leading: Builder(
          builder: (context) => GestureDetector(
            onTap: () => Scaffold.of(context).openDrawer(),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: isDark 
                    ? Colors.white.withValues(alpha: 0.15) 
                    : AppColors.primary.withValues(alpha: 0.15),
                child: Text(
                  auth.user?.fullName.isNotEmpty == true ? auth.user!.fullName[0] : 'م',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white : AppColors.primary,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
          ),
        ),
        actions: [
          const Center(child: SyncIndicator()),
          const SizedBox(width: 8),
          // شمس (تغيير المظهر)
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            tooltip: 'تغيير المظهر',
            onPressed: () => context.read<ThemeProvider>().toggle(context),
          ),
          // جرس (الإشعارات)
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'الإشعارات',
            onPressed: _showNotifications,
          ),
          const SizedBox(width: 8),
        ],
      ),

      // القائمة الجانبية (Sidebar Drawer)
      drawer: _buildSidebar(context, auth),

      body: Stack(
        children: [
          // الفقاعة الزخرفية 1 (أعلى اليمين)
          Positioned(
            top: -120,
            right: -120,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.18),
                    AppColors.primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          // الفقاعة الزخرفية 2 (أسفل اليسار)
          Positioned(
            bottom: 40,
            left: -140,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.secondary.withValues(alpha: isDark ? 0.08 : 0.14),
                    AppColors.secondary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),

          // محتوى الصفحة الرئيسي
          RefreshIndicator(
            onRefresh: () => permitProvider.forceSync(),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---- 1. كارت الواجهة الرسمي: مديرية بلدية الهاشمية ----
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
                            : [AppColors.primary, AppColors.primaryDark],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                          ),
                          child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 34),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'مديرية بلدية الهاشمية',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                              SizedBox(height: 3),
                              Text(
                                'منظومة إجازات البناء الرقمية الموحدة',
                                style: TextStyle(color: Colors.white70, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ---- 2. عنوان "قسم الإجازات" المتركز بين خطين فاخرين ----
                  Row(
                    children: [
                      const Expanded(child: Divider(thickness: 1.5, endIndent: 12)),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.stars_rounded, color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'قسم الإجازات',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14.5,
                                color: isDark ? Colors.white : AppColors.primary,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Expanded(child: Divider(thickness: 1.5, indent: 12)),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ---- 3. شبكة الكروت الـ 4 الرسمية المتناسقة ----
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: isWide ? 4 : 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: ratio,
                    children: cards,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// القائمة الجانبية للتنقل (Drawer)
  Widget _buildSidebar(BuildContext context, AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // تدرج أزرق ملكي احترافي ومتناسق جداً للوضعين الليلي والنهاري
    final gradientColors = isDark
        ? [const Color(0xFF1B3D5E), const Color(0xFF0F172A)]
        : [const Color(0xFF1A365D), const Color(0xFF2B6CB0), const Color(0xFF2A5C8A)];

    final userRoleLabel = auth.isAdmin ? 'مدير النظام (Admin)' : 'موظف إدخال (Employee)';

    return Drawer(
      elevation: 16,
      backgroundColor: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: Column(
        children: [
          // ---- هيدر مخصص احترافي مع تدرج أزرق فاخر ----
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 20,
              bottom: 24,
              left: 20,
              right: 20,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(30),
                bottomRight: Radius.circular(30),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // صورة المستخدم الدائرية مع إطار مزدوج وتأثير إشراق
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(2.5),
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(3.5),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.white,
                          backgroundImage: AssetImage('assets/images/logo.jpg'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // معلومات البلدية والمنظومة بشكل تجميلي
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'جمهورية العراق',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'وزارة الإعمار والإسكان والبلديات',
                            style: TextStyle(color: Colors.white70, fontSize: 11.5, fontFamily: 'Cairo'),
                          ),
                          SizedBox(height: 3),
                          Text(
                            'بلدية الهاشمية',
                            style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Cairo'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // اسم الموظف ورتبته
                Text(
                  auth.user?.fullName ?? 'مستخدم بلدية الهاشمية',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16.5,
                    color: Colors.white,
                    fontFamily: 'Cairo',
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    userRoleLabel,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 18),
          
          // تسمية قسم القائمة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'التنقـل العام',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white60 : Colors.black45,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

          // خيارات القائمة الجانبية المصممة كـ بطاقات زجاجية فاخرة
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                _buildSidebarItem(
                  context: context,
                  icon: Icons.badge_rounded,
                  title: 'الملف الشخصي للمستخدم',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                const SizedBox(height: 8),
                _buildSidebarItem(
                  context: context,
                  icon: Icons.history_rounded,
                  title: 'سجل عمليات البحث المسبق',
                  color: AppColors.secondary,
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SearchHistoryScreen()),
                    );
                  },
                  isDark: isDark,
                ),
                
                if (auth.isAdmin) ...[
                  const SizedBox(height: 14),
                  const Divider(indent: 10, endIndent: 10),
                  const SizedBox(height: 6),
                  
                  // قسم الإشراف
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'إدارة النظام والأمن',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: isDark ? Colors.white60 : Colors.black45,
                        ),
                      ),
                    ),
                  ),
                  _buildSidebarItem(
                    context: context,
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'إدارة المستخدمين والصلاحيات',
                    color: AppColors.accent,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const UserManagementScreen()),
                      );
                    },
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  _buildSidebarItem(
                    context: context,
                    icon: Icons.verified_user_rounded,
                    title: 'إدارة التراخيص والأجهزة',
                    color: AppColors.secondary,
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LicensingScreen()),
                      );
                    },
                    isDark: isDark,
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),
          // زر تسجيل الخروج المصمم بذكاء وفخامة
          Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: () async {
                Navigator.pop(context);
                await auth.signOut();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.22),
                    width: 1.2,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, color: AppColors.danger, size: 20),
                    SizedBox(width: 10),
                    Text(
                      'تسجيل خروج من الحساب',
                      style: TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // تذييل الصفحة بمعلومات البلدية الرسمية
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'منظومة بلدية الهاشمية الرقمية v1.2.0',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white30 : Colors.black38,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ويجت مساعد لبناء عناصر القائمة بشكل فاخر ومرتفع قليلاً
  Widget _buildSidebarItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required Color color,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            fontFamily: 'Cairo',
          ),
        ),
        trailing: const Icon(Icons.arrow_back_ios_new_rounded, size: 13, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }




  

  void _showNoPermissionSnackBar(BuildContext context, String actionName) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('عذراً، لا تملك صلاحية ($actionName). يرجى مراجعة مسؤول النظام.', style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildLockedView(BuildContext context, AuthProvider auth, {bool isAddOnly = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: (isAddOnly ? AppColors.accent : AppColors.danger).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: (isAddOnly ? AppColors.accent : AppColors.danger).withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  isAddOnly ? Icons.add_moderator_rounded : Icons.lock_person_rounded,
                  color: isAddOnly ? AppColors.accent : AppColors.danger,
                  size: 64,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isAddOnly ? 'غير مسموح بالإدخال أو الإضافة' : 'الحساب غير مصرح له بالمشاهدة',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Cairo',
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isAddOnly 
                    ? 'تم إيقاف صلاحية إضافة إجازات جديدة لهذا الحساب من قبل مدير النظام.\nيرجى مراجعة الإدارة لتفعيل الصلاحية.'
                    : 'تم إيقاف صلاحية تصفح ومشاهدة البيانات لهذا الحساب من قبل مسؤول النظام.\nيرجى التواصل مع الإدارة لاستعادة الصلاحية.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5, 
                  color: isDark ? Colors.white70 : Colors.black54, 
                  height: 1.6, 
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData selectedIcon, IconData unselectedIcon, String label, bool isDark) {
    final isSelected = _currentIndex == index;
    final activeColor = index == 1 
        ? AppColors.secondary 
        : (index == 3 ? AppColors.accent : AppColors.primary);
    
    final color = isSelected 
        ? activeColor 
        : (isDark ? Colors.white54 : Colors.black.withValues(alpha: 0.65));

    return Expanded(
      child: InkWell(
        onTap: () {
          final auth = context.read<AuthProvider>();
          final hasView = auth.user?.canView ?? true;
          final hasAdd = auth.user?.canAdd ?? true;

          if (index != 4 && !hasView) {
            _showNoPermissionSnackBar(context, 'مشاهدة البيانات');
            return;
          }
          if (index == 1 && !hasAdd) {
            _showNoPermissionSnackBar(context, 'إضافة إجازات جديدة');
            return;
          }
          setState(() => _currentIndex = index);
        },
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected 
                ? activeColor.withValues(alpha: 0.12) 
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.15 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  isSelected ? selectedIcon : unselectedIcon,
                  color: color,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
