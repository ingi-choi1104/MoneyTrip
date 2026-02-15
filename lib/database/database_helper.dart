import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/expense.dart';
import '../models/income.dart';
import '../models/trip.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) {
      try {
        // DB 연결 유효성 확인
        await _database!.rawQuery('SELECT 1');
        return _database!;
      } catch (e) {
        // 연결이 끊어진 경우 재연결
        _database = null;
      }
    }
    _database = await _initDB('travel_expense.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const realType = 'REAL NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE trips (
        id $idType,
        name $textType,
        country $textType,
        startDate $textType,
        endDate $textType,
        currency $textType,
        budget $realType,
        isActive $intType
      )
    ''');

    await db.execute('''
      CREATE TABLE expenses (
        id $idType,
        tripId $intType,
        amount $realType,
        category $textType,
        paymentMethod $textType,
        date $textType,
        title TEXT,
        note TEXT,
        imagePath TEXT,
        latitude REAL,
        longitude REAL,
        locationName TEXT,
        originalCurrency TEXT,
        originalAmount REAL,
        FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE incomes (
        id $idType,
        tripId $intType,
        amount $realType,
        date $textType,
        note TEXT,
        FOREIGN KEY (tripId) REFERENCES trips (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key $textType UNIQUE,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id $idType,
        name $textType,
        icon $textType,
        color $intType,
        isDefault $intType
      )
    ''');

    await _insertDefaultCategories(db);
  }

  Future<void> _insertDefaultCategories(Database db) async {
    final defaults = [
      {'name': '식비', 'icon': '🍽️', 'color': 0xFFFF6B6B, 'isDefault': 1},
      {'name': '쇼핑', 'icon': '🛍️', 'color': 0xFF4ECDC4, 'isDefault': 1},
      {'name': '관광', 'icon': '🎡', 'color': 0xFFFFBE0B, 'isDefault': 1},
      {'name': '교통', 'icon': '🚗', 'color': 0xFF95E1D3, 'isDefault': 1},
      {'name': '숙박', 'icon': '🏨', 'color': 0xFFA8E6CF, 'isDefault': 1},
    ];
    for (final cat in defaults) {
      await db.insert('categories', cat);
    }
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE expenses ADD COLUMN tripId INTEGER DEFAULT 1',
      );
      await db.execute(
        'ALTER TABLE incomes ADD COLUMN tripId INTEGER DEFAULT 1',
      );
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE expenses ADD COLUMN title TEXT');
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE expenses ADD COLUMN latitude REAL');
      await db.execute('ALTER TABLE expenses ADD COLUMN longitude REAL');
      await db.execute('ALTER TABLE expenses ADD COLUMN locationName TEXT');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          icon TEXT NOT NULL,
          color INTEGER NOT NULL,
          isDefault INTEGER NOT NULL
        )
      ''');
      await _insertDefaultCategories(db);
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE expenses ADD COLUMN originalCurrency TEXT');
      await db.execute('ALTER TABLE expenses ADD COLUMN originalAmount REAL');
    }
    if (oldVersion < 7) {
      // settings 테이블 중복 행 정리 후 UNIQUE 제약 적용
      final rows = await db.query('settings');
      await db.execute('DROP TABLE settings');
      await db.execute('CREATE TABLE settings (key TEXT NOT NULL UNIQUE, value TEXT)');
      final seen = <String>{};
      for (final row in rows.reversed) {
        final key = row['key'] as String;
        if (!seen.contains(key)) {
          seen.add(key);
          await db.insert('settings', {'key': key, 'value': row['value']});
        }
      }
    }
  }

  // Trip CRUD
  Future<int> insertTrip(Trip trip) async {
    final db = await database;
    return await db.insert('trips', trip.toMap());
  }

  Future<List<Trip>> getAllTrips() async {
    final db = await database;
    final result = await db.query('trips', orderBy: 'startDate DESC');
    return result.map((map) => Trip.fromMap(map)).toList();
  }

  Future<Trip?> getActiveTrip() async {
    final db = await database;
    final result = await db.query(
      'trips',
      where: 'isActive = ?',
      whereArgs: [1],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return Trip.fromMap(result.first);
  }

  Future<Trip?> getTripById(int id) async {
    final db = await database;
    final result = await db.query('trips', where: 'id = ?', whereArgs: [id]);
    if (result.isEmpty) return null;
    return Trip.fromMap(result.first);
  }

  Future<int> updateTrip(Trip trip) async {
    final db = await database;
    return await db.update(
      'trips',
      trip.toMap(),
      where: 'id = ?',
      whereArgs: [trip.id],
    );
  }

  Future<int> deleteTrip(int id) async {
    final db = await database;
    return await db.delete('trips', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setActiveTrip(int tripId) async {
    final db = await database;
    await db.update('trips', {'isActive': 0});
    await db.update(
      'trips',
      {'isActive': 1},
      where: 'id = ?',
      whereArgs: [tripId],
    );
  }

  // Expense CRUD
  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    return await db.insert('expenses', expense.toMap());
  }

  Future<List<Expense>> getExpensesByTrip(int tripId) async {
    final db = await database;
    final result = await db.query(
      'expenses',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'date DESC',
    );
    return result.map((map) => Expense.fromMap(map)).toList();
  }

  Future<int> updateExpense(Expense expense) async {
    final db = await database;
    return await db.update(
      'expenses',
      expense.toMap(),
      where: 'id = ?',
      whereArgs: [expense.id],
    );
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }

  // Income CRUD
  Future<int> insertIncome(Income income) async {
    final db = await database;
    return await db.insert('incomes', income.toMap());
  }

  Future<List<Income>> getIncomesByTrip(int tripId) async {
    final db = await database;
    final result = await db.query(
      'incomes',
      where: 'tripId = ?',
      whereArgs: [tripId],
      orderBy: 'date DESC',
    );
    return result.map((map) => Income.fromMap(map)).toList();
  }

  Future<int> deleteIncome(int id) async {
    final db = await database;
    return await db.delete('incomes', where: 'id = ?', whereArgs: [id]);
  }

  // Settings
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.delete('settings', where: 'key = ?', whereArgs: [key]);
    await db.insert('settings', {'key': key, 'value': value});
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result.isNotEmpty) {
      return result.first['value'] as String;
    }
    return null;
  }

  // Category CRUD
  Future<List<Map<String, dynamic>>> getCategories() async {
    final db = await database;
    final result = await db.query('categories', orderBy: 'id ASC');
    return result;
  }

  Future<int> insertCategory(String name, String icon, int color) async {
    final db = await database;
    return await db.insert('categories', {
      'name': name,
      'icon': icon,
      'color': color,
      'isDefault': 0,
    });
  }

  Future<int> deleteCategory(int id) async {
    final db = await database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> replaceAllCategories(List<Map<String, dynamic>> newCategories) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('categories');
      for (final cat in newCategories) {
        await txn.insert('categories', {
          'name': cat['name'],
          'icon': cat['icon'],
          'color': cat['color'],
          'isDefault': cat['isDefault'] ?? 0,
        });
      }
    });
  }

  Future close() async {
    final db = await database;
    db.close();
  }
}
