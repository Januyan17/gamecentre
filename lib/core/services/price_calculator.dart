import 'package:cloud_firestore/cloud_firestore.dart';

class PriceCalculator {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Map<String, dynamic>? _cachedPrices;
  static DateTime? _cacheTime;
  static const Duration _cacheDuration = Duration(minutes: 5);

  // Default prices (fallback if Firestore is unavailable)
  static const double _defaultPs4HourlyRate = 250.0;
  static const double _defaultPs5HourlyRate = 350.0;
  static const double _defaultAdditionalController = 150.0;
  static const double _defaultVr = 700.0;
  static const double _defaultRacingWheel = 500.0;
  static const Map<int, double> _defaultTheatre = {
    1: 1500.0,
    2: 2000.0,
    3: 2500.0,
    4: 3000.0,
  };
  static const Map<int, double> _defaultPersonCharge = {
    1: 350.0,
    2: 350.0,
    3: 350.0,
    4: 350.0,
  };

  static Future<Map<String, dynamic>> _getPrices() async {
    // Return cached prices if still valid
    if (_cachedPrices != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedPrices!;
    }

    try {
      final doc = await _firestore.collection('settings').doc('pricing').get();
      if (doc.exists) {
        _cachedPrices = doc.data() as Map<String, dynamic>;
        _cacheTime = DateTime.now();
        return _cachedPrices!;
      }
    } catch (e) {
      // If error, use defaults
    }

    // Return defaults if no data in Firestore
    return {
      'ps4HourlyRate': _defaultPs4HourlyRate,
      'ps5HourlyRate': _defaultPs5HourlyRate,
      'additionalController': _defaultAdditionalController,
      'vr': _defaultVr,
      'racingWheel': _defaultRacingWheel,
      'theatre1hr': _defaultTheatre[1]!,
      'theatre2hr': _defaultTheatre[2]!,
      'theatre3hr': _defaultTheatre[3]!,
      'theatre4hr': _defaultTheatre[4]!,
      'person1hr': _defaultPersonCharge[1]!,
      'person2hr': _defaultPersonCharge[2]!,
      'person3hr': _defaultPersonCharge[3]!,
      'person4hr': _defaultPersonCharge[4]!,
    };
  }

  static void clearCache() {
    _cachedPrices = null;
    _cacheTime = null;
  }

  /// Calculate price for PS4 gaming session
  /// 
  /// Pricing Rules:
  /// 1. Base hourly rate = PS4 rate + (Additional Controllers × Controller Price)
  /// 2. Full hours = Hours × Base Hourly Rate
  /// 3. Additional minutes = (Base Hourly Rate ÷ 2) × (Minutes ÷ 30)
  /// 4. Total = Full Hours Price + Additional Minutes Price
  /// 
  /// Example:
  /// - PS4 base: 250 LKR/hour
  /// - 1 controller: 150 LKR/hour
  /// - Base hourly rate: 250 + 150 = 400 LKR/hour
  /// - 1 hour: 400 LKR
  /// - 30 minutes extension: (400 ÷ 2) × (30 ÷ 60) = 100 LKR
  /// - Total: 400 + 100 = 500 LKR
  static Future<double> ps4Price({
    required int hours,
    required int minutes,
    int additionalControllers = 0,
  }) async {
    final prices = await _getPrices();
    final ps4HourlyRate =
        (prices['ps4HourlyRate'] ?? _defaultPs4HourlyRate).toDouble();
    final additionalControllerRate =
        (prices['additionalController'] ?? _defaultAdditionalController)
            .toDouble();

    // Step 1: Calculate base hourly rate (device + controllers)
    double baseHourlyRate = ps4HourlyRate + (additionalControllers * additionalControllerRate);
    
    // Step 2: Calculate full hours price
    double fullHoursPrice = (hours * baseHourlyRate).toDouble();
    
    // Step 3: Calculate additional minutes at 50% of hourly rate
    // 30 minutes = 50% of hourly rate, so formula: (hourly rate / 2) × (minutes / 30)
    double additionalMinutesPrice = 0.0;
    if (minutes > 0) {
      additionalMinutesPrice = (baseHourlyRate / 2) * (minutes / 30.0);
    }
    
    // Step 4: Return total
    return fullHoursPrice + additionalMinutesPrice;
  }

  /// Calculate price for PS5 gaming session
  /// 
  /// Pricing Rules:
  /// 1. Base hourly rate = PS5 rate + (Additional Controllers × Controller Price)
  /// 2. Full hours = Hours × Base Hourly Rate
  /// 3. Additional minutes = (Base Hourly Rate ÷ 2) × (Minutes ÷ 30)
  /// 4. Total = Full Hours Price + Additional Minutes Price
  /// 
  /// Example:
  /// - PS5 base: 350 LKR/hour
  /// - 1 controller: 150 LKR/hour
  /// - Base hourly rate: 350 + 150 = 500 LKR/hour
  /// - 1 hour: 500 LKR
  /// - 30 minutes extension: (500 ÷ 2) × (30 ÷ 60) = 250 LKR
  /// - Total: 500 + 250 = 750 LKR
  static Future<double> ps5Price({
    required int hours,
    required int minutes,
    int additionalControllers = 0,
  }) async {
    final prices = await _getPrices();
    final ps5HourlyRate =
        (prices['ps5HourlyRate'] ?? _defaultPs5HourlyRate).toDouble();
    final additionalControllerRate =
        (prices['additionalController'] ?? _defaultAdditionalController)
            .toDouble();

    // Step 1: Calculate base hourly rate (device + controllers)
    double baseHourlyRate = ps5HourlyRate + (additionalControllers * additionalControllerRate);
    
    // Step 2: Calculate full hours price
    double fullHoursPrice = (hours * baseHourlyRate).toDouble();
    
    // Step 3: Calculate additional minutes at 50% of hourly rate
    // 30 minutes = 50% of hourly rate, so formula: (hourly rate / 2) × (minutes / 30)
    double additionalMinutesPrice = 0.0;
    if (minutes > 0) {
      additionalMinutesPrice = (baseHourlyRate / 2) * (minutes / 30.0);
    }
    
    // Step 4: Return total
    return fullHoursPrice + additionalMinutesPrice;
  }

  static Future<double> carSimulator() async {
    final prices = await _getPrices();
    return (prices['racingWheel'] ?? _defaultRacingWheel).toDouble();
  }

  static Future<double> vr() async {
    final prices = await _getPrices();
    return (prices['vr'] ?? _defaultVr).toDouble();
  }

  static Future<double> theatre({
    required int hours,
    required int people,
  }) async {
    final prices = await _getPrices();

    double base = 0.0;
    switch (hours) {
      case 1:
        base = (prices['theatre1hr'] ?? _defaultTheatre[1]!).toDouble();
        break;
      case 2:
        base = (prices['theatre2hr'] ?? _defaultTheatre[2]!).toDouble();
        break;
      case 3:
        base = (prices['theatre3hr'] ?? _defaultTheatre[3]!).toDouble();
        break;
      case 4:
        base = (prices['theatre4hr'] ?? _defaultTheatre[4]!).toDouble();
        break;
      default:
        base = 0.0;
    }

    if (people > 4) {
      double personCharge = 0.0;
      switch (hours) {
        case 1:
          personCharge =
              (prices['person1hr'] ?? _defaultPersonCharge[1]!).toDouble();
          break;
        case 2:
          personCharge =
              (prices['person2hr'] ?? _defaultPersonCharge[2]!).toDouble();
          break;
        case 3:
          personCharge =
              (prices['person3hr'] ?? _defaultPersonCharge[3]!).toDouble();
          break;
        case 4:
          personCharge =
              (prices['person4hr'] ?? _defaultPersonCharge[4]!).toDouble();
          break;
      }
      base += (people - 4) * personCharge;
    }

    return base;
  }

  /// Get additional controller price (standalone method for UI display)
  static Future<double> getAdditionalControllerPrice() async {
    final prices = await _getPrices();
    return (prices['additionalController'] ?? _defaultAdditionalController)
        .toDouble();
  }
}
