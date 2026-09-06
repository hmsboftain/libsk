import { Button, Link, Section, Text } from "@react-email/components";
import { Layout } from "./components/Layout.jsx";
import { colors, fonts, button as btn } from "./theme.js";

/**
 * Password reset. Sent via a custom Cloud Function that mints the reset link
 * with admin.auth().generatePasswordResetLink(), replacing Firebase Auth's
 * built-in (unbranded) reset email. Link expiry is Firebase's default (1h).
 */
export default function PasswordReset({ customerName, resetUrl }) {
  return (
    <Layout preview="Reset your LIBSK password">
      <Text style={heading}>Reset your password</Text>
      <Text style={body}>
        {customerName ? `Hi ${customerName}, we` : "We"} received a request to
        reset the password for your LIBSK account. Tap the button below to
        choose a new one.
      </Text>

      <Section style={{ margin: "28px 0", textAlign: "center" }}>
        <Button href={resetUrl} style={taupeButton}>
          Reset password
        </Button>
      </Section>

      <Text style={fineprint}>
        This link expires in 1 hour. If the button doesn't work, copy and paste
        this link into your browser:
      </Text>
      <Text style={{ margin: "0 0 20px" }}>
        <Link href={resetUrl} style={rawLink}>
          {resetUrl}
        </Link>
      </Text>
      <Text style={fineprint}>
        If you didn't request a password reset, you can safely ignore this
        email — your password won't change.
      </Text>
    </Layout>
  );
}

PasswordReset.PreviewProps = {
  customerName: "Retaj",
  resetUrl:
    "https://libsk-b68f5.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=SAMPLE_CODE_abc123&apiKey=SAMPLE",
};

const heading = {
  margin: "0 0 16px",
  fontFamily: fonts.serif,
  fontSize: "24px",
  color: colors.ink,
};

const body = {
  margin: "0 0 8px",
  fontFamily: fonts.sans,
  fontSize: "14px",
  lineHeight: "22px",
  color: colors.ink,
};

const fineprint = {
  margin: "0 0 6px",
  fontFamily: fonts.sans,
  fontSize: "12px",
  lineHeight: "18px",
  color: colors.muted,
};

const rawLink = {
  fontFamily: fonts.sans,
  fontSize: "12px",
  color: colors.muted,
  wordBreak: "break-all",
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
