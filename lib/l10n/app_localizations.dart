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

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @accountInformation.
  ///
  /// In en, this message translates to:
  /// **'Account Information'**
  String get accountInformation;

  /// No description provided for @username.
  ///
  /// In en, this message translates to:
  /// **'USERNAME'**
  String get username;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'EMAIL'**
  String get email;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'PHONE NUMBER'**
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
  /// **'SAVE CHANGES'**
  String get saveChanges;

  /// No description provided for @addDeliveryAddress.
  ///
  /// In en, this message translates to:
  /// **'Add Delivery Address'**
  String get addDeliveryAddress;

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

  /// No description provided for @addNow.
  ///
  /// In en, this message translates to:
  /// **'ADD NOW'**
  String get addNow;

  /// No description provided for @boutiques.
  ///
  /// In en, this message translates to:
  /// **'Boutiques'**
  String get boutiques;

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

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'ADD PRODUCT'**
  String get addProduct;

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

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

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

  /// No description provided for @stock.
  ///
  /// In en, this message translates to:
  /// **'Stock'**
  String get stock;

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

  /// No description provided for @exploreRamadanCollection.
  ///
  /// In en, this message translates to:
  /// **'Explore Ramadan Collection'**
  String get exploreRamadanCollection;

  /// No description provided for @featuredPieces.
  ///
  /// In en, this message translates to:
  /// **'Featured Pieces'**
  String get featuredPieces;

  /// No description provided for @failedToLoadFeaturedProducts.
  ///
  /// In en, this message translates to:
  /// **'Failed to load featured products'**
  String get failedToLoadFeaturedProducts;

  /// No description provided for @noFeaturedProductsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No featured products available'**
  String get noFeaturedProductsAvailable;

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

  /// No description provided for @boutique.
  ///
  /// In en, this message translates to:
  /// **'Boutique'**
  String get boutique;

  /// No description provided for @exploreBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Explore Boutiques'**
  String get exploreBoutiques;

  /// No description provided for @failedToLoadBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Failed to load boutiques'**
  String get failedToLoadBoutiques;

  /// No description provided for @noBoutiquesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No boutiques available'**
  String get noBoutiquesAvailable;


  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed'**
  String get loginFailed;

  /// No description provided for @noAccountFoundForThisEmail.
  ///
  /// In en, this message translates to:
  /// **'No account found for this email'**
  String get noAccountFoundForThisEmail;

  /// No description provided for @incorrectPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect password'**
  String get incorrectPassword;

  /// No description provided for @invalidEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Invalid email address'**
  String get invalidEmailAddress;

  /// No description provided for @incorrectEmailOrPassword.
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password'**
  String get incorrectEmailOrPassword;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome Back'**
  String get welcomeBack;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email Address'**
  String get emailAddress;

  /// No description provided for @emailExample.
  ///
  /// In en, this message translates to:
  /// **'John.Doe1984@gmail.com'**
  String get emailExample;

  /// No description provided for @emailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get emailRequired;

  /// No description provided for @enterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get enterValidEmail;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @passwordHidden.
  ///
  /// In en, this message translates to:
  /// **'*************'**
  String get passwordHidden;

  /// No description provided for @passwordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get passwordRequired;

  /// No description provided for @minimumSixCharacters.
  ///
  /// In en, this message translates to:
  /// **'Minimum 6 characters'**
  String get minimumSixCharacters;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot Password?'**
  String get forgotPassword;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign In'**
  String get signIn;

  /// No description provided for @dontHaveAnAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? '**
  String get dontHaveAnAccount;

  /// No description provided for @signUp.
  ///
  /// In en, this message translates to:
  /// **'Sign Up'**
  String get signUp;

  /// No description provided for @or.
  ///
  /// In en, this message translates to:
  /// **'Or'**
  String get or;

  /// No description provided for @continueWithGoogle.
  ///
  /// In en, this message translates to:
  /// **'Continue with Google'**
  String get continueWithGoogle;

  /// No description provided for @signUpFailed.
  ///
  /// In en, this message translates to:
  /// **'Sign up failed'**
  String get signUpFailed;

  /// No description provided for @emailAlreadyInUse.
  ///
  /// In en, this message translates to:
  /// **'This email is already in use'**
  String get emailAlreadyInUse;

  /// No description provided for @passwordTooWeak.
  ///
  /// In en, this message translates to:
  /// **'Password is too weak'**
  String get passwordTooWeak;

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

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create Account'**
  String get createAccount;

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

  /// No description provided for @failedToLoadSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Failed to load search results'**
  String get failedToLoadSearchResults;

  /// No description provided for @searchProductsOrBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Search products or boutiques'**
  String get searchProductsOrBoutiques;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @noMatchingProductsFound.
  ///
  /// In en, this message translates to:
  /// **'No matching products found.'**
  String get noMatchingProductsFound;

  /// No description provided for @noMatchingBoutiquesFound.
  ///
  /// In en, this message translates to:
  /// **'No matching boutiques found.'**
  String get noMatchingBoutiquesFound;

  /// No description provided for @itemSaved.
  ///
  /// In en, this message translates to:
  /// **'Item saved'**
  String get itemSaved;

  /// No description provided for @itemRemovedFromSavedItems.
  ///
  /// In en, this message translates to:
  /// **'Item removed from saved items'**
  String get itemRemovedFromSavedItems;

  /// No description provided for @thisProductIsOutOfStock.
  ///
  /// In en, this message translates to:
  /// **'This product is out of stock'**
  String get thisProductIsOutOfStock;

  /// No description provided for @pleaseSelectASize.
  ///
  /// In en, this message translates to:
  /// **'Please select a size'**
  String get pleaseSelectASize;

  /// No description provided for @itemAddedToCart.
  ///
  /// In en, this message translates to:
  /// **'Item added to cart'**
  String get itemAddedToCart;

  /// No description provided for @by.
  ///
  /// In en, this message translates to:
  /// **'By'**
  String get by;

  /// No description provided for @inStock.
  ///
  /// In en, this message translates to:
  /// **'In stock'**
  String get inStock;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @size.
  ///
  /// In en, this message translates to:
  /// **'Size:'**
  String get size;

  /// No description provided for @noSizesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No sizes available'**
  String get noSizesAvailable;

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

  /// No description provided for @sizeFit.
  ///
  /// In en, this message translates to:
  /// **'Size & Fit'**
  String get sizeFit;

  /// No description provided for @materialAndCareDetailsCanBeAddedLater.
  ///
  /// In en, this message translates to:
  /// **'Material and care details can be added later by the boutique owner.'**
  String get materialAndCareDetailsCanBeAddedLater;

  /// No description provided for @availableSizes.
  ///
  /// In en, this message translates to:
  /// **'Available sizes:'**
  String get availableSizes;

  /// No description provided for @noSizeInformationAvailable.
  ///
  /// In en, this message translates to:
  /// **'No size information available.'**
  String get noSizeInformationAvailable;

  /// No description provided for @itemRemovedFromCart.
  ///
  /// In en, this message translates to:
  /// **'Item removed from cart'**
  String get itemRemovedFromCart;

  /// No description provided for @yourCartIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your cart is empty'**
  String get yourCartIsEmpty;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'SUBTOTAL'**
  String get subtotal;

  /// No description provided for @shippingChargesAndDiscountCodesCalculatedAtCheckout.
  ///
  /// In en, this message translates to:
  /// **'*shipping charges and discount codes\nare calculated at checkout.'**
  String get shippingChargesAndDiscountCodesCalculatedAtCheckout;

  /// No description provided for @checkoutButton.
  ///
  /// In en, this message translates to:
  /// **'CHECKOUT'**
  String get checkoutButton;

  /// No description provided for @pleaseLogInToContinueToCheckout.
  ///
  /// In en, this message translates to:
  /// **'Please log in to continue to checkout'**
  String get pleaseLogInToContinueToCheckout;

  /// No description provided for @user.
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get user;

  /// No description provided for @noEmail.
  ///
  /// In en, this message translates to:
  /// **'No email'**
  String get noEmail;

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

  /// No description provided for @couldNotLoadSavedAddresses.
  ///
  /// In en, this message translates to:
  /// **'Could not load saved addresses'**
  String get couldNotLoadSavedAddresses;

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

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get error;

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

  /// No description provided for @customer.
  ///
  /// In en, this message translates to:
  /// **'Customer'**
  String get customer;

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

  /// No description provided for @thankYou.
  ///
  /// In en, this message translates to:
  /// **'Thank you'**
  String get thankYou;

  /// No description provided for @backToHome.
  ///
  /// In en, this message translates to:
  /// **'BACK TO HOME'**
  String get backToHome;

  /// No description provided for @signInToViewYourOrders.
  ///
  /// In en, this message translates to:
  /// **'Sign in to view your orders'**
  String get signInToViewYourOrders;

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

  /// No description provided for @noPastOrdersYet.
  ///
  /// In en, this message translates to:
  /// **'No past orders yet'**
  String get noPastOrdersYet;

  /// No description provided for @completedOrdersWillAppearHere.
  ///
  /// In en, this message translates to:
  /// **'Your completed orders will appear here.'**
  String get completedOrdersWillAppearHere;

  /// No description provided for @orderLabel.
  ///
  /// In en, this message translates to:
  /// **'Order'**
  String get orderLabel;

  /// No description provided for @statusLabel.
  ///
  /// In en, this message translates to:
  /// **'Status:'**
  String get statusLabel;

  /// No description provided for @itemsOrdered.
  ///
  /// In en, this message translates to:
  /// **'Items Ordered'**
  String get itemsOrdered;

  /// No description provided for @quantityLabel.
  ///
  /// In en, this message translates to:
  /// **'Quantity:'**
  String get quantityLabel;

  /// No description provided for @subtotalNormal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotalNormal;

  /// No description provided for @accountSection.
  ///
  /// In en, this message translates to:
  /// **'ACCOUNT'**
  String get accountSection;

  /// No description provided for @yourAccount.
  ///
  /// In en, this message translates to:
  /// **'Your Account'**
  String get yourAccount;

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

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logout;

  /// No description provided for @changePassword.
  ///
  /// In en, this message translates to:
  /// **'Change Password'**
  String get changePassword;

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

  /// No description provided for @somethingWentWrongWhileLoadingAddresses.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while loading addresses'**
  String get somethingWentWrongWhileLoadingAddresses;

  /// No description provided for @noSavedAddressesYet.
  ///
  /// In en, this message translates to:
  /// **'No saved addresses yet'**
  String get noSavedAddressesYet;

  /// No description provided for @addressRemoved.
  ///
  /// In en, this message translates to:
  /// **'Address removed'**
  String get addressRemoved;

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

  /// No description provided for @addNewAddress.
  ///
  /// In en, this message translates to:
  /// **'ADD NEW ADDRESS'**
  String get addNewAddress;

  /// No description provided for @failedToLoadSavedItems.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while loading saved items'**
  String get failedToLoadSavedItems;

  /// No description provided for @noSavedItemsYet.
  ///
  /// In en, this message translates to:
  /// **'No saved items yet'**
  String get noSavedItemsYet;

  /// No description provided for @itemRemovedFromSaved.
  ///
  /// In en, this message translates to:
  /// **'Item removed from saved items'**
  String get itemRemovedFromSaved;

  /// No description provided for @failedToLoadSavedBoutiques.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while loading saved boutiques'**
  String get failedToLoadSavedBoutiques;

  /// No description provided for @noSavedBoutiquesYet.
  ///
  /// In en, this message translates to:
  /// **'No saved boutiques yet'**
  String get noSavedBoutiquesYet;

  /// No description provided for @boutiqueRemovedFromSaved.
  ///
  /// In en, this message translates to:
  /// **'Boutique removed from saved boutiques'**
  String get boutiqueRemovedFromSaved;

  /// No description provided for @languages.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGES'**
  String get languages;
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
