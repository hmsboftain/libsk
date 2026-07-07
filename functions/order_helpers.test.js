const assert = require("node:assert/strict");
const {describe, test} = require("node:test");

const {
  amountFromKwd,
  buildProductRequirements,
  buildStockUpdate,
  deliveryCostForMethod,
  effectiveProductPrice,
  validatePaymentIntentForOrder,
  validateProductAvailability,
} = require("./order_helpers");

const fieldValue = {
  increment: (value) => ({increment: value}),
};
const serverTimestamp = () => "serverTimestamp";

describe("order helper pricing", () => {
  test("uses active sale price and KWD minor units", () => {
    assert.equal(effectiveProductPrice({price: 10, salePrice: 7.5}), 7.5);
    assert.equal(effectiveProductPrice({price: 10, salePrice: 12}), 10);
    assert.equal(amountFromKwd(12.345), 12345);
    assert.equal(amountFromKwd(12.3454), 12345);
    assert.equal(deliveryCostForMethod("Same Day Delivery"), 5);
  });
});

describe("order helper stock aggregation", () => {
  test("aggregates duplicate product and size quantities", () => {
    const {productAgg, sizeAgg} = buildProductRequirements([
      {boutiqueId: "b1", productId: "p1", size: "S", quantity: 2},
      {boutiqueId: "b1", productId: "p1", size: "S", quantity: 3},
      {boutiqueId: "b1", productId: "p1", size: "M", quantity: 1},
    ]);

    assert.deepEqual(productAgg.b1__p1, {
      boutiqueId: "b1",
      productId: "p1",
      qty: 6,
    });
    assert.deepEqual(sizeAgg.b1__p1, {S: 5, M: 1});
  });

  test("rejects per-size oversell even when aggregate stock is enough", () => {
    assert.throws(
      () => validateProductAvailability(
        {
          title: "Dress",
          stock: 10,
          sizeEntries: [
            {name: "S", stock: 2},
            {name: "M", stock: 8},
          ],
        },
        5,
        {S: 5},
      ),
      /size S/,
    );
  });

  test("decrements size stock and recomputes aggregate stock", () => {
    const update = buildStockUpdate(
      {
        stock: 10,
        sizeEntries: [
          {name: "S", stock: 2},
          {name: "M", stock: 8},
        ],
      },
      3,
      {S: 1, M: 2},
      fieldValue,
      serverTimestamp,
    );

    assert.deepEqual(update.sizeEntries, [
      {name: "S", stock: 1},
      {name: "M", stock: 6},
    ]);
    assert.equal(update.stock, 7);
    assert.deepEqual(update.weeklyOrders, {increment: 3});
    assert.deepEqual(update.salesCount, {increment: 3});
  });
});

describe("payment intent verification", () => {
  const basePaymentIntent = {
    id: "pi_test",
    status: "succeeded",
    amount: 8500,
    currency: "kwd",
    metadata: {uid: "user_1"},
  };

  test("accepts exact same-user succeeded KWD payment", () => {
    assert.doesNotThrow(() => validatePaymentIntentForOrder(
      basePaymentIntent,
      {uid: "user_1", amount: 8500, currency: "kwd"},
    ));
  });

  test("rejects underpaid, wrong user, and refunded payments", () => {
    assert.throws(
      () => validatePaymentIntentForOrder(
        {...basePaymentIntent, amount: 8000},
        {uid: "user_1", amount: 8500, currency: "kwd"},
      ),
      /amount/,
    );
    assert.throws(
      () => validatePaymentIntentForOrder(
        {...basePaymentIntent, metadata: {uid: "user_2"}},
        {uid: "user_1", amount: 8500, currency: "kwd"},
      ),
      /different customer/,
    );
    assert.throws(
      () => validatePaymentIntentForOrder(
        {...basePaymentIntent, latest_charge: {refunded: true}},
        {uid: "user_1", amount: 8500, currency: "kwd"},
      ),
      /refunded/,
    );
  });
});
