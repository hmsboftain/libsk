class AppCountry {
  final String code;
  final String nameEn;
  final String nameAr;
  final String currency;
  final String currencySymbol;
  final bool hasSameDay;

  const AppCountry({
    required this.code,
    required this.nameEn,
    required this.nameAr,
    required this.currency,
    required this.currencySymbol,
    required this.hasSameDay,
  });
}

const List<AppCountry> kSupportedCountries = [
  AppCountry(
    code: 'KW',
    nameEn: 'Kuwait',
    nameAr: 'الكويت',
    currency: 'KWD',
    currencySymbol: 'KD',
    hasSameDay: true,
  ),
  AppCountry(
    code: 'SA',
    nameEn: 'Saudi Arabia',
    nameAr: 'السعودية',
    currency: 'SAR',
    currencySymbol: 'SR',
    hasSameDay: false,
  ),
  AppCountry(
    code: 'AE',
    nameEn: 'UAE',
    nameAr: 'الإمارات',
    currency: 'AED',
    currencySymbol: 'AED',
    hasSameDay: false,
  ),
  AppCountry(
    code: 'BH',
    nameEn: 'Bahrain',
    nameAr: 'البحرين',
    currency: 'BHD',
    currencySymbol: 'BD',
    hasSameDay: false,
  ),
  AppCountry(
    code: 'QA',
    nameEn: 'Qatar',
    nameAr: 'قطر',
    currency: 'QAR',
    currencySymbol: 'QR',
    hasSameDay: false,
  ),
  AppCountry(
    code: 'OM',
    nameEn: 'Oman',
    nameAr: 'عُمان',
    currency: 'OMR',
    currencySymbol: 'OMR',
    hasSameDay: false,
  ),
];

AppCountry countryByCode(String code) => kSupportedCountries.firstWhere(
  (c) => c.code == code,
  orElse: () => kSupportedCountries.first,
);
