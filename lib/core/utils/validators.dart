/// Shared input validators used by every form in the app.
///
/// Each method returns `null` when the value passes and a localised-looking
/// English error message when it fails. Pages can either pass these into a
/// `TextFormField.validator` directly or call them imperatively before
/// firing off a Cloud Function / Firestore write.
class Validators {
  const Validators._();

  static String? required(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return '$fieldName is required';
    }
    return null;
  }

  static String? maxLength(String? value, int max, String fieldName) {
    if (value != null && value.trim().length > max) {
      return '$fieldName must be under $max characters';
    }
    return null;
  }

  static String? minLength(String? value, int min, String fieldName) {
    if (value == null || value.trim().length < min) {
      return '$fieldName must be at least $min characters';
    }
    return null;
  }

  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return 'Email is required';
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(value.trim())) return 'Enter a valid email address';
    return null;
  }

  static String? phone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Phone number is required';
    }
    final cleaned = value.trim().replaceAll(RegExp(r'[\s\-\+\(\)]'), '');
    if (cleaned.length < 8 || cleaned.length > 15) {
      return 'Enter a valid phone number';
    }
    if (!RegExp(r'^\d+$').hasMatch(cleaned)) {
      return 'Phone number must contain only digits';
    }
    return null;
  }

  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) return 'Price is required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null) return 'Enter a valid price';
    if (parsed <= 0) return 'Price must be greater than 0';
    if (parsed > 100000) return 'Price cannot exceed KD 100,000';
    return null;
  }

  static String? stock(String? value) {
    if (value == null || value.trim().isEmpty) return 'Stock is required';
    final parsed = int.tryParse(value.trim());
    if (parsed == null) return 'Stock must be a whole number';
    if (parsed < 0) return 'Stock cannot be negative';
    if (parsed > 99999) return 'Stock cannot exceed 99,999';
    return null;
  }

  /// Runs each rule in order and returns the first failure, if any.
  static String? combine(
    String? value,
    List<String? Function(String?)> rules,
  ) {
    for (final rule in rules) {
      final error = rule(value);
      if (error != null) return error;
    }
    return null;
  }
}
