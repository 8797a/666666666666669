import 'dart:io';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 用户信息模型
class UserProfile {
  final String? avatarPath;
  final String username;
  final String memberType;
  final DateTime? memberExpiry;

  UserProfile({
    this.avatarPath,
    this.username = '游客',
    this.memberType = '普通会员',
    this.memberExpiry,
  });

  UserProfile copyWith({
    String? avatarPath,
    String? username,
    String? memberType,
    DateTime? memberExpiry,
  }) {
    return UserProfile(
      avatarPath: avatarPath ?? this.avatarPath,
      username: username ?? this.username,
      memberType: memberType ?? this.memberType,
      memberExpiry: memberExpiry ?? this.memberExpiry,
    );
  }

  bool get isVip => memberType != '普通会员';
  
  bool get isExpired {
    if (memberExpiry == null) return true;
    return DateTime.now().isAfter(memberExpiry!);
  }
}

// 状态管理
class UserProfileNotifier extends Notifier<UserProfile> {
  @override
  UserProfile build() {
    _loadProfile();
    return UserProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    state = UserProfile(
      avatarPath: prefs.getString('user_avatar'),
      username: prefs.getString('user_name') ?? '游客',
      memberType: prefs.getString('member_type') ?? '普通会员',
      memberExpiry: prefs.getString('member_expiry') != null
          ? DateTime.parse(prefs.getString('member_expiry')!)
          : null,
    );
  }

  Future<void> updateAvatar(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_avatar', path);
    state = state.copyWith(avatarPath: path);
  }

  Future<void> updateUsername(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    state = state.copyWith(username: name);
  }
}

final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(() {
  return UserProfileNotifier();
});

class ProfileCenterView extends ConsumerWidget {
  const ProfileCenterView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userProfile = ref.watch(userProfileProvider);
    
    return CommonScaffold(
      title: appLocalizations.requests,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMemberCard(context, ref, userProfile),
              const SizedBox(height: 24),
              _buildLogoutButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCard(BuildContext context, WidgetRef ref, UserProfile profile) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: profile.isVip
              ? [
                  const Color(0xFFFFD700),
                  const Color(0xFFFFA500),
                ]
              : [
                  context.colorScheme.primaryContainer,
                  context.colorScheme.secondaryContainer,
                ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            // 头像（带皇冠）
            _buildAvatar(context, ref, profile),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    profile.username,
                    style: context.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: profile.isVip ? Colors.white : null,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.edit,
                    size: 20,
                    color: profile.isVip ? Colors.white70 : null,
                  ),
                  onPressed: () => _showEditNameDialog(context, ref, profile.username),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: profile.isVip
                    ? Colors.white.withOpacity(0.3)
                    : context.colorScheme.surface.withOpacity(0.5),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: profile.isVip ? Colors.white : context.colorScheme.outline,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (profile.isVip)
                    Icon(
                      Icons.star,
                      size: 20,
                      color: profile.isExpired ? Colors.grey : Colors.white,
                    ),
                  if (profile.isVip) const SizedBox(width: 8),
                  Text(
                    profile.memberType,
                    style: context.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: profile.isVip ? Colors.white : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (profile.memberExpiry != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: profile.isVip
                      ? Colors.white.withOpacity(0.2)
                      : context.colorScheme.surface.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 18,
                          color: profile.isVip ? Colors.white70 : null,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '会员有效期',
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: profile.isVip ? Colors.white70 : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _formatDate(profile.memberExpiry!),
                      style: context.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: profile.isVip
                            ? (profile.isExpired ? Colors.red[300] : Colors.white)
                            : (profile.isExpired ? Colors.red : null),
                      ),
                    ),
                    if (profile.isExpired) ...[
                      const SizedBox(height: 8),
                      Text(
                        '已过期',
                        style: context.textTheme.bodySmall?.copyWith(
                          color: Colors.red[300],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(BuildContext context, WidgetRef ref, UserProfile profile) {
    return GestureDetector(
      onTap: () => _pickImage(context, ref),
      child: SizedBox(
        width: 120,
        height: 140, // 增加高度以容纳皇冠
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 皇冠（VIP 专属，位于头像上方）
            if (profile.isVip)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Icon(
                    Icons.workspace_premium,
                    size: 40,
                    color: profile.isExpired ? Colors.grey : Colors.white,
                  ),
                ),
              ),
            // 头像
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: profile.isVip ? Colors.white : context.colorScheme.outline,
                    width: 4,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: profile.avatarPath != null && File(profile.avatarPath!).existsSync()
                      ? Image.file(
                          File(profile.avatarPath!),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                context.colorScheme.primary,
                                context.colorScheme.secondary,
                              ],
                            ),
                          ),
                          child: Icon(
                            Icons.person,
                            size: 60,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
            // 相机按钮
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: profile.isVip ? Colors.white : context.colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: profile.isVip 
                        ? const Color(0xFFFFD700) 
                        : context.colorScheme.surface,
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.camera_alt,
                  size: 20,
                  color: profile.isVip ? const Color(0xFFFFD700) : Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(BuildContext context, WidgetRef ref) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );

    if (image != null) {
      await ref.read(userProfileProvider.notifier).updateAvatar(image.path);
    }
  }

  void _showEditNameDialog(BuildContext context, WidgetRef ref, String currentName) {
    final controller = TextEditingController(text: currentName);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('修改用户名'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: '请输入用户名',
            border: OutlineInputBorder(),
          ),
          maxLength: 20,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                ref.read(userProfileProvider.notifier).updateUsername(controller.text.trim());
                Navigator.pop(context);
              }
            },
            child: Text('确定'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}年${date.month}月${date.day}日';
  }

  Widget _buildLogoutButton(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      child: OutlinedButton.icon(
        onPressed: () => _handleLogout(context),
        icon: const Icon(Icons.logout),
        label: const Text('退出登录'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          side: BorderSide(color: Colors.red.withOpacity(0.5)),
          foregroundColor: Colors.red,
        ),
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出登录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('退出'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isLoggedIn', false);
      
      if (context.mounted) {
        // 重启应用以返回登录页面
        // 这里使用一个简单的方法：关闭当前窗口
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已退出登录，请重新启动应用'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
