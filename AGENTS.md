# LIBSK — Codex Project Context

## What is LIBSK
LIBSK is a multi-vendor fashion marketplace app for Kuwait's independent boutique market. It is built in Flutter (frontend) and Firebase (backend). Boutiques list products, customers browse and buy, and LIBSK takes a flat 15% commission on GMV (net ~12–13% after payment gateway fees). Promo slots are a secondary revenue stream sold separately to boutiques at published rates. There are no subscription tiers.

The company is registered as **"LIBSK Commission Agency and Trading Company"** (Arabic: شركة لبسك للوكيل بالعمولة والأتجار بالعمولة).

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter (Dart) |
| Backend | Firebase (Firestore, Auth, Cloud Functions, FCM, Hosting) |
| Cloud Functions | Node.js |
| Search | Algolia (synced via Cloud Functions) |
| Email | Resend (domain verified) / SendGrid planned |
| Payment | Payzah (KWD + KNET + Apple Pay) |
| Delivery | Delivery API integration pending |
| SMS | Unifonic (planned) |
| WhatsApp AI | 360dialog + Codex API (planned) |
| IDE | Cursor |
| Repo | github.com/hmsboftain/libsk |

---

## Design System

- **Fonts:** Cormorant Garant (headings) + DM Sans (body)
- **Background:** `#FFFDF8` (warm off-white)
- **Buttons:** Taupe
- **Cards:** Square with 4:5 image ratio
- **Aesthetic:** Minimal, luxury, warm neutrals
- **Language:** English + Arabic (bilingual support)

---

## Core Architecture

- Flutter frontend talks to Firestore directly for reads (with security rules enforced)
- All sensitive writes go through **Cloud Functions** (Node.js) — never trusted client-side
- `createOrder` Cloud Function uses Firestore transactions for:
  - Atomic stock decrement
  - Server-side price verification (never trust client price)
  - Multi-collection writes
- Firebase Auth handles all authentication
- Algolia search is synced in real-time via Cloud Functions triggers

---

## Security Rules — Key Principles
- Firestore security rules are written and deployed
- Client-side price trust has been removed — all prices verified server-side
- Stripe API key has been moved out of source code
- Guest cart IDs use `Random.secure()`
- **Do not reintroduce client-side price trust under any circumstance**
- **Do not hardcode API keys or secrets in Flutter source**

---

## Completed Features
- Full UI/UX overhaul (design system applied throughout)
- Hero banner management (admin)
- Promo slot booking flow (admin)
- Promotional campaign builder
- Order tracking
- Filter system (category / price / size / color)
- Reviews and ratings
- Boutique analytics and sales charts
- Payout history
- Inventory alerts
- Made-to-order toggle with auto-detected delivery flow
- Per-size stock system with size guide upload
- Color options
- Boutique onboarding page
- Super admin revenue breakdown
- Trending and new arrivals sections
- Dispute resolution with image upload
- Instagram-style shoppable home feed with follow system + sponsored/trending layers
- GCC country switcher with flag emojis + auto-detection on first launch
- Influencer/social profile system (built, not yet launched)

---

## Pending / In Progress

### Launch Blockers (Priority Order)
1. Payment gateway integration — Payzah: KNET verified end-to-end in sandbox
   (Direct Integration, in-app WebView); credit card (MPGS hosted checkout)
   declining in sandbox, under investigation; Apple Pay (Transit) not yet
   scoped — Stripe fully removed (client + Cloud Functions); refunds are
   manual via Payzah dashboard + superadmin "Mark as Refunded"
2. Delivery API integration
3. Apple Developer enrollment (Organization, DUNS requested — blocked Apple-side)
4. Firebase Crashlytics — integration incomplete, do not treat as active

### Pending Integrations (Priority Order)
1. Order confirmation email (SendGrid + FCM)
2. FCM push for boutique follow notifications
3. WhatsApp AI auto-reply (360dialog + Codex API)
4. SMS delivery updates (Unifonic)
5. Internal payout tracking dashboard (interim, using existing Firestore order data)

---

## Business Rules — Do Not Break
- Commission is flat **15% on GMV** — no subscription tiers
- Promo slots are sold separately to all boutiques at published rates
- GCC multi-currency support required (KWD primary)
- Governed by Kuwait law; arbitration seat Kuwait
- Privacy contact: privacy@libsk.com
- Legal contact: legal@libsk.com

---

## Brands on LIBSK

### LUNE (owned by Hussain)
- Kuwait girls' streetwear, Brandy Melville-inspired
- Produced in Egypt via Seif Clothing (Giza cotton)
- Drop 001: 10 pieces, 400 units total
- Sizes: S/M only permanently
- Prices: 7.500–13.000 KWD
- Sells exclusively on LIBSK

### Glamaura (owned by Hussain)
- Kuwait perfume brand
- AI-driven custom perfume generation
- 10ml testers, 70% alcohol, 30% oils

---

## Planned Features (Post-Launch)

### Pre-Order System
Upgrade the current made-to-order toggle to a full pre-order system.

**Boutique owner controls (edit_product_page):**
- Enable Pre-Order toggle (replaces current MTO toggle)
- Expected dispatch date (date picker)
- Pre-order limit (max units they can commit to)
- Custom message to customers (e.g. "Ships after Eid", "Next run: July")
- Optional deposit mode — take full price now, or a deposit % with remainder charged on dispatch

**Customer experience (product_page):**
- "PRE-ORDER" badge replacing "Add to Cart"
- Estimated dispatch date shown prominently below price
- Custom boutique message displayed
- Clear "You'll be charged now, ships [date]" messaging
- Pre-order confirmation email with expected dispatch date

**Order management:**
- Pre-orders flagged separately in boutique owner dashboard
- Dedicated "Pre-Orders" tab for owners to track commitments
- Owner marks as "Ready to Ship" when dispatch date arrives
- Separate pre-order status flow distinct from regular orders

**Notes:**
- Build after launch based on real boutique feedback
- Replaces current madeToOrder boolean — migrate existing MTO products to new pre-order format
- Pairs naturally with LUNE drop culture (limited runs, seasonal drops)
- Detailed technical migration plan lives in `PRE_ORDER_PLAN.md` (project root)

---

## Coding Conventions
- Always use server-side Cloud Functions for any financial logic
- Firestore writes that affect stock, pricing, or orders must go through transactions
- Never trust client-supplied prices — always re-fetch from Firestore server-side
- Keep API keys and secrets in Firebase environment config, never in Flutter source
- Follow existing design system — do not introduce new fonts, colors, or card layouts without asking
- All new user-facing strings should support both English and Arabic
- Use `Random.secure()` for any ID generation

---

## Key Contacts
- Founder/Developer: Hussain
- Marketing/Brand: Retaj (wife) — manages Glamour brand, active on TikTok, Instagram, Snapchat, YouTube
- Domain: libsk.com (managed via Squarespace)
- Google Workspace: email aliases set up
- Banking: National Bank of Kuwait (recommended)