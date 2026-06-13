import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' hide context;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'api_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FinanceApp());
}

class FinanceApp extends StatelessWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Catat Keuangan',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[100],
      ),
      home: const DashboardScreen(),
    );
  }
}

// ==========================================
// 1. MODEL DATA
// ==========================================
class TransactionItem {
  final int? id;
  final String title;
  final double amount;
  final int isIncome; // 1 = Pemasukan, 0 = Pengeluaran
  final DateTime date;

  TransactionItem({
    this.id,
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.date,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'isIncome': isIncome,
      'date': date.toIso8601String(),
    };
  }

  factory TransactionItem.fromMap(Map<String, dynamic> map) {
    return TransactionItem(
      id: map['id'],
      title: map['title'],
      amount: map['amount'],
      isIncome: map['isIncome'],
      date: DateTime.parse(map['date']),
    );
  }
}

// ==========================================
// 2. DATABASE HELPER (CRUD)
// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('finance.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(path, version: 1, onCreate: _createDB);
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        isIncome INTEGER NOT NULL,
        date TEXT NOT NULL
      )
    ''');
  }

  // CREATE
  Future<int> insertTransaction(TransactionItem transaction) async {
    final db = await instance.database;
    return await db.insert('transactions', transaction.toMap());
  }

  // READ ALL
  Future<List<TransactionItem>> fetchTransactions() async {
    final db = await instance.database;
    final maps = await db.query('transactions', orderBy: 'date DESC');
    return maps.map((json) => TransactionItem.fromMap(json)).toList();
  }

  // DELETE
  Future<int> deleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
}

// ==========================================
// 3. UI DASHBOARD & GRAFIK
// ==========================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<TransactionItem> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshTransactions();
  }

  Future<void> _refreshTransactions() async {
    setState(() => _isLoading = true);
    _transactions = await DatabaseHelper.instance.fetchTransactions();
    setState(() => _isLoading = false);
  }

  // Fungsi untuk memunculkan BottomSheet (Form Tambah Data)
  void _showAddTransactionModal() {
    final titleController = TextEditingController();
    final amountController = TextEditingController();
    int isIncome = 0; // Default: Pengeluaran

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: 'Keterangan (Contoh: Beli Kopi)'),
                  ),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(labelText: 'Nominal (Rp)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      ChoiceChip(
                        label: const Text('Pengeluaran'),
                        selected: isIncome == 0,
                        selectedColor: Colors.red[200],
                        onSelected: (val) => setModalState(() => isIncome = 0),
                      ),
                      ChoiceChip(
                        label: const Text('Pemasukan'),
                        selected: isIncome == 1,
                        selectedColor: Colors.green[200],
                        onSelected: (val) => setModalState(() => isIncome = 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () async {
                      if (titleController.text.isEmpty || amountController.text.isEmpty) return;
                      
                      final newTx = TransactionItem(
                        title: titleController.text,
                        amount: double.parse(amountController.text),
                        isIncome: isIncome,
                        date: DateTime.now(),
                      );
                      
                      await DatabaseHelper.instance.insertTransaction(newTx);
                      _refreshTransactions(); // Perbarui UI & Grafik
                      Navigator.of(context).pop();
                    },
                    child: const Text('Simpan Data'),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Logika untuk mengelompokkan data ke dalam grafik (7 hari terakhir)
  List<BarChartGroupData> _generateChartData() {
    // Inisialisasi data 7 hari (0 = hari ini, 6 = 6 hari lalu)
    List<Map<String, double>> weeklyData = List.generate(7, (index) => {'income': 0.0, 'expense': 0.0});
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    double maxVal = 10000; // Skala default grafik

    for (var tx in _transactions) {
      final txDate = DateTime(tx.date.year, tx.date.month, tx.date.day);
      final difference = today.difference(txDate).inDays;

      if (difference >= 0 && difference < 7) {
        if (tx.isIncome == 1) {
          weeklyData[difference]['income'] = (weeklyData[difference]['income'] ?? 0) + tx.amount;
        } else {
          weeklyData[difference]['expense'] = (weeklyData[difference]['expense'] ?? 0) + tx.amount;
        }
        
        // Cari nilai tertinggi untuk skala grafik
        if (weeklyData[difference]['income']! > maxVal) maxVal = weeklyData[difference]['income']!;
        if (weeklyData[difference]['expense']! > maxVal) maxVal = weeklyData[difference]['expense']!;
      }
    }

    return List.generate(7, (index) {
      // Kita membalik urutannya agar hari terlama ada di sebelah kiri grafik
      int reversedIndex = 6 - index;
      double inc = weeklyData[reversedIndex]['income']!;
      double exp = weeklyData[reversedIndex]['expense']!;
      
      // Normalisasi nilai agar muat di chart (misal skala Y max 20)
      double barInc = (inc / maxVal) * 20;
      double barExp = (exp / maxVal) * 20;

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(toY: barInc, color: Colors.green, width: 10, borderRadius: BorderRadius.circular(2)),
          BarChartRodData(toY: barExp, color: Colors.redAccent, width: 10, borderRadius: BorderRadius.circular(2)),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard Keuangan'),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.api),
            tooltip: 'Test Koneksi API',
            onPressed: () async {
              // Menampilkan loading indikator (opsional)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Menghubungi Server API...')),
              );

              // Memanggil fungsi dari api_service.dart
              final apiService = FinanceApiService();
              final token = await apiService.getPublicToken();

              if (token != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Koneksi Berhasil! Token diterima.', style: TextStyle(color: Colors.green))),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Koneksi Gagal. Cek console log.', style: TextStyle(color: Colors.red))),
                );
              }
            },
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // BAGIAN GRAFIK
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  height: 250,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                  ),
                  child: Column(
                    children: [
                      const Text('Pemasukan & Pengeluaran (7 Hari Terakhir)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      Expanded(
                        child: BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: 20,
                            barTouchData: BarTouchData(enabled: false),
                            titlesData: FlTitlesData(
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    // Membuat label tanggal di bawah grafik
                                    final date = DateTime.now().subtract(Duration(days: 6 - value.toInt()));
                                    return Text(DateFormat('dd/MM').format(date), style: const TextStyle(fontSize: 10));
                                  },
                                ),
                              ),
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                            ),
                            borderData: FlBorderData(show: false),
                            barGroups: _generateChartData(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // BAGIAN LIST HISTORY (CRUD - Read & Delete)
                Expanded(
                  child: ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final tx = _transactions[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: tx.isIncome == 1 ? Colors.green[100] : Colors.red[100],
                            child: Icon(
                              tx.isIncome == 1 ? Icons.arrow_downward : Icons.arrow_upward,
                              color: tx.isIncome == 1 ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Text(tx.title, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(DateFormat('dd MMM yyyy, HH:mm').format(tx.date)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                currencyFormatter.format(tx.amount),
                                style: TextStyle(
                                  color: tx.isIncome == 1 ? Colors.green : Colors.red,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.grey),
                                onPressed: () async {
                                  await DatabaseHelper.instance.deleteTransaction(tx.id!);
                                  _refreshTransactions();
                                },
                              )
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTransactionModal,
        child: const Icon(Icons.add),
      ),
    );
  }
}