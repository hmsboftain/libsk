"use strict";

// Unit tests for formatKwd — the one formatter for every KWD amount in LIBSK
// email. Run with `npm test` (functions/). A green run means amounts keep all
// three fils decimals ("1.250 KWD", never "1 KWD" — the order emails used to
// round every amount with toFixed(0)), in both the HTML emails index.js builds
// and the React Email templates.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const { formatKwd } = require("../format_kwd");

test('1.250 renders as "1.250 KWD", not "1 KWD"', () => {
  assert.equal(formatKwd(1.25), "1.250 KWD");
  assert.notEqual(formatKwd(1.25), "1 KWD");
});

test("whole, sub-dinar and half-dinar amounts keep exactly 3 decimals", () => {
  assert.equal(formatKwd(1), "1.000 KWD"); // toFixed(0) said "1 KWD"
  assert.equal(formatKwd(0.15), "0.150 KWD"); // toFixed(0) said "0 KWD"
  assert.equal(formatKwd(12.5), "12.500 KWD"); // toFixed(0) said "13 KWD"
});

test("floating-point noise and rounding to the fils", () => {
  assert.equal(formatKwd(0.1 + 0.2), "0.300 KWD"); // 0.30000000000000004
  assert.equal(formatKwd(13.75), "13.750 KWD");
  assert.equal(formatKwd(1234.5678), "1234.568 KWD");
});

test("an amount stored as a numeric string formats the same", () => {
  assert.equal(formatKwd("2.5"), "2.500 KWD");
});

test("a missing amount shows 0.000 KWD instead of throwing", () => {
  assert.equal(formatKwd(undefined), "0.000 KWD");
  assert.equal(formatKwd(null), "0.000 KWD");
});

// orderEmailHtml (the order confirmation + status emails) lives in index.js,
// which can't be loaded in a unit test — it initializes firebase-admin at
// require time. So this guards the template's source instead.
test("orderEmailHtml formats every amount with formatKwd — none by hand", () => {
  const src = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");
  const start = src.indexOf("function orderEmailHtml(");
  const end = src.indexOf("\n}\n", start);
  assert.ok(start >= 0 && end > start, "orderEmailHtml not found in index.js");
  const body = src.slice(start, end);

  // " KWD" right after a template expression is an amount formatted by hand —
  // exactly how the toFixed(0) bug was written.
  assert.doesNotMatch(body, /\}\s*KWD/);
  for (const amount of ["item.price", "subtotal", "deliveryCost", "total"]) {
    assert.ok(body.includes(`formatKwd(${amount})`), `${amount} must go through formatKwd`);
  }
});

test("the React Email order template renders amounts through the same formatter", async () => {
  const { renderOrderConfirmation } = require("../emails/dist/render.cjs");
  const { text } = await renderOrderConfirmation({
    orderNumber: "100123",
    date: "11/9/2026",
    customerName: "Test",
    items: [{ title: "Linen shirt", price: 12.5, quantity: 1, boutiqueName: "Katleir" }],
    subtotal: 12.5,
    deliveryCost: 1.25,
    deliveryMethod: "Standard Delivery",
    total: 13.75,
  });
  assert.match(text, /1\.250 KWD/);
  assert.match(text, /13\.750 KWD/);
});
