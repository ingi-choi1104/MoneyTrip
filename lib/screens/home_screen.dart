import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../providers/expense_provider.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../services/exchange_rate_service.dart';
import '../services/export_service.dart';
import '../services/ad_helper.dart';
import 'add_expense_screen.dart';
import 'add_income_screen.dart';
import 'statistics_screen.dart';
import 'settings_screen.dart';
import 'trips_list_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _selectedDate;
  bool _isPreTripSelected = false;
  Map<String, double>? _exchangeRates;
  bool _isLoadingRates = false;
  bool _isNewestFirst = true;
  bool _hasInitialized = false;
  String _paymentFilter = 'all'; // 'all', 'cash', 'card'
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    _loadExchangeRates();

    // 다음 프레임에서 날짜 선택 (Provider가 준비된 후)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectInitialDate();
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  void _loadBannerAd() {
    _bannerAd = BannerAd(
      adUnitId: AdHelper.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          setState(() {});
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          _bannerAd = null;
        },
      ),
    )..load();
  }

  void _selectInitialDate() {
    if (_hasInitialized) return;

    final provider = Provider.of<ExpenseProvider>(context, listen: false);
    if (provider.activeTrip == null) return;

    final today = DateTime.now();
    final tripDates = _getTripDates(
      provider.activeTrip!.startDate,
      provider.activeTrip!.endDate,
    );

    // 오늘 날짜가 여행 기간에 포함되는지 확인
    final isTodayInTrip = tripDates.any(
      (date) =>
          date.year == today.year &&
          date.month == today.month &&
          date.day == today.day,
    );

    setState(() {
      if (isTodayInTrip) {
        _selectedDate = today;
      } else {
        _selectedDate = null; // 전체 선택
      }
      _hasInitialized = true;
    });
  }

  Future<void> _loadExchangeRates() async {
    setState(() {
      _isLoadingRates = true;
    });

    try {
      final rates = await ExchangeRateService.instance.getExchangeRates();
      setState(() {
        _exchangeRates = rates;
        _isLoadingRates = false;
      });
    } catch (e) {
      print('환율 로딩 실패: $e');
      setState(() {
        _isLoadingRates = false;
      });
    }
  }

  double _convertToKRW(double amount, String currency) {
    if (_exchangeRates == null) {
      return amount * 1380.0;
    }
    return amount * (_exchangeRates![currency] ?? 1.0);
  }

  List<DateTime> _getTripDates(DateTime startDate, DateTime endDate) {
    List<DateTime> dates = [];
    DateTime current = startDate;

    while (current.isBefore(endDate) || current.isAtSameMomentAs(endDate)) {
      dates.add(current);
      current = current.add(const Duration(days: 1));
    }

    return dates;
  }

  List<Expense> _sortExpenses(List<Expense> expenses) {
    final sorted = List<Expense>.from(expenses);
    if (_isNewestFirst) {
      sorted.sort((a, b) => b.date.compareTo(a.date));
    } else {
      sorted.sort((a, b) => a.date.compareTo(b.date));
    }
    return sorted;
  }

  void _exportToExcel(BuildContext context) async {
    final provider = Provider.of<ExpenseProvider>(context, listen: false);
    if (provider.activeTrip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('활성화된 여행이 없습니다')),
      );
      return;
    }
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('엑셀 파일을 생성하고 있습니다...')),
      );
      await ExportService.exportToExcel(
        trip: provider.activeTrip!,
        expenses: provider.expenses,
        incomes: provider.incomes,
        currencySymbol: provider.currencySymbol,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('엑셀 파일이 생성되었습니다')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류 발생: $e')),
      );
    }
  }

  void _exportToPdf(BuildContext context) async {
    final provider = Provider.of<ExpenseProvider>(context, listen: false);
    if (provider.activeTrip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('활성화된 여행이 없습니다')),
      );
      return;
    }
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF 파일을 생성하고 있습니다...')),
      );
      await ExportService.exportToPdf(
        trip: provider.activeTrip!,
        expenses: provider.expenses,
        incomes: provider.incomes,
        currencySymbol: provider.currencySymbol,
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류 발생: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Consumer<ExpenseProvider>(
          builder: (context, provider, child) {
            if (provider.activeTrip == null) {
              return const Text('TripMoney');
            }
            return Text(
              provider.activeTrip!.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            );
          },
        ),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.home),
          tooltip: '여행 목록',
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const TripsListScreen()),
            );
          },
        ),
        actions: [
          IconButton(
            icon: _isLoadingRates
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.refresh),
            tooltip: '환율 새로고침',
            onPressed: _isLoadingRates
                ? null
                : () {
                    ExchangeRateService.instance.clearCache();
                    _loadExchangeRates();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('환율을 업데이트하고 있습니다...')),
                    );
                  },
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const StatisticsScreen(),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.file_download),
            tooltip: '내보내기',
            onSelected: (value) {
              if (value == 'excel') {
                _exportToExcel(context);
              } else if (value == 'pdf') {
                _exportToPdf(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Color(0xFF1D6F42), size: 20),
                    SizedBox(width: 8),
                    Text('엑셀로 출력'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Color(0xFFE53935), size: 20),
                    SizedBox(width: 8),
                    Text('PDF로 출력'),
                  ],
                ),
              ),
            ],
          ),
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
          if (provider.activeTrip == null) {
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
                    '여행을 선택해주세요',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const TripsListScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.list),
                    label: const Text('여행 목록으로'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 16,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final List<Expense> filteredExpenses;
          if (_isPreTripSelected) {
            filteredExpenses = provider.expenses
                .where((e) => e.date.isBefore(DateTime(
                    provider.activeTrip!.startDate.year,
                    provider.activeTrip!.startDate.month,
                    provider.activeTrip!.startDate.day)))
                .toList();
          } else if (_selectedDate == null) {
            filteredExpenses = provider.expenses;
          } else {
            filteredExpenses = provider.getExpensesByDate(_selectedDate!);
          }

          final paymentFiltered = _paymentFilter == 'all'
              ? filteredExpenses
              : filteredExpenses.where((e) => e.paymentMethod == _paymentFilter).toList();

          final sortedExpenses = _sortExpenses(paymentFiltered);

          return Column(
            children: [
              _buildSummaryCard(context, provider),
              const SizedBox(height: 8),
              _buildDateTabs(context, provider),
              const SizedBox(height: 8),
              // 정렬 + 결제수단 필터
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          _isNewestFirst = !_isNewestFirst;
                        });
                      },
                      child: Row(
                        children: [
                          Icon(
                            _isNewestFirst
                                ? Icons.arrow_downward
                                : Icons.arrow_upward,
                            size: 16,
                            color: const Color(0xFF6C63FF),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _isNewestFirst ? '최신순' : '오래된순',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF6C63FF),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.swap_vert,
                            size: 16,
                            color: Color(0xFF6C63FF),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildPaymentFilterChip('전체', 'all'),
                    const SizedBox(width: 6),
                    _buildPaymentFilterChip('현금', 'cash'),
                    const SizedBox(width: 6),
                    _buildPaymentFilterChip('카드', 'card'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildQuickActionButtons(context),
              const SizedBox(height: 8),
              Expanded(
                child: _isPreTripSelected
                    ? _buildPreTripList(context, provider, sortedExpenses)
                    : _buildExpenseList(context, provider, sortedExpenses),
              ),
              if (_bannerAd != null)
                SafeArea(
                  top: false,
                  child: SizedBox(
                    width: _bannerAd!.size.width.toDouble(),
                    height: _bannerAd!.size.height.toDouble(),
                    child: AdWidget(ad: _bannerAd!),
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          if (provider.activeTrip == null) return const SizedBox.shrink();

          return FloatingActionButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      AddExpenseScreen(initialDate: _selectedDate, isPreTrip: _isPreTripSelected),
                ),
              );
            },
            backgroundColor: const Color(0xFF6C63FF),
            child: const Icon(Icons.add),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context, ExpenseProvider provider) {
    final currencyFormat = NumberFormat.currency(
      locale: 'ko_KR',
      symbol: provider.currencySymbol,
      decimalDigits: 0,
    );

    final krwFormat = NumberFormat.currency(
      locale: 'ko_KR',
      symbol: '₩',
      decimalDigits: 0,
    );

    final double displayExpenses;
    if (_isPreTripSelected) {
      final tripStart = DateTime(
        provider.activeTrip!.startDate.year,
        provider.activeTrip!.startDate.month,
        provider.activeTrip!.startDate.day,
      );
      displayExpenses = provider.expenses
          .where((e) => e.date.isBefore(tripStart))
          .fold(0.0, (sum, e) => sum + e.amount);
    } else if (_selectedDate == null) {
      displayExpenses = provider.totalExpenses;
    } else {
      displayExpenses = provider.getTotalExpensesByDate(_selectedDate!);
    }

    final displayIncome = (_selectedDate == null && !_isPreTripSelected) ? provider.totalIncome : 0.0;

    final displayExpensesKRW = _convertToKRW(
      displayExpenses,
      provider.selectedCurrency,
    );

    final displayIncomeKRW = _convertToKRW(
      displayIncome,
      provider.selectedCurrency,
    );

    final remainingBalanceKRW = _convertToKRW(
      provider.remainingBalance,
      provider.selectedCurrency,
    );

    // 선택된 날짜 기준 누적 잔액 계산
    double balanceAtDate = provider.remainingBalance;
    double balanceAtDateKRW = remainingBalanceKRW;
    if (_isPreTripSelected) {
      final tripStart = DateTime(
        provider.activeTrip!.startDate.year,
        provider.activeTrip!.startDate.month,
        provider.activeTrip!.startDate.day,
      );
      final preTripExpenses = provider.expenses
          .where((e) => e.date.isBefore(tripStart))
          .fold(0.0, (sum, e) => sum + e.amount);
      balanceAtDate = provider.totalIncome - preTripExpenses;
      balanceAtDateKRW = _convertToKRW(balanceAtDate, provider.selectedCurrency);
    } else if (_selectedDate != null) {
      final cutoff = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day + 1);
      final cumulativeExpenses = provider.expenses
          .where((e) => e.date.isBefore(cutoff))
          .fold(0.0, (sum, e) => sum + e.amount);
      balanceAtDate = provider.totalIncome - cumulativeExpenses;
      balanceAtDateKRW = _convertToKRW(balanceAtDate, provider.selectedCurrency);
    }

    final c = provider.isCompactMode;
    return Container(
      margin: EdgeInsets.fromLTRB(16, c ? 8 : 16, 16, 0),
      padding: EdgeInsets.all(c ? 14 : 24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF5A52D5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(c ? 14 : 20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: c
          ? _buildCompactSummaryContent(provider, currencyFormat, krwFormat, displayIncome, displayExpenses, displayIncomeKRW, displayExpensesKRW, remainingBalanceKRW, balanceAtDate, balanceAtDateKRW)
          : _buildNormalSummaryContent(provider, currencyFormat, krwFormat, displayIncome, displayExpenses, displayIncomeKRW, displayExpensesKRW, remainingBalanceKRW, balanceAtDate, balanceAtDateKRW),
    );
  }

  Widget _buildCompactSummaryContent(
    ExpenseProvider provider,
    NumberFormat currencyFormat,
    NumberFormat krwFormat,
    double displayIncome,
    double displayExpenses,
    double displayIncomeKRW,
    double displayExpensesKRW,
    double remainingBalanceKRW,
    double balanceAtDate,
    double balanceAtDateKRW,
  ) {
    final showKRW = provider.selectedCurrency != 'KRW';
    final dateSelected = _selectedDate != null || _isPreTripSelected;
    final String dateLabel;
    if (_isPreTripSelected) {
      dateLabel = '여행 전 지출';
    } else if (_selectedDate != null) {
      dateLabel = '${_selectedDate!.month}/${_selectedDate!.day} 지출';
    } else {
      dateLabel = '지출';
    }

    return Column(
      children: [
        Row(
          children: [
            if (!dateSelected) ...[
              Expanded(
                child: Column(
                  children: [
                    const Text('예산', style: TextStyle(color: Colors.white70, fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(
                      currencyFormat.format(displayIncome),
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showKRW)
                      Text(krwFormat.format(displayIncomeKRW),
                          style: const TextStyle(color: Colors.white60, fontSize: 9)),
                  ],
                ),
              ),
              Container(width: 1, height: showKRW ? 38 : 28, color: Colors.white30),
            ],
            Expanded(
              child: Column(
                children: [
                  Text(dateLabel, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(
                    currencyFormat.format(displayExpenses),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showKRW)
                    Text(krwFormat.format(displayExpensesKRW),
                        style: const TextStyle(color: Colors.white60, fontSize: 9)),
                ],
              ),
            ),
            Container(width: 1, height: showKRW ? 38 : 28, color: Colors.white30),
            Expanded(
              child: Column(
                children: [
                  const Text('잔액', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  const SizedBox(height: 2),
                  Text(
                    currencyFormat.format(dateSelected ? balanceAtDate : provider.remainingBalance),
                    style: TextStyle(
                      color: (dateSelected ? balanceAtDate : provider.remainingBalance) >= 0
                          ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showKRW)
                    Text(krwFormat.format(dateSelected ? balanceAtDateKRW : remainingBalanceKRW),
                        style: TextStyle(
                          color: (dateSelected ? balanceAtDate : provider.remainingBalance) >= 0
                              ? Colors.greenAccent.withOpacity(0.7)
                              : Colors.redAccent.withOpacity(0.7),
                          fontSize: 9,
                        )),
                ],
              ),
            ),
          ],
        ),
        if (!dateSelected && provider.totalIncome > 0) ...[
          const SizedBox(height: 8),
          const Divider(color: Colors.white30, height: 1),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('사용률', style: TextStyle(color: Colors.white70, fontSize: 10)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (provider.totalExpenses / provider.totalIncome).clamp(0.0, 1.0),
                    backgroundColor: Colors.white30,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider.totalExpenses > provider.totalIncome ? Colors.redAccent : Colors.greenAccent,
                    ),
                    minHeight: 5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${((provider.totalExpenses / provider.totalIncome) * 100).toStringAsFixed(0)}%',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildNormalSummaryContent(
    ExpenseProvider provider,
    NumberFormat currencyFormat,
    NumberFormat krwFormat,
    double displayIncome,
    double displayExpenses,
    double displayIncomeKRW,
    double displayExpensesKRW,
    double remainingBalanceKRW,
    double balanceAtDate,
    double balanceAtDateKRW,
  ) {
    final showKRW = provider.selectedCurrency != 'KRW';
    final dateSelected = _selectedDate != null || _isPreTripSelected;
    final String dateLabel;
    if (_isPreTripSelected) {
      dateLabel = '여행 전 지출';
    } else if (_selectedDate != null) {
      dateLabel = '${_selectedDate!.month}/${_selectedDate!.day} 지출';
    } else {
      dateLabel = '지출';
    }
    final balanceValue = dateSelected ? balanceAtDate : provider.remainingBalance;
    final balanceKRWValue = dateSelected ? balanceAtDateKRW : remainingBalanceKRW;

    return Column(
      children: [
        if (_exchangeRates != null && showKRW) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.currency_exchange, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text(
                  '1 ${provider.selectedCurrency} = ${krwFormat.format(_exchangeRates![provider.selectedCurrency])}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          children: [
            if (!dateSelected) ...[
              Expanded(
                child: Column(
                  children: [
                    const Text('예산', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(
                      currencyFormat.format(displayIncome),
                      style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showKRW) ...[
                      const SizedBox(height: 2),
                      Text(krwFormat.format(displayIncomeKRW), style: const TextStyle(color: Colors.white60, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              Container(width: 1, height: showKRW ? 50 : 38, color: Colors.white30),
            ],
            Expanded(
              child: Column(
                children: [
                  Text(dateLabel, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(displayExpenses),
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showKRW) ...[
                    const SizedBox(height: 2),
                    Text(krwFormat.format(displayExpensesKRW), style: const TextStyle(color: Colors.white60, fontSize: 11)),
                  ],
                ],
              ),
            ),
            Container(width: 1, height: showKRW ? 50 : 38, color: Colors.white30),
            Expanded(
              child: Column(
                children: [
                  const Text('잔액', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(
                    currencyFormat.format(balanceValue),
                    style: TextStyle(
                      color: balanceValue >= 0 ? Colors.greenAccent : Colors.redAccent,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showKRW) ...[
                    const SizedBox(height: 2),
                    Text(
                      krwFormat.format(balanceKRWValue),
                      style: TextStyle(
                        color: balanceValue >= 0
                            ? Colors.greenAccent.withOpacity(0.7)
                            : Colors.redAccent.withOpacity(0.7),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (!dateSelected && provider.totalIncome > 0) ...[
          const SizedBox(height: 12),
          const Divider(color: Colors.white30, height: 1),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('사용률', style: TextStyle(color: Colors.white70, fontSize: 12)),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (provider.totalExpenses / provider.totalIncome).clamp(0.0, 1.0),
                    backgroundColor: Colors.white30,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider.totalExpenses > provider.totalIncome ? Colors.redAccent : Colors.greenAccent,
                    ),
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${((provider.totalExpenses / provider.totalIncome) * 100).toStringAsFixed(1)}%',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDateTabs(BuildContext context, ExpenseProvider provider) {
    final tripDates = _getTripDates(
      provider.activeTrip!.startDate,
      provider.activeTrip!.endDate,
    );

    final c = provider.isCompactMode;
    return Container(
      height: c ? 44 : 60,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildDateTab(
            context,
            provider,
            '전체',
            null,
            provider.expenses.length,
            _selectedDate == null && !_isPreTripSelected,
          ),
          const SizedBox(width: 8),
          _buildPreTripTab(context, provider),
          const SizedBox(width: 8),

          ...tripDates.map((date) {
            final expensesForDate = provider.getExpensesByDate(date);
            final dateFormat = DateFormat('M/d(E)', 'ko_KR');

            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildDateTab(
                context,
                provider,
                dateFormat.format(date),
                date,
                expensesForDate.length,
                _selectedDate != null &&
                    _selectedDate!.year == date.year &&
                    _selectedDate!.month == date.month &&
                    _selectedDate!.day == date.day,
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDateTab(
    BuildContext context,
    ExpenseProvider provider,
    String label,
    DateTime? date,
    int count,
    bool isSelected,
  ) {
    final c = provider.isCompactMode;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedDate = date;
          _isPreTripSelected = false;
        });
      },
      child: Container(
        width: c ? 56 : 70,
        padding: EdgeInsets.symmetric(horizontal: c ? 4 : 8, vertical: c ? 4 : 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : Colors.white,
          borderRadius: BorderRadius.circular(c ? 10 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF2C3E50),
                fontSize: c ? 10 : 12,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
            if (!c) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withOpacity(0.3)
                      : const Color(0xFF6C63FF).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count건',
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF6C63FF),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPreTripTab(BuildContext context, ExpenseProvider provider) {
    final c = provider.isCompactMode;
    final tripStart = DateTime(
      provider.activeTrip!.startDate.year,
      provider.activeTrip!.startDate.month,
      provider.activeTrip!.startDate.day,
    );
    final preTripCount = provider.expenses
        .where((e) => e.date.isBefore(tripStart))
        .length;

    return InkWell(
      onTap: () {
        setState(() {
          _isPreTripSelected = true;
          _selectedDate = null;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: c ? 8 : 12, vertical: c ? 4 : 8),
        decoration: BoxDecoration(
          color: _isPreTripSelected ? const Color(0xFFFF9F43) : Colors.white,
          borderRadius: BorderRadius.circular(c ? 10 : 16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '여행 전',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _isPreTripSelected ? Colors.white : const Color(0xFFFF9F43),
                fontSize: c ? 10 : 12,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
            if (!c) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _isPreTripSelected
                      ? Colors.white.withOpacity(0.3)
                      : const Color(0xFFFF9F43).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$preTripCount건',
                  style: TextStyle(
                    color: _isPreTripSelected ? Colors.white : const Color(0xFFFF9F43),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentFilterChip(String label, String value) {
    final isSelected = _paymentFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _paymentFilter = value;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6C63FF) : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActionButtons(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              context,
              '지출 추가',
              Icons.remove_circle_outline,
              const Color(0xFFFF6B6B),
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddExpenseScreen(initialDate: _selectedDate, isPreTrip: _isPreTripSelected),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              context,
              '예산 추가',
              Icons.add_circle_outline,
              const Color(0xFF51CF66),
              () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        AddIncomeScreen(initialDate: _selectedDate, isPreTrip: _isPreTripSelected),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    final c = Provider.of<ExpenseProvider>(context, listen: false).isCompactMode;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: c ? 8 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(c ? 8 : 12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: c ? 18 : 24),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: c ? 13 : 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseList(
    BuildContext context,
    ExpenseProvider provider,
    List<Expense> expenses,
  ) {
    // 해당 뷰에 맞는 Income 필터링
    final List<Income> filteredIncomes;
    if (_selectedDate == null) {
      filteredIncomes = List.from(provider.incomes);
    } else {
      filteredIncomes = provider.incomes.where((i) =>
        i.date.year == _selectedDate!.year &&
        i.date.month == _selectedDate!.month &&
        i.date.day == _selectedDate!.day,
      ).toList();
    }

    if (expenses.isEmpty && filteredIncomes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              _selectedDate == null ? '아직 내역이 없습니다' : '이 날짜에 내역이 없습니다',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            if (_selectedDate != null) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedDate = null;
                  });
                },
                icon: const Icon(Icons.list),
                label: const Text('전체 보기'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF6C63FF),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // Income + Expense를 합쳐서 날짜순 정렬
    final items = <_PreTripItem>[];
    for (final income in filteredIncomes) {
      items.add(_PreTripItem(income: income, date: income.date));
    }
    for (final expense in expenses) {
      items.add(_PreTripItem(expense: expense, date: expense.date));
    }
    if (_isNewestFirst) {
      items.sort((a, b) => b.date.compareTo(a.date));
    } else {
      items.sort((a, b) => a.date.compareTo(b.date));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.income != null) {
          return _buildIncomeCard(context, provider, item.income!);
        }
        return _buildExpenseCard(context, provider, item.expense!);
      },
    );
  }

  Widget _buildPreTripList(
    BuildContext context,
    ExpenseProvider provider,
    List<Expense> expenses,
  ) {
    final tripStart = DateTime(
      provider.activeTrip!.startDate.year,
      provider.activeTrip!.startDate.month,
      provider.activeTrip!.startDate.day,
    );
    final preTripIncomes = provider.incomes
        .where((i) => i.date.isBefore(tripStart))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    if (expenses.isEmpty && preTripIncomes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 80, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              '여행 전 내역이 없습니다',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    // income + expense를 합쳐서 날짜순 정렬
    final items = <_PreTripItem>[];
    for (final income in preTripIncomes) {
      items.add(_PreTripItem(income: income, date: income.date));
    }
    for (final expense in expenses) {
      items.add(_PreTripItem(expense: expense, date: expense.date));
    }
    if (_isNewestFirst) {
      items.sort((a, b) => b.date.compareTo(a.date));
    } else {
      items.sort((a, b) => a.date.compareTo(b.date));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item.income != null) {
          return _buildIncomeCard(context, provider, item.income!);
        }
        return _buildExpenseCard(context, provider, item.expense!);
      },
    );
  }

  Widget _buildIncomeCard(
    BuildContext context,
    ExpenseProvider provider,
    Income income,
  ) {
    final c = provider.isCompactMode;
    final currencyFormat = NumberFormat.currency(
      locale: 'ko_KR',
      symbol: provider.currencySymbol,
      decimalDigits: 0,
    );

    return Dismissible(
      key: Key('income_${income.id}'),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('예산 삭제'),
            content: const Text('이 예산을 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('삭제'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        provider.deleteIncome(income.id!);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('예산이 삭제되었습니다')),
        );
      },
      child: Container(
        margin: EdgeInsets.only(bottom: c ? 4 : 8),
        padding: EdgeInsets.all(c ? 10 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(c ? 8 : 12),
          border: Border.all(color: const Color(0xFF51CF66).withOpacity(0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: c ? 36 : 48,
              height: c ? 36 : 48,
              decoration: BoxDecoration(
                color: const Color(0xFF51CF66).withOpacity(0.1),
                borderRadius: BorderRadius.circular(c ? 8 : 12),
              ),
              child: Center(
                child: Icon(
                  Icons.account_balance_wallet,
                  color: const Color(0xFF51CF66),
                  size: c ? 18 : 24,
                ),
              ),
            ),
            SizedBox(width: c ? 8 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    income.note ?? '예산',
                    style: TextStyle(
                      fontSize: c ? 13 : 16,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF2C3E50),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${income.date.month}/${income.date.day}',
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Text(
              '+${currencyFormat.format(income.amount)}',
              style: TextStyle(
                fontSize: c ? 14 : 18,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF51CF66),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpenseCard(
    BuildContext context,
    ExpenseProvider provider,
    Expense expense,
  ) {
    final category = provider.categories.firstWhere(
      (cat) => cat['name'] == expense.category,
      orElse: () => provider.categories[0],
    );
    final c = provider.isCompactMode;

    final currencyFormat = NumberFormat.currency(
      locale: 'ko_KR',
      symbol: provider.currencySymbol,
      decimalDigits: 0,
    );

    return Dismissible(
      key: Key(expense.id.toString()),
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('지출 삭제'),
            content: const Text('이 지출을 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('삭제'),
              ),
            ],
          ),
        );
      },
      onDismissed: (direction) {
        provider.deleteExpense(expense.id!);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지출이 삭제되었습니다')));
      },
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddExpenseScreen(expense: expense),
            ),
          );
        },
        child: Container(
          margin: EdgeInsets.only(bottom: c ? 4 : 8),
          padding: EdgeInsets.all(c ? 10 : 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(c ? 8 : 12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: c ? 36 : 48,
                height: c ? 36 : 48,
                decoration: BoxDecoration(
                  color: Color(category['color']).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(c ? 8 : 12),
                ),
                child: Center(
                  child: Text(
                    category['icon'],
                    style: TextStyle(fontSize: c ? 18 : 24),
                  ),
                ),
              ),
              SizedBox(width: c ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.title != null && expense.title!.isNotEmpty
                          ? expense.title!
                          : expense.category,
                      style: TextStyle(
                        fontSize: c ? 13 : 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (expense.title != null &&
                            expense.title!.isNotEmpty) ...[
                          Text(
                            expense.category,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            ' · ',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                        Text(
                          expense.paymentMethod == 'cash' ? '현금' : '카드',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                        Text(
                          ' · ',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[500],
                          ),
                        ),
                        Text(
                          '${expense.date.month}/${expense.date.day} ${expense.date.hour.toString().padLeft(2, '0')}:${expense.date.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    if (expense.note != null && expense.note!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        expense.note!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                currencyFormat.format(expense.amount),
                style: TextStyle(
                  fontSize: c ? 14 : 18,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFF6B6B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PreTripItem {
  final Expense? expense;
  final Income? income;
  final DateTime date;

  _PreTripItem({this.expense, this.income, required this.date});
}
