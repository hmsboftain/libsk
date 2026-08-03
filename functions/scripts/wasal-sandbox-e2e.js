"use strict";

// ================= WASAL SANDBOX END-TO-END TEST =================
//
// Walks the full delivery lifecycle against the REAL Wasal sandbox using the
// same client the Cloud Functions use (functions/wasal.js). No Firebase, no
// emulator — just the Wasal API. Run it from functions/:
//
//   WASAL_API_KEY=pk_test_xxx node scripts/wasal-sandbox-e2e.js
//
// Optional: WASAL_BRANCH_CODE=MAIN (defaults to the first branch on the
// account). Everything it creates is sandbox data — no drivers, no wallet.

const {
  createWasalClient,
  resolveZoneFee,
  normalizeKuwaitPhone,
  matchBlockId,
} = require("../wasal");

const API_KEY = process.env.WASAL_API_KEY || "";

function fail(msg) {
  console.error(`\n✗ ${msg}`);
  process.exit(1);
}
function ok(msg) {
  console.log(`✓ ${msg}`);
}

async function main() {
  if (!API_KEY.startsWith("pk_test_")) {
    fail("Set WASAL_API_KEY to your pk_test_ sandbox key (never pk_live_ for this script).");
  }
  const client = createWasalClient(API_KEY);

  // 1. Areas (public)
  const govs = await client.listGovernorates();
  const govList = govs.list || [];
  if (govList.length === 0) fail("No governorates returned");
  const gov = govList[0];
  ok(`Areas: ${govList.length} governorates (first: ${gov.title?.en})`);

  const neighs = await client.listNeighborhoods(gov.sourceId);
  const neighList = neighs.list || [];
  if (neighList.length === 0) fail(`No neighborhoods in ${gov.title?.en}`);
  const neigh = neighList[0];
  ok(`Neighborhoods in ${gov.title?.en}: ${neighList.length} (first: ${neigh.title?.en})`);

  // 2. Pricing — logs the raw shape so resolveZoneFee's tolerant matching
  //    can be tightened against reality if needed.
  let fee = null;
  try {
    const pricing = await client.getPricing();
    console.log("  pricing payload:", JSON.stringify(pricing).slice(0, 400));
    fee = resolveZoneFee(pricing, {
      governorateId: gov.sourceId,
      neighborhoodId: neigh.sourceId,
    });
    ok(`Pricing fetched — resolved fee for ${neigh.title?.en}: ${fee ?? "no zone match (flat fallback)"}`);
  } catch (e) {
    console.warn(`  pricing endpoint failed (${e.code}): ${e.message} — continuing`);
  }

  // 3. Branch
  const branches = await client.listBranches();
  const branchList = branches.list || [];
  if (branchList.length === 0) {
    fail("No branches on this merchant account — create one in the Wasal dashboard first.");
  }
  const branchCode = process.env.WASAL_BRANCH_CODE || branchList[0].code;
  ok(`Branches: ${branchList.map((b) => b.code).join(", ")} — using ${branchCode}`);

  // 4. Customer upsert + address
  const phone = normalizeKuwaitPhone("50001234");
  const up = await client.upsertCustomer({ phoneNumber: phone, name: "LIBSK Sandbox Test" });
  const customer = up.customer;
  ok(`Customer ${up.created ? "created" : "found"}: ${customer._id}`);

  let addresses = customer.addresses || [];
  let addressId = addresses[0]?._id;
  if (!addressId) {
    // blockId must be a REAL PACI reference — resolve one from the area tree
    // (mirrors markReadyForPickup). Free-text block/street go in line1.
    let blockId = null;
    try {
      const blocks = await client.listBlocks(neigh.sourceId);
      const list = blocks.list || [];
      blockId = list[0] ? String(list[0].sourceId) : null;
      if (list[0]) {
        ok(`Blocks in ${neigh.title?.en}: ${list.length} — using "${list[0].title?.en}"`);
        // Also exercise the production matcher against a real title.
        const matched = matchBlockId(list, list[0].title?.en);
        if (matched !== blockId) fail("matchBlockId failed to match a real block title");
      }
    } catch (e) {
      console.warn(`  block lookup failed (${e.code}) — adding address without blockId`);
    }
    const added = await client.addCustomerAddress(customer._id, {
      label: "Home",
      governorateId: gov.sourceId,
      neighborhoodId: neigh.sourceId,
      ...(blockId ? { blockId } : {}),
      houseNumber: "8",
      line1: "Street 12, House 8 (LIBSK sandbox test)",
    });
    addressId = added.address._id;
    ok(`Address added: ${addressId}`);
  } else {
    ok(`Reusing address: ${addressId}`);
  }

  // 5. Create order (prepaid — mirrors markReadyForPickup exactly)
  const created = await client.createOrder({
    customerId: customer._id,
    customerAddressId: addressId,
    branchCode,
    specialHandlingTags: ["none"],
    paymentMethod: "prepaid",
    pricing: { subtotal: 12.5, total: 12.5 },
    items: [{ name: "Sandbox Tee", qty: 1, price: 12.5 }],
    orderMerchantReferenceNumber: `E2E-${Date.now()}`,
    merchantNotes: "LIBSK sandbox e2e — safe to ignore",
  });
  const order = created.order;
  ok(`Order created: ${order.orderNumber} (${order._id}) status=${order.status}`);

  // 6. Walk the lifecycle (sandbox-only endpoint)
  for (const status of ["assigned", "on_way_to_merchant", "picked_up", "in_transit", "delivered"]) {
    const advanced = await client.advanceSandboxStatus(order._id, status);
    ok(`Advanced → ${advanced.status}`);
  }

  // 7. Read back
  const final = await client.getOrder(order._id);
  const finalStatus = final.order?.status || final.status;
  if (finalStatus !== "delivered") fail(`Expected delivered, got ${finalStatus}`);
  ok("Final status verified: delivered");

  const history = await client.getOrderHistory(order._id);
  const steps = (history.statusHistory || history.list || []).length;
  ok(`Status history entries: ${steps}`);

  console.log("\nAll sandbox checks passed.");
}

main().catch((e) => {
  console.error("\n✗ E2E failed:", e.message, e.code ? `(${e.code})` : "", e.errors || "");
  process.exit(1);
});
