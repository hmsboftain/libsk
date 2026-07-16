import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale) : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'LIBSK'**
  String get appTitle;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @cart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get cart;

  /// No description provided for @checkout.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkout;

  /// No description provided for @profile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profile;

  /// No description provided for @orders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get orders;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @addToCart.
  ///
  /// In en, this message translates to:
  /// **'Add to Cart'**
  String get addToCart;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @deliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Delivery Address'**
  String get deliveryAddress;

  /// No description provided for @placeOrder.
  ///
  /// In en, this message translates to:
  /// **'Place Order'**
  String get placeOrder;

  /// No description provided for @payment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get payment;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @arabic.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get arabic;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get or;

  /// No description provided for @and.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get and;

  /// No description provided for @send.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get send;

  /// No description provided for @manage.
  ///
  /// In en, this message translates to:
  /// **'Manage'**
  String get manage;

  /// No description provided for @review.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get review;

  /// No description provided for @onboard.
  ///
  /// In en, this message translates to:
  /// **'Onboard'**
  String get onboard;

  /// No description provided for @featured.
  ///
  /// In en, this message translates to:
  /// **'Featured'**
  String get featured;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @boutiqueName.
  ///
  /// In en, this message translates to:
  /// **'Boutique Name'**
  String get boutiqueName;

  /// No description provided for @stock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stock;

  /// No description provided for @by.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get by;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size:'**
  String get size;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @add.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// No description provided for @browse.
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get browse;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @pullDownToRetry.
  ///
  /// In en, this message translates to:
  /// **'Pull down to retry'**
  String get pullDownToRetry;

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

  /// No description provided for @accountUpdated.
  ///
  /// In en, this message translates to:
  /// **'Account information updated'**
  String get accountUpdated;

  /// No description provided for @failedToUpdateAccount.
  ///
  /// In en, this message translates to:
  /// **'Failed to update account information'**
  String get failedToUpdateAccount;

  /// No description provided for @accountInformation.
  ///
  /// In en, this message translates to:
  /// **'Account Information'**
  String get accountInformation;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get username;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone Number'**
  String get phoneNumber;

  /// No description provided for @enterUsername.
  ///
  /// In en, this message translates to:
  /// **'Enter your username'**
  String get enterUsername;

  /// No description provided for @enterEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get enterEmail;

  /// No description provided for @enterPhoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter your phone number'**
  String get enterPhoneNumber;

  /// No description provided for @requiredField.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get requiredField;

  /// No description provided for @emailNotEditable.
  ///
  /// In en, this message translates to:
  /// **'Email cannot be changed here.'**
  String get emailNotEditable;

  /// No description provided for @saveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChanges;

  /// No description provided for @editPersonalInformation.
  ///
  /// In en, this message translates to:
  /// **'Edit Personal Information'**
  String get editPersonalInformation;

  /// No description provided for @fullNameLabel.
  ///
  /// In en, this message translates to:
  /// **'FULL NAME'**
  String get fullNameLabel;

  /// No description provided for @emailAddressLabel.
  ///
  /// In en, this message translates to:
  /// **'EMAIL ADDRESS'**
  String get emailAddressLabel;

  /// No description provided for @securitySection.
  ///
  /// In en, this message translates to:
  /// **'SECURITY'**
  String get securitySection;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log Out'**
  String get logout;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @continueWithApple.
  ///
  /// In en, this message translates to:
  /// **'Continue with Apple'**
  String get continueWithApple;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back,'**
  String get welcomeBack;

  /// No description provided for @dontHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get dontHaveAnAccount;

  /// No description provided for @signInToViewOrders.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view your orders'**
  String get signInToViewOrders;

  /// No description provided for @signInToViewYourOrders.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view your orders'**
  String get signInToViewYourOrders;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @emailExample.
  ///
  /// In en, this message translates to:
  /// **'email@example.com'**
  String get emailExample;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get enterValidEmail;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordHidden.
  ///
  /// In en, this message translates to:
  /// **'••••••'**
  String get passwordHidden;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @minimumSixCharacters.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters'**
  String get minimumSixCharacters;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPassword;

  /// No description provided for @pleaseConfirmYourPassword.
  ///
  /// In en, this message translates to:
  /// **'Please confirm your password'**
  String get pleaseConfirmYourPassword;

  /// No description provided for @passwordsDoNotMatch.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// No description provided for @passwordMinLength.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 8 characters'**
  String get passwordMinLength;

  /// No description provided for @passwordNeedsUppercase.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one uppercase letter'**
  String get passwordNeedsUppercase;

  /// No description provided for @passwordNeedsLowercase.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one lowercase letter'**
  String get passwordNeedsLowercase;

  /// No description provided for @passwordNeedsNumber.
  ///
  /// In en, this message translates to:
  /// **'Password must contain at least one number'**
  String get passwordNeedsNumber;

  /// No description provided for @firstName.
  ///
  /// In en, this message translates to:
  /// **'First Name'**
  String get firstName;

  /// No description provided for @lastName.
  ///
  /// In en, this message translates to:
  /// **'Last Name'**
  String get lastName;

  /// No description provided for @firstNameRequired.
  ///
  /// In en, this message translates to:
  /// **'First name is required'**
  String get firstNameRequired;

  /// No description provided for @lastNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Last name is required'**
  String get lastNameRequired;

  /// No description provided for @phoneNumberRequired.
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get phoneNumberRequired;

  /// No description provided for @byCreatingAccount.
  ///
  /// In en, this message translates to:
  /// **'By creating an account you agree to our '**
  String get byCreatingAccount;

  /// No description provided for @termsOfUse.
  ///
  /// In en, this message translates to:
  /// **'Terms of Use'**
  String get termsOfUse;

  /// No description provided for @privacyPolicy.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicy;

  /// No description provided for @strengthWeak.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get strengthWeak;

  /// No description provided for @strengthFair.
  ///
  /// In en, this message translates to:
  /// **'Fair'**
  String get strengthFair;

  /// No description provided for @strengthGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get strengthGood;

  /// No description provided for @strengthStrong.
  ///
  /// In en, this message translates to:
  /// **'Strong'**
  String get strengthStrong;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed. Please try again.'**
  String get loginFailed;

  /// No description provided for @signUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign up failed. Please try again.'**
  String get signUpFailed;

  /// No description provided for @emailAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'An account already exists with this email.'**
  String get emailAlreadyInUse;

  /// No description provided for @invalidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get invalidEmailAddress;

  /// No description provided for @passwordTooWeak.
  ///
  /// In en, this message translates to:
  /// **'Password is too weak'**
  String get passwordTooWeak;

  /// No description provided for @noAccountFoundForThisEmail.
  ///
  /// In en, this message translates to:
  /// **'No account found for this email.'**
  String get noAccountFoundForThisEmail;

  /// No description provided for @incorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password.'**
  String get incorrectPassword;

  /// No description provided for @incorrectEmailOrPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password.'**
  String get incorrectEmailOrPassword;

  /// No description provided for @passwordResetEmailSent.
  ///
  /// In en, this message translates to:
  /// **'Password reset email sent'**
  String get passwordResetEmailSent;

  /// No description provided for @couldNotSendResetEmail.
  ///
  /// In en, this message translates to:
  /// **'Could not send reset email'**
  String get couldNotSendResetEmail;

  /// No description provided for @enterEmailForResetLink.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address and we will send you a password reset link.'**
  String get enterEmailForResetLink;

  /// No description provided for @enterYourEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Enter your email address'**
  String get enterYourEmailAddress;

  /// No description provided for @sendResetLink.
  ///
  /// In en, this message translates to:
  /// **'SEND RESET LINK'**
  String get sendResetLink;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @customer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customer;

  /// No description provided for @noEmail.
  ///
  /// In en, this message translates to:
  /// **'No email'**
  String get noEmail;

  /// No description provided for @yourAccount.
  ///
  /// In en, this message translates to:
  /// **'Your Account'**
  String get yourAccount;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get accountSection;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete Account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete your account? This action cannot be undone.'**
  String get deleteAccountConfirm;

  /// No description provided for @deleteAccountConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to permanently delete your account? This action cannot be undone.'**
  String get deleteAccountConfirmation;

  /// No description provided for @deleteAccountButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAccountButton;

  /// No description provided for @deleteButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteButton;

  /// No description provided for @confirmPasswordTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Password'**
  String get confirmPasswordTitle;

  /// No description provided for @confirmPasswordDescription.
  ///
  /// In en, this message translates to:
  /// **'Please enter your password to confirm account deletion.'**
  String get confirmPasswordDescription;

  /// No description provided for @confirmButton.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirmButton;

  /// No description provided for @passwordUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Password updated successfully'**
  String get passwordUpdatedSuccessfully;

  /// No description provided for @failedToChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Failed to change password'**
  String get failedToChangePassword;

  /// No description provided for @currentPasswordIncorrect.
  ///
  /// In en, this message translates to:
  /// **'Current password is incorrect'**
  String get currentPasswordIncorrect;

  /// No description provided for @newPasswordTooWeak.
  ///
  /// In en, this message translates to:
  /// **'New password is too weak'**
  String get newPasswordTooWeak;

  /// No description provided for @currentPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'CURRENT PASSWORD'**
  String get currentPasswordLabel;

  /// No description provided for @newPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'NEW PASSWORD'**
  String get newPasswordLabel;

  /// No description provided for @confirmNewPasswordLabel.
  ///
  /// In en, this message translates to:
  /// **'CONFIRM NEW PASSWORD'**
  String get confirmNewPasswordLabel;

  /// No description provided for @newPasswordMustBeDifferent.
  ///
  /// In en, this message translates to:
  /// **'New password must be different'**
  String get newPasswordMustBeDifferent;

  /// No description provided for @updatePassword.
  ///
  /// In en, this message translates to:
  /// **'UPDATE PASSWORD'**
  String get updatePassword;

  /// No description provided for @savedItems.
  ///
  /// In en, this message translates to:
  /// **'Saved Items'**
  String get savedItems;

  /// No description provided for @savedBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Saved Boutiques'**
  String get savedBoutiques;

  /// No description provided for @savedAddresses.
  ///
  /// In en, this message translates to:
  /// **'Saved Addresses'**
  String get savedAddresses;

  /// No description provided for @adminSection.
  ///
  /// In en, this message translates to:
  /// **'ADMIN'**
  String get adminSection;

  /// No description provided for @superAdminDashboard.
  ///
  /// In en, this message translates to:
  /// **'Super Admin Dashboard'**
  String get superAdminDashboard;

  /// No description provided for @adminPanel.
  ///
  /// In en, this message translates to:
  /// **'Admin Panel'**
  String get adminPanel;

  /// No description provided for @boutiqueSection.
  ///
  /// In en, this message translates to:
  /// **'BOUTIQUE'**
  String get boutiqueSection;

  /// No description provided for @boutiqueDashboard.
  ///
  /// In en, this message translates to:
  /// **'Boutique Dashboard'**
  String get boutiqueDashboard;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGES'**
  String get languages;

  /// No description provided for @supportSection.
  ///
  /// In en, this message translates to:
  /// **'SUPPORT'**
  String get supportSection;

  /// No description provided for @helpSupport.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get helpSupport;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get appearance;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark Mode'**
  String get darkMode;

  /// No description provided for @systemDefault.
  ///
  /// In en, this message translates to:
  /// **'System Default'**
  String get systemDefault;

  /// No description provided for @light.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get light;

  /// No description provided for @dark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get dark;

  /// No description provided for @myOrders.
  ///
  /// In en, this message translates to:
  /// **'My Orders'**
  String get myOrders;

  /// No description provided for @orderNumber.
  ///
  /// In en, this message translates to:
  /// **'Order #{n}'**
  String orderNumber(String n);

  /// No description provided for @orderDate.
  ///
  /// In en, this message translates to:
  /// **'Date: {date}'**
  String orderDate(String date);

  /// No description provided for @orderLabel.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get orderLabel;

  /// No description provided for @orderNumberLabel.
  ///
  /// In en, this message translates to:
  /// **'Order Number:'**
  String get orderNumberLabel;

  /// No description provided for @dateLabel.
  ///
  /// In en, this message translates to:
  /// **'Date:'**
  String get dateLabel;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String statusLabel(String status);

  /// No description provided for @statusPlaced.
  ///
  /// In en, this message translates to:
  /// **'Placed'**
  String get statusPlaced;

  /// No description provided for @statusConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get statusConfirmed;

  /// No description provided for @statusOnTheWay.
  ///
  /// In en, this message translates to:
  /// **'On the Way'**
  String get statusOnTheWay;

  /// No description provided for @statusDelivered.
  ///
  /// In en, this message translates to:
  /// **'Delivered'**
  String get statusDelivered;

  /// No description provided for @statusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get statusCancelled;

  /// No description provided for @itemsOrdered.
  ///
  /// In en, this message translates to:
  /// **'Items Ordered'**
  String get itemsOrdered;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @subtotalNormal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotalNormal;

  /// No description provided for @noPastOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No past orders yet'**
  String get noPastOrdersYet;

  /// No description provided for @completedOrdersWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Completed orders will appear here.'**
  String get completedOrdersWillAppearHere;

  /// No description provided for @trackYourRecentPurchases.
  ///
  /// In en, this message translates to:
  /// **'Track your recent purchases'**
  String get trackYourRecentPurchases;

  /// No description provided for @orderHistoryWillAppearWhenLoggedIn.
  ///
  /// In en, this message translates to:
  /// **'Your order history will appear here once you\'re logged in.'**
  String get orderHistoryWillAppearWhenLoggedIn;

  /// No description provided for @couldNotLoadOrders.
  ///
  /// In en, this message translates to:
  /// **'Could not load orders'**
  String get couldNotLoadOrders;

  /// No description provided for @orderStatus.
  ///
  /// In en, this message translates to:
  /// **'Order Status'**
  String get orderStatus;

  /// No description provided for @placedOrders.
  ///
  /// In en, this message translates to:
  /// **'Placed Orders'**
  String get placedOrders;

  /// No description provided for @processingOrders.
  ///
  /// In en, this message translates to:
  /// **'Processing Orders'**
  String get processingOrders;

  /// No description provided for @shippedOrders.
  ///
  /// In en, this message translates to:
  /// **'Shipped Orders'**
  String get shippedOrders;

  /// No description provided for @deliveredOrders.
  ///
  /// In en, this message translates to:
  /// **'Delivered Orders'**
  String get deliveredOrders;

  /// No description provided for @sizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String sizeLabel(String size);

  /// No description provided for @quantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Qty: {qty}'**
  String quantityLabel(String qty);

  /// No description provided for @colourLabel.
  ///
  /// In en, this message translates to:
  /// **'Colour: {color}'**
  String colourLabel(String color);

  /// No description provided for @disputeAlreadySubmitted.
  ///
  /// In en, this message translates to:
  /// **'You have already submitted a dispute for this order.'**
  String get disputeAlreadySubmitted;

  /// No description provided for @disputeOrder.
  ///
  /// In en, this message translates to:
  /// **'Dispute Order'**
  String get disputeOrder;

  /// No description provided for @disputeWindowPassed.
  ///
  /// In en, this message translates to:
  /// **'The 7-day dispute window has passed.'**
  String get disputeWindowPassed;

  /// No description provided for @disputeWrongItem.
  ///
  /// In en, this message translates to:
  /// **'Wrong item received'**
  String get disputeWrongItem;

  /// No description provided for @disputeDamagedItem.
  ///
  /// In en, this message translates to:
  /// **'Item is damaged'**
  String get disputeDamagedItem;

  /// No description provided for @disputeNotDelivered.
  ///
  /// In en, this message translates to:
  /// **'Not delivered'**
  String get disputeNotDelivered;

  /// No description provided for @disputeOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get disputeOther;

  /// No description provided for @submitDispute.
  ///
  /// In en, this message translates to:
  /// **'Submit Dispute'**
  String get submitDispute;

  /// No description provided for @disputeIssueQuestion.
  ///
  /// In en, this message translates to:
  /// **'What\'s the issue with your order?'**
  String get disputeIssueQuestion;

  /// No description provided for @additionalDetailsOptional.
  ///
  /// In en, this message translates to:
  /// **'Additional details (optional)'**
  String get additionalDetailsOptional;

  /// No description provided for @disputeSubmittedReviewSoon.
  ///
  /// In en, this message translates to:
  /// **'Dispute submitted. We\'ll review it soon.'**
  String get disputeSubmittedReviewSoon;

  /// No description provided for @failedToSubmitDispute.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit dispute'**
  String get failedToSubmitDispute;

  /// No description provided for @orderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Order Confirmation'**
  String get orderConfirmation;

  /// No description provided for @yourPaymentWasSuccessful.
  ///
  /// In en, this message translates to:
  /// **'Your payment was successful'**
  String get yourPaymentWasSuccessful;

  /// No description provided for @orderFromBoutique.
  ///
  /// In en, this message translates to:
  /// **'Your order from {boutiqueName}'**
  String orderFromBoutique(String boutiqueName);

  /// No description provided for @paidSecurelyViaPayzah.
  ///
  /// In en, this message translates to:
  /// **'Paid securely via Payzah'**
  String get paidSecurelyViaPayzah;

  /// No description provided for @thankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you'**
  String get thankYou;

  /// No description provided for @thankYouWithName.
  ///
  /// In en, this message translates to:
  /// **'Thank you, {name}'**
  String thankYouWithName(String name);

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'Back to Home'**
  String get backToHome;

  /// No description provided for @yourCartIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get yourCartIsEmpty;

  /// No description provided for @cartEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty. Add items from a boutique to get started.'**
  String get cartEmptySubtitle;

  /// No description provided for @browseBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Browse Boutiques'**
  String get browseBoutiques;

  /// No description provided for @itemRemovedFromCart.
  ///
  /// In en, this message translates to:
  /// **'Item removed from cart'**
  String get itemRemovedFromCart;

  /// No description provided for @shippingChargesAndDiscountCodesCalculatedAtCheckout.
  ///
  /// In en, this message translates to:
  /// **'Shipping charges and discount codes are calculated at checkout'**
  String get shippingChargesAndDiscountCodesCalculatedAtCheckout;

  /// No description provided for @checkoutButton.
  ///
  /// In en, this message translates to:
  /// **'Checkout'**
  String get checkoutButton;

  /// No description provided for @pleaseLogInToContinueToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Please log in to continue to checkout'**
  String get pleaseLogInToContinueToCheckout;

  /// No description provided for @couldNotLoadCart.
  ///
  /// In en, this message translates to:
  /// **'Could not load cart'**
  String get couldNotLoadCart;

  /// No description provided for @accountDetails.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT DETAILS'**
  String get accountDetails;

  /// No description provided for @deliveryMethod.
  ///
  /// In en, this message translates to:
  /// **'DELIVERY METHOD'**
  String get deliveryMethod;

  /// No description provided for @regularDelivery.
  ///
  /// In en, this message translates to:
  /// **'Regular Delivery'**
  String get regularDelivery;

  /// No description provided for @sameDayDelivery.
  ///
  /// In en, this message translates to:
  /// **'Same Day Delivery'**
  String get sameDayDelivery;

  /// No description provided for @madeToOrder.
  ///
  /// In en, this message translates to:
  /// **'Made to Order'**
  String get madeToOrder;

  /// No description provided for @estimatedDays.
  ///
  /// In en, this message translates to:
  /// **'Estimated ready in'**
  String get estimatedDays;

  /// No description provided for @businessDays.
  ///
  /// In en, this message translates to:
  /// **'business days'**
  String get businessDays;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'PAYMENT METHOD'**
  String get paymentMethod;

  /// No description provided for @card.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get card;

  /// No description provided for @delivery.
  ///
  /// In en, this message translates to:
  /// **'DELIVERY'**
  String get delivery;

  /// No description provided for @pleaseAddADeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Please add a delivery address'**
  String get pleaseAddADeliveryAddress;

  /// No description provided for @paymentCancelled.
  ///
  /// In en, this message translates to:
  /// **'Payment cancelled'**
  String get paymentCancelled;

  /// No description provided for @placingOrder.
  ///
  /// In en, this message translates to:
  /// **'PLACING ORDER...'**
  String get placingOrder;

  /// No description provided for @changeDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Change Delivery Address'**
  String get changeDeliveryAddress;

  /// No description provided for @house.
  ///
  /// In en, this message translates to:
  /// **'House'**
  String get house;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add Product'**
  String get addProduct;

  /// No description provided for @editProduct.
  ///
  /// In en, this message translates to:
  /// **'Edit Product'**
  String get editProduct;

  /// No description provided for @deleteProduct.
  ///
  /// In en, this message translates to:
  /// **'Delete Product'**
  String get deleteProduct;

  /// No description provided for @deleteProductConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this product? This action cannot be undone.'**
  String get deleteProductConfirm;

  /// No description provided for @productDeleted.
  ///
  /// In en, this message translates to:
  /// **'Product deleted'**
  String get productDeleted;

  /// No description provided for @failedToDeleteProduct.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete product'**
  String get failedToDeleteProduct;

  /// No description provided for @failedToLoadProducts.
  ///
  /// In en, this message translates to:
  /// **'Failed to load products'**
  String get failedToLoadProducts;

  /// No description provided for @failedToLoadUsers.
  ///
  /// In en, this message translates to:
  /// **'Failed to load users'**
  String get failedToLoadUsers;

  /// No description provided for @noMatchingProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No matching products found'**
  String get noMatchingProductsFound;

  /// No description provided for @noMatchingBoutiquesFound.
  ///
  /// In en, this message translates to:
  /// **'No matching boutiques found.'**
  String get noMatchingBoutiquesFound;

  /// No description provided for @noDescriptionAddedYet.
  ///
  /// In en, this message translates to:
  /// **'No description added yet.'**
  String get noDescriptionAddedYet;

  /// No description provided for @untitledProduct.
  ///
  /// In en, this message translates to:
  /// **'Untitled Product'**
  String get untitledProduct;

  /// No description provided for @noDescription.
  ///
  /// In en, this message translates to:
  /// **'No description'**
  String get noDescription;

  /// No description provided for @productAddedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Product added successfully'**
  String get productAddedSuccessfully;

  /// No description provided for @failedToAddProduct.
  ///
  /// In en, this message translates to:
  /// **'Failed to add product'**
  String get failedToAddProduct;

  /// No description provided for @createNewProductForBoutique.
  ///
  /// In en, this message translates to:
  /// **'Create a new product for your boutique.'**
  String get createNewProductForBoutique;

  /// No description provided for @productImage.
  ///
  /// In en, this message translates to:
  /// **'Product Image'**
  String get productImage;

  /// No description provided for @tapToUploadImage.
  ///
  /// In en, this message translates to:
  /// **'Tap to upload image'**
  String get tapToUploadImage;

  /// No description provided for @productImages.
  ///
  /// In en, this message translates to:
  /// **'Product images'**
  String get productImages;

  /// No description provided for @tapToUploadImages.
  ///
  /// In en, this message translates to:
  /// **'Tap to upload product images'**
  String get tapToUploadImages;

  /// No description provided for @productTitle.
  ///
  /// In en, this message translates to:
  /// **'Product Title'**
  String get productTitle;

  /// No description provided for @enterProductTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter product title'**
  String get enterProductTitle;

  /// No description provided for @titleRequired.
  ///
  /// In en, this message translates to:
  /// **'Title is required'**
  String get titleRequired;

  /// No description provided for @enterProductDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter product description'**
  String get enterProductDescription;

  /// No description provided for @descriptionRequired.
  ///
  /// In en, this message translates to:
  /// **'Description is required'**
  String get descriptionRequired;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @priceExample.
  ///
  /// In en, this message translates to:
  /// **'Example: 35'**
  String get priceExample;

  /// No description provided for @priceRequired.
  ///
  /// In en, this message translates to:
  /// **'Price is required'**
  String get priceRequired;

  /// No description provided for @enterValidPrice.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid price'**
  String get enterValidPrice;

  /// No description provided for @stockExample.
  ///
  /// In en, this message translates to:
  /// **'Example: 10'**
  String get stockExample;

  /// No description provided for @stockRequired.
  ///
  /// In en, this message translates to:
  /// **'Stock is required'**
  String get stockRequired;

  /// No description provided for @enterValidStockNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid stock number'**
  String get enterValidStockNumber;

  /// No description provided for @stockLabel.
  ///
  /// In en, this message translates to:
  /// **'Stock: {value}'**
  String stockLabel(String value);

  /// No description provided for @stockLeft.
  ///
  /// In en, this message translates to:
  /// **'{count} left'**
  String stockLeft(String count);

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'{count} in stock'**
  String inStock(String count);

  /// No description provided for @inStockWithCount.
  ///
  /// In en, this message translates to:
  /// **'In Stock: {count}'**
  String inStockWithCount(String count);

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @soldOut.
  ///
  /// In en, this message translates to:
  /// **'Sold Out'**
  String get soldOut;

  /// No description provided for @noSalesYet.
  ///
  /// In en, this message translates to:
  /// **'No sales yet'**
  String get noSalesYet;

  /// No description provided for @noProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No products found'**
  String get noProductsFound;

  /// No description provided for @noProductsAvailableYet.
  ///
  /// In en, this message translates to:
  /// **'No products available yet'**
  String get noProductsAvailableYet;

  /// No description provided for @noFeaturedProductsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No featured products available'**
  String get noFeaturedProductsAvailable;

  /// No description provided for @failedToLoadFeaturedProducts.
  ///
  /// In en, this message translates to:
  /// **'Failed to load featured products'**
  String get failedToLoadFeaturedProducts;

  /// No description provided for @noProductNotesYet.
  ///
  /// In en, this message translates to:
  /// **'No product notes yet.'**
  String get noProductNotesYet;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low Stock'**
  String get lowStock;

  /// No description provided for @lowStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get lowStockSubtitle;

  /// No description provided for @stockLooksGood.
  ///
  /// In en, this message translates to:
  /// **'Stock looks good'**
  String get stockLooksGood;

  /// No description provided for @sizes.
  ///
  /// In en, this message translates to:
  /// **'Sizes'**
  String get sizes;

  /// No description provided for @sizesExample.
  ///
  /// In en, this message translates to:
  /// **'Example: S,M,L'**
  String get sizesExample;

  /// No description provided for @sizesRequired.
  ///
  /// In en, this message translates to:
  /// **'Sizes are required'**
  String get sizesRequired;

  /// No description provided for @saveProduct.
  ///
  /// In en, this message translates to:
  /// **'Save Product'**
  String get saveProduct;

  /// No description provided for @sizeSection.
  ///
  /// In en, this message translates to:
  /// **'SIZE'**
  String get sizeSection;

  /// No description provided for @noSizesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No sizes available'**
  String get noSizesAvailable;

  /// No description provided for @sizesAndStock.
  ///
  /// In en, this message translates to:
  /// **'Sizes & stock'**
  String get sizesAndStock;

  /// No description provided for @addEachSizeWithStockCount.
  ///
  /// In en, this message translates to:
  /// **'Add each size with its own stock count'**
  String get addEachSizeWithStockCount;

  /// No description provided for @sizeHint.
  ///
  /// In en, this message translates to:
  /// **'Size (e.g. S, M, 38)'**
  String get sizeHint;

  /// No description provided for @addSize.
  ///
  /// In en, this message translates to:
  /// **'Add size'**
  String get addSize;

  /// No description provided for @sizeStockEntry.
  ///
  /// In en, this message translates to:
  /// **'{sizeName} — {stock} in stock'**
  String sizeStockEntry(String sizeName, String stock);

  /// No description provided for @sizeGuide.
  ///
  /// In en, this message translates to:
  /// **'Size Guide'**
  String get sizeGuide;

  /// No description provided for @sizeGuideSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Upload a chart buyers can reference before selecting a size.'**
  String get sizeGuideSubtitle;

  /// No description provided for @uploadSizeGuide.
  ///
  /// In en, this message translates to:
  /// **'Upload size guide image'**
  String get uploadSizeGuide;

  /// No description provided for @changeImage.
  ///
  /// In en, this message translates to:
  /// **'Change image'**
  String get changeImage;

  /// No description provided for @productDetails.
  ///
  /// In en, this message translates to:
  /// **'Product Details'**
  String get productDetails;

  /// No description provided for @materialCare.
  ///
  /// In en, this message translates to:
  /// **'Material & Care'**
  String get materialCare;

  /// No description provided for @materialCareDetails.
  ///
  /// In en, this message translates to:
  /// **'Material and care details can be added later.'**
  String get materialCareDetails;

  /// No description provided for @materialAndCareDetailsCanBeAddedLater.
  ///
  /// In en, this message translates to:
  /// **'Material and care details can be added later by the boutique owner.'**
  String get materialAndCareDetailsCanBeAddedLater;

  /// No description provided for @sizeFit.
  ///
  /// In en, this message translates to:
  /// **'Size & Fit'**
  String get sizeFit;

  /// No description provided for @availableSizes.
  ///
  /// In en, this message translates to:
  /// **'Available sizes:'**
  String get availableSizes;

  /// No description provided for @availableSizesText.
  ///
  /// In en, this message translates to:
  /// **'Available sizes: {sizes}'**
  String availableSizesText(String sizes);

  /// No description provided for @noSizeInformationAvailable.
  ///
  /// In en, this message translates to:
  /// **'No size information available.'**
  String get noSizeInformationAvailable;

  /// No description provided for @colours.
  ///
  /// In en, this message translates to:
  /// **'COLOURS'**
  String get colours;

  /// No description provided for @addAColour.
  ///
  /// In en, this message translates to:
  /// **'Add a colour'**
  String get addAColour;

  /// No description provided for @madeToOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Enable if this item is produced after purchase'**
  String get madeToOrderSubtitle;

  /// No description provided for @deliveryTimeframe.
  ///
  /// In en, this message translates to:
  /// **'Delivery timeframe'**
  String get deliveryTimeframe;

  /// No description provided for @deliveryTimeframeHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 7–10 business days'**
  String get deliveryTimeframeHint;

  /// No description provided for @atLeastOneImageRequired.
  ///
  /// In en, this message translates to:
  /// **'Please add at least one product image'**
  String get atLeastOneImageRequired;

  /// No description provided for @atLeastOneCategoryRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one category'**
  String get atLeastOneCategoryRequired;

  /// No description provided for @atLeastOneSizeRequired.
  ///
  /// In en, this message translates to:
  /// **'Please add at least one size'**
  String get atLeastOneSizeRequired;

  /// No description provided for @deliveryTimeframeRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a delivery timeframe'**
  String get deliveryTimeframeRequired;

  /// No description provided for @enterSizeName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a size name'**
  String get enterSizeName;

  /// No description provided for @enterValidStock.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid stock number'**
  String get enterValidStock;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @selectAllThatApply.
  ///
  /// In en, this message translates to:
  /// **'Select all that apply'**
  String get selectAllThatApply;

  /// No description provided for @pleaseSelectASize.
  ///
  /// In en, this message translates to:
  /// **'Please select a size'**
  String get pleaseSelectASize;

  /// No description provided for @pleaseSelectAColour.
  ///
  /// In en, this message translates to:
  /// **'Please select a colour'**
  String get pleaseSelectAColour;

  /// No description provided for @itemSaved.
  ///
  /// In en, this message translates to:
  /// **'Item saved'**
  String get itemSaved;

  /// No description provided for @itemRemovedFromSavedItems.
  ///
  /// In en, this message translates to:
  /// **'Removed from saved items'**
  String get itemRemovedFromSavedItems;

  /// No description provided for @itemRemovedFromSaved.
  ///
  /// In en, this message translates to:
  /// **'Removed from saved'**
  String get itemRemovedFromSaved;

  /// No description provided for @itemAddedToCart.
  ///
  /// In en, this message translates to:
  /// **'Item added to cart'**
  String get itemAddedToCart;

  /// No description provided for @thisProductIsOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'This product is out of stock'**
  String get thisProductIsOutOfStock;

  /// No description provided for @byBoutique.
  ///
  /// In en, this message translates to:
  /// **'by {boutiqueName}'**
  String byBoutique(String boutiqueName);

  /// No description provided for @boutique.
  ///
  /// In en, this message translates to:
  /// **'Boutique'**
  String get boutique;

  /// No description provided for @boutiques.
  ///
  /// In en, this message translates to:
  /// **'Boutiques'**
  String get boutiques;

  /// No description provided for @myBoutique.
  ///
  /// In en, this message translates to:
  /// **'My Boutique'**
  String get myBoutique;

  /// No description provided for @myBoutiqueDescription.
  ///
  /// In en, this message translates to:
  /// **'View and manage your boutique details.'**
  String get myBoutiqueDescription;

  /// No description provided for @myBoutiqueDefault.
  ///
  /// In en, this message translates to:
  /// **'My Boutique'**
  String get myBoutiqueDefault;

  /// No description provided for @editBoutique.
  ///
  /// In en, this message translates to:
  /// **'Edit Boutique'**
  String get editBoutique;

  /// No description provided for @logoImage.
  ///
  /// In en, this message translates to:
  /// **'Logo Image'**
  String get logoImage;

  /// No description provided for @bannerImage.
  ///
  /// In en, this message translates to:
  /// **'Banner Image'**
  String get bannerImage;

  /// No description provided for @failedToLoadBoutique.
  ///
  /// In en, this message translates to:
  /// **'Failed to load boutique'**
  String get failedToLoadBoutique;

  /// No description provided for @failedToLoadBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Failed to load boutiques'**
  String get failedToLoadBoutiques;

  /// No description provided for @imageCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Image could not load'**
  String get imageCouldNotLoad;

  /// No description provided for @noImageUploaded.
  ///
  /// In en, this message translates to:
  /// **'No image uploaded'**
  String get noImageUploaded;

  /// No description provided for @noBoutiqueFound.
  ///
  /// In en, this message translates to:
  /// **'No boutique found'**
  String get noBoutiqueFound;

  /// No description provided for @noBoutiquesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No boutiques available'**
  String get noBoutiquesAvailable;

  /// No description provided for @boutiqueNotFound.
  ///
  /// In en, this message translates to:
  /// **'Boutique not found'**
  String get boutiqueNotFound;

  /// No description provided for @boutiqueNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'This boutique is no longer available.'**
  String get boutiqueNoLongerAvailable;

  /// No description provided for @exploreBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Explore Boutiques'**
  String get exploreBoutiques;

  /// No description provided for @boutiquesYouFollow.
  ///
  /// In en, this message translates to:
  /// **'Boutiques you follow'**
  String get boutiquesYouFollow;

  /// No description provided for @boutiquesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} boutiques'**
  String boutiquesCount(int count);

  /// No description provided for @noBoutiquesFound.
  ///
  /// In en, this message translates to:
  /// **'No boutiques found'**
  String get noBoutiquesFound;

  /// No description provided for @noSavedBoutiquesYet.
  ///
  /// In en, this message translates to:
  /// **'No saved boutiques yet'**
  String get noSavedBoutiquesYet;

  /// No description provided for @failedToLoadSavedBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Failed to load saved boutiques'**
  String get failedToLoadSavedBoutiques;

  /// No description provided for @boutiqueRemovedFromSaved.
  ///
  /// In en, this message translates to:
  /// **'Boutique removed from saved'**
  String get boutiqueRemovedFromSaved;

  /// No description provided for @boutiquesAndProducts.
  ///
  /// In en, this message translates to:
  /// **'Boutiques & products'**
  String get boutiquesAndProducts;

  /// No description provided for @noDescriptionAvailable.
  ///
  /// In en, this message translates to:
  /// **'No description available.'**
  String get noDescriptionAvailable;

  /// No description provided for @soldCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sold'**
  String soldCount(String count);

  /// No description provided for @productsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} products'**
  String productsCount(int count);

  /// No description provided for @noSavedItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No saved items yet'**
  String get noSavedItemsYet;

  /// No description provided for @failedToLoadSavedItems.
  ///
  /// In en, this message translates to:
  /// **'Failed to load saved items'**
  String get failedToLoadSavedItems;

  /// No description provided for @yourCuratedWishlist.
  ///
  /// In en, this message translates to:
  /// **'Your curated wishlist'**
  String get yourCuratedWishlist;

  /// No description provided for @addDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Add Delivery Address'**
  String get addDeliveryAddress;

  /// No description provided for @governorate.
  ///
  /// In en, this message translates to:
  /// **'Governorate'**
  String get governorate;

  /// No description provided for @area.
  ///
  /// In en, this message translates to:
  /// **'Area'**
  String get area;

  /// No description provided for @block.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// No description provided for @street.
  ///
  /// In en, this message translates to:
  /// **'Street'**
  String get street;

  /// No description provided for @houseBuilding.
  ///
  /// In en, this message translates to:
  /// **'House/Building'**
  String get houseBuilding;

  /// No description provided for @floorOptional.
  ///
  /// In en, this message translates to:
  /// **'Floor (Optional)'**
  String get floorOptional;

  /// No description provided for @apartmentOptional.
  ///
  /// In en, this message translates to:
  /// **'Apartment (Optional)'**
  String get apartmentOptional;

  /// No description provided for @failedToSaveAddress.
  ///
  /// In en, this message translates to:
  /// **'Failed to save address'**
  String get failedToSaveAddress;

  /// No description provided for @floor.
  ///
  /// In en, this message translates to:
  /// **'Floor'**
  String get floor;

  /// No description provided for @apartment.
  ///
  /// In en, this message translates to:
  /// **'Apartment'**
  String get apartment;

  /// No description provided for @phone.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phone;

  /// No description provided for @addressLine1.
  ///
  /// In en, this message translates to:
  /// **'Address Line 1'**
  String get addressLine1;

  /// No description provided for @addressLine2Optional.
  ///
  /// In en, this message translates to:
  /// **'Address Line 2 (optional)'**
  String get addressLine2Optional;

  /// No description provided for @city.
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get city;

  /// No description provided for @zipCode.
  ///
  /// In en, this message translates to:
  /// **'Zip / Postal Code'**
  String get zipCode;

  /// No description provided for @countryRegion.
  ///
  /// In en, this message translates to:
  /// **'Country / Region'**
  String get countryRegion;

  /// No description provided for @selectCountry.
  ///
  /// In en, this message translates to:
  /// **'Select Country'**
  String get selectCountry;

  /// No description provided for @somethingWentWrongWhileLoadingAddresses.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while loading addresses'**
  String get somethingWentWrongWhileLoadingAddresses;

  /// No description provided for @noSavedAddressesYet.
  ///
  /// In en, this message translates to:
  /// **'No saved addresses yet.'**
  String get noSavedAddressesYet;

  /// No description provided for @addressRemoved.
  ///
  /// In en, this message translates to:
  /// **'Address removed'**
  String get addressRemoved;

  /// No description provided for @failedToRemoveAddress.
  ///
  /// In en, this message translates to:
  /// **'Failed to remove address'**
  String get failedToRemoveAddress;

  /// No description provided for @addNewAddress.
  ///
  /// In en, this message translates to:
  /// **'Add New Address'**
  String get addNewAddress;

  /// No description provided for @addNow.
  ///
  /// In en, this message translates to:
  /// **'ADD NOW'**
  String get addNow;

  /// No description provided for @couldNotLoadSavedAddresses.
  ///
  /// In en, this message translates to:
  /// **'Could not load saved addresses'**
  String get couldNotLoadSavedAddresses;

  /// No description provided for @blockStreetLine.
  ///
  /// In en, this message translates to:
  /// **'Block {block}, Street {street}'**
  String blockStreetLine(String block, String street);

  /// No description provided for @houseBuildingValue.
  ///
  /// In en, this message translates to:
  /// **'House/Building: {value}'**
  String houseBuildingValue(String value);

  /// No description provided for @floorValue.
  ///
  /// In en, this message translates to:
  /// **'Floor: {value}'**
  String floorValue(String value);

  /// No description provided for @apartmentValue.
  ///
  /// In en, this message translates to:
  /// **'Apartment: {value}'**
  String apartmentValue(String value);

  /// No description provided for @phoneValue.
  ///
  /// In en, this message translates to:
  /// **'Phone: {value}'**
  String phoneValue(String value);

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search products, boutiques...'**
  String get searchHint;

  /// No description provided for @searchForProductsOrBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Search for products or boutiques'**
  String get searchForProductsOrBoutiques;

  /// No description provided for @searchProductsOrBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Search products or boutiques'**
  String get searchProductsOrBoutiques;

  /// No description provided for @searchBoutiquesHint.
  ///
  /// In en, this message translates to:
  /// **'Search boutiques...'**
  String get searchBoutiquesHint;

  /// No description provided for @failedToLoadSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Failed to load search results'**
  String get failedToLoadSearchResults;

  /// No description provided for @productsTab.
  ///
  /// In en, this message translates to:
  /// **'PRODUCTS'**
  String get productsTab;

  /// No description provided for @boutiquesTab.
  ///
  /// In en, this message translates to:
  /// **'BOUTIQUES'**
  String get boutiquesTab;

  /// No description provided for @productsTabWithCount.
  ///
  /// In en, this message translates to:
  /// **'PRODUCTS ({count})'**
  String productsTabWithCount(int count);

  /// No description provided for @boutiquesTabWithCount.
  ///
  /// In en, this message translates to:
  /// **'BOUTIQUES ({count})'**
  String boutiquesTabWithCount(int count);

  /// No description provided for @itemsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String itemsCount(int count);

  /// No description provided for @noMatchingBoutiquesFound2.
  ///
  /// In en, this message translates to:
  /// **'No matching boutiques found.'**
  String get noMatchingBoutiquesFound2;

  /// No description provided for @shopByCategoryAcrossAllBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Shop by category across all boutiques'**
  String get shopByCategoryAcrossAllBoutiques;

  /// No description provided for @allProducts.
  ///
  /// In en, this message translates to:
  /// **'All Products'**
  String get allProducts;

  /// No description provided for @sortNewest.
  ///
  /// In en, this message translates to:
  /// **'Newest'**
  String get sortNewest;

  /// No description provided for @sortOldest.
  ///
  /// In en, this message translates to:
  /// **'Oldest'**
  String get sortOldest;

  /// No description provided for @sortPriceLow.
  ///
  /// In en, this message translates to:
  /// **'Price ↑'**
  String get sortPriceLow;

  /// No description provided for @sortPriceHigh.
  ///
  /// In en, this message translates to:
  /// **'Price ↓'**
  String get sortPriceHigh;

  /// No description provided for @featuredPieces.
  ///
  /// In en, this message translates to:
  /// **'Featured Pieces'**
  String get featuredPieces;

  /// No description provided for @topBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Top Boutiques'**
  String get topBoutiques;

  /// No description provided for @exploreRamadanCollection.
  ///
  /// In en, this message translates to:
  /// **'Explore Ramadan Collection'**
  String get exploreRamadanCollection;

  /// No description provided for @curatedIndependentLabels.
  ///
  /// In en, this message translates to:
  /// **'Curated independent labels'**
  String get curatedIndependentLabels;

  /// No description provided for @failedToPickImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick image'**
  String get failedToPickImage;

  /// No description provided for @pleaseSelectImage.
  ///
  /// In en, this message translates to:
  /// **'Please select an image'**
  String get pleaseSelectImage;

  /// No description provided for @welcomeBack2.
  ///
  /// In en, this message translates to:
  /// **'Welcome back,'**
  String get welcomeBack2;

  /// No description provided for @ownerFallback.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get ownerFallback;

  /// No description provided for @dashboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage your boutique, products, and sales from one place.'**
  String get dashboardDescription;

  /// No description provided for @todaysSales.
  ///
  /// In en, this message translates to:
  /// **'Today\'s Sales'**
  String get todaysSales;

  /// No description provided for @updatedFromRealOrders.
  ///
  /// In en, this message translates to:
  /// **'Updated from real orders'**
  String get updatedFromRealOrders;

  /// No description provided for @noSalesToday.
  ///
  /// In en, this message translates to:
  /// **'No sales today'**
  String get noSalesToday;

  /// No description provided for @activeListings.
  ///
  /// In en, this message translates to:
  /// **'Active listings'**
  String get activeListings;

  /// No description provided for @ordersCountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} total orders'**
  String ordersCountSubtitle(int count);

  /// No description provided for @needsRestock.
  ///
  /// In en, this message translates to:
  /// **'Needs restock'**
  String get needsRestock;

  /// No description provided for @needRestock.
  ///
  /// In en, this message translates to:
  /// **'Need restock'**
  String get needRestock;

  /// No description provided for @salesOverview.
  ///
  /// In en, this message translates to:
  /// **'Sales Overview'**
  String get salesOverview;

  /// No description provided for @weeklySales.
  ///
  /// In en, this message translates to:
  /// **'Weekly Sales'**
  String get weeklySales;

  /// No description provided for @weeklySalesDescription.
  ///
  /// In en, this message translates to:
  /// **'Based on real order totals from the last 7 days.'**
  String get weeklySalesDescription;

  /// No description provided for @dayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get dayMon;

  /// No description provided for @dayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get dayTue;

  /// No description provided for @dayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get dayWed;

  /// No description provided for @dayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get dayThu;

  /// No description provided for @dayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get dayFri;

  /// No description provided for @daySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get daySat;

  /// No description provided for @daySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get daySun;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActions;

  /// No description provided for @viewBoutiqueDetails.
  ///
  /// In en, this message translates to:
  /// **'View boutique details'**
  String get viewBoutiqueDetails;

  /// No description provided for @myProducts.
  ///
  /// In en, this message translates to:
  /// **'My Products'**
  String get myProducts;

  /// No description provided for @manageProductList.
  ///
  /// In en, this message translates to:
  /// **'Manage product list'**
  String get manageProductList;

  /// No description provided for @createANewListing.
  ///
  /// In en, this message translates to:
  /// **'Create a new listing'**
  String get createANewListing;

  /// No description provided for @trackIncomingSales.
  ///
  /// In en, this message translates to:
  /// **'Track incoming sales'**
  String get trackIncomingSales;

  /// No description provided for @inventoryNotes.
  ///
  /// In en, this message translates to:
  /// **'Inventory Notes'**
  String get inventoryNotes;

  /// No description provided for @failedToLoadDashboard.
  ///
  /// In en, this message translates to:
  /// **'Failed to load dashboard'**
  String get failedToLoadDashboard;

  /// No description provided for @analytics.
  ///
  /// In en, this message translates to:
  /// **'Analytics'**
  String get analytics;

  /// No description provided for @marketplacePerformanceOverview.
  ///
  /// In en, this message translates to:
  /// **'Marketplace performance overview'**
  String get marketplacePerformanceOverview;

  /// No description provided for @marketplaceActivityOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview of your marketplace activity.'**
  String get marketplaceActivityOverview;

  /// No description provided for @failedToLoadAnalytics.
  ///
  /// In en, this message translates to:
  /// **'Failed to load analytics'**
  String get failedToLoadAnalytics;

  /// No description provided for @allTime.
  ///
  /// In en, this message translates to:
  /// **'All time'**
  String get allTime;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @thisWeek.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get thisWeek;

  /// No description provided for @thisMonth.
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get thisMonth;

  /// No description provided for @totalRevenue.
  ///
  /// In en, this message translates to:
  /// **'Total Revenue'**
  String get totalRevenue;

  /// No description provided for @totalOrders.
  ///
  /// In en, this message translates to:
  /// **'Total Orders'**
  String get totalOrders;

  /// No description provided for @ordersInSelectedPeriod.
  ///
  /// In en, this message translates to:
  /// **'Orders in selected period'**
  String get ordersInSelectedPeriod;

  /// No description provided for @averageOrderValue.
  ///
  /// In en, this message translates to:
  /// **'Average Order Value'**
  String get averageOrderValue;

  /// No description provided for @revenueDividedByOrderCount.
  ///
  /// In en, this message translates to:
  /// **'Revenue ÷ order count'**
  String get revenueDividedByOrderCount;

  /// No description provided for @topBoutique.
  ///
  /// In en, this message translates to:
  /// **'Top Boutique'**
  String get topBoutique;

  /// No description provided for @basedOnTotalSales.
  ///
  /// In en, this message translates to:
  /// **'Based on total sales'**
  String get basedOnTotalSales;

  /// No description provided for @amountKwd.
  ///
  /// In en, this message translates to:
  /// **'{amount} KWD'**
  String amountKwd(String amount);

  /// No description provided for @superAdmin.
  ///
  /// In en, this message translates to:
  /// **'SUPER ADMIN'**
  String get superAdmin;

  /// No description provided for @overview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get overview;

  /// No description provided for @totalUsers.
  ///
  /// In en, this message translates to:
  /// **'Total Users'**
  String get totalUsers;

  /// No description provided for @allRegisteredUsers.
  ///
  /// In en, this message translates to:
  /// **'All registered users'**
  String get allRegisteredUsers;

  /// No description provided for @recentlyActive.
  ///
  /// In en, this message translates to:
  /// **'Recently Active'**
  String get recentlyActive;

  /// No description provided for @seenInLast5Min.
  ///
  /// In en, this message translates to:
  /// **'Seen in last 5 min'**
  String get seenInLast5Min;

  /// No description provided for @allBoutiques.
  ///
  /// In en, this message translates to:
  /// **'All Boutiques'**
  String get allBoutiques;

  /// No description provided for @allBoutiqueDocuments.
  ///
  /// In en, this message translates to:
  /// **'All boutique documents'**
  String get allBoutiqueDocuments;

  /// No description provided for @globalOrders.
  ///
  /// In en, this message translates to:
  /// **'Global Orders'**
  String get globalOrders;

  /// No description provided for @acrossAllBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Across all boutiques'**
  String get acrossAllBoutiques;

  /// No description provided for @totalSales.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get totalSales;

  /// No description provided for @tapToViewBoutiqueSales.
  ///
  /// In en, this message translates to:
  /// **'Tap to view boutique sales'**
  String get tapToViewBoutiqueSales;

  /// No description provided for @userManagement.
  ///
  /// In en, this message translates to:
  /// **'User Management'**
  String get userManagement;

  /// No description provided for @regularUsers.
  ///
  /// In en, this message translates to:
  /// **'Regular Users'**
  String get regularUsers;

  /// No description provided for @customerAccounts.
  ///
  /// In en, this message translates to:
  /// **'Customer accounts'**
  String get customerAccounts;

  /// No description provided for @boutiqueOwners.
  ///
  /// In en, this message translates to:
  /// **'Boutique Owners'**
  String get boutiqueOwners;

  /// No description provided for @ownerAccounts.
  ///
  /// In en, this message translates to:
  /// **'Owner accounts'**
  String get ownerAccounts;

  /// No description provided for @admins.
  ///
  /// In en, this message translates to:
  /// **'Admins'**
  String get admins;

  /// No description provided for @adminAccounts.
  ///
  /// In en, this message translates to:
  /// **'Admin accounts'**
  String get adminAccounts;

  /// No description provided for @fullAccessAccount.
  ///
  /// In en, this message translates to:
  /// **'Full access account'**
  String get fullAccessAccount;

  /// No description provided for @marketplaceControl.
  ///
  /// In en, this message translates to:
  /// **'Marketplace Control'**
  String get marketplaceControl;

  /// No description provided for @homepage.
  ///
  /// In en, this message translates to:
  /// **'Homepage'**
  String get homepage;

  /// No description provided for @heroBanners.
  ///
  /// In en, this message translates to:
  /// **'Hero Banners'**
  String get heroBanners;

  /// No description provided for @uploadAndScheduleBanners.
  ///
  /// In en, this message translates to:
  /// **'Upload & schedule banners'**
  String get uploadAndScheduleBanners;

  /// No description provided for @disputes.
  ///
  /// In en, this message translates to:
  /// **'Disputes'**
  String get disputes;

  /// No description provided for @customerOrderDisputes.
  ///
  /// In en, this message translates to:
  /// **'Customer order disputes'**
  String get customerOrderDisputes;

  /// No description provided for @notifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get notifications;

  /// No description provided for @messageUsers.
  ///
  /// In en, this message translates to:
  /// **'Message users'**
  String get messageUsers;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @viewInsights.
  ///
  /// In en, this message translates to:
  /// **'View insights'**
  String get viewInsights;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenue;

  /// No description provided for @breakdown.
  ///
  /// In en, this message translates to:
  /// **'Breakdown'**
  String get breakdown;

  /// No description provided for @commissionsAndPromoSlots.
  ///
  /// In en, this message translates to:
  /// **'Commissions & promo slots'**
  String get commissionsAndPromoSlots;

  /// No description provided for @boutiqueManagement.
  ///
  /// In en, this message translates to:
  /// **'Boutique Management'**
  String get boutiqueManagement;

  /// No description provided for @boutiqueOnboarding.
  ///
  /// In en, this message translates to:
  /// **'Boutique Onboarding'**
  String get boutiqueOnboarding;

  /// No description provided for @boutiqueOnboardingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Register a new boutique owner'**
  String get boutiqueOnboardingSubtitle;

  /// No description provided for @findUser.
  ///
  /// In en, this message translates to:
  /// **'Find User'**
  String get findUser;

  /// No description provided for @boutiqueDetails.
  ///
  /// In en, this message translates to:
  /// **'Boutique Details'**
  String get boutiqueDetails;

  /// No description provided for @upgradeUserToBoutiqueOwner.
  ///
  /// In en, this message translates to:
  /// **'Upgrade an existing user account to a boutique owner.'**
  String get upgradeUserToBoutiqueOwner;

  /// No description provided for @findAccount.
  ///
  /// In en, this message translates to:
  /// **'Find Account'**
  String get findAccount;

  /// No description provided for @enterOwnerSignupEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter the email the boutique owner used to sign up.'**
  String get enterOwnerSignupEmail;

  /// No description provided for @userAlreadyBoutiqueOwner.
  ///
  /// In en, this message translates to:
  /// **'This user is already a boutique owner'**
  String get userAlreadyBoutiqueOwner;

  /// No description provided for @noAccountFoundAskSignup.
  ///
  /// In en, this message translates to:
  /// **'No account found with this email. Ask the owner to sign up first.'**
  String get noAccountFoundAskSignup;

  /// No description provided for @ownerLabel.
  ///
  /// In en, this message translates to:
  /// **'OWNER'**
  String get ownerLabel;

  /// No description provided for @ownerCanNowLogin.
  ///
  /// In en, this message translates to:
  /// **'The owner can now log in and access their boutique dashboard.'**
  String get ownerCanNowLogin;

  /// No description provided for @boutiqueNowLiveOnLibsk.
  ///
  /// In en, this message translates to:
  /// **'{boutiqueName} is now live on LIBSK.'**
  String boutiqueNowLiveOnLibsk(String boutiqueName);

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get descriptionOptional;

  /// No description provided for @commission.
  ///
  /// In en, this message translates to:
  /// **'commission'**
  String get commission;

  /// No description provided for @createBoutique.
  ///
  /// In en, this message translates to:
  /// **'Create Boutique'**
  String get createBoutique;

  /// No description provided for @cropBanner.
  ///
  /// In en, this message translates to:
  /// **'Crop Banner'**
  String get cropBanner;

  /// No description provided for @selectBannerImage.
  ///
  /// In en, this message translates to:
  /// **'Please select a banner image'**
  String get selectBannerImage;

  /// No description provided for @bannerUploadedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Banner uploaded successfully'**
  String get bannerUploadedSuccessfully;

  /// No description provided for @uploadFailed.
  ///
  /// In en, this message translates to:
  /// **'Upload failed'**
  String get uploadFailed;

  /// No description provided for @deleteBanner.
  ///
  /// In en, this message translates to:
  /// **'Delete Banner'**
  String get deleteBanner;

  /// No description provided for @confirmDeleteBanner.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove this banner?'**
  String get confirmDeleteBanner;

  /// No description provided for @bannerRemoved.
  ///
  /// In en, this message translates to:
  /// **'Banner removed'**
  String get bannerRemoved;

  /// No description provided for @manageHomepageBanners.
  ///
  /// In en, this message translates to:
  /// **'Manage homepage rotating banners.'**
  String get manageHomepageBanners;

  /// No description provided for @noActiveBanners.
  ///
  /// In en, this message translates to:
  /// **'No active banners'**
  String get noActiveBanners;

  /// No description provided for @livePreview.
  ///
  /// In en, this message translates to:
  /// **'LIVE PREVIEW'**
  String get livePreview;

  /// No description provided for @allBanners.
  ///
  /// In en, this message translates to:
  /// **'ALL BANNERS'**
  String get allBanners;

  /// No description provided for @noBannersAddedYet.
  ///
  /// In en, this message translates to:
  /// **'No banners added yet'**
  String get noBannersAddedYet;

  /// No description provided for @untitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get untitled;

  /// No description provided for @activeCaps.
  ///
  /// In en, this message translates to:
  /// **'ACTIVE'**
  String get activeCaps;

  /// No description provided for @hiddenCaps.
  ///
  /// In en, this message translates to:
  /// **'HIDDEN'**
  String get hiddenCaps;

  /// No description provided for @addNewBanner.
  ///
  /// In en, this message translates to:
  /// **'ADD NEW BANNER'**
  String get addNewBanner;

  /// No description provided for @bannerImageGuideline.
  ///
  /// In en, this message translates to:
  /// **'Images are cropped to 16:9 ratio. Recommended size: 1920×1080px. The banner displays at full width, 300px tall on the home screen.'**
  String get bannerImageGuideline;

  /// No description provided for @changeCaps.
  ///
  /// In en, this message translates to:
  /// **'CHANGE'**
  String get changeCaps;

  /// No description provided for @tapToSelectCropBannerImage.
  ///
  /// In en, this message translates to:
  /// **'Tap to select & crop banner image'**
  String get tapToSelectCropBannerImage;

  /// No description provided for @willBeCroppedToRatio.
  ///
  /// In en, this message translates to:
  /// **'Will be cropped to 16:9'**
  String get willBeCroppedToRatio;

  /// No description provided for @bannerTitleOptional.
  ///
  /// In en, this message translates to:
  /// **'Banner title (optional)'**
  String get bannerTitleOptional;

  /// No description provided for @subtitleOptional.
  ///
  /// In en, this message translates to:
  /// **'Subtitle (optional)'**
  String get subtitleOptional;

  /// No description provided for @exactHomePreview.
  ///
  /// In en, this message translates to:
  /// **'↑ Exact preview of how it appears on the home screen'**
  String get exactHomePreview;

  /// No description provided for @uploadBannerButton.
  ///
  /// In en, this message translates to:
  /// **'Upload Banner'**
  String get uploadBannerButton;

  /// No description provided for @sendNotificationTitle.
  ///
  /// In en, this message translates to:
  /// **'Send Notification'**
  String get sendNotificationTitle;

  /// No description provided for @sendNotificationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Send a push notification to your users.'**
  String get sendNotificationSubtitle;

  /// No description provided for @target.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get target;

  /// No description provided for @selectTarget.
  ///
  /// In en, this message translates to:
  /// **'Select target'**
  String get selectTarget;

  /// No description provided for @allUsers.
  ///
  /// In en, this message translates to:
  /// **'All Users'**
  String get allUsers;

  /// No description provided for @notificationTitleLabel.
  ///
  /// In en, this message translates to:
  /// **'Notification Title'**
  String get notificationTitleLabel;

  /// No description provided for @message.
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get message;

  /// No description provided for @sendNotificationButton.
  ///
  /// In en, this message translates to:
  /// **'Send Notification'**
  String get sendNotificationButton;

  /// No description provided for @enterTitleAndMessage.
  ///
  /// In en, this message translates to:
  /// **'Please enter a title and message'**
  String get enterTitleAndMessage;

  /// No description provided for @notificationSentToUsers.
  ///
  /// In en, this message translates to:
  /// **'Notification sent to {count} users'**
  String notificationSentToUsers(String count);

  /// No description provided for @notificationSentToAllUsers.
  ///
  /// In en, this message translates to:
  /// **'Notification sent to all users'**
  String get notificationSentToAllUsers;

  /// No description provided for @failedToSendNotification.
  ///
  /// In en, this message translates to:
  /// **'Failed to send notification: {error}'**
  String failedToSendNotification(String error);

  /// No description provided for @libskTagline.
  ///
  /// In en, this message translates to:
  /// **'Shop Local. Dress Global.'**
  String get libskTagline;

  /// No description provided for @libskDescription.
  ///
  /// In en, this message translates to:
  /// **'LIBSK is Kuwait\'s fashion marketplace connecting shoppers with the best independent local boutiques, all in one place. Browse, order, and receive from your favourite Kuwait brands with ease.'**
  String get libskDescription;

  /// No description provided for @howCanWeHelpYouToday.
  ///
  /// In en, this message translates to:
  /// **'How can we help you today?'**
  String get howCanWeHelpYouToday;

  /// No description provided for @contactUs.
  ///
  /// In en, this message translates to:
  /// **'CONTACT US'**
  String get contactUs;

  /// No description provided for @emailSupport.
  ///
  /// In en, this message translates to:
  /// **'Email Support'**
  String get emailSupport;

  /// No description provided for @sendAMessage.
  ///
  /// In en, this message translates to:
  /// **'SEND A MESSAGE'**
  String get sendAMessage;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourEmail.
  ///
  /// In en, this message translates to:
  /// **'Your email'**
  String get yourEmail;

  /// No description provided for @describeYourIssue.
  ///
  /// In en, this message translates to:
  /// **'Describe your issue or question'**
  String get describeYourIssue;

  /// No description provided for @sendMessage.
  ///
  /// In en, this message translates to:
  /// **'Send Message'**
  String get sendMessage;

  /// No description provided for @messageSentSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Your message has been sent. We will get back to you shortly.'**
  String get messageSentSuccessfully;

  /// No description provided for @fillAllFields.
  ///
  /// In en, this message translates to:
  /// **'Please fill in all fields'**
  String get fillAllFields;

  /// No description provided for @helpTopicOrders.
  ///
  /// In en, this message translates to:
  /// **'Orders'**
  String get helpTopicOrders;

  /// No description provided for @helpTopicDelivery.
  ///
  /// In en, this message translates to:
  /// **'Delivery'**
  String get helpTopicDelivery;

  /// No description provided for @helpTopicReturns.
  ///
  /// In en, this message translates to:
  /// **'Returns'**
  String get helpTopicReturns;

  /// No description provided for @helpTopicPayment.
  ///
  /// In en, this message translates to:
  /// **'Payment'**
  String get helpTopicPayment;

  /// No description provided for @helpTopicAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get helpTopicAccount;

  /// No description provided for @helpTopicBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Boutiques'**
  String get helpTopicBoutiques;

  /// No description provided for @helpOrdersQ1.
  ///
  /// In en, this message translates to:
  /// **'How do I track my order?'**
  String get helpOrdersQ1;

  /// No description provided for @helpOrdersA1.
  ///
  /// In en, this message translates to:
  /// **'Once your order is placed, you can track it from the Orders section in your profile. You will see real-time status updates as your order is processed and delivered.'**
  String get helpOrdersA1;

  /// No description provided for @helpOrdersQ2.
  ///
  /// In en, this message translates to:
  /// **'Can I cancel my order?'**
  String get helpOrdersQ2;

  /// No description provided for @helpOrdersA2.
  ///
  /// In en, this message translates to:
  /// **'Orders can be cancelled within 1 hour of placement. After that, the boutique may have already begun processing it. Contact us immediately if you need to cancel.'**
  String get helpOrdersA2;

  /// No description provided for @helpOrdersQ3.
  ///
  /// In en, this message translates to:
  /// **'My order shows delivered but I have not received it.'**
  String get helpOrdersQ3;

  /// No description provided for @helpOrdersA3.
  ///
  /// In en, this message translates to:
  /// **'Please check with neighbours or building reception first. If the item is still missing, contact our support team within 48 hours and we will investigate.'**
  String get helpOrdersA3;

  /// No description provided for @helpOrdersQ4.
  ///
  /// In en, this message translates to:
  /// **'How do I open a dispute?'**
  String get helpOrdersQ4;

  /// No description provided for @helpOrdersA4.
  ///
  /// In en, this message translates to:
  /// **'You have 7 days from the delivery date to open a dispute. Go to your Orders, select the relevant order, and tap Open Dispute. Describe your issue and submit. Please note that boutique owners and admins have the right to review and reject disputes based on the nature and validity of the claim.'**
  String get helpOrdersA4;

  /// No description provided for @helpDeliveryQ1.
  ///
  /// In en, this message translates to:
  /// **'What areas do you deliver to?'**
  String get helpDeliveryQ1;

  /// No description provided for @helpDeliveryA1.
  ///
  /// In en, this message translates to:
  /// **'We currently deliver across all governorates in Kuwait including Capital, Hawalli, Farwaniya, Ahmadi, Jahra, and Mubarak Al-Kabeer.'**
  String get helpDeliveryA1;

  /// No description provided for @helpDeliveryQ2.
  ///
  /// In en, this message translates to:
  /// **'How long does delivery take?'**
  String get helpDeliveryQ2;

  /// No description provided for @helpDeliveryA2.
  ///
  /// In en, this message translates to:
  /// **'Delivery times depend on the delivery type you select and your location. Standard delivery typically takes 2 to 4 business days. Same-day delivery is available for select areas.'**
  String get helpDeliveryA2;

  /// No description provided for @helpDeliveryQ3.
  ///
  /// In en, this message translates to:
  /// **'How much does delivery cost?'**
  String get helpDeliveryQ3;

  /// No description provided for @helpDeliveryA3.
  ///
  /// In en, this message translates to:
  /// **'Delivery fees depend on the type of delivery selected and the delivery area. The exact fee will be shown at checkout before you confirm your order.'**
  String get helpDeliveryA3;

  /// No description provided for @helpReturnsQ1.
  ///
  /// In en, this message translates to:
  /// **'What is the return policy?'**
  String get helpReturnsQ1;

  /// No description provided for @helpReturnsA1.
  ///
  /// In en, this message translates to:
  /// **'LIBSK has a 7-day return window from the date of delivery. Return eligibility may also depend on the individual boutique requirements. Please check the boutique storefront for any additional conditions before purchasing.'**
  String get helpReturnsA1;

  /// No description provided for @helpReturnsQ2.
  ///
  /// In en, this message translates to:
  /// **'How do I return an item?'**
  String get helpReturnsQ2;

  /// No description provided for @helpReturnsA2.
  ///
  /// In en, this message translates to:
  /// **'To initiate a return, go to your Orders, select the item, and tap Request Return. Our team will coordinate with the boutique on your behalf.'**
  String get helpReturnsA2;

  /// No description provided for @helpReturnsQ3.
  ///
  /// In en, this message translates to:
  /// **'How long do refunds take?'**
  String get helpReturnsQ3;

  /// No description provided for @helpReturnsA3.
  ///
  /// In en, this message translates to:
  /// **'Once a return is approved, refunds are processed within 5 to 7 business days depending on your payment method.'**
  String get helpReturnsA3;

  /// No description provided for @helpPaymentQ1.
  ///
  /// In en, this message translates to:
  /// **'What payment methods are accepted?'**
  String get helpPaymentQ1;

  /// No description provided for @helpPaymentA1.
  ///
  /// In en, this message translates to:
  /// **'We accept KNet, Visa, Mastercard, Apple Pay, debit cards, credit cards, and Deema.'**
  String get helpPaymentA1;

  /// No description provided for @helpPaymentQ2.
  ///
  /// In en, this message translates to:
  /// **'Is my payment information secure?'**
  String get helpPaymentQ2;

  /// No description provided for @helpPaymentA2.
  ///
  /// In en, this message translates to:
  /// **'Yes. We do not store any card details. All transactions are processed through secure, encrypted payment gateways.'**
  String get helpPaymentA2;

  /// No description provided for @helpPaymentQ3.
  ///
  /// In en, this message translates to:
  /// **'I was charged but my order was not placed.'**
  String get helpPaymentQ3;

  /// No description provided for @helpPaymentA3.
  ///
  /// In en, this message translates to:
  /// **'This can happen due to a connection issue. Please contact us immediately with your payment reference and we will resolve it within 24 hours.'**
  String get helpPaymentA3;

  /// No description provided for @helpAccountQ1.
  ///
  /// In en, this message translates to:
  /// **'How do I change my password?'**
  String get helpAccountQ1;

  /// No description provided for @helpAccountA1.
  ///
  /// In en, this message translates to:
  /// **'Go to Profile, tap Your Account, then tap Change Password. You will receive a reset link to your registered email.'**
  String get helpAccountA1;

  /// No description provided for @helpAccountQ2.
  ///
  /// In en, this message translates to:
  /// **'How do I update my delivery address?'**
  String get helpAccountQ2;

  /// No description provided for @helpAccountA2.
  ///
  /// In en, this message translates to:
  /// **'Go to Profile, then Saved Addresses. You can add, edit, or remove addresses at any time.'**
  String get helpAccountA2;

  /// No description provided for @helpAccountQ3.
  ///
  /// In en, this message translates to:
  /// **'How do I delete my account?'**
  String get helpAccountQ3;

  /// No description provided for @helpAccountA3.
  ///
  /// In en, this message translates to:
  /// **'You can delete your account from the Profile page under Your Account settings. Account deletion is permanent and cannot be undone.'**
  String get helpAccountA3;

  /// No description provided for @helpBoutiquesQ1.
  ///
  /// In en, this message translates to:
  /// **'How do I become a boutique owner on LIBSK?'**
  String get helpBoutiquesQ1;

  /// No description provided for @helpBoutiquesA1.
  ///
  /// In en, this message translates to:
  /// **'Send us an email at boutiques@libsk.com with details about your boutique. Our team will review your application and get back to you within 3 business days.'**
  String get helpBoutiquesA1;

  /// No description provided for @helpBoutiquesQ2.
  ///
  /// In en, this message translates to:
  /// **'Can I save a boutique to view later?'**
  String get helpBoutiquesQ2;

  /// No description provided for @helpBoutiquesA2.
  ///
  /// In en, this message translates to:
  /// **'Yes. Tap the save icon on any boutique storefront to add it to your Saved Boutiques in your profile.'**
  String get helpBoutiquesA2;

  /// No description provided for @helpBoutiquesQ3.
  ///
  /// In en, this message translates to:
  /// **'A boutique is not responding to my order.'**
  String get helpBoutiquesQ3;

  /// No description provided for @helpBoutiquesA3.
  ///
  /// In en, this message translates to:
  /// **'If a boutique has not updated your order status within 48 hours, contact our support team and we will follow up on your behalf.'**
  String get helpBoutiquesA3;

  /// No description provided for @homepageControl.
  ///
  /// In en, this message translates to:
  /// **'Homepage Control'**
  String get homepageControl;

  /// No description provided for @homepageControlDescription.
  ///
  /// In en, this message translates to:
  /// **'Manage featured boutiques and products on the home screen.'**
  String get homepageControlDescription;

  /// No description provided for @homepageBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Homepage Boutiques'**
  String get homepageBoutiques;

  /// No description provided for @homepageBoutiquesDescription.
  ///
  /// In en, this message translates to:
  /// **'Boutiques shown in the top carousel.'**
  String get homepageBoutiquesDescription;

  /// No description provided for @noOrderSet.
  ///
  /// In en, this message translates to:
  /// **'No order set'**
  String get noOrderSet;

  /// No description provided for @featuredProducts.
  ///
  /// In en, this message translates to:
  /// **'Featured Products'**
  String get featuredProducts;

  /// No description provided for @featuredProductsDescription.
  ///
  /// In en, this message translates to:
  /// **'Products shown in the featured section.'**
  String get featuredProductsDescription;

  /// No description provided for @thisYear.
  ///
  /// In en, this message translates to:
  /// **'This Year'**
  String get thisYear;

  /// No description provided for @revenueBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Revenue Breakdown'**
  String get revenueBreakdown;

  /// No description provided for @revenueBreakdownDescription.
  ///
  /// In en, this message translates to:
  /// **'Commissions and promotional slots.'**
  String get revenueBreakdownDescription;

  /// No description provided for @commissions.
  ///
  /// In en, this message translates to:
  /// **'Commissions'**
  String get commissions;

  /// No description provided for @commissionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'From completed orders'**
  String get commissionsSubtitle;

  /// No description provided for @promoSlots.
  ///
  /// In en, this message translates to:
  /// **'Promo Slots'**
  String get promoSlots;

  /// No description provided for @promoSlotsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Paid placement revenue'**
  String get promoSlotsSubtitle;

  /// No description provided for @promoSlotTypes.
  ///
  /// In en, this message translates to:
  /// **'Promo Slot Types'**
  String get promoSlotTypes;

  /// No description provided for @homepageBanner.
  ///
  /// In en, this message translates to:
  /// **'Homepage Banner'**
  String get homepageBanner;

  /// No description provided for @promoHomepageBannerPricing.
  ///
  /// In en, this message translates to:
  /// **'From 35 KWD/week'**
  String get promoHomepageBannerPricing;

  /// No description provided for @featuredBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Featured Boutiques'**
  String get featuredBoutiques;

  /// No description provided for @promoFeaturedBoutiquesPricing.
  ///
  /// In en, this message translates to:
  /// **'From 20 KWD/week'**
  String get promoFeaturedBoutiquesPricing;

  /// No description provided for @promoFeaturedProductsPricing.
  ///
  /// In en, this message translates to:
  /// **'From 15 KWD/week'**
  String get promoFeaturedProductsPricing;

  /// No description provided for @searchPlacement.
  ///
  /// In en, this message translates to:
  /// **'Search Placement'**
  String get searchPlacement;

  /// No description provided for @promoSearchPlacementPricing.
  ///
  /// In en, this message translates to:
  /// **'From 12 KWD/week'**
  String get promoSearchPlacementPricing;

  /// No description provided for @unknownOwner.
  ///
  /// In en, this message translates to:
  /// **'Unknown owner'**
  String get unknownOwner;

  /// No description provided for @failedToLoadBoutiqueOverview.
  ///
  /// In en, this message translates to:
  /// **'Failed to load boutique overview'**
  String get failedToLoadBoutiqueOverview;

  /// No description provided for @totalProducts.
  ///
  /// In en, this message translates to:
  /// **'Total products'**
  String get totalProducts;

  /// No description provided for @boutiqueOrders.
  ///
  /// In en, this message translates to:
  /// **'Boutique orders'**
  String get boutiqueOrders;

  /// No description provided for @sales.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get sales;

  /// No description provided for @totalBoutiqueSales.
  ///
  /// In en, this message translates to:
  /// **'Total boutique sales'**
  String get totalBoutiqueSales;

  /// No description provided for @ownerDetails.
  ///
  /// In en, this message translates to:
  /// **'Owner Details'**
  String get ownerDetails;

  /// No description provided for @ownerName.
  ///
  /// In en, this message translates to:
  /// **'Owner name'**
  String get ownerName;

  /// No description provided for @ownerEmail.
  ///
  /// In en, this message translates to:
  /// **'Owner email'**
  String get ownerEmail;

  /// No description provided for @ownerUid.
  ///
  /// In en, this message translates to:
  /// **'Owner UID'**
  String get ownerUid;

  /// No description provided for @openStorefront.
  ///
  /// In en, this message translates to:
  /// **'Open Storefront'**
  String get openStorefront;

  /// No description provided for @cropLogo.
  ///
  /// In en, this message translates to:
  /// **'Crop Logo'**
  String get cropLogo;

  /// No description provided for @failedToPickLogoImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick logo image'**
  String get failedToPickLogoImage;

  /// No description provided for @failedToPickBannerImage.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick banner image'**
  String get failedToPickBannerImage;

  /// No description provided for @boutiqueUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Boutique updated successfully'**
  String get boutiqueUpdatedSuccessfully;

  /// No description provided for @failedToUpdateBoutique.
  ///
  /// In en, this message translates to:
  /// **'Failed to update boutique'**
  String get failedToUpdateBoutique;

  /// No description provided for @editBoutiqueDescription.
  ///
  /// In en, this message translates to:
  /// **'Update your boutique name, description, and images.'**
  String get editBoutiqueDescription;

  /// No description provided for @enterBoutiqueName.
  ///
  /// In en, this message translates to:
  /// **'Enter boutique name'**
  String get enterBoutiqueName;

  /// No description provided for @boutiqueNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Boutique name is required'**
  String get boutiqueNameRequired;

  /// No description provided for @enterBoutiqueDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter boutique description'**
  String get enterBoutiqueDescription;

  /// No description provided for @tapToUploadLogo.
  ///
  /// In en, this message translates to:
  /// **'Tap to upload logo'**
  String get tapToUploadLogo;

  /// No description provided for @logoCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Logo could not load'**
  String get logoCouldNotLoad;

  /// No description provided for @tapToUploadBanner.
  ///
  /// In en, this message translates to:
  /// **'Tap to upload banner'**
  String get tapToUploadBanner;

  /// No description provided for @bannerCouldNotLoad.
  ///
  /// In en, this message translates to:
  /// **'Banner could not load'**
  String get bannerCouldNotLoad;

  /// No description provided for @failedToPickImages.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick images'**
  String get failedToPickImages;

  /// No description provided for @productMustHaveAtLeastOneImage.
  ///
  /// In en, this message translates to:
  /// **'Product must have at least one image'**
  String get productMustHaveAtLeastOneImage;

  /// No description provided for @productUpdatedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Product updated successfully'**
  String get productUpdatedSuccessfully;

  /// No description provided for @failedToUpdateProduct.
  ///
  /// In en, this message translates to:
  /// **'Failed to update product'**
  String get failedToUpdateProduct;

  /// No description provided for @tapToAddMoreImages.
  ///
  /// In en, this message translates to:
  /// **'Tap to add more images'**
  String get tapToAddMoreImages;

  /// No description provided for @mainImage.
  ///
  /// In en, this message translates to:
  /// **'Main'**
  String get mainImage;

  /// No description provided for @makeMain.
  ///
  /// In en, this message translates to:
  /// **'Make main'**
  String get makeMain;

  /// No description provided for @editProductDescription.
  ///
  /// In en, this message translates to:
  /// **'Update product details, images, and inventory.'**
  String get editProductDescription;

  /// No description provided for @failedToLoadAddresses.
  ///
  /// In en, this message translates to:
  /// **'Failed to load addresses'**
  String get failedToLoadAddresses;

  /// No description provided for @failedToLoadOrders.
  ///
  /// In en, this message translates to:
  /// **'Failed to load orders'**
  String get failedToLoadOrders;

  /// No description provided for @homepageOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Order: {order}'**
  String homepageOrderSubtitle(String order);

  /// No description provided for @featuredOrderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{boutiqueName} · Order: {order}'**
  String featuredOrderSubtitle(String boutiqueName, String order);

  /// No description provided for @percentOfTotalRevenue.
  ///
  /// In en, this message translates to:
  /// **'{percent}% of total revenue'**
  String percentOfTotalRevenue(String percent);

  /// No description provided for @itemsAcrossAllBoutiques.
  ///
  /// In en, this message translates to:
  /// **'{count} items across all boutiques'**
  String itemsAcrossAllBoutiques(int count);

  /// No description provided for @noProductsInCategory.
  ///
  /// In en, this message translates to:
  /// **'No products in {category}'**
  String noProductsInCategory(String category);

  /// No description provided for @filterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get filterAll;

  /// No description provided for @disputeStatusOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get disputeStatusOpen;

  /// No description provided for @disputeStatusUnderReview.
  ///
  /// In en, this message translates to:
  /// **'Under Review'**
  String get disputeStatusUnderReview;

  /// No description provided for @disputeStatusResolved.
  ///
  /// In en, this message translates to:
  /// **'Resolved'**
  String get disputeStatusResolved;

  /// No description provided for @disputeStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get disputeStatusRejected;

  /// No description provided for @resolveDispute.
  ///
  /// In en, this message translates to:
  /// **'Resolve Dispute'**
  String get resolveDispute;

  /// No description provided for @resolveDisputeQuestion.
  ///
  /// In en, this message translates to:
  /// **'How would you like to resolve this dispute?'**
  String get resolveDisputeQuestion;

  /// No description provided for @resolveNoRefund.
  ///
  /// In en, this message translates to:
  /// **'Resolve — No Refund'**
  String get resolveNoRefund;

  /// No description provided for @resolveWithRefund.
  ///
  /// In en, this message translates to:
  /// **'Resolve — Refund Issued'**
  String get resolveWithRefund;

  /// No description provided for @noPaymentIntentFound.
  ///
  /// In en, this message translates to:
  /// **'No payment intent found for this order'**
  String get noPaymentIntentFound;

  /// No description provided for @disputeResolvedWithRefund.
  ///
  /// In en, this message translates to:
  /// **'Dispute resolved and order marked as Refunded'**
  String get disputeResolvedWithRefund;

  /// No description provided for @failedToProcessRefund.
  ///
  /// In en, this message translates to:
  /// **'Failed to process refund'**
  String get failedToProcessRefund;

  /// No description provided for @markAsRefunded.
  ///
  /// In en, this message translates to:
  /// **'Mark as Refunded'**
  String get markAsRefunded;

  /// No description provided for @refundManualNote.
  ///
  /// In en, this message translates to:
  /// **'Refunds are issued manually from the Payzah merchant dashboard. This action only marks the order as Refunded and records your admin account — it does not move any money.'**
  String get refundManualNote;

  /// No description provided for @orderMarkedRefunded.
  ///
  /// In en, this message translates to:
  /// **'Order marked as Refunded'**
  String get orderMarkedRefunded;

  /// No description provided for @disputeResolved.
  ///
  /// In en, this message translates to:
  /// **'Dispute resolved successfully'**
  String get disputeResolved;

  /// No description provided for @failedToUpdateDispute.
  ///
  /// In en, this message translates to:
  /// **'Failed to update dispute'**
  String get failedToUpdateDispute;

  /// No description provided for @failedToLoadDisputes.
  ///
  /// In en, this message translates to:
  /// **'Failed to load disputes'**
  String get failedToLoadDisputes;

  /// No description provided for @noDisputesFound.
  ///
  /// In en, this message translates to:
  /// **'No disputes found'**
  String get noDisputesFound;

  /// No description provided for @unknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknown;

  /// No description provided for @refundIssued.
  ///
  /// In en, this message translates to:
  /// **'Refund issued'**
  String get refundIssued;

  /// No description provided for @unknownOrder.
  ///
  /// In en, this message translates to:
  /// **'Unknown order'**
  String get unknownOrder;

  /// No description provided for @unknownCustomer.
  ///
  /// In en, this message translates to:
  /// **'Unknown customer'**
  String get unknownCustomer;

  /// No description provided for @noDate.
  ///
  /// In en, this message translates to:
  /// **'No date'**
  String get noDate;

  /// No description provided for @searchOrders.
  ///
  /// In en, this message translates to:
  /// **'Search orders...'**
  String get searchOrders;

  /// No description provided for @noOrdersFound.
  ///
  /// In en, this message translates to:
  /// **'No orders found'**
  String get noOrdersFound;

  /// No description provided for @noMatchingOrdersFound.
  ///
  /// In en, this message translates to:
  /// **'No matching orders found'**
  String get noMatchingOrdersFound;

  /// No description provided for @failedToLoadBoutiqueOrders.
  ///
  /// In en, this message translates to:
  /// **'Failed to load boutique orders'**
  String get failedToLoadBoutiqueOrders;

  /// No description provided for @orderStatusUpdated.
  ///
  /// In en, this message translates to:
  /// **'Order status updated successfully'**
  String get orderStatusUpdated;

  /// No description provided for @failedToUpdateOrderStatus.
  ///
  /// In en, this message translates to:
  /// **'Failed to update order status'**
  String get failedToUpdateOrderStatus;

  /// No description provided for @noOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No orders yet'**
  String get noOrdersYet;

  /// No description provided for @cancelOrder.
  ///
  /// In en, this message translates to:
  /// **'Cancel Order'**
  String get cancelOrder;

  /// No description provided for @cancelOrderConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to cancel this order?'**
  String get cancelOrderConfirmation;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @noAddressAvailable.
  ///
  /// In en, this message translates to:
  /// **'No address available'**
  String get noAddressAvailable;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'Items'**
  String get items;

  /// No description provided for @confirmOrder.
  ///
  /// In en, this message translates to:
  /// **'Confirm Order'**
  String get confirmOrder;

  /// No description provided for @disputeMarkedAs.
  ///
  /// In en, this message translates to:
  /// **'Dispute marked as {status}'**
  String disputeMarkedAs(String status);

  /// No description provided for @disputesCount.
  ///
  /// In en, this message translates to:
  /// **'{count} disputes'**
  String disputesCount(int count);

  /// No description provided for @orderTotalKwd.
  ///
  /// In en, this message translates to:
  /// **'Order total: {amount} KWD'**
  String orderTotalKwd(String amount);

  /// No description provided for @globalOrdersCount.
  ///
  /// In en, this message translates to:
  /// **'{count} global orders'**
  String globalOrdersCount(int count);

  /// No description provided for @itemsLabel.
  ///
  /// In en, this message translates to:
  /// **'Items: {count}'**
  String itemsLabel(String count);

  /// No description provided for @totalKwd.
  ///
  /// In en, this message translates to:
  /// **'Total: {amount} KWD'**
  String totalKwd(String amount);

  /// No description provided for @noSalesData.
  ///
  /// In en, this message translates to:
  /// **'No sales data'**
  String get noSalesData;

  /// No description provided for @failedToLoadBoutiqueDetails.
  ///
  /// In en, this message translates to:
  /// **'Failed to load boutique details'**
  String get failedToLoadBoutiqueDetails;

  /// No description provided for @boutiqueSalesOverview.
  ///
  /// In en, this message translates to:
  /// **'Boutique sales overview'**
  String get boutiqueSalesOverview;

  /// No description provided for @totalSalesTitle.
  ///
  /// In en, this message translates to:
  /// **'Total Sales'**
  String get totalSalesTitle;

  /// No description provided for @allBoutiqueSales.
  ///
  /// In en, this message translates to:
  /// **'All boutique sales'**
  String get allBoutiqueSales;

  /// No description provided for @totalBoutiqueOrders.
  ///
  /// In en, this message translates to:
  /// **'Total boutique orders'**
  String get totalBoutiqueOrders;

  /// No description provided for @itemsSold.
  ///
  /// In en, this message translates to:
  /// **'Items Sold'**
  String get itemsSold;

  /// No description provided for @totalSoldItems.
  ///
  /// In en, this message translates to:
  /// **'Total sold items'**
  String get totalSoldItems;

  /// No description provided for @bestSeller.
  ///
  /// In en, this message translates to:
  /// **'Best Seller'**
  String get bestSeller;

  /// No description provided for @quantitySold.
  ///
  /// In en, this message translates to:
  /// **'{count} sold'**
  String quantitySold(String count);

  /// No description provided for @monthlySales.
  ///
  /// In en, this message translates to:
  /// **'Monthly Sales'**
  String get monthlySales;

  /// No description provided for @recentSales.
  ///
  /// In en, this message translates to:
  /// **'Recent Sales'**
  String get recentSales;

  /// No description provided for @noSalesFound.
  ///
  /// In en, this message translates to:
  /// **'No sales found.'**
  String get noSalesFound;

  /// No description provided for @monthJan.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get monthJan;

  /// No description provided for @monthFeb.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get monthFeb;

  /// No description provided for @monthMar.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get monthMar;

  /// No description provided for @monthApr.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get monthApr;

  /// No description provided for @monthMay.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get monthMay;

  /// No description provided for @monthJun.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get monthJun;

  /// No description provided for @monthJul.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get monthJul;

  /// No description provided for @monthAug.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get monthAug;

  /// No description provided for @monthSep.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get monthSep;

  /// No description provided for @monthOct.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get monthOct;

  /// No description provided for @monthNov.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get monthNov;

  /// No description provided for @monthDec.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get monthDec;

  /// No description provided for @failedToLoadBoutiqueSales.
  ///
  /// In en, this message translates to:
  /// **'Failed to load boutique sales'**
  String get failedToLoadBoutiqueSales;

  /// No description provided for @noBoutiqueSalesFound.
  ///
  /// In en, this message translates to:
  /// **'No boutique sales found.'**
  String get noBoutiqueSalesFound;

  /// No description provided for @boutiqueSalesTitle.
  ///
  /// In en, this message translates to:
  /// **'Boutique Sales'**
  String get boutiqueSalesTitle;

  /// No description provided for @boutiquesWithSales.
  ///
  /// In en, this message translates to:
  /// **'{count} boutiques with sales'**
  String boutiquesWithSales(String count);

  /// No description provided for @orderCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} orders'**
  String orderCountLabel(String count);

  /// No description provided for @paymentSetupFailed.
  ///
  /// In en, this message translates to:
  /// **'Payment setup failed'**
  String get paymentSetupFailed;

  /// No description provided for @productNoLongerAvailable.
  ///
  /// In en, this message translates to:
  /// **'{title} is no longer available'**
  String productNoLongerAvailable(String title);

  /// No description provided for @productNotEnoughStock.
  ///
  /// In en, this message translates to:
  /// **'{title} does not have enough stock'**
  String productNotEnoughStock(String title);

  /// No description provided for @secureCheckout.
  ///
  /// In en, this message translates to:
  /// **'Secure checkout'**
  String get secureCheckout;

  /// No description provided for @knet.
  ///
  /// In en, this message translates to:
  /// **'KNET'**
  String get knet;

  /// No description provided for @applePay.
  ///
  /// In en, this message translates to:
  /// **'Apple Pay'**
  String get applePay;

  /// No description provided for @markAsOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'Mark as Out of Stock'**
  String get markAsOutOfStock;

  /// No description provided for @markAsOutOfStockSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide Add to Cart and show an out-of-stock label, regardless of stock count.'**
  String get markAsOutOfStockSubtitle;

  /// No description provided for @salePrice.
  ///
  /// In en, this message translates to:
  /// **'Sale Price'**
  String get salePrice;

  /// No description provided for @salePriceHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 20.000'**
  String get salePriceHint;

  /// No description provided for @saleBadge.
  ///
  /// In en, this message translates to:
  /// **'SALE'**
  String get saleBadge;

  /// No description provided for @salePriceMustBeLessThanPrice.
  ///
  /// In en, this message translates to:
  /// **'Sale price must be less than the regular price'**
  String get salePriceMustBeLessThanPrice;

  /// No description provided for @pendingOrders.
  ///
  /// In en, this message translates to:
  /// **'Pending Orders'**
  String get pendingOrders;

  /// No description provided for @allCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get allCaughtUp;

  /// No description provided for @ordersNeedAction.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 order needs action} other{{count} orders need action}}'**
  String ordersNeedAction(int count);

  /// No description provided for @totalEarnings.
  ///
  /// In en, this message translates to:
  /// **'Total earnings'**
  String get totalEarnings;

  /// No description provided for @allGood.
  ///
  /// In en, this message translates to:
  /// **'All good'**
  String get allGood;

  /// No description provided for @stockAlerts.
  ///
  /// In en, this message translates to:
  /// **'Stock Alerts'**
  String get stockAlerts;

  /// No description provided for @allStockLevelsGood.
  ///
  /// In en, this message translates to:
  /// **'All stock levels good'**
  String get allStockLevelsGood;

  /// No description provided for @manageBoutiqueAndProducts.
  ///
  /// In en, this message translates to:
  /// **'Manage boutique & products'**
  String get manageBoutiqueAndProducts;

  /// No description provided for @promotions.
  ///
  /// In en, this message translates to:
  /// **'Promotions'**
  String get promotions;

  /// No description provided for @discountCodes.
  ///
  /// In en, this message translates to:
  /// **'Discount Codes'**
  String get discountCodes;

  /// No description provided for @discountCodesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create codes for your boutique customers.'**
  String get discountCodesSubtitle;

  /// No description provided for @showInFeed.
  ///
  /// In en, this message translates to:
  /// **'Show in feed'**
  String get showInFeed;

  /// No description provided for @showInFeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Followers see this product in their home feed when you post it.'**
  String get showInFeedSubtitle;

  /// No description provided for @statusAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get statusAll;

  /// No description provided for @noStatusOrders.
  ///
  /// In en, this message translates to:
  /// **'No {status} orders'**
  String noStatusOrders(String status);

  /// No description provided for @addressBlock.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get addressBlock;

  /// No description provided for @addressStreet.
  ///
  /// In en, this message translates to:
  /// **'Street'**
  String get addressStreet;

  /// No description provided for @addressHouse.
  ///
  /// In en, this message translates to:
  /// **'House'**
  String get addressHouse;

  /// No description provided for @addYourFirstProduct.
  ///
  /// In en, this message translates to:
  /// **'Add your first product'**
  String get addYourFirstProduct;

  /// No description provided for @followersCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 follower} other{{count} followers}}'**
  String followersCount(int count);

  /// No description provided for @appliedToBoutiqueItemsOnly.
  ///
  /// In en, this message translates to:
  /// **'Applied to {boutique} items only'**
  String appliedToBoutiqueItemsOnly(String boutique);

  /// No description provided for @someRevenueDataUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Some revenue data couldn\'t be loaded.'**
  String get someRevenueDataUnavailable;

  /// No description provided for @discountThisItem.
  ///
  /// In en, this message translates to:
  /// **'Discount this item'**
  String get discountThisItem;

  /// No description provided for @removeDiscount.
  ///
  /// In en, this message translates to:
  /// **'Remove discount'**
  String get removeDiscount;

  /// No description provided for @saleLessThanOriginalHint.
  ///
  /// In en, this message translates to:
  /// **'Must be less than original price'**
  String get saleLessThanOriginalHint;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @letterSizes.
  ///
  /// In en, this message translates to:
  /// **'Letter Sizes'**
  String get letterSizes;

  /// No description provided for @numericSizes.
  ///
  /// In en, this message translates to:
  /// **'Numeric Sizes'**
  String get numericSizes;

  /// No description provided for @sizeColumnHeader.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get sizeColumnHeader;

  /// No description provided for @showStockCount.
  ///
  /// In en, this message translates to:
  /// **'Show stock count to customers'**
  String get showStockCount;

  /// No description provided for @showStockCountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Customers see how many units are left on product pages.'**
  String get showStockCountSubtitle;

  /// No description provided for @categorySwimwear.
  ///
  /// In en, this message translates to:
  /// **'Swimwear'**
  String get categorySwimwear;

  /// No description provided for @categoryAccessories.
  ///
  /// In en, this message translates to:
  /// **'Accessories'**
  String get categoryAccessories;

  /// No description provided for @addPromoCode.
  ///
  /// In en, this message translates to:
  /// **'Add promo code'**
  String get addPromoCode;

  /// No description provided for @promoCode.
  ///
  /// In en, this message translates to:
  /// **'Promo code'**
  String get promoCode;

  /// No description provided for @enterPromoCode.
  ///
  /// In en, this message translates to:
  /// **'Enter code'**
  String get enterPromoCode;

  /// No description provided for @apply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// No description provided for @applied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get applied;

  /// No description provided for @orderSummary.
  ///
  /// In en, this message translates to:
  /// **'Order summary'**
  String get orderSummary;

  /// No description provided for @itemCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, one{1 item} other{{count} items}}'**
  String itemCount(int count);

  /// No description provided for @payAmount.
  ///
  /// In en, this message translates to:
  /// **'Pay {amount}'**
  String payAmount(String amount);

  /// No description provided for @discountLabel.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discountLabel;

  /// No description provided for @paymentPreparingTitle.
  ///
  /// In en, this message translates to:
  /// **'Preparing your payment'**
  String get paymentPreparingTitle;

  /// No description provided for @paymentPreparingBody.
  ///
  /// In en, this message translates to:
  /// **'Just a moment while we set things up.'**
  String get paymentPreparingBody;

  /// No description provided for @paymentRedirectingTitle.
  ///
  /// In en, this message translates to:
  /// **'Taking you to secure payment'**
  String get paymentRedirectingTitle;

  /// No description provided for @paymentRedirectingBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll be redirected to complete your payment.'**
  String get paymentRedirectingBody;

  /// No description provided for @paymentVerifyingTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirming your payment'**
  String get paymentVerifyingTitle;

  /// No description provided for @paymentVerifyingBody.
  ///
  /// In en, this message translates to:
  /// **'This may take a few moments. Please keep the app open.'**
  String get paymentVerifyingBody;

  /// No description provided for @paymentConfirmedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment confirmed'**
  String get paymentConfirmedTitle;

  /// No description provided for @paymentConfirmedBody.
  ///
  /// In en, this message translates to:
  /// **'Thank you — your order has been placed.'**
  String get paymentConfirmedBody;

  /// No description provided for @paymentFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment unsuccessful'**
  String get paymentFailedTitle;

  /// No description provided for @paymentFailedBody.
  ///
  /// In en, this message translates to:
  /// **'Your payment could not be completed and you have not been charged. Please try again.'**
  String get paymentFailedBody;

  /// No description provided for @paymentUnderReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment under review'**
  String get paymentUnderReviewTitle;

  /// No description provided for @paymentUnderReviewBody.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t confirm the outcome of your payment yet. Please don\'t pay again — our team is verifying it and your order will be updated shortly.'**
  String get paymentUnderReviewBody;

  /// No description provided for @specialRequest.
  ///
  /// In en, this message translates to:
  /// **'Special Request'**
  String get specialRequest;

  /// No description provided for @specialRequestHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. make it a little longer or shorter (optional)'**
  String get specialRequestHint;

  /// No description provided for @addedToCartTitle.
  ///
  /// In en, this message translates to:
  /// **'Added to cart'**
  String get addedToCartTitle;

  /// No description provided for @goToCart.
  ///
  /// In en, this message translates to:
  /// **'Go to Cart'**
  String get goToCart;

  /// No description provided for @continueShopping.
  ///
  /// In en, this message translates to:
  /// **'Continue Shopping'**
  String get continueShopping;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// No description provided for @paymentNotCompletedTitle.
  ///
  /// In en, this message translates to:
  /// **'Payment not completed'**
  String get paymentNotCompletedTitle;

  /// No description provided for @paymentNotCompletedBody.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t been charged. You can try again to finish paying, or return to your cart.'**
  String get paymentNotCompletedBody;

  /// No description provided for @returnToCart.
  ///
  /// In en, this message translates to:
  /// **'Return to cart'**
  String get returnToCart;

  /// No description provided for @continueAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueAction;

  /// No description provided for @promoPaymentBookedBody.
  ///
  /// In en, this message translates to:
  /// **'Your promotion is booked and goes live next week.'**
  String get promoPaymentBookedBody;

  /// No description provided for @promoPaymentNotCompletedBody.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t been charged. You can try again to finish paying, or go back to your dashboard.'**
  String get promoPaymentNotCompletedBody;

  /// No description provided for @promoReturnToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Back to dashboard'**
  String get promoReturnToDashboard;

  /// No description provided for @bookPromotion.
  ///
  /// In en, this message translates to:
  /// **'Book a Promotion'**
  String get bookPromotion;

  /// No description provided for @bookPromotionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Promote your boutique on the home page'**
  String get bookPromotionSubtitle;

  /// No description provided for @promoBookingInterimNote.
  ///
  /// In en, this message translates to:
  /// **'Books a Featured Boutique slot for the upcoming week (Sun–Sat). Choose a payment method to continue.'**
  String get promoBookingInterimNote;

  /// No description provided for @bookAndPay.
  ///
  /// In en, this message translates to:
  /// **'Book & Pay'**
  String get bookAndPay;

  /// No description provided for @promoPerWeek.
  ///
  /// In en, this message translates to:
  /// **'{price} KWD / week'**
  String promoPerWeek(String price);

  /// No description provided for @promoStartDay.
  ///
  /// In en, this message translates to:
  /// **'Start day'**
  String get promoStartDay;

  /// No description provided for @promoDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get promoDays;

  /// No description provided for @promoSelectedTotal.
  ///
  /// In en, this message translates to:
  /// **'Total: {price} KWD'**
  String promoSelectedTotal(String price);

  /// No description provided for @promoTabBook.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get promoTabBook;

  /// No description provided for @promoTabMyBookings.
  ///
  /// In en, this message translates to:
  /// **'My bookings'**
  String get promoTabMyBookings;

  /// No description provided for @promoUpcomingWeek.
  ///
  /// In en, this message translates to:
  /// **'Upcoming week'**
  String get promoUpcomingWeek;

  /// No description provided for @promoRateLine.
  ///
  /// In en, this message translates to:
  /// **'{daily}/day · {weekly} full week'**
  String promoRateLine(String daily, String weekly);

  /// No description provided for @promoFeedRateLine.
  ///
  /// In en, this message translates to:
  /// **'{one} for 1 post · {two} for 2'**
  String promoFeedRateLine(String one, String two);

  /// No description provided for @promoNeedsApproval.
  ///
  /// In en, this message translates to:
  /// **'Needs approval'**
  String get promoNeedsApproval;

  /// No description provided for @promoByCategoryNote.
  ///
  /// In en, this message translates to:
  /// **'Availability shown per category'**
  String get promoByCategoryNote;

  /// No description provided for @promoFeedWeekNote.
  ///
  /// In en, this message translates to:
  /// **'Whole week · 1–2 posts · no dates'**
  String get promoFeedWeekNote;

  /// No description provided for @promoSoldOutWeek.
  ///
  /// In en, this message translates to:
  /// **'Fully booked next week'**
  String get promoSoldOutWeek;

  /// No description provided for @promoPickYourDays.
  ///
  /// In en, this message translates to:
  /// **'Pick your days'**
  String get promoPickYourDays;

  /// No description provided for @promoPickCategoryFirst.
  ///
  /// In en, this message translates to:
  /// **'Choose a category and products to see day availability.'**
  String get promoPickCategoryFirst;

  /// No description provided for @promoLegendPicked.
  ///
  /// In en, this message translates to:
  /// **'Picked'**
  String get promoLegendPicked;

  /// No description provided for @promoLegendOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get promoLegendOpen;

  /// No description provided for @promoLegendFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get promoLegendFull;

  /// No description provided for @promoTotalLabel.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get promoTotalLabel;

  /// No description provided for @promoPriceKwd.
  ///
  /// In en, this message translates to:
  /// **'{price} KWD'**
  String promoPriceKwd(String price);

  /// No description provided for @promoFullWeekNudge.
  ///
  /// In en, this message translates to:
  /// **'Book the full week for {price} KWD — {saving} KWD less than these days.'**
  String promoFullWeekNudge(String price, String saving);

  /// No description provided for @promoExtendFullWeek.
  ///
  /// In en, this message translates to:
  /// **'Extend to full week'**
  String get promoExtendFullWeek;

  /// No description provided for @promoProductToFeature.
  ///
  /// In en, this message translates to:
  /// **'Product to feature'**
  String get promoProductToFeature;

  /// No description provided for @promoChooseProduct.
  ///
  /// In en, this message translates to:
  /// **'Choose a product'**
  String get promoChooseProduct;

  /// No description provided for @promoChoosePosts.
  ///
  /// In en, this message translates to:
  /// **'Choose 1–2 posts'**
  String get promoChoosePosts;

  /// No description provided for @promoChooseCategory.
  ///
  /// In en, this message translates to:
  /// **'Choose a category'**
  String get promoChooseCategory;

  /// No description provided for @promoCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get promoCategory;

  /// No description provided for @promoPinProducts.
  ///
  /// In en, this message translates to:
  /// **'Products to pin (1–2)'**
  String get promoPinProducts;

  /// No description provided for @promoPostsToSponsor.
  ///
  /// In en, this message translates to:
  /// **'Posts to sponsor'**
  String get promoPostsToSponsor;

  /// No description provided for @promoBannerImage.
  ///
  /// In en, this message translates to:
  /// **'Banner image'**
  String get promoBannerImage;

  /// No description provided for @promoUploadBanner.
  ///
  /// In en, this message translates to:
  /// **'Upload banner image'**
  String get promoUploadBanner;

  /// No description provided for @promoBannerReviewNote.
  ///
  /// In en, this message translates to:
  /// **'Banner creatives are reviewed by our team before they go live.'**
  String get promoBannerReviewNote;

  /// No description provided for @promoChange.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get promoChange;

  /// No description provided for @promoChangeSelection.
  ///
  /// In en, this message translates to:
  /// **'Change selection'**
  String get promoChangeSelection;

  /// No description provided for @promoSearchProducts.
  ///
  /// In en, this message translates to:
  /// **'Search your products'**
  String get promoSearchProducts;

  /// No description provided for @promoNoProducts.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t added any products yet.'**
  String get promoNoProducts;

  /// No description provided for @promoSelectProduct.
  ///
  /// In en, this message translates to:
  /// **'Select product'**
  String get promoSelectProduct;

  /// No description provided for @promoSelectCount.
  ///
  /// In en, this message translates to:
  /// **'Select {count}'**
  String promoSelectCount(int count);

  /// No description provided for @promoBookAndPayAmount.
  ///
  /// In en, this message translates to:
  /// **'Book & pay · {price} KWD'**
  String promoBookAndPayAmount(String price);

  /// No description provided for @promoUseCredit.
  ///
  /// In en, this message translates to:
  /// **'Use promo credit · {amount} KWD available'**
  String promoUseCredit(String amount);

  /// No description provided for @promoCreditApplied.
  ///
  /// In en, this message translates to:
  /// **'Promo credit'**
  String get promoCreditApplied;

  /// No description provided for @promoRemainingToPay.
  ///
  /// In en, this message translates to:
  /// **'To pay'**
  String get promoRemainingToPay;

  /// No description provided for @promoConfirmBooking.
  ///
  /// In en, this message translates to:
  /// **'Confirm booking'**
  String get promoConfirmBooking;

  /// No description provided for @promoCreditBookedTitle.
  ///
  /// In en, this message translates to:
  /// **'Booking confirmed'**
  String get promoCreditBookedTitle;

  /// No description provided for @promoCreditBookedBody.
  ///
  /// In en, this message translates to:
  /// **'{amount} KWD of promo credit was used — nothing to pay. Your promotion is booked and goes live next week.'**
  String promoCreditBookedBody(String amount);

  /// No description provided for @promoCreditAdmin.
  ///
  /// In en, this message translates to:
  /// **'Promo Credits'**
  String get promoCreditAdmin;

  /// No description provided for @promoCreditAdminSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Founding partner credit and manual adjustments.'**
  String get promoCreditAdminSubtitle;

  /// No description provided for @promoCreditLaunchRecharge.
  ///
  /// In en, this message translates to:
  /// **'Launch recharge'**
  String get promoCreditLaunchRecharge;

  /// No description provided for @promoCreditLaunchRechargeDesc.
  ///
  /// In en, this message translates to:
  /// **'Grants Week-1 founding credit to every boutique still pending, and schedules their Week-2 grant 7 days later. Safe to re-run — already-recharged boutiques are skipped.'**
  String get promoCreditLaunchRechargeDesc;

  /// No description provided for @promoCreditPendingCount.
  ///
  /// In en, this message translates to:
  /// **'{count} pending'**
  String promoCreditPendingCount(String count);

  /// No description provided for @promoCreditRunRecharge.
  ///
  /// In en, this message translates to:
  /// **'Run recharge'**
  String get promoCreditRunRecharge;

  /// No description provided for @promoCreditRechargeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Grant Week-1 promo credit to {count} boutique(s) now? This also schedules their Week-2 grant.'**
  String promoCreditRechargeConfirm(String count);

  /// No description provided for @promoCreditRechargeResult.
  ///
  /// In en, this message translates to:
  /// **'Recharged {recharged}, skipped {skipped}.'**
  String promoCreditRechargeResult(String recharged, String skipped);

  /// No description provided for @promoCreditNoPending.
  ///
  /// In en, this message translates to:
  /// **'No boutiques are pending founding credit.'**
  String get promoCreditNoPending;

  /// No description provided for @promoCreditSearchBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Search boutiques'**
  String get promoCreditSearchBoutiques;

  /// No description provided for @promoCreditFoundingBadge.
  ///
  /// In en, this message translates to:
  /// **'Founding'**
  String get promoCreditFoundingBadge;

  /// No description provided for @promoCreditPendingBadge.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get promoCreditPendingBadge;

  /// No description provided for @promoCreditAdjustTitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust promo credit'**
  String get promoCreditAdjustTitle;

  /// No description provided for @promoCreditAmountHint.
  ///
  /// In en, this message translates to:
  /// **'Amount in KWD (negative to remove)'**
  String get promoCreditAmountHint;

  /// No description provided for @promoCreditReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason (e.g. goodwill top-up)'**
  String get promoCreditReasonHint;

  /// No description provided for @promoCreditExpiryHint.
  ///
  /// In en, this message translates to:
  /// **'Expires in days (0 = never)'**
  String get promoCreditExpiryHint;

  /// No description provided for @promoCreditApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get promoCreditApply;

  /// No description provided for @promoCreditAdjustResult.
  ///
  /// In en, this message translates to:
  /// **'Applied {applied} KWD. New balance {balance} KWD.'**
  String promoCreditAdjustResult(String applied, String balance);

  /// No description provided for @promoCreditAmountRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a non-zero amount.'**
  String get promoCreditAmountRequired;

  /// No description provided for @foundingPartnerLabel.
  ///
  /// In en, this message translates to:
  /// **'Founding partner'**
  String get foundingPartnerLabel;

  /// No description provided for @foundingPartnerHint.
  ///
  /// In en, this message translates to:
  /// **'Grants free promo credit at launch (Week 1, then Week 2). Credit is issued by the launch recharge, not now.'**
  String get foundingPartnerHint;

  /// No description provided for @promoNoBookings.
  ///
  /// In en, this message translates to:
  /// **'You haven\'t booked any promotions yet.'**
  String get promoNoBookings;

  /// No description provided for @promoGroupCurrent.
  ///
  /// In en, this message translates to:
  /// **'Active & upcoming'**
  String get promoGroupCurrent;

  /// No description provided for @promoGroupPast.
  ///
  /// In en, this message translates to:
  /// **'Past'**
  String get promoGroupPast;

  /// No description provided for @promoStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get promoStatusActive;

  /// No description provided for @promoStatusPendingReview.
  ///
  /// In en, this message translates to:
  /// **'Pending review'**
  String get promoStatusPendingReview;

  /// No description provided for @promoStatusAwaitingPayment.
  ///
  /// In en, this message translates to:
  /// **'Awaiting payment'**
  String get promoStatusAwaitingPayment;

  /// No description provided for @promoStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get promoStatusRejected;

  /// No description provided for @promoStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get promoStatusCancelled;

  /// No description provided for @promoStatusExpired.
  ///
  /// In en, this message translates to:
  /// **'Expired'**
  String get promoStatusExpired;

  /// No description provided for @promoPlacementHomeBanner.
  ///
  /// In en, this message translates to:
  /// **'Home banner'**
  String get promoPlacementHomeBanner;

  /// No description provided for @promoPlacementFeaturedProduct.
  ///
  /// In en, this message translates to:
  /// **'Featured product'**
  String get promoPlacementFeaturedProduct;

  /// No description provided for @promoPlacementFeaturedBoutique.
  ///
  /// In en, this message translates to:
  /// **'Featured boutique'**
  String get promoPlacementFeaturedBoutique;

  /// No description provided for @promoPlacementTopOfCategory.
  ///
  /// In en, this message translates to:
  /// **'Top of category'**
  String get promoPlacementTopOfCategory;

  /// No description provided for @promoPlacementFeedSponsored.
  ///
  /// In en, this message translates to:
  /// **'Feed sponsored'**
  String get promoPlacementFeedSponsored;

  /// No description provided for @promoBannerApprovals.
  ///
  /// In en, this message translates to:
  /// **'Banner approvals'**
  String get promoBannerApprovals;

  /// No description provided for @promoBannerApprovalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review paid home-banner creatives.'**
  String get promoBannerApprovalsSubtitle;

  /// No description provided for @promoNoPendingBanners.
  ///
  /// In en, this message translates to:
  /// **'No banners awaiting review.'**
  String get promoNoPendingBanners;

  /// No description provided for @promoApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get promoApprove;

  /// No description provided for @promoReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get promoReject;

  /// No description provided for @promoRejectReasonHint.
  ///
  /// In en, this message translates to:
  /// **'Reason (optional)'**
  String get promoRejectReasonHint;

  /// No description provided for @promoBannerApproved.
  ///
  /// In en, this message translates to:
  /// **'Banner approved.'**
  String get promoBannerApproved;

  /// No description provided for @promoBannerRejected.
  ///
  /// In en, this message translates to:
  /// **'Banner rejected.'**
  String get promoBannerRejected;

  /// No description provided for @promoRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get promoRemove;

  /// No description provided for @promoImageTooLarge.
  ///
  /// In en, this message translates to:
  /// **'Image must be under 5 MB. Please choose a smaller file.'**
  String get promoImageTooLarge;

  /// No description provided for @promoImageWrongType.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t an image. Choose a JPG, PNG, or WebP.'**
  String get promoImageWrongType;
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {


  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar': return AppLocalizationsAr();
    case 'en': return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.'
  );
}
