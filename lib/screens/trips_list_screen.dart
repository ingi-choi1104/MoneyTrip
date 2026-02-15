import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/expense_provider.dart';
import 'create_trip_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';

class TripsListScreen extends StatelessWidget {
  const TripsListScreen({Key? key}) : super(key: key);

  // 국가별 국기 이모지
  static const Map<String, String> _countryFlags = {
    '대한민국': '🇰🇷',
    '그리스': '🇬🇷',
    '노르웨이': '🇳🇴',
    '남아프리카공화국': '🇿🇦',
    '네덜란드': '🇳🇱',
    '뉴질랜드': '🇳🇿',
    '대만': '🇹🇼',
    '독일': '🇩🇪',
    '러시아': '🇷🇺',
    '말레이시아': '🇲🇾',
    '멕시코': '🇲🇽',
    '모로코': '🇲🇦',
    '미국': '🇺🇸',
    '베트남': '🇻🇳',
    '벨기에': '🇧🇪',
    '브라질': '🇧🇷',
    '사우디아라비아': '🇸🇦',
    '스위스': '🇨🇭',
    '스웨덴': '🇸🇪',
    '스페인': '🇪🇸',
    '싱가포르': '🇸🇬',
    '아랍에미리트': '🇦🇪',
    '아르헨티나': '🇦🇷',
    '에콰도르': '🇪🇨',
    '영국': '🇬🇧',
    '오스트리아': '🇦🇹',
    '이집트': '🇪🇬',
    '이탈리아': '🇮🇹',
    '인도': '🇮🇳',
    '인도네시아': '🇮🇩',
    '일본': '🇯🇵',
    '중국': '🇨🇳',
    '체코': '🇨🇿',
    '캐나다': '🇨🇦',
    '크로아티아': '🇭🇷',
    '태국': '🇹🇭',
    '터키': '🇹🇷',
    '페루': '🇵🇪',
    '포르투갈': '🇵🇹',
    '폴란드': '🇵🇱',
    '프랑스': '🇫🇷',
    '필리핀': '🇵🇭',
    '호주': '🇦🇺',
  };

  String _getCountryFlag(String country) {
    return _countryFlags[country] ?? '🌍';
  }

  void _deleteTrip(BuildContext context, int tripId, String tripName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('여행 삭제'),
        content: Text(
          '$tripName을(를) 삭제하시겠습니까?\n\n이 여행의 모든 지출 및 예산 내역이 함께 삭제됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              final provider = Provider.of<ExpenseProvider>(
                context,
                listen: false,
              );
              provider.deleteTrip(tripId);
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('$tripName이(가) 삭제되었습니다')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTripGrid(BuildContext context, ExpenseProvider provider) {
    final dateFormat = DateFormat('MM.dd');
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.3,
      ),
      itemCount: provider.trips.length,
      itemBuilder: (context, index) {
        final trip = provider.trips[index];
        final isActive = provider.activeTrip?.id == trip.id;
        return InkWell(
          onTap: () async {
            await provider.setActiveTrip(trip.id!);
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          },
          onLongPress: () => _deleteTrip(context, trip.id!, trip.name),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: isActive
                  ? Border.all(color: const Color(0xFF6C63FF), width: 2)
                  : null,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _getCountryFlag(trip.country),
                      style: const TextStyle(fontSize: 24),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        trip.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  trip.country,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const Spacer(),
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 10, color: Colors.grey[500]),
                    const SizedBox(width: 3),
                    Text(
                      '${dateFormat.format(trip.startDate)}-${dateFormat.format(trip.endDate)}',
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    ),
                  ],
                ),
                if (isActive) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C63FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '활성',
                      style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('여행 목록'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          if (provider.trips.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.flight_takeoff,
                    size: 100,
                    color: Colors.grey[300],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '아직 여행이 없습니다',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '새로운 여행을 만들어보세요!',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          final c = provider.isCompactMode;
          if (c) {
            return _buildCompactTripGrid(context, provider);
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: provider.trips.length,
            itemBuilder: (context, index) {
              final trip = provider.trips[index];
              final isActive = provider.activeTrip?.id == trip.id;
              final dateFormat = DateFormat('yyyy.MM.dd');

              return Dismissible(
                key: Key(trip.id.toString()),
                background: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.delete, color: Colors.white, size: 32),
                      SizedBox(height: 4),
                      Text(
                        '삭제',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                direction: DismissDirection.endToStart,
                confirmDismiss: (direction) async {
                  return await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('여행 삭제'),
                      content: Text(
                        '${trip.name}을(를) 삭제하시겠습니까?\n\n이 여행의 모든 지출 및 예산 내역이 함께 삭제됩니다.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소'),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text('삭제'),
                        ),
                      ],
                    ),
                  );
                },
                onDismissed: (direction) {
                  provider.deleteTrip(trip.id!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${trip.name}이(가) 삭제되었습니다')),
                  );
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () async {
                      await provider.setActiveTrip(trip.id!);
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const HomeScreen(),
                        ),
                      );
                    },
                    onLongPress: () {
                      _deleteTrip(context, trip.id!, trip.name);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: isActive
                            ? Border.all(
                                color: const Color(0xFF6C63FF),
                                width: 2,
                              )
                            : null,
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
                          // 국기 아이콘
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Center(
                              child: Text(
                                _getCountryFlag(trip.country),
                                style: const TextStyle(fontSize: 40),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        trip.name,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF2C3E50),
                                        ),
                                      ),
                                    ),
                                    if (isActive)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6C63FF),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: const Text(
                                          '활성',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  trip.country,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      size: 14,
                                      color: Colors.grey[600],
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${dateFormat.format(trip.startDate)} - ${dateFormat.format(trip.endDate)}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              const Icon(
                                Icons.arrow_forward_ios,
                                size: 20,
                                color: Color(0xFF6C63FF),
                              ),
                              const SizedBox(height: 8),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                onPressed: () {
                                  _deleteTrip(context, trip.id!, trip.name);
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateTripScreen()),
          );
        },
        backgroundColor: const Color(0xFF6C63FF),
        icon: const Icon(Icons.add),
        label: const Text(
          '새 여행',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
