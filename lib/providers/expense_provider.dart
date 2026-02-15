import 'package:flutter/foundation.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/trip.dart';
import '../database/database_helper.dart';
import '../services/sms_service.dart';

class ExpenseProvider extends ChangeNotifier {
  List<Expense> _expenses = [];
  List<Income> _incomes = [];
  List<Trip> _trips = [];
  Trip? _activeTrip;

  List<Expense> get expenses => _expenses;
  List<Income> get incomes => _incomes;
  List<Trip> get trips => _trips;
  Trip? get activeTrip => _activeTrip;

  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  // Categories
  List<Map<String, dynamic>> categories = [];

  // Compact mode
  bool _isCompactMode = false;
  bool get isCompactMode => _isCompactMode;

  // SMS auto register
  bool _isSmsAutoRegister = false;
  bool get isSmsAutoRegister => _isSmsAutoRegister;

  // Popup notification (기본값 비허용)
  bool _isPopupNotification = false;
  bool get isPopupNotification => _isPopupNotification;

  ExpenseProvider() {
    _loadData();
  }

  /// 앱이 백그라운드에서 복귀할 때 데이터 새로고침
  Future<void> refreshData() async {
    await _loadData();
  }

  Future<void> _loadData() async {
    await loadCategories();
    await _loadCompactMode();
    await _loadSmsAutoRegister();
    await _loadPopupNotification();
    _trips = await _dbHelper.getAllTrips();
    _activeTrip = await _dbHelper.getActiveTrip();

    if (_activeTrip != null) {
      _expenses = await _dbHelper.getExpensesByTrip(_activeTrip!.id!);
      _incomes = await _dbHelper.getIncomesByTrip(_activeTrip!.id!);
    }

    notifyListeners();
  }

  // Trip Management
  Future<void> createTrip(Trip trip) async {
    final id = await _dbHelper.insertTrip(trip);
    final newTrip = trip.copyWith(id: id);
    _trips.insert(0, newTrip);

    // 예산이 0보다 크면 Income으로 추가 (여행 전 항목으로 하루 전 날짜)
    if (trip.budget > 0) {
      final income = Income(
        tripId: id,
        amount: trip.budget,
        date: trip.startDate.subtract(const Duration(days: 1)),
        note: '초기 예산',
      );
      await _dbHelper.insertIncome(income);
    }

    // 새로 만든 여행을 바로 활성화
    await setActiveTrip(id);

    notifyListeners();
  }

  Future<void> addTrip(Trip trip) async {
    await createTrip(trip);
  }

  Future<void> setActiveTrip(int tripId) async {
    await _dbHelper.setActiveTrip(tripId);
    _activeTrip = await _dbHelper.getTripById(tripId);

    if (_activeTrip != null) {
      _expenses = await _dbHelper.getExpensesByTrip(_activeTrip!.id!);
      _incomes = await _dbHelper.getIncomesByTrip(_activeTrip!.id!);
    }

    notifyListeners();
  }

  Future<void> deleteTrip(int tripId) async {
    await _dbHelper.deleteTrip(tripId);
    _trips.removeWhere((trip) => trip.id == tripId);

    if (_activeTrip?.id == tripId) {
      if (_trips.isNotEmpty) {
        await setActiveTrip(_trips.first.id!);
      } else {
        _activeTrip = null;
        _expenses = [];
        _incomes = [];
      }
    }

    notifyListeners();
  }

  // Calculate total expenses for current trip
  double get totalExpenses {
    return _expenses.fold(0, (sum, expense) => sum + expense.amount);
  }

  // Calculate total income for current trip
  double get totalIncome {
    return _incomes.fold(0, (sum, income) => sum + income.amount);
  }

  // Calculate remaining balance for current trip
  double get remainingBalance {
    return totalIncome - totalExpenses;
  }

  // Get total expenses by trip
  double getTotalExpensesByTrip(int tripId) {
    return _expenses
        .where((e) => e.tripId == tripId)
        .fold(0, (sum, expense) => sum + expense.amount);
  }

  // Get total income by trip
  double getTotalIncomeByTrip(int tripId) {
    return _incomes
        .where((i) => i.tripId == tripId)
        .fold(0, (sum, income) => sum + income.amount);
  }

  // Get expenses by date
  List<Expense> getExpensesByDate(DateTime date) {
    return _expenses.where((expense) {
      return expense.date.year == date.year &&
          expense.date.month == date.month &&
          expense.date.day == date.day;
    }).toList();
  }

  // Get total expenses for a specific date
  double getTotalExpensesByDate(DateTime date) {
    final expensesForDate = getExpensesByDate(date);
    return expensesForDate.fold(0, (sum, expense) => sum + expense.amount);
  }

  // Get expenses grouped by date
  Map<String, List<Expense>> get expensesGroupedByDate {
    final Map<String, List<Expense>> grouped = {};

    for (var expense in _expenses) {
      final dateKey =
          '${expense.date.year}-${expense.date.month.toString().padLeft(2, '0')}-${expense.date.day.toString().padLeft(2, '0')}';

      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(expense);
    }

    return grouped;
  }

  // Get expenses by category
  Map<String, double> get expensesByCategory {
    final Map<String, double> categoryTotals = {};

    for (var expense in _expenses) {
      categoryTotals[expense.category] =
          (categoryTotals[expense.category] ?? 0) + expense.amount;
    }

    return categoryTotals;
  }

  // Compact mode management
  Future<void> _loadCompactMode() async {
    final value = await _dbHelper.getSetting('compact_mode');
    _isCompactMode = value == 'true';
  }

  Future<void> setCompactMode(bool value) async {
    _isCompactMode = value;
    await _dbHelper.saveSetting('compact_mode', value.toString());
    notifyListeners();
  }

  // SMS auto register management
  Future<void> _loadSmsAutoRegister() async {
    final value = await _dbHelper.getSetting('sms_auto_register');
    _isSmsAutoRegister = value == 'true';
    if (_isSmsAutoRegister) {
      SmsService.instance.initializeIfPermitted();
    }
  }

  void setSmsAutoRegister(bool value) {
    _isSmsAutoRegister = value;
    notifyListeners();
    _dbHelper.saveSetting('sms_auto_register', value.toString());

    if (value && !SmsService.instance.isInitialized) {
      // 최초 1회만 권한 요청 + 초기화. 이미 초기화됐으면 아무것도 안 함.
      SmsService.instance.requestAndInitialize().then((granted) {
        if (!granted) {
          _isSmsAutoRegister = false;
          _dbHelper.saveSetting('sms_auto_register', 'false');
          notifyListeners();
        }
      });
    }
  }

  // Popup notification management
  Future<void> _loadPopupNotification() async {
    final value = await _dbHelper.getSetting('popup_notification');
    _isPopupNotification = value == 'true';
  }

  void setPopupNotification(bool value) {
    _isPopupNotification = value;
    notifyListeners(); // UI 즉시 업데이트

    // DB 저장 (백그라운드)
    _dbHelper.saveSetting('popup_notification', value.toString());
  }

  // Category management
  Future<void> loadCategories() async {
    final dbCategories = await _dbHelper.getCategories();
    categories = dbCategories.map((cat) => Map<String, dynamic>.from(cat)).toList();
    notifyListeners();
  }

  Future<bool> addCategory(String name, String icon, int color) async {
    if (categories.length >= 10) return false;
    if (categories.any((cat) => cat['name'] == name)) return false;
    final id = await _dbHelper.insertCategory(name, icon, color);
    categories.add({
      'id': id,
      'name': name,
      'icon': icon,
      'color': color,
      'isDefault': 0,
    });
    notifyListeners();
    return true;
  }

  Future<bool> deleteCategory(int id) async {
    final cat = categories.firstWhere((c) => c['id'] == id, orElse: () => {});
    if (cat.isEmpty) return false;
    if (categories.length <= 1) return false;
    await _dbHelper.deleteCategory(id);
    categories.removeWhere((c) => c['id'] == id);
    notifyListeners();
    return true;
  }

  Future<void> replaceCategories(List<Map<String, dynamic>> newCategories) async {
    await _dbHelper.replaceAllCategories(newCategories);
    await loadCategories();
  }

  // Add expense
  Future<void> addExpense(Expense expense) async {
    final id = await _dbHelper.insertExpense(expense);
    _expenses.insert(0, expense.copyWith(id: id));
    notifyListeners();
  }

  // Update expense
  Future<void> updateExpense(Expense expense) async {
    await _dbHelper.updateExpense(expense);
    final index = _expenses.indexWhere((e) => e.id == expense.id);
    if (index != -1) {
      _expenses[index] = expense;
      notifyListeners();
    }
  }

  // Delete expense
  Future<void> deleteExpense(int id) async {
    await _dbHelper.deleteExpense(id);
    _expenses.removeWhere((expense) => expense.id == id);
    notifyListeners();
  }

  // Add income
  Future<void> addIncome(Income income) async {
    final id = await _dbHelper.insertIncome(income);
    _incomes.insert(
      0,
      Income(
        id: id,
        tripId: income.tripId,
        amount: income.amount,
        date: income.date,
        note: income.note,
      ),
    );
    notifyListeners();
  }

  // Delete income
  Future<void> deleteIncome(int id) async {
    await _dbHelper.deleteIncome(id);
    _incomes.removeWhere((income) => income.id == id);
    notifyListeners();
  }

  // Get currency symbol for active trip
  String get currencySymbol {
    if (_activeTrip == null) return '₩';

    const symbols = {
      'KRW': '₩',
      'USD': '\$',
      'EUR': '€',
      'JPY': '¥',
      'CNY': '¥',
      'GBP': '£',
      'THB': '฿',
      'VND': '₫',
      'SGD': 'S\$',
      'AUD': 'A\$',
      'CAD': 'C\$',
      'CHF': 'Fr',
    };

    return symbols[_activeTrip!.currency] ?? _activeTrip!.currency;
  }

  String get selectedCurrency {
    return _activeTrip?.currency ?? 'KRW';
  }

  double get budget {
    return _activeTrip?.budget ?? 0;
  }
}
