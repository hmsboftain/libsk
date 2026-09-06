/**
 * LIBSK email design tokens.
 *
 * Carried over verbatim from the Flutter app (lib/widgets/theme.dart) and the
 * existing transactional emails in index.js, so mail matches the product.
 * Keep this the single source of truth for email colours/fonts — do not
 * hard-code hexes in individual templates.
 */

export const colors = {
  background: "#FFFDF8", // warm off-white — app scaffold background
  card: "#FFFFFF",
  ink: "#2C2925", // warm near-black — primary text (app _ink)
  muted: "#8E877D", // taupe — secondary text AND button fill (deepAccent)
  mutedText: "#6E6A66", // secondaryText
  border: "#DDD8D1", // hairline borders / dividers
  hairline: "#E8E4DF", // lighter row separators
  panel: "#F5F1EA", // soft accent fill (highlight / code blocks)
  field: "#F4F2ED",
};

// The taupe button, matched to the Flutter ElevatedButton theme:
// deepAccent fill, white label, square (zero radius), DM Sans 500.
export const button = {
  bg: colors.muted,
  text: "#FFFFFF",
};

/**
 * Cormorant Garamond + DM Sans are NOT email-safe fonts. Clients that support
 * webfonts (Apple Mail, iOS Mail, some webmail) load them via the <Head> <link>
 * below; everyone else (Outlook Windows, Gmail app) falls back to Georgia /
 * Arial — which is exactly what the current LIBSK emails already use, so there
 * is no visual regression anywhere.
 */
export const fonts = {
  serif: "'Cormorant Garamond', Georgia, 'Times New Roman', serif",
  sans: "'DM Sans', -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, Helvetica, sans-serif",
};

export const googleFontsHref =
  "https://fonts.googleapis.com/css2?family=Cormorant+Garamond:ital,wght@0,400;0,500;0,600;1,300;1,400&family=DM+Sans:wght@300;400;500&display=swap";

/**
 * Public base URL for hosted email images. Email clients can't load local
 * paths, so logos live at a stable CDN URL: the dedicated `libsk-email`
 * Firebase Hosting site (separate from the marketing site on libsk-b68f5.web.app).
 * Source of truth is functions/emails/public/ — redeploy with
 * `firebase deploy --only hosting:libsk-email` after changing a logo.
 * Overridable via env for local preview (EMAIL_ASSETS_BASE=http://localhost:8791).
 */
export const assetsBase =
  process.env.EMAIL_ASSETS_BASE || "https://libsk-email.web.app";
export const logoUrl = `${assetsBase}/libsk-wordmark.png`;
// Monogram bumped to the -v2 asset (see commit c4e3019, which corrected this in
// the compiled bundle only). The live libsk-email hosting site already serves
// libsk-monogram-v2.png; keep this in lockstep with what is hosted there.
export const monogramUrl = `${assetsBase}/libsk-monogram-v2.png`;

/** Company / footer facts. Legal name + CR per the registration; socials from the app. */
export const company = {
  legalName: "LIBSK Commission Agency and Trading Company",
  tagline: "Shop Local, Dress Global",
  cr: "549382",
  country: "Kuwait",
  supportEmail: "support@libsk.com",
  // Handles corrected in c4e3019 (bundle-only until now): the live accounts are
  // @libskapp on both, and TikTok resolves on the www host.
  instagram: "https://instagram.com/libskapp",
  tiktok: "https://www.tiktok.com/@libskapp",
};

/** Kuwaiti Dinar is a 3-decimal (fils) currency: 7.5 -> "7.500 KWD". */
export function formatKwd(amount) {
  return `${Number(amount || 0).toFixed(3)} KWD`;
}
