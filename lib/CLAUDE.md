# LIBSK Project

## Stack
- Flutter + Firebase (Firestore, Auth, Storage, Messaging, Functions)
- Stripe payments via flutter_stripe
- Kuwait market, Arabic + English (flutter_localizations)

## Design System

### Fonts
- Headings/Display: CormorantGaramond (serif, italic, w300/400/500)
- Body/UI/Buttons: DMSans (sans-serif, w300/400/500)
- Always import from lib/widgets/theme.dart

### Colors
Always use AppColors from lib/widgets/theme.dart. Never hardcode hex or Colors.*
- Background: AppColors.background
- Primary text: AppColors.primaryText
- Secondary text: AppColors.secondaryText
- Buttons/accents: AppColors.deepAccent
- Borders: AppColors.border
- Input fields: AppColors.field
- Image placeholders: AppColors.imagePlaceholder

### Text Styles
Always use AppTextStyles from lib/widgets/theme.dart. Never use raw TextStyle.

### Cards & Containers
- Square corners — no BorderRadius on cards
- Border: 0.5px, AppColors.border
- No elevation, no shadows unless subtle

### Buttons
- Background: AppColors.deepAccent
- Max border radius: 8px
- No gradients

### Images
- Product images: 4:5 ratio

### Icons
- Line style, size 24, color AppColors.primaryText

## Rules
- Never hardcode colors or text styles
- Never add rounded corners to cards
- Never modify Firebase logic, navigation, or localization strings
- Only change visual/styling code unless asked otherwise