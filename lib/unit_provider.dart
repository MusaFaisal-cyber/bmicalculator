import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two unit systems the Calculator screen supports.
enum UnitSystem { metric, imperial }

/// All conversion + formatting math lives here so the UI code just calls
/// these instead of repeating factors everywhere.
///
/// IMPORTANT: BmiProvider always stores height in cm and weight in kg
/// (this matches what's already saved in Firestore history). These
/// helpers only convert for *display* and for translating user input
/// back into cm/kg before it's saved to BmiProvider.
class UnitConversions {
  static const double cmPerInch = 2.54;
  static const double kgPerLb = 0.45359237;

  static double cmToInches(double cm) => cm / cmPerInch;
  static double inchesToCm(double inches) => inches * cmPerInch;

  static double kgToLbs(double kg) => kg / kgPerLb;
  static double lbsToKg(double lbs) => lbs * kgPerLb;

  /// Splits a height in cm into whole feet + whole inches, e.g. 175cm -> (5, 9).
  static (int feet, int inches) cmToFeetAndInches(double cm) {
    final totalInches = cmToInches(cm);
    var feet = totalInches ~/ 12;
    var inches = (totalInches - feet * 12).round();
    // Rounding can push inches to 12 (e.g. 71.6" -> 5'12" instead of 6'0").
    if (inches == 12) {
      feet += 1;
      inches = 0;
    }
    return (feet.toInt(), inches);
  }

  static double feetAndInchesToCm(int feet, int inches) {
    return inchesToCm((feet * 12 + inches).toDouble());
  }

  /// Human-readable height for the given system, e.g. "175 cm" or "5' 9"".
  static String formatHeight(double heightCm, bool isImperial) {
    if (!isImperial) return '${heightCm.toStringAsFixed(0)} cm';
    final (feet, inches) = cmToFeetAndInches(heightCm);
    return "$feet' $inches\"";
  }

  /// Human-readable weight for the given system, e.g. "65 kg" or "143 lbs".
  static String formatWeight(double weightKg, bool isImperial) {
    if (!isImperial) return '${weightKg.toStringAsFixed(0)} kg';
    return '${kgToLbs(weightKg).round()} lbs';
  }
}

/// Holds the current UnitSystem and persists the user's choice to disk
/// with shared_preferences, mirroring ThemeProvider so it survives an
/// app restart.
class UnitProvider extends ChangeNotifier {
  static const _prefsKey = 'unit_system';

  UnitSystem _unitSystem = UnitSystem.metric; // sensible default
  UnitSystem get unitSystem => _unitSystem;
  bool get isImperial => _unitSystem == UnitSystem.imperial;

  /// Call this once at startup (see main.dart) before runApp so the
  /// correct unit system is used on first frame instead of flashing
  /// the default.
  Future<void> loadSavedUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    _unitSystem = saved == 'imperial' ? UnitSystem.imperial : UnitSystem.metric;
    notifyListeners();
  }

  Future<void> setImperial(bool isImperial) async {
    if (this.isImperial == isImperial) return;
    _unitSystem = isImperial ? UnitSystem.imperial : UnitSystem.metric;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, isImperial ? 'imperial' : 'metric');
  }
}