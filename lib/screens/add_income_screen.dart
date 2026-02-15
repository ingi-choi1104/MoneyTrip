import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../models/income.dart';
import 'add_expense_screen.dart' show ThousandsSeparatorInputFormatter;

class AddIncomeScreen extends StatefulWidget {
  final DateTime? initialDate;
  final bool isPreTrip;

  const AddIncomeScreen({Key? key, this.initialDate, this.isPreTrip = false}) : super(key: key);

  @override
  State<AddIncomeScreen> createState() => _AddIncomeScreenState();
}

class _AddIncomeScreenState extends State<AddIncomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    if (widget.initialDate != null) {
      _selectedDate = widget.initialDate!;
    } else if (widget.isPreTrip) {
      final provider = Provider.of<ExpenseProvider>(context, listen: false);
      if (provider.activeTrip != null) {
        final tripStart = provider.activeTrip!.startDate;
        final today = DateTime.now();
        _selectedDate = today.isBefore(tripStart)
            ? today
            : tripStart.subtract(const Duration(days: 1));
      } else {
        _selectedDate = DateTime.now();
      }
    } else {
      _selectedDate = DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _saveIncome() {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<ExpenseProvider>(context, listen: false);

      if (provider.activeTrip == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('먼저 여행을 생성해주세요')));
        return;
      }

      final income = Income(
        tripId: provider.activeTrip!.id!,
        amount: double.parse(_amountController.text.replaceAll(',', '')),
        date: _selectedDate,
        note: _noteController.text.isEmpty ? null : _noteController.text,
      );

      provider.addIncome(income);
      Navigator.pop(context);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('예산이 추가되었습니다')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('예산 추가'),
        backgroundColor: const Color(0xFF51CF66),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Consumer<ExpenseProvider>(
        builder: (context, provider, child) {
          final c = provider.isCompactMode;
          return Form(
            key: _formKey,
            child: ListView(
              padding: EdgeInsets.all(c ? 8 : 16),
              children: [
                // 금액 입력
                Container(
                  padding: EdgeInsets.all(c ? 10 : 24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF51CF66), Color(0xFF40C057)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(c ? 10 : 20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF51CF66).withOpacity(0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '금액',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            provider.currencySymbol,
                            style: TextStyle(
                              fontSize: c ? 24 : 32,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
                                color: Colors.white,
                              ),
                              decoration: const InputDecoration(
                                hintText: '0',
                                hintStyle: TextStyle(color: Colors.white54),
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
                    ],
                  ),
                ),

                SizedBox(height: c ? 6 : 16),

                // 날짜 선택
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
                  child: InkWell(
                    onTap: () async {
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
                    },
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today,
                          color: Color(0xFF51CF66),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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
                      prefixIcon: const Icon(Icons.note, color: Color(0xFF51CF66)),
                      isDense: c,
                      contentPadding: c ? const EdgeInsets.symmetric(vertical: 8) : null,
                    ),
                    maxLines: c ? 1 : 3,
                    style: c ? const TextStyle(fontSize: 13) : null,
                  ),
                ),

                SizedBox(height: c ? 16 : 24),

                // 저장 버튼
                ElevatedButton(
                  onPressed: _saveIncome,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF51CF66),
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: c ? 10 : 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(c ? 8 : 12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    '저장',
                    style: TextStyle(fontSize: c ? 15 : 18, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 60),
              ],
            ),
          );
        },
      ),
    );
  }
}
