import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import '../providers/expense_provider.dart';
import '../services/receipt_scanner.dart';
import '../services/ad_helper.dart';
import '../models/expense.dart';
import '../services/exchange_rate_service.dart';
import 'location_picker_screen.dart';

class AddExpenseScreen extends StatefulWidget {
  final Expense? expense;
  final DateTime? initialDate;
  final bool isPreTrip;

  const AddExpenseScreen({Key? key, this.expense, this.initialDate, this.isPreTrip = false})
    : super(key: key);

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();

  String _selectedCategory = '식비';
  String _selectedPaymentMethod = 'cash';
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  File? _selectedImage;
  bool _isEditing = false;
  String? _inputCurrency; // 입력 통화 (null이면 여행 통화 사용)

  // 위치 정보
  double? _latitude;
  double? _longitude;
  String? _locationName;

  // 배너 광고
  BannerAd? _bannerAd;

  static const List<String> _availableCurrencies = [
    'KRW', 'USD', 'EUR', 'JPY', 'CNY', 'GBP', 'THB', 'VND', 'AUD', 'CAD',
  ];

  static const Map<String, String> _currencySymbols = {
    'KRW': '₩', 'USD': '\$', 'EUR': '€', 'JPY': '¥', 'CNY': '¥',
    'GBP': '£', 'THB': '฿', 'VND': '₫', 'AUD': 'A\$', 'CAD': 'C\$',
  };

  @override
  void initState() {
    super.initState();
    _loadBannerAd();
    if (widget.expense != null) {
      _isEditing = true;
      _titleController.text = widget.expense!.title ?? '';
      _noteController.text = widget.expense!.note ?? '';
      _selectedCategory = widget.expense!.category;
      _selectedPaymentMethod = widget.expense!.paymentMethod;
      _selectedDate = widget.expense!.date;
      _selectedTime = TimeOfDay(
        hour: widget.expense!.date.hour,
        minute: widget.expense!.date.minute,
      );
      _latitude = widget.expense!.latitude;
      _longitude = widget.expense!.longitude;
      _locationName = widget.expense!.locationName;
      if (widget.expense!.imagePath != null) {
        _selectedImage = File(widget.expense!.imagePath!);
      }
      // 원래 통화로 금액 표시 (쉼표 포함)
      if (widget.expense!.originalCurrency != null && widget.expense!.originalAmount != null) {
        _inputCurrency = widget.expense!.originalCurrency;
        final origAmt = widget.expense!.originalAmount!;
        _amountController.text = origAmt == origAmt.roundToDouble()
            ? _formatWithCommas(origAmt.toInt())
            : origAmt.toString();
      } else {
        final amt = widget.expense!.amount;
        _amountController.text = amt == amt.roundToDouble()
            ? _formatWithCommas(amt.toInt())
            : amt.toString();
      }
    } else if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
      _selectedTime = TimeOfDay.now();
    } else if (widget.isPreTrip) {
      // 여행 전: 오늘이 여행 시작 전이면 오늘, 아니면 여행 시작 전날
      final provider = Provider.of<ExpenseProvider>(context, listen: false);
      if (provider.activeTrip != null) {
        final tripStart = provider.activeTrip!.startDate;
        final today = DateTime.now();
        if (today.isBefore(tripStart)) {
          _selectedDate = today;
        } else {
          _selectedDate = tripStart.subtract(const Duration(days: 1));
        }
      }
      _selectedTime = TimeOfDay.now();
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _amountController.dispose();
    _titleController.dispose();
    _noteController.dispose();
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _selectDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) {
      setState(() {
        _selectedDate = date;
      });
    }
  }

  Future<void> _selectTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (time != null) {
      setState(() {
        _selectedTime = time;
      });
    }
  }

  Future<void> _saveCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치 서비스가 비활성화되어 있습니다')),
        );
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 권한이 거부되었습니다')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('위치 권한이 영구적으로 거부되었습니다. 설정에서 변경해주세요')),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });

      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          String address = place.name ?? '';
          if (address.isEmpty) address = place.street ?? '';
          if (address.isEmpty) address = place.subLocality ?? '';
          if (address.isEmpty) address = place.locality ?? '';
          if (place.locality != null && place.locality!.isNotEmpty && address != place.locality) {
            address = '$address, ${place.locality}';
          }
          if (address.isEmpty) address = '현재 위치';
          setState(() {
            _locationName = address;
          });
        }
      } catch (_) {
        setState(() {
          _locationName = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        });
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('현재 위치가 저장되었습니다: $_locationName')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져올 수 없습니다')),
      );
    }
  }

  Future<void> _searchLocation() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          initialLatitude: _latitude,
          initialLongitude: _longitude,
          initialLocationName: _locationName,
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _latitude = result['latitude'];
        _longitude = result['longitude'];
        _locationName = result['locationName'];
      });
    }
  }

  void _showEditCategoryDialog(
      BuildContext context, ExpenseProvider provider) {
    final tempCategories = provider.categories
        .map((cat) => Map<String, dynamic>.from(cat))
        .toList();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('카테고리 편집'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: tempCategories.length + (tempCategories.length < 10 ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    if (index == tempCategories.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _showAddCategoryInEditDialog(
                              context, tempCategories, setDialogState,
                            );
                          },
                          icon: const Icon(Icons.add),
                          label: const Text('카테고리 추가'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF6C63FF),
                            side: const BorderSide(color: Color(0xFF6C63FF)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      );
                    }
                    final category = tempCategories[index];
                    final canDelete = tempCategories.length > 1;
                    return Container(
                      decoration: BoxDecoration(
                        color: Color(category['color']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Text(
                          category['icon'],
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(category['name']),
                        trailing: canDelete
                            ? IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: Colors.red, size: 20),
                                onPressed: () {
                                  setDialogState(() {
                                    tempCategories.removeAt(index);
                                  });
                                },
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    await provider.replaceCategories(tempCategories);
                    if (!provider.categories.any((c) => c['name'] == _selectedCategory)) {
                      setState(() {
                        _selectedCategory = provider.categories.first['name'];
                      });
                    }
                    setState(() {});
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                  ),
                  child: const Text('저장', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddCategoryInEditDialog(
      BuildContext context,
      List<Map<String, dynamic>> tempCategories,
      void Function(void Function()) setParentState) {
    final nameController = TextEditingController();
    String selectedIcon = '🎵';
    int selectedColor = 0xFFFF6B6B;

    const icons = [
      '🎵', '🎮', '💊', '🎁', '📚', '✈️', '🏋️', '🍺',
      '☕', '💇', '🎬', '🏥', '📱', '🐶', '🎂', '💼',
    ];
    const colors = [
      0xFFFF6B6B, 0xFF4ECDC4, 0xFFFFBE0B, 0xFF95E1D3,
      0xFFA8E6CF, 0xFF6C63FF, 0xFFFF9F43, 0xFFEE5A24,
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('카테고리 추가'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '카테고리 이름',
                        hintText: '예: 카페',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 10,
                    ),
                    const SizedBox(height: 16),
                    const Text('아이콘 선택',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: icons.map((icon) {
                        final isSelected = selectedIcon == icon;
                        return GestureDetector(
                          onTap: () => setDialogState(() => selectedIcon = icon),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6C63FF).withOpacity(0.2)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected
                                  ? Border.all(color: const Color(0xFF6C63FF), width: 2)
                                  : null,
                            ),
                            child: Center(child: Text(icon, style: const TextStyle(fontSize: 22))),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('색상 선택',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: colors.map((color) {
                        final isSelected = selectedColor == color;
                        return GestureDetector(
                          onTap: () => setDialogState(() => selectedColor = color),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.black, width: 3)
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('카테고리 이름을 입력해주세요')),
                      );
                      return;
                    }
                    if (tempCategories.any((cat) => cat['name'] == name)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('이미 존재하는 카테고리 이름입니다')),
                      );
                      return;
                    }
                    setParentState(() {
                      tempCategories.add({
                        'name': name,
                        'icon': selectedIcon,
                        'color': selectedColor,
                        'isDefault': 0,
                      });
                    });
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                  ),
                  child: const Text('추가', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddCategoryDialog(
      BuildContext context, ExpenseProvider provider) {
    final nameController = TextEditingController();
    String selectedIcon = '🎵';
    int selectedColor = 0xFFFF6B6B;

    const icons = [
      '🎵', '🎮', '💊', '🎁', '📚', '✈️', '🏋️', '🍺',
      '☕', '💇', '🎬', '🏥', '📱', '🐶', '🎂', '💼',
    ];
    const colors = [
      0xFFFF6B6B, 0xFF4ECDC4, 0xFFFFBE0B, 0xFF95E1D3,
      0xFFA8E6CF, 0xFF6C63FF, 0xFFFF9F43, 0xFFEE5A24,
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('카테고리 추가'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: '카테고리 이름',
                        hintText: '예: 카페',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 10,
                    ),
                    const SizedBox(height: 16),
                    const Text('아이콘 선택',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: icons.map((icon) {
                        final isSelected = selectedIcon == icon;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => selectedIcon = icon);
                          },
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF6C63FF).withOpacity(0.2)
                                  : Colors.grey[100],
                              borderRadius: BorderRadius.circular(10),
                              border: isSelected
                                  ? Border.all(
                                      color: const Color(0xFF6C63FF), width: 2)
                                  : null,
                            ),
                            child: Center(
                              child:
                                  Text(icon, style: const TextStyle(fontSize: 22)),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    const Text('색상 선택',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: colors.map((color) {
                        final isSelected = selectedColor == color;
                        return GestureDetector(
                          onTap: () {
                            setDialogState(() => selectedColor = color);
                          },
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: Color(color),
                              shape: BoxShape.circle,
                              border: isSelected
                                  ? Border.all(color: Colors.black, width: 3)
                                  : null,
                            ),
                            child: isSelected
                                ? const Icon(Icons.check,
                                    color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('카테고리 이름을 입력해주세요')),
                      );
                      return;
                    }
                    final success = await provider.addCategory(
                        name, selectedIcon, selectedColor);
                    if (success) {
                      Navigator.pop(ctx);
                      setState(() {});
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('이미 존재하는 이름이거나 최대 개수(10개)를 초과했습니다')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                  ),
                  child: const Text('추가', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteCategoryDialog(BuildContext context,
      ExpenseProvider provider, Map<String, dynamic> category) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('카테고리 삭제'),
          content: Text("'${category['name']}' 카테고리를 삭제하시겠습니까?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                final success =
                    await provider.deleteCategory(category['id']);
                if (success) {
                  if (_selectedCategory == category['name']) {
                    setState(() {
                      _selectedCategory = provider.categories.first['name'];
                    });
                  }
                  Navigator.pop(ctx);
                  setState(() {});
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child:
                  const Text('삭제', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _clearLocation() {
    setState(() {
      _latitude = null;
      _longitude = null;
      _locationName = null;
    });
  }

  /// 세 자리마다 쉼표 포맷 (8100 → "8,100")
  String _formatWithCommas(int number) {
    final str = number.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return buffer.toString();
  }

  Future<void> _scanReceipt() async {
    final picker = ImagePicker();

    final source = await showDialog<ImageSource>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('영수증 스캔'),
        content: const Text('영수증을 어떻게 가져올까요?'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.camera),
            icon: const Icon(Icons.camera_alt),
            label: const Text('카메라'),
          ),
          TextButton.icon(
            onPressed: () => Navigator.pop(ctx, ImageSource.gallery),
            icon: const Icon(Icons.photo_library),
            label: const Text('갤러리'),
          ),
        ],
      ),
    );

    if (source == null) return;

    final pickedFile = await picker.pickImage(source: source, imageQuality: 100);
    if (pickedFile == null) return;

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final result = await ReceiptScanner.scan(pickedFile.path);

      if (!mounted) return;
      Navigator.pop(context);

      // 결과 적용
      setState(() {
        if (result.amount != null) {
          if (result.amount! == result.amount!.roundToDouble() && result.amount! >= 1) {
            _amountController.text = _formatWithCommas(result.amount!.toInt());
          } else {
            _amountController.text = result.amount!.toString();
          }
        }
        if (result.date != null) _selectedDate = result.date!;
        if (result.time != null) _selectedTime = result.time!;
        if (result.storeName != null) _titleController.text = result.storeName!;
        _selectedImage = File(pickedFile.path);
      });

      // 주소 → 지오코딩 → 위치
      if (result.address != null && result.address!.isNotEmpty) {
        try {
          final locations = await locationFromAddress(result.address!);
          if (locations.isNotEmpty) {
            setState(() {
              _latitude = locations.first.latitude;
              _longitude = locations.first.longitude;
              _locationName = result.address;
            });
          }
        } catch (_) {
          setState(() { _locationName = result.address; });
        }
      }

      if (!mounted) return;
      final msgs = <String>[];
      if (result.amount != null) {
        final amtStr = (result.amount! == result.amount!.roundToDouble() && result.amount! >= 1)
            ? _formatWithCommas(result.amount!.toInt())
            : result.amount!.toString();
        msgs.add('금액: $amtStr');
      }
      if (result.storeName != null) msgs.add('상호: ${result.storeName}');
      if (result.date != null) msgs.add('날짜: ${result.date!.month}/${result.date!.day}');
      if (result.time != null) msgs.add('시간: ${result.time!.hour}:${result.time!.minute.toString().padLeft(2, '0')}');
      if (result.address != null) msgs.add('주소: ${result.address}');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msgs.isEmpty ? '인식된 정보가 없습니다' : '스캔 완료: ${msgs.join(', ')}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('영수증 스캔 실패: $e')),
      );
    }
  }

  void _saveExpense() {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<ExpenseProvider>(context, listen: false);

      if (provider.activeTrip == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('먼저 여행을 생성해주세요')));
        return;
      }

      final combinedDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      final inputAmount = double.parse(_amountController.text.replaceAll(',', ''));
      final tripCurrency = provider.selectedCurrency;
      final actualInputCurrency = _inputCurrency ?? tripCurrency;
      double finalAmount = inputAmount;

      if (actualInputCurrency != tripCurrency) {
        finalAmount = ExchangeRateService.instance.convert(
          inputAmount, actualInputCurrency, tripCurrency,
        );
      }

      final expense = Expense(
        id: _isEditing ? widget.expense!.id : null,
        tripId: provider.activeTrip!.id!,
        amount: finalAmount,
        category: _selectedCategory,
        paymentMethod: _selectedPaymentMethod,
        date: combinedDateTime,
        title: _titleController.text.isEmpty ? null : _titleController.text,
        note: _noteController.text.isEmpty ? null : _noteController.text,
        imagePath: _selectedImage?.path,
        latitude: _latitude,
        longitude: _longitude,
        locationName: _locationName,
        originalCurrency: actualInputCurrency != tripCurrency ? actualInputCurrency : null,
        originalAmount: actualInputCurrency != tripCurrency ? inputAmount : null,
      );

      if (_isEditing) {
        provider.updateExpense(expense);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지출이 수정되었습니다')));
      } else {
        provider.addExpense(expense);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('지출이 추가되었습니다')));
      }

      Navigator.pop(context);
    }
  }

  void _deleteExpense() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지출 삭제'),
        content: const Text('이 지출을 삭제하시겠습니까?'),
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
              provider.deleteExpense(widget.expense!.id!);
              Navigator.pop(context);
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('지출이 삭제되었습니다')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(_isEditing ? '지출 수정' : '지출 추가'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: _isEditing
            ? [
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _deleteExpense,
                ),
              ]
            : null,
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          final c = provider.isCompactMode;
          return Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: EdgeInsets.all(c ? 8 : 16),
                    children: [
                // 영수증 스캔
                if (!_isEditing)
                  Container(
                    margin: EdgeInsets.only(bottom: c ? 6 : 16),
                    child: InkWell(
                      onTap: _scanReceipt,
                      child: Container(
                        padding: EdgeInsets.symmetric(vertical: c ? 10 : 14, horizontal: c ? 12 : 16),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF9F43), Color(0xFFFF6B6B)],
                          ),
                          borderRadius: BorderRadius.circular(c ? 10 : 16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFFF9F43).withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.document_scanner, color: Colors.white, size: c ? 20 : 24),
                            const SizedBox(width: 10),
                            Text(
                              '영수증 스캔',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: c ? 14 : 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // 금액 입력
                Container(
                  padding: EdgeInsets.all(c ? 10 : 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '금액',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _inputCurrency ?? provider.selectedCurrency,
                                isDense: true,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6C63FF),
                                ),
                                icon: const Icon(Icons.swap_horiz, size: 16, color: Color(0xFF6C63FF)),
                                items: _availableCurrencies.map((cur) {
                                  return DropdownMenuItem(
                                    value: cur,
                                    child: Text('$cur ${_currencySymbols[cur] ?? cur}'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _inputCurrency = value == provider.selectedCurrency ? null : value;
                                  });
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            _currencySymbols[_inputCurrency ?? provider.selectedCurrency] ?? provider.currencySymbol,
                            style: TextStyle(
                              fontSize: c ? 24 : 32,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF6C63FF),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: _amountController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [ThousandsSeparatorInputFormatter()],
                              style: TextStyle(
                                fontSize: c ? 24 : 32,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF2C3E50),
                              ),
                              decoration: const InputDecoration(
                                hintText: '0',
                                border: InputBorder.none,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return '금액을 입력해주세요';
                                }
                                if (double.tryParse(value.replaceAll(',', '')) == null) {
                                  return '유효한 금액을 입력해주세요';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      if (_inputCurrency != null && _inputCurrency != provider.selectedCurrency) ...[
                        const SizedBox(height: 8),
                        Builder(builder: (context) {
                          final inputAmt = double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;
                          final tripCur = provider.selectedCurrency;
                          final converted = ExchangeRateService.instance.convert(inputAmt, _inputCurrency!, tripCur);
                          final krw = ExchangeRateService.instance.convertToKRW(inputAmt, _inputCurrency!);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '≈ ${provider.currencySymbol}${converted.toStringAsFixed(0)} ($tripCur)',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600], fontWeight: FontWeight.w500),
                              ),
                              if (tripCur != 'KRW')
                                Text(
                                  '≈ ₩${krw.toStringAsFixed(0)} (KRW)',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                                ),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
                ),

                SizedBox(height: c ? 6 : 16),

                // 제목
                Container(
                  padding: EdgeInsets.all(c ? 8 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: '제목 (선택사항)',
                      hintText: '예: 점심 식사',
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.title, color: Color(0xFF6C63FF)),
                      isDense: c,
                      contentPadding: c ? const EdgeInsets.symmetric(vertical: 8) : null,
                    ),
                    style: c ? const TextStyle(fontSize: 13) : null,
                  ),
                ),

                SizedBox(height: c ? 6 : 16),

                // 카테고리
                Container(
                  padding: EdgeInsets.all(c ? 8 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
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
                        '카테고리',
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
                        children: [
                          ...provider.categories.map((category) {
                            final isSelected =
                                _selectedCategory == category['name'];
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = category['name'];
                                });
                              },
                              onLongPress: provider.categories.length > 1
                                  ? () => _showDeleteCategoryDialog(
                                      context, provider, category)
                                  : null,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: c ? 10 : 16,
                                  vertical: c ? 8 : 12,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Color(category['color'])
                                      : Color(category['color'])
                                          .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(c ? 8 : 12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      category['icon'],
                                      style: TextStyle(fontSize: c ? 16 : 20),
                                    ),
                                    SizedBox(width: c ? 4 : 8),
                                    Text(
                                      category['name'],
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Color(category['color']),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          InkWell(
                              onTap: () =>
                                  _showEditCategoryDialog(context, provider),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: c ? 10 : 16,
                                  vertical: c ? 8 : 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(c ? 8 : 12),
                                  border: Border.all(
                                    color: Colors.grey[300]!,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit,
                                        size: c ? 16 : 20, color: Colors.grey[600]),
                                    SizedBox(width: c ? 2 : 4),
                                    Text(
                                      '편집',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: c ? 6 : 16),

                // 결제 방법
                Container(
                  padding: EdgeInsets.all(c ? 8 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
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
                        '결제 방법',
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
                            child: _buildPaymentMethodButton(
                              '현금',
                              'cash',
                              Icons.money,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildPaymentMethodButton(
                              '카드',
                              'card',
                              Icons.credit_card,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                SizedBox(height: c ? 6 : 16),

                // 날짜와 시간
                Container(
                  padding: EdgeInsets.all(c ? 8 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
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
                        '날짜 및 시간',
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
                              onTap: _selectDate,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6C63FF,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.calendar_today,
                                      color: Color(0xFF6C63FF),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_selectedDate.month}/${_selectedDate.day}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: _selectTime,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6C63FF,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.access_time,
                                      color: Color(0xFF6C63FF),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
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

                SizedBox(height: c ? 6 : 16),

                // 메모
                Container(
                  padding: EdgeInsets.all(c ? 8 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: '메모 (선택사항)',
                      border: InputBorder.none,
                      prefixIcon: const Icon(Icons.note),
                      isDense: c,
                      contentPadding: c ? const EdgeInsets.symmetric(vertical: 8) : null,
                    ),
                    maxLines: c ? 1 : 3,
                    style: c ? const TextStyle(fontSize: 13) : null,
                  ),
                ),

                SizedBox(height: c ? 6 : 16),

                // 사진 추가
                Container(
                  padding: EdgeInsets.all(c ? 8 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
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
                      InkWell(
                        onTap: _pickImage,
                        child: Row(
                          children: [
                            const Icon(
                              Icons.photo_camera,
                              color: Color(0xFF6C63FF),
                            ),
                            const SizedBox(width: 12),
                            const Text(
                              '사진 추가 (선택사항)',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_selectedImage != null) ...[
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            _selectedImage!,
                            height: c ? 100 : 150,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                SizedBox(height: c ? 6 : 16),

                // 위치
                Container(
                  padding: EdgeInsets.all(c ? 8 : 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '위치 (선택사항)',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_locationName != null)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: _clearLocation,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // 지도 미리보기
                      if (_latitude != null && _longitude != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: c ? 100 : 150,
                            width: double.infinity,
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(_latitude!, _longitude!),
                                zoom: 15,
                              ),
                              markers: {
                                Marker(
                                  markerId: const MarkerId('selected'),
                                  position: LatLng(_latitude!, _longitude!),
                                ),
                              },
                              zoomControlsEnabled: false,
                              scrollGesturesEnabled: false,
                              zoomGesturesEnabled: false,
                              tiltGesturesEnabled: false,
                              rotateGesturesEnabled: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],

                      if (_locationName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _locationName!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2C3E50),
                            ),
                          ),
                        ),

                      // 위치 선택 버튼들
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _saveCurrentLocation,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6C63FF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.my_location,
                                      color: Color(0xFF6C63FF),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '현재 위치 저장',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6C63FF),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: _searchLocation,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6C63FF).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.search,
                                      color: Color(0xFF6C63FF),
                                      size: 20,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      '검색',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF6C63FF),
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

                SizedBox(height: c ? 16 : 24),

                // 저장 버튼
                ElevatedButton(
                  onPressed: _saveExpense,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6C63FF),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: c ? 10 : 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(c ? 8 : 12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isEditing ? '수정' : '저장',
                    style: TextStyle(
                      fontSize: c ? 15 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 100),
                    ],
                  ),
                ),
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
    );
  }

  Widget _buildPaymentMethodButton(String label, String value, IconData icon) {
    final isSelected = _selectedPaymentMethod == value;
    final c = Provider.of<ExpenseProvider>(context, listen: false).isCompactMode;

    return InkWell(
      onTap: () {
        setState(() {
          _selectedPaymentMethod = value;
        });
      },
      child: Container(
        padding: EdgeInsets.symmetric(vertical: c ? 8 : 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6C63FF)
              : const Color(0xFF6C63FF).withOpacity(0.1),
          borderRadius: BorderRadius.circular(c ? 8 : 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : const Color(0xFF6C63FF),
              size: c ? 18 : 24,
            ),
            SizedBox(width: c ? 4 : 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF6C63FF),
                fontWeight: FontWeight.w600,
                fontSize: c ? 13 : 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 숫자 입력 시 세 자리마다 쉼표를 자동 추가하는 포매터
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 빈 값이면 그대로
    if (newValue.text.isEmpty) return newValue;

    // 숫자와 소수점만 남기기
    final cleanText = newValue.text.replaceAll(',', '');

    // 숫자(소수점 포함)가 아니면 이전 값 유지
    if (double.tryParse(cleanText) == null && cleanText != '.') {
      return oldValue;
    }

    // 소수점 분리
    final parts = cleanText.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? '.${parts[1]}' : '';

    // 정수 부분에 쉼표 추가
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(intPart[i]);
    }

    final formatted = '$buffer$decPart';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
