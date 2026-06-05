const assert = require("node:assert/strict");
const {beforeEach, describe, it} = require("node:test");

class FakeHttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

class FakeDocSnapshot {
  constructor(data) {
    this._data = data;
    this.exists = data !== undefined;
  }

  data() {
    return this._data;
  }
}

class FakeDocRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
    this.id = path.split("/").pop();
  }

  collection(name) {
    return new FakeCollectionRef(this.db, `${this.path}/${name}`);
  }

  async get() {
    return this.db.snapshot(this.path);
  }
}

class FakeCollectionRef {
  constructor(db, path) {
    this.db = db;
    this.path = path;
  }

  doc(id) {
    return new FakeDocRef(this.db, `${this.path}/${id || this.db.autoId()}`);
  }

  orderBy() {
    return this;
  }

  limit() {
    return this;
  }

  async get() {
    return {empty: true, docs: []};
  }
}

class FakeTransaction {
  constructor(db) {
    this.db = db;
    this.sets = [];
    this.updates = [];
  }

  async get(ref) {
    return this.db.snapshot(ref.path);
  }

  set(ref, data, options) {
    this.sets.push({ref, data, options});
  }

  update(ref, data) {
    this.updates.push({ref, data});
  }

  commit() {
    for (const {ref, data, options} of this.sets) {
      const current = options && options.merge
        ? {...(this.db.docs.get(ref.path) || {})}
        : {};
      this.db.docs.set(ref.path, this.db.materialize({...current, ...data}));
    }

    for (const {ref, data} of this.updates) {
      const current = {...(this.db.docs.get(ref.path) || {})};
      for (const [key, value] of Object.entries(data)) {
        if (value && value.__increment !== undefined) {
          current[key] = (Number(current[key]) || 0) + value.__increment;
        } else {
          current[key] = this.db.materialize(value);
        }
      }
      this.db.docs.set(ref.path, current);
    }
  }
}

class FakeFirestore {
  constructor() {
    this.docs = new Map();
    this.nextAutoId = 1;
  }

  collection(name) {
    return new FakeCollectionRef(this, name);
  }

  autoId() {
    return `auto_${this.nextAutoId++}`;
  }

  snapshot(path) {
    return new FakeDocSnapshot(this.docs.get(path));
  }

  materialize(value) {
    if (Array.isArray(value)) {
      return value.map((item) => this.materialize(item));
    }
    if (value && typeof value === "object") {
      if (value.__serverTimestamp) return "serverTimestamp";
      if (value.__increment !== undefined) return value;
      return Object.fromEntries(
        Object.entries(value).map(([key, item]) => [key, this.materialize(item)]),
      );
    }
    return value;
  }

  async runTransaction(callback) {
    const tx = new FakeTransaction(this);
    const result = await callback(tx);
    tx.commit();
    return result;
  }
}

let fakeDb;
let fakePaymentIntent;
let fakeRefunds;
let createOrder;

function installModuleStubs() {
  const firestoreFunction = () => fakeDb;
  firestoreFunction.FieldValue = {
    serverTimestamp: () => ({__serverTimestamp: true}),
    increment: (value) => ({__increment: value}),
  };

  const fakeAdmin = {
    initializeApp: () => {},
    firestore: firestoreFunction,
  };

  const fakeStripeFactory = () => ({
    paymentIntents: {
      retrieve: async () => fakePaymentIntent,
    },
    refunds: {
      create: async (payload) => {
        fakeRefunds.push(payload);
        return {id: `re_${fakeRefunds.length}`};
      },
    },
  });

  const stubs = {
    "firebase-functions": {
      setGlobalOptions: () => {},
    },
    "firebase-admin": fakeAdmin,
    "firebase-functions/logger": {
      error: () => {},
      info: () => {},
      warn: () => {},
    },
    "firebase-functions/params": {
      defineString: () => ({value: () => "test_secret"}),
    },
    "firebase-functions/v2/https": {
      HttpsError: FakeHttpsError,
      onCall: (handler) => handler,
    },
    "firebase-functions/v2/firestore": {
      onDocumentCreated: () => () => {},
      onDocumentDeleted: () => () => {},
      onDocumentUpdated: () => () => {},
    },
    "firebase-functions/v2/scheduler": {
      onSchedule: () => () => {},
    },
    algoliasearch: {
      algoliasearch: () => ({}),
    },
    stripe: fakeStripeFactory,
  };

  for (const [moduleName, exports] of Object.entries(stubs)) {
    require.cache[require.resolve(moduleName)] = {
      id: moduleName,
      filename: moduleName,
      loaded: true,
      exports,
    };
  }
}

function seedOrderDocs() {
  fakeDb.docs.set("users/user_1", {
    fullName: "Test User",
    email: "test@example.com",
  });
  fakeDb.docs.set("metadata/order_counter", {lastOrderNumber: 100000});
  fakeDb.docs.set("boutiques/b1/products/p1", {
    title: "Dress",
    description: "Server description",
    price: 5,
    stock: 10,
    boutiqueName: "Boutique",
  });
}

function orderRequest(overrides = {}) {
  return {
    auth: {uid: "user_1", token: {name: "Token User", email: "token@example.com"}},
    data: {
      items: [{boutiqueId: "b1", productId: "p1", quantity: 1}],
      deliveryMethod: "Regular Delivery",
      paymentMethod: "Card",
      paymentIntentId: "pi_123",
      ...overrides,
    },
  };
}

beforeEach(() => {
  fakeDb = new FakeFirestore();
  fakePaymentIntent = {
    status: "succeeded",
    amount: 8000,
    amount_received: 8000,
    currency: "kwd",
    metadata: {uid: "user_1"},
  };
  fakeRefunds = [];
  installModuleStubs();
  delete require.cache[require.resolve("./index")];
  createOrder = require("./index").createOrder;
});

describe("createOrder payment enforcement", () => {
  it("creates an order only after consuming a matching same-user payment", async () => {
    seedOrderDocs();

    const result = await createOrder(orderRequest());

    assert.deepEqual(result, {orderNumber: "100001"});
    assert.equal(
      fakeDb.docs.get("payment_intents/pi_123").orderNumber,
      "100001",
    );
    assert.equal(fakeDb.docs.get("boutiques/b1/products/p1").stock, 9);
    assert.equal(fakeDb.docs.get("global_orders/auto_1").total, 8);
    assert.equal(fakeRefunds.length, 0);
  });

  it("rejects underpaid payment intents and refunds the unused payment", async () => {
    seedOrderDocs();
    fakePaymentIntent.amount = 1000;
    fakePaymentIntent.amount_received = 1000;

    await assert.rejects(
      () => createOrder(orderRequest()),
      (error) => (
        error instanceof FakeHttpsError &&
        error.code === "failed-precondition" &&
        error.message === "Payment amount does not match order total."
      ),
    );

    assert.equal(fakeDb.docs.has("payment_intents/pi_123"), false);
    assert.equal(fakeDb.docs.has("global_orders/auto_1"), false);
    assert.equal(fakeDb.docs.get("boutiques/b1/products/p1").stock, 10);
    assert.deepEqual(fakeRefunds, [{
      payment_intent: "pi_123",
      metadata: {reason: "order_creation_failed"},
    }]);
  });

  it("returns the existing order number when the same user retries a consumed payment", async () => {
    seedOrderDocs();
    fakeDb.docs.set("payment_intents/pi_123", {
      uid: "user_1",
      orderNumber: "100001",
    });

    const result = await createOrder(orderRequest({
      items: [{boutiqueId: "b1", productId: "p1", quantity: 10}],
    }));

    assert.deepEqual(result, {orderNumber: "100001"});
    assert.equal(fakeDb.docs.get("boutiques/b1/products/p1").stock, 10);
    assert.equal(fakeRefunds.length, 0);
  });
});
