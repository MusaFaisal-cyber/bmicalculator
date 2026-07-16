import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:fl_chart/fl_chart.dart';
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

/// Retries a Firestore operation with exponential backoff (1s, 2s, 4s)
/// when it fails with a transient `unavailable` error. Any other
/// FirebaseException (permission-denied, not-found, etc.) is rethrown
/// immediately since retrying won't help those.
Future<T> withFirestoreRetry<T>(Future<T> Function() action, {int retries = 3}) async {
  for (var attempt = 0; attempt < retries; attempt++) {
    try {
      return await action();
    } on FirebaseException catch (e) {
      final isLast = attempt == retries - 1;
      if (e.code != 'unavailable' || isLast) rethrow;
      await Future.delayed(Duration(seconds: 1 << attempt)); // 1s, 2s, 4s
    }
  }
  throw StateError('unreachable');
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // FIX: on Flutter Web, some networks (corporate proxies/VPNs,
  // certain ad-blockers or ISPs) silently drop Firestore's default
  // gRPC-Web streaming connection. Instead of erroring out, the
  // request just hangs — which is exactly the "buffers forever, then
  // times out after 15s" behavior seen on the Profile page. Forcing
  // Firestore to auto-detect and fall back to plain long-polling on
  // web works around this. This must be set before any other
  // Firestore call is made.
  if (kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      webExperimentalAutoDetectLongPolling: true,
    );
  }

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
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
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
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
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

// ---------------- BMI RECORD (Firestore-backed) ----------------

class BmiRecord {
  final String? id;
  final double bmi;
  final double height;
  final double weight;
  final String gender;
  final DateTime date;

  BmiRecord({
    this.id,
    required this.bmi,
    required this.height,
    required this.weight,
    required this.gender,
    required this.date,
  });

  factory BmiRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return BmiRecord(
      id: doc.id,
      bmi: (data['bmi'] as num).toDouble(),
      height: (data['height'] as num).toDouble(),
      weight: (data['weight'] as num).toDouble(),
      gender: data['gender'] as String,
      date: (data['date'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bmi': bmi,
      'height': height,
      'weight': weight,
      'gender': gender,
      'date': Timestamp.fromDate(date),
    };
  }
}

class BmiProvider extends ChangeNotifier {
  double? bmi;
  String gender = 'Male';
  double height = 170;
  double weight = 65;
  int age = 25;
  List<BmiRecord> history = [];
  bool isLoadingHistory = false;

  String? _uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _historySub;

  CollectionReference<Map<String, dynamic>> _historyRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid).collection('bmi_history');

  void loadHistory(String uid) {
    if (_uid == uid && _historySub != null) return;
    _uid = uid;
    isLoadingHistory = true;
    notifyListeners();
    _historySub?.cancel();
    _historySub = _historyRef(uid)
        .orderBy('date', descending: true)
        .snapshots()
        .listen((snapshot) {
      history = snapshot.docs.map(BmiRecord.fromFirestore).toList();
      isLoadingHistory = false;
      notifyListeners();
    }, onError: (e) {
      // ignore: avoid_print
      print('BMI history stream failed for uid=$uid: $e');
      isLoadingHistory = false;
      notifyListeners();
    });
  }

  void clearUser() {
    _historySub?.cancel();
    _historySub = null;
    _uid = null;
    history = [];
    bmi = null;
    notifyListeners();
  }

  Future<void> calculateAndSave() async {
    final heightM = height / 100;
    final calculatedBmi = weight / (heightM * heightM);
    bmi = calculatedBmi;
    notifyListeners();

    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final record = BmiRecord(
      bmi: calculatedBmi,
      height: height,
      weight: weight,
      gender: gender,
      date: DateTime.now(),
    );
    unawaited(_saveHistoryRecord(uid, record));
  }

  Future<void> _saveHistoryRecord(String uid, BmiRecord record) async {
    try {
      await withFirestoreRetry(
        () => _historyRef(uid).add(record.toMap()).timeout(const Duration(seconds: 15)),
      );
    } catch (e) {
      // ignore: avoid_print
      print('BMI history save failed: $e');
    }
  }

  Future<void> clearHistory() async {
    final uid = _uid;
    if (uid == null) return;
    final snapshot = await _historyRef(uid).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
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

  @override
  void dispose() {
    _historySub?.cancel();
    super.dispose();
  }
}

// ---------------- CALORIE CALCULATION ----------------

double calculateBMR({
  required double weightKg,
  required double heightCm,
  required int age,
  required String gender,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return gender == 'Male' ? base + 5 : base - 161;
}

double calculateTDEE(double bmr) {
  const activityMultiplier = 1.375;
  return bmr * activityMultiplier;
}

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
    final url = 'https://spoonacular.com/recipeImages/$id-312x231.$imageType';
    return MealPlanMeal(
      id: id,
      title: json['title'] as String? ?? 'Untitled recipe',
      imageUrl: url,
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

    final response = await http.get(uri).timeout(const Duration(seconds: 15));

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
      // ignore: avoid_print
      print('Meal plan generation failed: $e');
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
      await _auth
          .signInWithEmailAndPassword(email: email, password: password)
          .timeout(const Duration(seconds: 15));
      isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      errorMessage = _mapError(e.code);
      isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Something went wrong. Please check your connection and try again.';
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

      // Persist the profile fields FirebaseAuth doesn't natively store
      // (name/gender/age) to Firestore, keyed by uid. Timeboxed so a
      // slow/stuck connection surfaces a clear error instead of leaving
      // the sign-up screen spinning forever — the auth account itself
      // is already created at this point either way.
      //
      // FIX: previously, if this write timed out, sign-up still returned
      // `true` and the app moved on — but the users/{uid} doc was never
      // created, so ProfileScreen would show "No profile data found."
      // forever with no way to fix it from inside the app.
      // UserProfileProvider.loadProfile() now self-heals this by
      // auto-creating a default profile doc from the Auth account if one
      // is missing, so this is no longer a dead end even if this write
      // fails.
      try {
        await withFirestoreRetry(
          () => FirebaseFirestore.instance
              .collection('users')
              .doc(credential.user!.uid)
              .set({
            'name': name,
            'email': email,
            'gender': gender,
            'age': age,
          }).timeout(const Duration(seconds: 15)),
        );
      } catch (e) {
        // ignore: avoid_print
        print('Profile write on sign-up failed: $e');
        errorMessage =
            'Account created, but saving your profile timed out. '
            'It will be filled in automatically next time you open the Profile tab.';
        isLoading = false;
        notifyListeners();
        return true; // auth account exists; treat sign-up as successful
      }

      isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      errorMessage = _mapError(e.code);
      isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      errorMessage = 'Something went wrong. Please check your connection and try again.';
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

// ---------------- USER PROFILE (Firestore-backed) ----------------

class UserProfile {
  final String name;
  final String email;
  final String gender;
  final int age;
  final String? photoUrl;

  UserProfile({
    required this.name,
    required this.email,
    required this.gender,
    required this.age,
    this.photoUrl,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      name: map['name'] as String? ?? '',
      email: map['email'] as String? ?? '',
      gender: map['gender'] as String? ?? 'Other',
      age: (map['age'] as num?)?.toInt() ?? 0,
      photoUrl: map['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'gender': gender,
      'age': age,
      'photoUrl': photoUrl,
    };
  }
}

class UserProfileProvider extends ChangeNotifier {
  UserProfile? profile;
  bool isLoading = false;
  String? errorMessage;
  String? _uid;

  DocumentReference<Map<String, dynamic>> _docRef(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  /// Loads the profile doc for [uid]. If it doesn't exist yet (e.g. the
  /// write during sign-up failed or timed out), this now auto-creates a
  /// sensible default from the FirebaseAuth account instead of leaving
  /// the user stuck on "No profile data found." with no way to recover.
  ///
  /// FIX: transient `unavailable` errors (weak wifi, cold-start network
  /// races, a proxy/VPN blip) are now retried with backoff via
  /// withFirestoreRetry before giving up. If every retry still fails —
  /// meaning the device is genuinely offline — this falls back to
  /// whatever Firestore has cached locally from a previous successful
  /// load, so the screen doesn't dead-end on a single bad network
  /// moment.
  Future<void> loadProfile(String uid) async {
    _uid = uid;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final doc = await withFirestoreRetry(
        () => _docRef(uid).get().timeout(const Duration(seconds: 30)),
      );
      if (doc.exists) {
        profile = UserProfile.fromMap(doc.data()!);
      } else {
        profile = await _createDefaultProfile(uid);
      }
    } catch (e) {
      // ignore: avoid_print
      print('loadProfile failed for uid=$uid: $e');
      // Last resort: whatever Firestore has cached locally, even if stale.
      try {
        final cached = await _docRef(uid).get(const GetOptions(source: Source.cache));
        if (cached.exists) {
          profile = UserProfile.fromMap(cached.data()!);
          errorMessage = null;
          isLoading = false;
          notifyListeners();
          return;
        }
      } catch (_) {
        // no cache available either — fall through to the error state below
      }
      errorMessage = 'Could not load profile. Check your connection and try again.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Builds a starter profile from whatever FirebaseAuth already knows
  /// (display name / email) and writes it to Firestore so future loads
  /// find a real document. If this write also fails (e.g. still
  /// offline), the returned profile is still shown locally so the
  /// screen isn't stuck — it'll just retry the write on next load.
  Future<UserProfile> _createDefaultProfile(String uid) async {
    final authUser = FirebaseAuth.instance.currentUser;
    final defaultProfile = UserProfile(
      name: authUser?.displayName ?? '',
      email: authUser?.email ?? '',
      gender: 'Other',
      age: 0,
    );
    await AddFireStore(defaultProfile);
    return defaultProfile;
  }

  /// Writes the given profile to Firestore at users/{uid} and updates
  /// local state. Based on the simpler set()-based approach — using the
  /// same lowercase 'users' collection as the rest of the app (loadProfile,
  /// BMI history, sign-up) so reads and writes stay in sync, and setting
  /// isLoading = true *before* the write (not after) so the Save button's
  /// spinner shows correctly and isLoading is always reset to false when
  /// the write finishes or fails — otherwise the UI would look stuck.
  Future<bool> AddFireStore(UserProfile pd) async {
    final uid = _uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'name': pd.name,
        'gender': pd.gender,
        'age': pd.age,
        'email': pd.email,
        'photoUrl': pd.photoUrl,
      });
      profile = pd;
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('AddFireStore failed for uid=$uid: $e');
      errorMessage = 'Could not update profile. Check your connection and try again.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearUser() {
    profile = null;
    _uid = null;
    errorMessage = null;
    notifyListeners();
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

/// Signs out of Firebase Auth and clears the locally cached Firestore
/// data (profile + BMI history) so the next login on this device starts
/// clean rather than briefly showing the previous user's data.
Future<void> _performLogout(BuildContext context) async {
  await context.read<AuthProvider>().logout();
  if (context.mounted) {
    context.read<BmiProvider>().clearUser();
    context.read<UserProfileProvider>().clearUser();
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
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      // Deferred to after the first frame so Provider is fully wired up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<BmiProvider>().loadHistory(uid);
        context.read<UserProfileProvider>().loadProfile(uid);
      });
    }
  }

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
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
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
            onPressed: () => _performLogout(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final dotX = gaugePos * constraints.maxWidth;
                      return Stack(
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
                          Positioned(
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
                          ),
                        ],
                      );
                    },
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(mealPlanProvider.errorMessage!,
                      style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      final bmiProvider = context.read<BmiProvider>();
                      context.read<MealPlanProvider>().generateForBmi(
                            bmi: bmiProvider.bmi!,
                            weightKg: bmiProvider.weight,
                            heightCm: bmiProvider.height,
                            age: bmiProvider.age,
                            gender: bmiProvider.gender,
                          );
                    },
                    child: const Text('Retry', style: TextStyle(color: AppColors.accent)),
                  ),
                ],
              )
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
              // Spoonacular's image CDN blocks requests that don't look
              // like they're coming from a real browser (Dart's default
              // "Dart/x.x (dart:io)" user-agent gets rejected on mobile).
              // On Flutter Web this header can't be set at all — browsers
              // forbid overriding User-Agent for security reasons, and
              // web has a separate, unrelated problem: Spoonacular's CDN
              // doesn't send CORS headers, so images will 404/fail to
              // load in any browser regardless. This only helps on
              // Android/iOS/desktop native builds.
              headers: kIsWeb
                  ? null
                  : const {
                      'User-Agent':
                          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                              '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
                    },
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

  String _formatShortDate(DateTime date) => '${date.day}/${date.month}';

  Color _catColor(double bmi) {
    if (bmi < 18.5) return Colors.lightBlueAccent;
    if (bmi < 25) return AppColors.accent;
    if (bmi <= 30) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BmiProvider>();
    final history = provider.history; // newest first
    final chartHistory = history.reversed.toList(); // oldest first, for the chart

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
      body: provider.isLoadingHistory && history.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : history.isEmpty
              ? const Center(
                  child: Text('No BMI records yet.',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (chartHistory.length >= 2) ...[
                      _BmiChart(history: chartHistory, formatDate: _formatShortDate),
                      const SizedBox(height: 20),
                    ],
                    ...history.map((record) {
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
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600),
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
                    }),
                  ],
                ),
    );
  }
}

class _BmiChart extends StatelessWidget {
  final List<BmiRecord> history;
  final String Function(DateTime) formatDate;

  const _BmiChart({required this.history, required this.formatDate});

  Color _zoneColor(double bmi) {
    if (bmi < 18.5) return Colors.lightBlueAccent;
    if (bmi < 25) return AppColors.accent;
    if (bmi <= 30) return Colors.orangeAccent;
    return Colors.redAccent;
  }

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[
      for (var i = 0; i < history.length; i++) FlSpot(i.toDouble(), history[i].bmi),
    ];
    final bmiValues = history.map((r) => r.bmi).toList();
    final minY = (bmiValues.reduce((a, b) => a < b ? a : b) - 3).clamp(10, 45).toDouble();
    final maxY = (bmiValues.reduce((a, b) => a > b ? a : b) + 3).clamp(10, 45).toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 20, 20, 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(24)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 12),
            child: Text('BMI Trend',
                style: TextStyle(
                    color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 220,
            child: LineChart(
              LineChartData(
                minY: minY,
                maxY: maxY,
                minX: 0,
                maxX: (history.length - 1).toDouble(),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                rangeAnnotations: RangeAnnotations(
                  horizontalRangeAnnotations: [
                    if (minY < 18.5)
                      HorizontalRangeAnnotation(
                        y1: minY,
                        y2: 18.5,
                        color: Colors.lightBlueAccent.withValues(alpha: 0.12),
                      ),
                    HorizontalRangeAnnotation(
                      y1: 18.5,
                      y2: 25,
                      color: AppColors.accent.withValues(alpha: 0.10),
                    ),
                    HorizontalRangeAnnotation(
                      y1: 25,
                      y2: 30,
                      color: Colors.orangeAccent.withValues(alpha: 0.12),
                    ),
                    if (maxY > 30)
                      HorizontalRangeAnnotation(
                        y1: 30,
                        y2: maxY,
                        color: Colors.redAccent.withValues(alpha: 0.12),
                      ),
                  ],
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: 5,
                      getTitlesWidget: (value, meta) => Text(
                        value.toStringAsFixed(0),
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 26,
                      interval: history.length > 6 ? (history.length / 5).ceilToDouble() : 1,
                      getTitlesWidget: (value, meta) {
                        final i = value.round();
                        if (i < 0 || i >= history.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            formatDate(history[i].date),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.cardAlt,
                    getTooltipItems: (spots) => spots.map((s) {
                      final record = history[s.x.round()];
                      return LineTooltipItem(
                        '${record.bmi.toStringAsFixed(1)}\n${formatDate(record.date)}',
                        const TextStyle(
                            color: AppColors.textPrimary, fontWeight: FontWeight.bold),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: AppColors.accent,
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                        radius: 4,
                        color: _zoneColor(spot.y),
                        strokeWidth: 2,
                        strokeColor: AppColors.card,
                      ),
                    ),
                    belowBarData: BarAreaData(show: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _LegendDot(color: Colors.lightBlueAccent, label: 'Underweight'),
              _LegendDot(color: AppColors.accent, label: 'Normal'),
              _LegendDot(color: Colors.orangeAccent, label: 'Overweight'),
              _LegendDot(color: Colors.redAccent, label: 'Obese'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }
}

// ---------------- PROFILE SCREEN ----------------

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  TextEditingController? _nameController;
  TextEditingController? _ageController;
  String? _selectedGender;
  XFile? _pickedImage;
  Uint8List? _pickedImageBytes;

  @override
  void dispose() {
    _nameController?.dispose();
    _ageController?.dispose();
    super.dispose();
  }

  void _startEditing(UserProfile profile) {
    _nameController?.dispose();
    _ageController?.dispose();
    _nameController = TextEditingController(text: profile.name);
    _ageController = TextEditingController(text: profile.age.toString());
    _selectedGender = profile.gender;
    _pickedImage = null;
    _pickedImageBytes = null;
    setState(() => _isEditing = true);
  }

  Future<void> _pickImage(ImageSource source) async {
    Navigator.of(context).pop();
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, maxWidth: 800, imageQuality: 80);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImage = file;
      _pickedImageBytes = bytes;
    });
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.accent),
              title: const Text('Choose from Gallery',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => _pickImage(ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: AppColors.accent),
              title: const Text('Take a Photo', style: TextStyle(color: AppColors.textPrimary)),
              onTap: () => _pickImage(ImageSource.camera),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;
    final provider = context.read<UserProfileProvider>();
    final currentProfile = provider.profile!;

    // NOTE: image upload to Firebase Storage is disabled for now (requires
    // the Blaze billing plan). The picked image is only shown as a local
    // preview in this screen/session — it is not uploaded or saved to
    // Firestore, so it will reset to the previous photo (or the initial
    // avatar letter) next time the profile is loaded.
    final updated = UserProfile(
      name: _nameController!.text.trim(),
      email: currentProfile.email,
      gender: _selectedGender ?? 'Other',
      age: int.parse(_ageController!.text.trim()),
      photoUrl: currentProfile.photoUrl,
    );
    final success = await provider.AddFireStore(updated);
    if (success && mounted) {
      setState(() {
        _isEditing = false;
      });
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Update failed')),
      );
    }
  }

  void _retryLoad() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      context.read<UserProfileProvider>().loadProfile(uid);
    }
  }

  Widget _buildAvatar(UserProfile profile) {
    ImageProvider? imageProvider;
    if (_pickedImageBytes != null) {
      imageProvider = MemoryImage(_pickedImageBytes!);
    } else if (profile.photoUrl != null && profile.photoUrl!.isNotEmpty) {
      imageProvider = NetworkImage(profile.photoUrl!);
    }

    return Stack(
      children: [
        Container(
          width: 84,
          height: 84,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
            image: imageProvider != null
                ? DecorationImage(image: imageProvider, fit: BoxFit.cover)
                : null,
          ),
          child: imageProvider == null
              ? Text(
                  profile.name.isNotEmpty ? profile.name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppColors.bg, fontSize: 32, fontWeight: FontWeight.bold),
                )
              : null,
        ),
        if (_isEditing)
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _showImageSourceSheet,
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.cardAlt,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg, width: 2),
                ),
                child: const Icon(Icons.camera_alt, size: 14, color: AppColors.accent),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<UserProfileProvider>();
    final profile = profileProvider.profile;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (!_isEditing && profile != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: AppColors.textSecondary),
              onPressed: () => _startEditing(profile),
            ),
        ],
      ),
      // FIX: previously, if loadProfile() failed (bad rules, offline,
      // or a missing doc that wasn't self-healed) this screen just
      // showed "No profile data found." with zero way to recover short
      // of restarting the app. It now shows a spinner only while
      // isLoading is actually true, and always gives a visible Retry
      // button once loading finishes with no profile — so it can never
      // look "stuck buffering forever" with no way out.
      body: profileProvider.isLoading && profile == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
          : profile == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        profileProvider.errorMessage ?? 'No profile data found.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _retryLoad,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.bg,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _buildAvatar(profile)),
                      const SizedBox(height: 28),
                      _isEditing
                          ? _buildEditForm(profile, profileProvider)
                          : _buildReadOnlyView(profile),
                      const SizedBox(height: 32),
                      SizedBox(
                        height: 54,
                        child: OutlinedButton.icon(
                          onPressed: () => _performLogout(context),
                          icon: const Icon(Icons.logout, color: Colors.redAccent),
                          label: const Text('Logout',
                              style: TextStyle(
                                  color: Colors.redAccent, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.redAccent),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildReadOnlyView(UserProfile profile) {
    return Column(
      children: [
        _ProfileField(label: 'Name', value: profile.name, icon: Icons.person_outline),
        const SizedBox(height: 14),
        _ProfileField(label: 'Email', value: profile.email, icon: Icons.email_outlined),
        const SizedBox(height: 14),
        _ProfileField(label: 'Gender', value: profile.gender, icon: Icons.wc_outlined),
        const SizedBox(height: 14),
        _ProfileField(
            label: 'Age', value: profile.age.toString(), icon: Icons.cake_outlined),
      ],
    );
  }

  Widget _buildEditForm(UserProfile profile, UserProfileProvider profileProvider) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Full Name',
              prefixIcon: Icon(Icons.person_outline, color: AppColors.textSecondary),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter your name';
              return null;
            },
          ),
          const SizedBox(height: 16),
          // Email is tied to the FirebaseAuth account and isn't editable
          // here — changing it would require re-authentication.
          _ProfileField(label: 'Email', value: profile.email, icon: Icons.email_outlined),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedGender,
            dropdownColor: AppColors.card,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              hintText: 'Gender',
              prefixIcon: Icon(Icons.wc_outlined, color: AppColors.textSecondary),
            ),
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
            decoration: const InputDecoration(
              hintText: 'Age',
              prefixIcon: Icon(Icons.cake_outlined, color: AppColors.textSecondary),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'Please enter your age';
              final age = int.tryParse(value.trim());
              if (age == null) return 'Enter a valid number';
              if (age < 13 || age > 120) return 'Enter an age between 13 and 120';
              return null;
            },
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _isEditing = false;
                    _pickedImage = null;
                    _pickedImageBytes = null;
                  }),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: AppColors.textSecondary),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary)),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: profileProvider.isLoading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : ElevatedButton(
                        onPressed: _saveChanges,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.bg,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                        ),
                        child: const Text('Save', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _ProfileField({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}