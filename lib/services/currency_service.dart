import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Currency {
  final String code;
  final String symbol;
  final String name;

  const Currency(this.code, this.symbol, this.name);
}

const List<Currency> supportedCurrencies = [
  Currency('INR', '₹', 'Indian Rupee'),
  Currency('USD', '\$', 'US Dollar'),
  Currency('EUR', '€', 'Euro'),
  Currency('GBP', '£', 'British Pound'),
  Currency('JPY', '¥', 'Japanese Yen'),
  Currency('CNY', '¥', 'Chinese Yuan'),
  Currency('AUD', '\$', 'Australian Dollar'),
  Currency('CAD', '\$', 'Canadian Dollar'),
  Currency('CHF', 'Fr', 'Swiss Franc'),
  Currency('HKD', '\$', 'Hong Kong Dollar'),
  Currency('NZD', '\$', 'New Zealand Dollar'),
  Currency('SGD', '\$', 'Singapore Dollar'),
  Currency('SEK', 'kr', 'Swedish Krona'),
  Currency('NOK', 'kr', 'Norwegian Krone'),
  Currency('DKK', 'kr', 'Danish Krone'),
  Currency('KRW', '₩', 'South Korean Won'),
  Currency('MXN', '\$', 'Mexican Peso'),
  Currency('ZAR', 'R', 'South African Rand'),
  Currency('BRL', 'R\$', 'Brazilian Real'),
  Currency('RUB', '₽', 'Russian Ruble'),
  Currency('AED', 'د.إ', 'UAE Dirham'),
  Currency('SAR', '﷼', 'Saudi Riyal'),
  Currency('QAR', '﷼', 'Qatari Riyal'),
  Currency('KWD', 'د.ك', 'Kuwaiti Dinar'),
  Currency('THB', '฿', 'Thai Baht'),
  Currency('MYR', 'RM', 'Malaysian Ringgit'),
  Currency('IDR', 'Rp', 'Indonesian Rupiah'),
  Currency('PHP', '₱', 'Philippine Peso'),
  Currency('VND', '₫', 'Vietnamese Dong'),
  Currency('TRY', '₺', 'Turkish Lira'),
  Currency('PLN', 'zł', 'Polish Zloty'),
  Currency('CZK', 'Kč', 'Czech Koruna'),
  Currency('HUF', 'Ft', 'Hungarian Forint'),
  Currency('ILS', '₪', 'Israeli Shekel'),
  Currency('PKR', '₨', 'Pakistani Rupee'),
  Currency('BDT', '৳', 'Bangladeshi Taka'),
  Currency('LKR', '₨', 'Sri Lankan Rupee'),
  Currency('NPR', '₨', 'Nepalese Rupee'),
  Currency('EGP', '£', 'Egyptian Pound'),
  Currency('NGN', '₦', 'Nigerian Naira'),
  Currency('KES', 'KSh', 'Kenyan Shilling'),
  Currency('GHS', '₵', 'Ghanaian Cedi'),
  Currency('ARS', '\$', 'Argentine Peso'),
  Currency('CLP', '\$', 'Chilean Peso'),
  Currency('COP', '\$', 'Colombian Peso'),
  Currency('PEN', 'S/', 'Peruvian Sol'),
  Currency('UAH', '₴', 'Ukrainian Hryvnia'),
  Currency('TWD', 'NT\$', 'Taiwan Dollar'),
];

class CurrencyService extends ChangeNotifier {
  static const _prefsKey = 'currency_code';

  Currency _currency = supportedCurrencies.first;
  Currency get currency => _currency;
  String get symbol => _currency.symbol;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_prefsKey);
    if (code != null) {
      _currency = supportedCurrencies.firstWhere(
        (c) => c.code == code,
        orElse: () => supportedCurrencies.first,
      );
      notifyListeners();
    }
  }

  Future<void> setCurrency(Currency currency) async {
    _currency = currency;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, currency.code);
  }
}
