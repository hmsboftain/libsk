"use strict";

// KWD amounts in customer-facing email. Kuwaiti Dinar is a 3-decimal (fils)
// currency, so every amount shows exactly 3 decimals — never rounded to whole
// dinars — the same rule the app applies to KWD (CurrencyService.format).
//
// The ONE formatter for all LIBSK email: the React Email templates get it via
// emails/theme.js (which re-exports it), and index.js's HTML emails require it
// directly — hence CommonJS. Unit-tested in test/format_kwd.test.js.

/** Kuwaiti Dinar is a 3-decimal (fils) currency: 7.5 -> "7.500 KWD". */
function formatKwd(amount) {
  return `${Number(amount || 0).toFixed(3)} KWD`;
}

module.exports = { formatKwd };
