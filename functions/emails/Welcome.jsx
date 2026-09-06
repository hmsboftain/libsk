import { Button, Section, Text } from "@react-email/components";
import { Layout } from "./components/Layout.jsx";
import { colors, fonts, button as btn } from "./theme.js";

/**
 * Welcome email, sent once after signup (post email-verification).
 */
export default function Welcome({ customerName, ctaUrl }) {
  return (
    <Layout preview="Welcome to LIBSK — Kuwait's boutique fashion, in one place">
      <Text style={heading}>Welcome to LIBSK</Text>
      <Text style={body}>
        {customerName ? `${customerName}, welcome` : "Welcome"} — we're glad
        you're here. LIBSK brings Kuwait's independent boutiques together in one
        place, so you can discover pieces you won't find anywhere else.
      </Text>
      <Text style={body}>
        Browse new arrivals, follow the boutiques you love, and check out in a
        few taps. Everything ships from local ateliers, curated for you.
      </Text>

      {ctaUrl ? (
        <Section style={{ marginTop: "32px", textAlign: "center" }}>
          <Button href={ctaUrl} style={taupeButton}>
            Start exploring
          </Button>
        </Section>
      ) : null}
    </Layout>
  );
}

Welcome.PreviewProps = {
  customerName: "Retaj",
  ctaUrl: "https://libsk.com",
};

const heading = {
  margin: "0 0 16px",
  fontFamily: fonts.serif,
  fontSize: "24px",
  color: colors.ink,
};

const body = {
  margin: "0 0 16px",
  fontFamily: fonts.sans,
  fontSize: "14px",
  lineHeight: "22px",
  color: colors.ink,
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
  borderRadius: "0",
  display: "inline-block",
};
