/// Yemeni mobile phone validation — mirrors backend PhoneHelper rules.
class YemenPhone {
  static const countryCode = '967';
  static const nationalLength = 9;
  static const prefixes = ['70', '71', '73', '77', '78', '10'];

  static String digitsOnly(String? value) {
    var phone = (value ?? '').replaceAll(RegExp(r'\D+'), '');
    if (phone.startsWith('00')) {
      phone = phone.substring(2);
    }
    return phone;
  }

  static String local(String? phone, {String countryCode = countryCode}) {
    final digits = digitsOnly(phone);
    final cc = digitsOnly(countryCode);
    if (digits.startsWith(cc) && digits.length > cc.length) {
      return digits.substring(cc.length);
    }
    return digits.replaceFirst(RegExp(r'^0+'), '');
  }

  static bool isValid(String? phone, {String countryCode = countryCode}) {
    final localNumber = local(phone, countryCode: countryCode);
    if (localNumber.length != nationalLength) return false;
    final prefix = localNumber.substring(0, 2);
    if (!prefixes.contains(prefix)) return false;
    return RegExp(r'^\d+$').hasMatch(localNumber);
  }

  static String canonical(String? phone, {String countryCode = countryCode}) {
    final localNumber = local(phone, countryCode: countryCode);
    if (!isValid(localNumber, countryCode: countryCode)) return '';
    return '+$countryCode$localNumber';
  }

  static bool backupDiffersFromPrimary(
    String? primary,
    String? backup, {
    String countryCode = countryCode,
  }) {
    if (backup == null || backup.trim().isEmpty) return true;
    final primaryCanonical = canonical(primary, countryCode: countryCode);
    final backupCanonical = canonical(backup, countryCode: countryCode);
    if (primaryCanonical.isEmpty || backupCanonical.isEmpty) return true;
    return primaryCanonical != backupCanonical;
  }
}

const passwordMinLength = 12;

bool isValidPassword(String? password) =>
    password != null && password.length >= passwordMinLength;
