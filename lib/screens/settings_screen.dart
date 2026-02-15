import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('설정'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 화면 설정
              const Text(
                '화면 설정',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.view_compact,
                iconColor: const Color(0xFF6C63FF),
                title: '컴팩트 모드',
                subtitle: '화면 요소를 작게 표시합니다',
                value: provider.isCompactMode,
                enabled: true,
                onChanged: (value) => provider.setCompactMode(value),
              ),

              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.sms,
                iconColor: const Color(0xFF6C63FF),
                title: '문자 자동 등록',
                subtitle: '카드 결제 문자를 자동으로 지출 등록합니다',
                value: provider.isSmsAutoRegister,
                enabled: true,
                onChanged: (value) {
                  provider.setSmsAutoRegister(value);
                  // 문자 자동 등록을 끄면 팝업 알림도 끔
                  if (!value && provider.isPopupNotification) {
                    provider.setPopupNotification(false);
                  }
                },
              ),

              const SizedBox(height: 12),

              _buildSettingTile(
                icon: Icons.notifications_active,
                iconColor: const Color(0xFFFF9800),
                title: '팝업 알림',
                subtitle: provider.isSmsAutoRegister
                    ? '자동 등록 시 알림을 표시합니다'
                    : '문자 자동 등록을 먼저 활성화하세요',
                value: provider.isPopupNotification,
                enabled: provider.isSmsAutoRegister,
                onChanged: (value) => provider.setPopupNotification(value),
              ),

              const SizedBox(height: 20),

              // 앱 정보
              const Text(
                '앱 정보',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C3E50),
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '버전',
                      style: TextStyle(
                        fontSize: 16,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    Text(
                      '1.0.0',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: enabled ? onChanged : null,
              activeColor: const Color(0xFF6C63FF),
            ),
          ],
        ),
      ),
    );
  }
}
