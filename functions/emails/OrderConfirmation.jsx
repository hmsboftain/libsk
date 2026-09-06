import {
  Button,
  Column,
  Hr,
  Row,
  Section,
  Text,
} from "@react-email/components";
import { Layout } from "./components/Layout.jsx";
import { colors, fonts, button as btn, formatKwd } from "./theme.js";

/**
 * Order confirmation / payment receipt.
 *
 * Sent once payment is confirmed (index.js sendOrderConfirmationEmail already
 * gates on status !== "Pending Payment"). Itemised: order number, date,
 * boutique, line items, subtotal, delivery, total.
 */
export default function OrderConfirmation({
  orderNumber,
  date,
  customerName,
  items = [],
  subtotal,
  deliveryCost,
  deliveryMethod,
  discountAmount = 0,
  total,
  orderUrl,
}) {
  // Group line items by boutique, preserving first-seen order — orders are
  // multi-vendor, so a single cart can span several boutiques.
  const groups = [];
  const groupIndex = {};
  for (const item of items) {
    const name = item.boutiqueName || "LIBSK";
    if (groupIndex[name] == null) {
      groupIndex[name] = groups.length;
      groups.push({ name, items: [] });
    }
    groups[groupIndex[name]].items.push(item);
  }

  return (
    <Layout preview={`Your LIBSK order #${orderNumber} is confirmed`}>
      <Text style={heading}>Order confirmed</Text>
      <Text style={intro}>
        Thank you{customerName ? `, ${customerName}` : ""}. Your order is
        confirmed and being prepared.
      </Text>

      {/* Order / date meta */}
      <Row style={{ marginBottom: "6px" }}>
        <Column>
          <Text style={metaLabel}>Order</Text>
        </Column>
        <Column style={{ textAlign: "right" }}>
          <Text style={metaLabel}>Date</Text>
        </Column>
      </Row>
      <Row style={{ marginBottom: "28px" }}>
        <Column>
          <Text style={metaValue}>#{orderNumber}</Text>
        </Column>
        <Column style={{ textAlign: "right" }}>
          <Text style={metaValue}>{date}</Text>
        </Column>
      </Row>

      {/* Items header */}
      <Row style={itemsHeaderRow}>
        <Column style={{ width: "50%" }}>
          <Text style={colHeadLeft}>Item</Text>
        </Column>
        <Column style={{ width: "14%", textAlign: "center" }}>
          <Text style={colHeadCenter}>Size</Text>
        </Column>
        <Column style={{ width: "14%", textAlign: "center" }}>
          <Text style={colHeadCenter}>Qty</Text>
        </Column>
        <Column style={{ width: "22%", textAlign: "right" }}>
          <Text style={colHeadRight}>Price</Text>
        </Column>
      </Row>

      {/* Item rows, grouped by boutique */}
      {groups.map((group, gi) => (
        <Section key={gi}>
          <Row style={boutiqueHeaderRow}>
            <Column>
              <Text style={boutiqueHeader}>{group.name}</Text>
            </Column>
          </Row>
          {group.items.map((item, i) => {
            const lineTotal = (item.price || 0) * (item.quantity || 1);
            return (
              <Row key={i} style={itemRow}>
                <Column style={{ width: "50%" }}>
                  <Text style={itemTitle}>{item.title}</Text>
                  {item.quantity > 1 ? (
                    <Text style={itemUnit}>
                      {item.quantity} × {formatKwd(item.price)}
                    </Text>
                  ) : null}
                </Column>
                <Column style={{ width: "14%", textAlign: "center" }}>
                  <Text style={itemCell}>{item.size || "—"}</Text>
                </Column>
                <Column style={{ width: "14%", textAlign: "center" }}>
                  <Text style={itemCell}>{item.quantity}</Text>
                </Column>
                <Column style={{ width: "22%", textAlign: "right" }}>
                  <Text style={itemCell}>{formatKwd(lineTotal)}</Text>
                </Column>
              </Row>
            );
          })}
        </Section>
      ))}

      {/* Totals */}
      <Section style={{ marginTop: "20px" }}>
        <Row>
          <Column>
            <Text style={totalLabel}>Subtotal</Text>
          </Column>
          <Column style={{ textAlign: "right" }}>
            <Text style={totalLabel}>{formatKwd(subtotal)}</Text>
          </Column>
        </Row>
        {discountAmount > 0 ? (
          <Row>
            <Column>
              <Text style={totalLabel}>Discount</Text>
            </Column>
            <Column style={{ textAlign: "right" }}>
              <Text style={totalLabel}>−{formatKwd(discountAmount)}</Text>
            </Column>
          </Row>
        ) : null}
        <Row>
          <Column>
            <Text style={totalLabel}>{deliveryMethod || "Delivery"}</Text>
          </Column>
          <Column style={{ textAlign: "right" }}>
            <Text style={totalLabel}>{formatKwd(deliveryCost)}</Text>
          </Column>
        </Row>
        <Hr style={totalsRule} />
        <Row>
          <Column>
            <Text style={grandTotalLabel}>Total</Text>
          </Column>
          <Column style={{ textAlign: "right" }}>
            <Text style={grandTotalValue}>{formatKwd(total)}</Text>
          </Column>
        </Row>
      </Section>

      {orderUrl ? (
        <Section style={{ marginTop: "32px", textAlign: "center" }}>
          <Button href={orderUrl} style={taupeButton}>
            View your order
          </Button>
        </Section>
      ) : null}
    </Layout>
  );
}

// Sample data for the local preview server (email dev) — spans two boutiques
// and carries a discount, to exercise grouping + the discount line.
OrderConfirmation.PreviewProps = {
  orderNumber: "LB-20482",
  date: "24 July 2026",
  customerName: "Retaj",
  items: [
    { title: "Washed Cotton Baby Tee — Ecru", size: "S", quantity: 2, price: 7.5, boutiqueName: "LUNE" },
    { title: "Pleated Mini Skirt — Sand", size: "M", quantity: 1, price: 13.0, boutiqueName: "LUNE" },
    { title: "Amber Oud 10ml Tester", size: "—", quantity: 1, price: 9.0, boutiqueName: "Glamaura" },
  ],
  subtotal: 37.0,
  discountAmount: 3.7,
  deliveryCost: 3.0,
  deliveryMethod: "Standard Delivery",
  total: 36.3,
  orderUrl: "https://libsk.com/orders/LB-20482",
};

const heading = {
  margin: "0 0 6px",
  fontFamily: fonts.serif,
  fontSize: "22px",
  color: colors.ink,
};

const intro = {
  margin: "0 0 28px",
  fontFamily: fonts.sans,
  fontSize: "13px",
  lineHeight: "20px",
  color: colors.muted,
};

const metaLabel = {
  margin: 0,
  fontFamily: fonts.sans,
  fontSize: "11px",
  color: colors.muted,
  textTransform: "uppercase",
  letterSpacing: "1px",
};

const metaValue = {
  margin: 0,
  fontFamily: fonts.serif,
  fontSize: "15px",
  color: colors.ink,
};

const itemsHeaderRow = {
  borderBottom: `1px solid ${colors.ink}`,
  paddingBottom: "8px",
};

const colHeadBase = {
  margin: 0,
  fontFamily: fonts.sans,
  fontSize: "11px",
  color: colors.muted,
  textTransform: "uppercase",
  letterSpacing: "1px",
};
const colHeadLeft = { ...colHeadBase };
const colHeadCenter = { ...colHeadBase, textAlign: "center" };
const colHeadRight = { ...colHeadBase, textAlign: "right" };

const boutiqueHeaderRow = {
  paddingTop: "14px",
};

const boutiqueHeader = {
  margin: "0 0 2px",
  fontFamily: fonts.sans,
  fontSize: "11px",
  fontWeight: "500",
  color: colors.ink,
  textTransform: "uppercase",
  letterSpacing: "1.5px",
};

const itemRow = {
  borderBottom: `1px solid ${colors.hairline}`,
};

const itemTitle = {
  margin: "10px 0 0",
  fontFamily: fonts.serif,
  fontSize: "14px",
  color: colors.ink,
};

const itemUnit = {
  margin: "2px 0 10px",
  fontFamily: fonts.sans,
  fontSize: "11px",
  color: colors.muted,
};

const itemCell = {
  margin: "10px 0",
  fontFamily: fonts.serif,
  fontSize: "14px",
  color: colors.ink,
};

const totalLabel = {
  margin: "4px 0",
  fontFamily: fonts.sans,
  fontSize: "13px",
  color: colors.muted,
};

const totalsRule = {
  borderColor: colors.border,
  margin: "10px 0",
};

const grandTotalLabel = {
  margin: "4px 0",
  fontFamily: fonts.serif,
  fontSize: "15px",
  fontWeight: "bold",
  color: colors.ink,
};

const grandTotalValue = {
  ...{
    margin: "4px 0",
    fontFamily: fonts.serif,
    fontSize: "15px",
    fontWeight: "bold",
    color: colors.ink,
  },
  textAlign: "right",
};

const taupeButton = {
  backgroundColor: btn.bg,
  color: btn.text,
  fontFamily: fonts.sans,
  fontSize: "14px",
  fontWeight: "500",
  letterSpacing: "0.5px",
  textDecoration: "none",
  textTransform: "uppercase",
  padding: "14px 32px",
  borderRadius: "0", // square, per LIBSK button style
  display: "inline-block",
};
