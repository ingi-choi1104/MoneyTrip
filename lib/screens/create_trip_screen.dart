import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/trip.dart';
import 'home_screen.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({Key? key}) : super(key: key);

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _budgetController = TextEditingController();

  String? _selectedCountry;
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedCurrency = 'KRW';

  // 국가 목록과 국기 이모지
  final Map<String, String> _countries = {
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

  final Map<String, String> _currencies = {
    'KRW': '₩',
    'USD': '\$',
    'EUR': '€',
    'JPY': '¥',
    'GBP': '£',
    'CNY': '¥',
    'THB': '฿',
    'VND': '₫',
    'SGD': 'S\$',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'CHF': 'Fr',
  };

  @override
  void dispose() {
    _nameController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF6C63FF),
              onPrimary: Colors.white,
              onSurface: Color(0xFF2C3E50),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
    }
  }

  void _showCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final searchController = TextEditingController();
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchController.text;
            final filteredEntries = _countries.entries
                .where((e) => query.isEmpty || e.key.contains(query))
                .toList();

            return Container(
              height: MediaQuery.of(context).size.height * 0.7,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Text(
                    '국가 선택',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: searchController,
                    decoration: InputDecoration(
                      hintText: '국가 검색',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredEntries.length,
                      itemBuilder: (context, index) {
                        final country = filteredEntries[index].key;
                        final flag = filteredEntries[index].value;
                        final isSelected = _selectedCountry == country;

                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedCountry = country;
                            });
                            Navigator.pop(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6C63FF).withOpacity(0.1)
                                  : null,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Text(flag, style: const TextStyle(fontSize: 32)),
                                const SizedBox(width: 16),
                                Text(
                                  country,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? const Color(0xFF6C63FF)
                                        : Colors.black,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const Spacer(),
                                  const Icon(
                                    Icons.check_circle,
                                    color: Color(0xFF6C63FF),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _saveTrip() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedCountry == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('국가를 선택해주세요')));
        return;
      }

      if (_startDate == null || _endDate == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('여행 기간을 설정해주세요')));
        return;
      }

      final provider = Provider.of<ExpenseProvider>(context, listen: false);

      // 예산이 비어있으면 0으로 설정
      final budgetValue = _budgetController.text.isEmpty
          ? 0.0
          : double.parse(_budgetController.text);

      final trip = Trip(
        name: _nameController.text,
        country: _selectedCountry!,
        startDate: _startDate!,
        endDate: _endDate!,
        currency: _selectedCurrency,
        budget: budgetValue,
        isActive: true,
      );

      await provider.createTrip(trip);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => const HomeScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('새 여행 만들기'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 여행 이름
            Container(
              padding: const EdgeInsets.all(16),
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
              child: TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: '여행 이름',
                  hintText: '예: 파리 여행',
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.title, color: Color(0xFF6C63FF)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '여행 이름을 입력해주세요';
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 16),

            // 국가 선택
            Container(
              padding: const EdgeInsets.all(16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '국가',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _showCountryPicker,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (_selectedCountry != null) ...[
                            Text(
                              _countries[_selectedCountry]!,
                              style: const TextStyle(fontSize: 32),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                _selectedCountry!,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ] else ...[
                            const Icon(Icons.public, color: Color(0xFF6C63FF)),
                            const SizedBox(width: 16),
                            const Expanded(
                              child: Text(
                                '국가를 선택하세요',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ],
                          const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Color(0xFF6C63FF),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 여행 기간
            Container(
              padding: const EdgeInsets.all(16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '여행 기간',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _selectDateRange,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '시작일',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _startDate != null
                                      ? '${_startDate!.year}.${_startDate!.month}.${_startDate!.day}'
                                      : '날짜 선택',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.arrow_forward, size: 20),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: _selectDateRange,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '종료일',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _endDate != null
                                      ? '${_endDate!.year}.${_endDate!.month}.${_endDate!.day}'
                                      : '날짜 선택',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 통화 선택
            Container(
              padding: const EdgeInsets.all(16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '통화',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _currencies.entries.map((entry) {
                      final isSelected = _selectedCurrency == entry.key;
                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedCurrency = entry.key;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF6C63FF)
                                : const Color(0xFF6C63FF).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${entry.value} ${entry.key}',
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF6C63FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 예산 (선택사항)
            Container(
              padding: const EdgeInsets.all(16),
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
              child: TextFormField(
                controller: _budgetController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: '예산 (선택사항)',
                  hintText: '0',
                  border: InputBorder.none,
                  prefixIcon: const Icon(
                    Icons.account_balance_wallet,
                    color: Color(0xFF6C63FF),
                  ),
                  prefixText: '${_currencies[_selectedCurrency]} ',
                ),
                validator: (value) {
                  // 비어있어도 OK (선택사항)
                  if (value != null && value.isNotEmpty) {
                    if (double.tryParse(value) == null) {
                      return '유효한 금액을 입력해주세요';
                    }
                  }
                  return null;
                },
              ),
            ),

            const SizedBox(height: 32),

            // 저장 버튼
            ElevatedButton(
              onPressed: _saveTrip,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text(
                '여행 만들기',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),

            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
