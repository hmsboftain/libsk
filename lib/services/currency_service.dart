import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class CurrencyService extends ChangeNotifier {
  static final CurrencyService _instance = CurrencyService._();
  static CurrencyService get instance => _instance;
  CurrencyService._();

  // Fallback rates in case the API is unreachable
  Map<String, double> _rates = {
    'KWD': 1.0,
    'SAR': 12.19,
    'AED': 11.93,
    'BHD': 1.22,
    'QAR': 11.85,
    'OMR': 1.25,
  };

  String _selectedCountryCode = 'KW';
  String get selectedCountryCode => _selectedCountryCode;
  Map<String, double> get rates => _rates;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('country_code');

    if (saved != null) {
      // User has a saved preference — use it
      _selectedCountryCode = saved;
    } else {
      // First launch — detect from device locale
      final deviceCountry =
          ui.PlatformDispatcher.instance.locale.countryCode?.toUpperCase() ??
              '';
      final supported = ['KW', 'SA', 'AE', 'BH', 'QA', 'OM'];
      _selectedCountryCode =
          supported.contains(deviceCountry) ? deviceCountry : 'KW';
      // Save it so we don't re-detect on next launch
      await prefs.setString('country_code', _selectedCountryCode);
    }

    await fetchRates();
  }

  Future<void> fetchRates() async {
    try {
      final response = await http
          .get(
            Uri.parse(
              'https://api.frankfurter.app/latest?from=KWD&to=SAR,AED,BHD,QAR,OMR',
            ),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final fetched = Map<String, double>.from(
          (data['rates'] as Map).map(
            (k, v) => MapEntry(k, (v as num).toDouble()),
          ),
        );
        _rates = {'KWD': 1.0, ...fetched};
        notifyListeners();
      }
    } catch (_) {
      // Use hardcoded fallback rates — already set above
    }
  }

  Future<void> setCountry(String countryCode) async {
    _selectedCountryCode = countryCode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('country_code', countryCode);
    notifyListeners();
  }

  /// Convert a KWD price to the selected country's currency
  double convert(double kwdPrice, String targetCurrency) {
    final rate = _rates[targetCurrency] ?? 1.0;
    return kwdPrice * rate;
  }

  /// Format a KWD price as a string in the target currency
  String format(double kwdPrice, String currencySymbol, String currency) {
    final converted = convert(kwdPrice, currency);
    final int decimals;
    if (currency == 'KWD' || currency == 'BHD' || currency == 'OMR') {
      decimals = 3; // fils-based currencies
    } else {
      decimals = 0; // SAR, AED, QAR display as whole numbers
    }
    return '${converted.toStringAsFixed(decimals)} $currencySymbol';
  }
}
