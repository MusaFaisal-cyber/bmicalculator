import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

class AppColors {
  static const bg = Color(0xFF141414);
  static const card = Color.fromARGB(255, 31, 31, 31);
  static const cardAlt = Color(0xFF262626);
  static const accent = Color.fromARGB(255, 77, 240, 255);
  static const accentDim = Color.fromARGB(255, 32, 40, 68); 
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFF9C9C9C);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await Hive.initFlutter();
  Hive.registerAdapter(BmiRecordAdapter());
  await Hive.openBox<BmiRecord>('bmi_history');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BmiProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => MealPlanProvider()),
      ],
      child: MaterialApp(
        title: 'BMI Calculator',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppColors.bg,
          primaryColor: AppColors.accent,
          colorScheme: const ColorScheme.dark(
            primary: AppColors.accent,
            surface: AppColors.card,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: AppColors.bg,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: AppColors.card,
            hintStyle: const TextStyle(color: AppColors.textSecondary),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          ),
        ),
        home: const SplashController(),
      ),
    );
  }
}

class SplashController extends StatefulWidget {
  const SplashController({super.key});

  @override
  State<SplashController> createState() => _SplashControllerState();
}

class _SplashControllerState extends State<SplashController> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showSplash = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _showSplash ? const SplashScreen() : const AuthGate();
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity, // <-- forces full width
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, // <-- also center vertically-ish
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(Icons.hourglass_bottom_rounded,
                    color: AppColors.bg, size: 36),
              ),
              const SizedBox(height: 20),
              const Text(
                'BMI Calculator',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(flex: 4),
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}


class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: AppColors.bg,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            ),
          );
        }
        return snapshot.hasData ? const RootNav() : const LoginScreen();
      },
    );
  }
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
    writer.writeInt(obj.date.millisecondsSinceEpoch);
  }
}


class BmiProvider extends ChangeNotifier {
  double? bmi;
  String gender = 'Male';
  double height = 170;
  double weight = 65;
  int age = 25;
  List<BmiRecord> history = [];

  final Box<BmiRecord> _box = Hive.box<BmiRecord>('bmi_history');

  BmiProvider() {
    _loadHistory();
  }

  void _loadHistory() {
    history = _box.values.toList().reversed.toList();
  }

  Future<void> calculateAndSave() async {
    final heightM = height / 100;
    final calculatedBmi = weight / (heightM * heightM);
    bmi = calculatedBmi;
    final record = BmiRecord(
      bmi: calculatedBmi,
      height: height,
      weight: weight,
      gender: gender,
      date: DateTime.now(),
    );
    await _box.add(record);
    _loadHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _box.clear();
    _loadHistory();
    notifyListeners();
  }

  void setGender(String g) {
    gender = g;
    notifyListeners();
  }

  void setHeight(double h) {
    height = h;
    notifyListeners();
  }

  void setWeight(double w) {
    weight = w.clamp(20, 250);
    notifyListeners();
  }

  void setAge(int a) {
    age = a.clamp(1, 120);
    notifyListeners();
  }
}

// ---------------- CALORIE CALCULATION ----------------
//
// Three small, pure functions: BMI -> BMR -> TDEE -> target calories.
// Kept as top-level functions (not methods) so they're easy to unit-test
// on their own later if you want to.

/// Basal Metabolic Rate via the Mifflin-St Jeor equation — the calories
/// your body burns at complete rest.
double calculateBMR({
  required double weightKg,
  required double heightCm,
  required int age,
  required String gender,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return gender == 'Male' ? base + 5 : base - 161;
}

/// Total Daily Energy Expenditure = BMR x an activity multiplier.
/// The app doesn't currently ask the user how active they are, so this
/// defaults to "lightly active" (1.375). Swap this for a user-selected
/// multiplier later if you add an activity-level question.
double calculateTDEE(double bmr) {
  const activityMultiplier = 1.375;
  return bmr * activityMultiplier;
}

/// Turns TDEE + BMI category into a daily calorie target:
/// - BMI < 18.5  -> surplus, to gain weight
/// - BMI < 25.0  -> maintenance, normal diet
/// - BMI >= 25.0 -> deficit, to lose weight (never below a safe 1200 floor)
double calculateTargetCalories({
  required double bmi,
  required double tdee,
}) {
  if (bmi < 18.5) {
    return tdee + 500;
  } else if (bmi < 25.0) {
    return tdee;
  } else {
    final target = tdee - 500;
    return target < 1200 ? 1200 : target;
  }
}

// ---------------- MEAL PLAN (SPOONACULAR) ----------------

class MealPlanMeal {
  final int id;
  final String title;
  final String imageUrl;
  final int readyInMinutes;
  final int servings;
  final String sourceUrl;

  MealPlanMeal({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.readyInMinutes,
    required this.servings,
    required this.sourceUrl,
  });

  factory MealPlanMeal.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as int;
    final imageType = json['imageType'] as String? ?? 'jpg';
    return MealPlanMeal(
      id: id,
      title: json['title'] as String? ?? 'Untitled recipe',
      imageUrl: 'https://spoonacular.com/recipeImages/$id-312x231.$imageType',
      readyInMinutes: json['readyInMinutes'] as int? ?? 0,
      servings: json['servings'] as int? ?? 1,
      sourceUrl: json['sourceUrl'] as String? ?? '',
    );
  }
}

class MealPlanNutrients {
  final double calories;
  final double protein;
  final double fat;
  final double carbohydrates;

  MealPlanNutrients({
    required this.calories,
    required this.protein,
    required this.fat,
    required this.carbohydrates,
  });

  factory MealPlanNutrients.fromJson(Map<String, dynamic> json) {
    return MealPlanNutrients(
      calories: (json['calories'] as num?)?.toDouble() ?? 0,
      protein: (json['protein'] as num?)?.toDouble() ?? 0,
      fat: (json['fat'] as num?)?.toDouble() ?? 0,
      carbohydrates: (json['carbohydrates'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DailyMealPlan {
  final List<MealPlanMeal> meals;
  final MealPlanNutrients nutrients;

  DailyMealPlan({required this.meals, required this.nutrients});

  factory DailyMealPlan.fromJson(Map<String, dynamic> json) {
    final mealsJson = json['meals'] as List<dynamic>? ?? [];
    return DailyMealPlan(
      meals: mealsJson
          .map((m) => MealPlanMeal.fromJson(m as Map<String, dynamic>))
          .toList(),
      nutrients: MealPlanNutrients.fromJson(
          json['nutrients'] as Map<String, dynamic>? ?? {}),
    );
  }
}

class MealPlanService {
  // TODO: paste your own Spoonacular API key here.
  // Get a free one at https://spoonacular.com/food-api (Sign Up -> Profile -> API Key).
  // NOTE: shipping a key like this directly in client code is fine for a
  // student/learning project, but not for a production app — for that
  // you'd proxy this call through your own backend so the key never
  // ships inside the APK.
  static const String _apiKey = '425edd131a2d45deb8015964f0f274b0';

  static Future<DailyMealPlan> fetchDailyMealPlan(double targetCalories) async {
    final uri = Uri.https('api.spoonacular.com', '/mealplanner/generate', {
      'timeFrame': 'day',
      'targetCalories': targetCalories.round().toString(),
      'apiKey': _apiKey,
    });

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Spoonacular request failed (${response.statusCode})');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return DailyMealPlan.fromJson(data);
  }
}

class MealPlanProvider extends ChangeNotifier {
  bool isLoading = false;
  String? errorMessage;
  DailyMealPlan? plan;
  double? targetCalories;

  /// Runs the full pipeline: BMR -> TDEE -> target calories -> API call.
  Future<void> generateForBmi({
    required double bmi,
    required double weightKg,
    required double heightCm,
    required int age,
    required String gender,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final bmr = calculateBMR(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        gender: gender,
      );
      final tdee = calculateTDEE(bmr);
      targetCalories = calculateTargetCalories(bmi: bmi, tdee: tdee);

      plan = await MealPlanService.fetchDailyMealPlan(targetCalories!);
    } catch (e) {
      errorMessage = 'Could not load a meal plan right now.';
      plan = null;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }
}


class AuthProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  bool isLoading = false;
  String? errorMessage;

  Future<bool> login(String email, String password) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      errorMessage = _mapError(e.code);
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp({
    required String name,
    required String email,
    required String password,
    required String gender,
    required int age,
  }) async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await credential.user?.updateDisplayName(name);
      // Gender/age aren't native FirebaseAuth fields — persist to
      // Firestore/Realtime DB here using credential.user!.uid if needed.
      isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      errorMessage = _mapError(e.code);
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
  }

  String _mapError(String code) {
    switch (code) {
      case 'invalid-email':
        return 'That email address is invalid.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
        return 'No account found with that email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'email-already-in-use':
        return 'An account already exists with that email.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}


class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final success =
        await auth.login(_emailController.text.trim(), _passwordController.text);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Login failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 40),
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child:
                        const Icon(Icons.lock_outline, color: AppColors.bg, size: 30),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Welcome Back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      hintText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined, color: AppColors.textSecondary),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your email';
                      }
                      final emailRegex = RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,4}$');
                      if (!emailRegex.hasMatch(value.trim())) {
                        return 'Enter a valid email address';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    style: const TextStyle(color: AppColors.textPrimary),
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      hintText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textSecondary),
                      suffixIcon: IconButton(
                        icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            color: AppColors.textSecondary),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 28),
                  auth.isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: AppColors.accent))
                      : ElevatedButton(
                          onPressed: _handleLogin,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            backgroundColor: AppColors.accent,
                            foregroundColor: AppColors.bg,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text('Login',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                  const SizedBox(height: 20),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SignUpScreen()),
                      );
                    },
                    child: const Text(
                      "Don't have an account? Create Account",
                      style: TextStyle(color: AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _ageController = TextEditingController();
  String? _selectedGender;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    final isFormValid = _formKey.currentState!.validate();
    if (!isFormValid || _selectedGender == null) {
      if (_selectedGender == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select your gender')),
        );
      }
      return;
    }
    final auth = context.read<AuthProvider>();
    final success = await auth.signUp(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      gender: _selectedGender!,
      age: int.parse(_ageController.text.trim()),
    );
    if (success && mounted) {
      Navigator.of(context).pop();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(auth.errorMessage ?? 'Sign up failed')),
      );
    }
  }

  InputDecoration _dec(String hint, IconData icon) => InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textSecondary),
      );

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: _dec('Full Name', Icons.person_outline),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your name';
                    if (value.trim().length < 2) return 'Name is too short';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec('Email', Icons.email_outlined),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your email';
                    final emailRegex = RegExp(r'^[\w.\-]+@([\w\-]+\.)+[\w\-]{2,4}$');
                    if (!emailRegex.hasMatch(value.trim())) return 'Enter a valid email address';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline, color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: AppColors.textSecondary),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter a password';
                    if (value.length < 6) return 'Password must be at least 6 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _selectedGender,
                  dropdownColor: AppColors.card,
                  style: const TextStyle(color: AppColors.textPrimary),
                  decoration: _dec('Gender', Icons.wc_outlined),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) => setState(() => _selectedGender = value),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _ageController,
                  style: const TextStyle(color: AppColors.textPrimary),
                  keyboardType: TextInputType.number,
                  decoration: _dec('Age', Icons.cake_outlined),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Please enter your age';
                    final age = int.tryParse(value.trim());
                    if (age == null) return 'Enter a valid number';
                    if (age < 13 || age > 120) return 'Enter an age between 13 and 120';
                    return null;
                  },
                ),
                const SizedBox(height: 28),
                auth.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : ElevatedButton(
                        onPressed: _handleSignUp,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.bg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('Create Account',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class RootNav extends StatefulWidget {
  const RootNav({super.key});

  @override
  State<RootNav> createState() => _RootNavState();
}

class _RootNavState extends State<RootNav> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    BmiHomePage(),
    HistoryPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _selectedIndex, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.card,
        currentIndex: _selectedIndex,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textSecondary,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.calculate), label: 'Calculator'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}


class BmiHomePage extends StatelessWidget {
  const BmiHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BmiProvider>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hourglass_bottom_rounded,
                  color: AppColors.bg, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('BMI Calculator'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.textSecondary),
            onPressed: () => context.read<AuthProvider>().logout(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Gender cards
            Row(
              children: [
                Expanded(
                  child: _GenderCard(
                    label: 'MALE',
                    icon: Icons.male,
                    selected: provider.gender == 'Male',
                    onTap: () => context.read<BmiProvider>().setGender('Male'),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _GenderCard(
                    label: 'FEMALE',
                    icon: Icons.female,
                    selected: provider.gender == 'Female',
                    onTap: () => context.read<BmiProvider>().setGender('Female'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Height slider card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Height',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      _UnitPill(label: 'CM'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    provider.height.toStringAsFixed(0),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 44,
                        fontWeight: FontWeight.bold),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: AppColors.accent,
                      inactiveTrackColor: AppColors.cardAlt,
                      thumbColor: AppColors.accent,
                      overlayColor: AppColors.accent.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      min: 100,
                      max: 220,
                      value: provider.height.clamp(100, 220),
                      onChanged: (v) => context.read<BmiProvider>().setHeight(v),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Weight & Age steppers
            Row(
              children: [
                Expanded(
                  child: _StepperCard(
                    label: 'Weight',
                    unit: 'kg',
                    value: provider.weight.toStringAsFixed(0),
                    onIncrement: () =>
                        context.read<BmiProvider>().setWeight(provider.weight + 1),
                    onDecrement: () =>
                        context.read<BmiProvider>().setWeight(provider.weight - 1),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _StepperCard(
                    label: 'Age',
                    unit: 'Year',
                    value: provider.age.toString(),
                    onIncrement: () =>
                        context.read<BmiProvider>().setAge(provider.age + 1),
                    onDecrement: () =>
                        context.read<BmiProvider>().setAge(provider.age - 1),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final bmiProvider = context.read<BmiProvider>();
                  await bmiProvider.calculateAndSave();
                  if (context.mounted) {
                    // Kick off the meal-plan pipeline (BMR -> TDEE -> target
                    // calories -> Spoonacular). ResultPage watches this
                    // provider and will show its own loading/error state.
                    context.read<MealPlanProvider>().generateForBmi(
                          bmi: bmiProvider.bmi!,
                          weightKg: bmiProvider.weight,
                          heightCm: bmiProvider.height,
                          age: bmiProvider.age,
                          gender: bmiProvider.gender,
                        );
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ResultPage()),
                    );
                  }
                },
                icon: const Icon(Icons.refresh, color: AppColors.bg),
                label: const Text('Calculate',
                    style: TextStyle(
                        color: AppColors.bg,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenderCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _GenderCard({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentDim : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: selected ? AppColors.accent : AppColors.textSecondary, size: 30),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.accent : AppColors.textSecondary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitPill extends StatelessWidget {
  final String label;
  const _UnitPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
            color: AppColors.bg, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _StepperCard extends StatelessWidget {
  final String label;
  final String unit;
  final String value;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  const _StepperCard({
    required this.label,
    required this.unit,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _StepButton(icon: Icons.remove, onTap: onDecrement),
              Text(value,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold)),
              _StepButton(icon: Icons.add, onTap: onIncrement),
            ],
          ),
          const SizedBox(height: 6),
          Text(unit, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: AppColors.bg),
      ),
    );
  }
}

class ResultPage extends StatelessWidget {
  const ResultPage({super.key});

  String category(double bmi) {
    if (bmi < 18.5) return 'Underweight';
    if (bmi < 25) return 'Good Weight';
    if (bmi <= 30) return 'Overweight';
    return 'Obese';
  }

  Color categoryColor(double bmi) {
    if (bmi < 18.5) return Colors.lightBlueAccent;
    if (bmi < 25) return AppColors.accent;
    if (bmi <= 30) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  List<String> tips(double bmi) {
    if (bmi < 18.5) {
      return [
        'Eat more calories: nuts, avocados and healthy oils.',
        'Increase portion sizes during meals.',
        'Choose nutrient-rich foods: lean meats, fish, eggs, legumes.',
        'Include complex carbohydrates for sustained energy.',
      ];
    } else if (bmi < 25) {
      return [
        'Maintain a balanced diet with regular meals.',
        'Keep up consistent physical activity.',
        'Stay hydrated and get enough sleep.',
        'Monitor your weight periodically.',
      ];
    } else if (bmi <= 30) {
      return [
        'Reduce intake of refined sugar and processed food.',
        'Add more whole grains, fruits and vegetables.',
        'Aim for 30 minutes of activity most days.',
        'Watch portion sizes at meals.',
      ];
    } else {
      return [
        'Consider consulting a healthcare professional.',
        'Build a structured, sustainable meal plan.',
        'Increase activity gradually and consistently.',
        'Focus on whole, unprocessed foods.',
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BmiProvider>();
    final mealPlanProvider = context.watch<MealPlanProvider>();
    final bmi = provider.bmi ?? 0;
    final color = categoryColor(bmi);
    // Map bmi (15-35 clamp) onto a 0-1 slider position for the gauge dot.
    final gaugePos = ((bmi - 15) / (35 - 15)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.hourglass_bottom_rounded,
                  color: AppColors.bg, size: 16),
            ),
            const SizedBox(width: 10),
            const Text('BMI Calculator'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Result',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Your BMI is',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                      Text(category(bmi),
                          style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    bmi.toStringAsFixed(1),
                    style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 44,
                        fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: const LinearGradient(colors: [
                            Colors.lightBlueAccent,
                            AppColors.accent,
                            Colors.orangeAccent,
                            Colors.redAccent,
                          ]),
                        ),
                      ),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final dotX = gaugePos * constraints.maxWidth;
                          return Positioned(
                            left: (dotX - 8).clamp(0, constraints.maxWidth - 16),
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: color, width: 3),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(category(bmi),
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('Diet and Nutrition',
                style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...tips(bmi).map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  ',
                        style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Text(t,
                          style: const TextStyle(color: AppColors.textPrimary, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),

            // ---- Suggested meal plan (Spoonacular) ----
            const SizedBox(height: 24),
            const Text('Suggested Meal Plan',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.bold)),
            if (mealPlanProvider.targetCalories != null) ...[
              const SizedBox(height: 4),
              Text(
                'Target: ${mealPlanProvider.targetCalories!.round()} kcal/day',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 12),
            if (mealPlanProvider.isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else if (mealPlanProvider.errorMessage != null)
              Text(mealPlanProvider.errorMessage!,
                  style: const TextStyle(color: Colors.redAccent))
            else if (mealPlanProvider.plan == null)
              const Text('No meal plan loaded yet.',
                  style: TextStyle(color: AppColors.textSecondary))
            else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _NutrientStat(
                        label: 'Cal',
                        value: mealPlanProvider.plan!.nutrients.calories.round().toString()),
                    _NutrientStat(
                        label: 'Protein',
                        value: '${mealPlanProvider.plan!.nutrients.protein.round()}g'),
                    _NutrientStat(
                        label: 'Fat',
                        value: '${mealPlanProvider.plan!.nutrients.fat.round()}g'),
                    _NutrientStat(
                        label: 'Carbs',
                        value: '${mealPlanProvider.plan!.nutrients.carbohydrates.round()}g'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ...mealPlanProvider.plan!.meals.map((meal) => _MealCard(meal: meal)),
            ],

            const SizedBox(height: 20),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.refresh, color: AppColors.bg),
                label: const Text('Re-Calculate',
                    style: TextStyle(
                        color: AppColors.bg,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NutrientStat extends StatelessWidget {
  final String label;
  final String value;
  const _NutrientStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: AppColors.accent, fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _MealCard extends StatelessWidget {
  final MealPlanMeal meal;
  const _MealCard({required this.meal});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              meal.imageUrl,
              width: 60,
              height: 60,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 60,
                height: 60,
                color: AppColors.cardAlt,
                child: const Icon(Icons.restaurant, color: AppColors.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(meal.title,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('${meal.readyInMinutes} min · ${meal.servings} serving(s)',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
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

  Color _catColor(double bmi) {
    if (bmi < 18.5) return Colors.lightBlueAccent;
    if (bmi < 25) return AppColors.accent;
    if (bmi <= 30) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BmiProvider>();
    final history = provider.history;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('BMI History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
            onPressed: history.isEmpty ? null : () => provider.clearHistory(),
            tooltip: 'Clear history',
          ),
        ],
      ),
      body: history.isEmpty
          ? const Center(
              child: Text('No BMI records yet.',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final record = history[index];
                final color = _catColor(record.bmi);
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          record.bmi.toStringAsFixed(1),
                          style: TextStyle(color: color, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${record.gender} · ${record.height.toStringAsFixed(0)}cm · ${record.weight.toStringAsFixed(0)}kg',
                              style: const TextStyle(
                                  color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(_formatDate(record.date),
                                style: const TextStyle(
                                    color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}