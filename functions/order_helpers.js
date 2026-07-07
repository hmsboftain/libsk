const {HttpsError} = require("firebase-functions/v2/https");

const ALLOWED_DELIVERY_METHODS = [
  "Regular Delivery",
  "Same Day Delivery",
  "Made to Order",
];

const KWD_CURRENCY = "kwd";
const KWD_MULTIPLIER = 1000;

function normalizeQuantity(value) {
  return Math.max(1, Math.floor(Number(value) || 1));
}

function roundKwd(value) {
  return parseFloat((Number(value) || 0).toFixed(3));
}

function amountFromKwd(total) {
  return Math.round(roundKwd(total) * KWD_MULTIPLIER);
}

function deliveryCostForMethod(deliveryMethod) {
  if (deliveryMethod === "Same Day Delivery") return 5;
  if (deliveryMethod === "Made to Order") return 0;
  if (deliveryMethod === "Regular Delivery") return 3;
  throw new HttpsError("invalid-argument", "Invalid delivery method.");
}

function productKeyOf(boutiqueId, productId) {
  return `${boutiqueId}__${productId}`;
}

function effectiveProductPrice(productData) {
  const basePrice = Number(productData.price) || 0;
  const sale = Number(productData.salePrice);
  return Number.isFinite(sale) && sale > 0 && sale < basePrice
    ? sale
    : basePrice;
}

function buildProductRequirements(items) {
  const lines = [];
  const productAgg = {};
  const sizeAgg = {};

  for (const item of items) {
    const boutiqueId = String(item.boutiqueId || "");
    const productId = String(item.productId || "");
    const quantity = normalizeQuantity(item.quantity);
    const size = String(item.size || "").trim();
    const color = String(item.color || "").trim();

    if (!boutiqueId || !productId) {
      throw new HttpsError("invalid-argument", "Invalid product information.");
    }
    if (quantity > 100) {
      throw new HttpsError("invalid-argument", "Quantity cannot exceed 100 per item.");
    }

    const key = productKeyOf(boutiqueId, productId);
    if (!productAgg[key]) productAgg[key] = {boutiqueId, productId, qty: 0};
    productAgg[key].qty += quantity;

    if (!sizeAgg[key]) sizeAgg[key] = {};
    sizeAgg[key][size] = (sizeAgg[key][size] || 0) + quantity;

    lines.push({
      boutiqueId,
      productId,
      quantity,
      size,
      color,
      original: item,
      key,
    });
  }

  return {lines, productAgg, sizeAgg};
}

function parseStock(value) {
  return Number.isFinite(Number(value)) ? Math.floor(Number(value)) : 0;
}

function parseSizeEntries(productData) {
  if (!Array.isArray(productData.sizeEntries) || productData.sizeEntries.length === 0) {
    return [];
  }

  return productData.sizeEntries
    .map((entry) => {
      if (!entry || typeof entry !== "object") return {name: "", stock: 0};
      return {
        ...entry,
        name: String(entry.name || "").trim(),
        stock: parseStock(entry.stock),
      };
    })
    .filter((entry) => entry.name);
}

function validateProductAvailability(productData, productQty, sizeQuantities) {
  const title = productData.title || "Product";
  if (productData.isOutOfStock === true) {
    throw new HttpsError("failed-precondition", `${title} is out of stock.`);
  }

  const sizeEntries = parseSizeEntries(productData);
  if (sizeEntries.length > 0) {
    for (const [size, qty] of Object.entries(sizeQuantities || {})) {
      if (!size) {
        throw new HttpsError("failed-precondition", `Please select a size for ${title}.`);
      }

      const entry = sizeEntries.find((candidate) => candidate.name === size);
      if (!entry) {
        throw new HttpsError("failed-precondition", `${title} is no longer available in size ${size}.`);
      }
      if (entry.stock < qty) {
        throw new HttpsError("failed-precondition", `${title} does not have enough stock in size ${size}.`);
      }
    }
    return;
  }

  const stock = parseStock(productData.stock);
  if (stock < productQty) {
    throw new HttpsError("failed-precondition", `${title} does not have enough stock.`);
  }
}

function buildStockUpdate(productData, productQty, sizeQuantities, fieldValue, serverTimestamp) {
  const baseUpdate = {
    weeklyOrders: fieldValue.increment(productQty),
    salesCount: fieldValue.increment(productQty),
    updatedAt: serverTimestamp(),
  };

  const sizeEntries = parseSizeEntries(productData);
  if (sizeEntries.length === 0) {
    return {
      ...baseUpdate,
      stock: fieldValue.increment(-productQty),
    };
  }

  const remainingBySize = {...(sizeQuantities || {})};
  const updatedEntries = sizeEntries.map((entry) => {
    const qty = remainingBySize[entry.name] || 0;
    if (qty > 0) delete remainingBySize[entry.name];
    return {
      ...entry,
      stock: entry.stock - qty,
    };
  });

  const updatedStock = updatedEntries.reduce((sum, entry) => sum + parseStock(entry.stock), 0);
  return {
    ...baseUpdate,
    sizeEntries: updatedEntries,
    stock: updatedStock,
  };
}

function paymentIntentWasRefunded(paymentIntent) {
  const latestCharge = paymentIntent && paymentIntent.latest_charge;
  if (latestCharge && typeof latestCharge === "object") {
    if (latestCharge.refunded === true) return true;
    if (Number(latestCharge.amount_refunded || 0) > 0) return true;
  }
  return false;
}

function validatePaymentIntentForOrder(paymentIntent, {uid, amount, currency = KWD_CURRENCY}) {
  if (!paymentIntent || typeof paymentIntent !== "object") {
    throw new HttpsError("failed-precondition", "Payment could not be verified.");
  }
  if (paymentIntent.status !== "succeeded") {
    throw new HttpsError("failed-precondition", "Payment has not completed.");
  }
  if (paymentIntent.metadata && paymentIntent.metadata.uid !== uid) {
    throw new HttpsError("permission-denied", "Payment belongs to a different customer.");
  }
  if (!paymentIntent.metadata || paymentIntent.metadata.uid !== uid) {
    throw new HttpsError("permission-denied", "Payment could not be linked to this customer.");
  }
  if (String(paymentIntent.currency || "").toLowerCase() !== currency) {
    throw new HttpsError("failed-precondition", "Payment currency does not match the order.");
  }
  if (Number(paymentIntent.amount) !== amount) {
    throw new HttpsError("failed-precondition", "Payment amount does not match the order total.");
  }
  if (paymentIntentWasRefunded(paymentIntent)) {
    throw new HttpsError("failed-precondition", "Payment has already been refunded.");
  }
}

module.exports = {
  ALLOWED_DELIVERY_METHODS,
  KWD_CURRENCY,
  amountFromKwd,
  buildProductRequirements,
  buildStockUpdate,
  deliveryCostForMethod,
  effectiveProductPrice,
  normalizeQuantity,
  paymentIntentWasRefunded,
  productKeyOf,
  roundKwd,
  validatePaymentIntentForOrder,
  validateProductAvailability,
};
