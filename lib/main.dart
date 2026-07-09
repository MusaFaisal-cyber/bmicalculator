import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(BmiRecordAdapter());
  await Hive.openBox<BmiRecord>('bmi_history');
  runApp(const MyApp());
}
class BmiRecord extends HiveObject {
  final double bmi;
  final double height;
  final double weight;
  final String gender;
  final DateTime date;
  BmiRecord({
    required this.bmi,
    required this.height,
    required this.weight,
    required this.gender,
    required this.date,
  });
}
class BmiRecordAdapter extends TypeAdapter<BmiRecord> {
  @override
  final int typeId = 0;
  @override
  BmiRecord read(BinaryReader reader) {
    return BmiRecord(
      bmi: reader.readDouble(),
      height: reader.readDouble(),
      weight: reader.readDouble(),
      gender: reader.readString(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
    );
  }
  @override
  void write(BinaryWriter writer, BmiRecord obj) {
    writer.writeDouble(obj.bmi);
    writer.writeDouble(obj.height);
    writer.writeDouble(obj.weight);
    writer.writeString(obj.gender);
    writer.writeInt(obj.date.millisecondsSinceEpoch);}
}
class BmiProvider extends ChangeNotifier {
  double? bmi;
  String gender = 'Male';
  double height = 0;
  double weight = 0;
  List<BmiRecord> history = [];
  final Box<BmiRecord> _box = Hive.box<BmiRecord>('bmi_history');
  BmiProvider() {
    _loadHistory();}
  void _loadHistory() {
    history = _box.values.toList().reversed.toList(); // newest first
  }
  Future<void> calculateAndSave({
    required double heightCm,
    required double weightKg,
    required String selectedGender,
  }) async {
    final heightM = heightCm / 100;
    final calculatedBmi = weightKg / (heightM * heightM);
    bmi = calculatedBmi;
    height = heightCm;
    weight = weightKg;
    gender = selectedGender;
    final record = BmiRecord(
      bmi: calculatedBmi,
      height: heightCm,
      weight: weightKg,
      gender: selectedGender,
      date: DateTime.now(),
    );
    await _box.add(record); 
    _loadHistory();
    notifyListeners();
  }
  Future<void> clearHistory() async {
    await _box.clear();
    _loadHistory();
    notifyListeners();}}
class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => BmiProvider(),
      child: MaterialApp(
        title: 'bmi Calculator',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: const BorderSide(color: Colors.grey),
            ),
          ),
        ),
        home: const RootNav(),
      ),
    );
  }}
class RootNav extends StatefulWidget {
  const RootNav({super.key});
  @override
  State<RootNav> createState() => _RootNavState();}
class _RootNavState extends State<RootNav> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    BmiHomePage(),
    HistoryPage(), 
    ];
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.calculate),
            label: 'Calculator',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
      ),
    );
  }}
class BmiHomePage extends StatefulWidget {
  const BmiHomePage({super.key});
  @override
  State<BmiHomePage> createState() => _BmiHomePageState();}
class _BmiHomePageState extends State<BmiHomePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController heightController = TextEditingController();
  final TextEditingController weightController = TextEditingController();
  String gender = 'Male';
  @override
  void dispose() {
    heightController.dispose();
    weightController.dispose();
    super.dispose();}
  String? validateHeight(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter height';}
    final double? height = double.tryParse(value);
    if (height == null) {
      return 'Enter a valid number';}
    if (height < 60) {
      return 'Height must be 60 cm or more';}
    return null;}
  String? validateWeight(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter weight';}
    final double? weight = double.tryParse(value);
    if (weight == null) {
      return 'Enter a valid number';}
if (weight < 20) {
      return 'Weight must be 20 kg or more';}
    return null;}
  Future<void> calculateBmi() async {
    if (_formKey.currentState!.validate()) {
      double heightCm = double.parse(heightController.text);
      double weightKg = double.parse(weightController.text);
      await context.read<BmiProvider>().calculateAndSave(
            heightCm: heightCm,
            weightKg: weightKg,
            selectedGender: gender,);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const ResultPage(),
        ),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BMI Calculator')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Gender',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Row(
                children: [
                  Radio<String>(
                    value: 'Male',
                    groupValue: gender,
                    onChanged: (value) {
                      setState(() {
                        gender = value!;
                      });
                    },
                  ),
                  const Text('Male'),
                  const SizedBox(width: 20),
                  Radio<String>(
                    value: 'Female',
                    groupValue: gender,
                    onChanged: (value) {
                      setState(() {
                        gender = value!;
                      });
                    },
                  ),
                  const Text('Female'),
                ],
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: heightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Height (cm)',
                  prefixIcon: Icon(Icons.height_rounded),
                ),
                validator: validateHeight,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Weight (kg)',
                  prefixIcon: Icon(Icons.line_weight_sharp),
                ),
                validator: validateWeight,
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: calculateBmi,
                  child: const Text(
                    'Calculate',
                    style: TextStyle(fontSize: 18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }}
class ResultPage extends StatelessWidget {
  const ResultPage({super.key});
  String category(double bmi) {
    if (bmi < 25) {
      return 'Good Weight';
    } else if (bmi >= 25 && bmi <= 30) {
      return 'Overweight';
    } else {
      return 'Obese';
    }}
Color categoryColor(double bmi) {
    if (bmi < 25) {
      return Colors.green;
    } else if (bmi >= 25 && bmi <= 30) {
      return Colors.purple;
    } else {
      return Colors.red;
    }}
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BmiProvider>();
    final bmi = provider.bmi ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('BMI Result')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Gender: ${provider.gender}',
              style: const TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your BMI is',
              style: TextStyle(fontSize: 20),
            ),
            const SizedBox(height: 10),
            Text(
              bmi.toStringAsFixed(2),
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                color: categoryColor(bmi),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                category(bmi),
                style: const TextStyle(
                  fontSize: 22,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.door_back_door_rounded),
              label: const Text('back'),
            ),
          ],
        ),
      ),
    );
  }
}
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  String _formatDate(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year}  $hour:$minute';
  }
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BmiProvider>();
    final history = provider.history;
    return Scaffold(
      appBar: AppBar(
        title: const Text('BMI History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: history.isEmpty ? null : () => provider.clearHistory(),
            tooltip: 'Clear history',
          ),
        ],
      ),
      body: history.isEmpty
          ? const Center(child: Text('No BMI records yet.'))
          : ListView.builder(
              itemCount: history.length,
              itemBuilder: (context, index) {
                final record = history[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(record.bmi.toStringAsFixed(1)),
                  ),
                  title: Text(
                    '${record.gender} · ${record.height.toStringAsFixed(0)}cm · ${record.weight.toStringAsFixed(0)}kg',
                  ),
                  subtitle: Text(_formatDate(record.date)),
                );
              },
            ),
    );
  }
}