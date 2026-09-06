import {
  Body,
  Container,
  Head,
  Hr,
  Html,
  Img,
  Link,
  Preview,
  Section,
  Text,
} from "@react-email/components";
import {
  colors,
  fonts,
  googleFontsHref,
  logoUrl,
  monogramUrl,
  company,
} from "../theme.js";

/**
 * Shared shell for every LIBSK transactional email: warm background, bordered
 * 560px card, image logo header, and a full company footer.
 *
 * No unsubscribe link — order confirmations, welcome, and password resets are
 * transactional/relationship mail, which is exempt from opt-out + physical-
 * address requirements (CAN-SPAM). An unsubscribe would also be wrong here:
 * users must keep receiving receipts and reset mail.
 *
 * Dark mode: forced `light only`. LIBSK's cream (#FFFDF8) inverts badly, so we
 * opt out where honoured (Apple Mail, iOS). The logos are images multiply-
 * composited onto cream, so there's no text-wordmark to recolour.
 */
export function Layout({ preview, children, footer }) {
  const year = new Date().getFullYear();

  return (
    <Html lang="en">
      <Head>
        <meta name="color-scheme" content="light only" />
        <meta name="supported-color-schemes" content="light only" />
        <link rel="stylesheet" href={googleFontsHref} />
      </Head>
      {preview ? <Preview>{preview}</Preview> : null}
      <Body style={bodyStyle} bgcolor={colors.background}>
        <Section style={outer} bgcolor={colors.background}>
          <Container style={card} bgcolor={colors.background}>
            {/* Header — logo image with alt fallback if images are blocked */}
            <Section style={header}>
              <Img
                src={logoUrl}
                width="160"
                height="75"
                alt="LIBSK"
                style={logoImg}
              />
            </Section>

            {/* Body */}
            <Section style={content}>{children}</Section>

            {/* Footer */}
            {footer || (
              <>
                <Hr style={rule} />
                <Section style={footerSection}>
                  <Img
                    src={monogramUrl}
                    width="30"
                    height="27"
                    alt="LIBSK"
                    style={monogramImg}
                  />
                  <Text style={footerCompany}>{company.legalName}</Text>
                  <Text style={footerTagline}>{company.tagline}</Text>

                  <Text style={footerLinks}>
                    <Link href={company.instagram} style={footerLink}>
                      Instagram
                    </Link>
                    <span style={footerDot}>·</span>
                    <Link href={company.tiktok} style={footerLink}>
                      TikTok
                    </Link>
                    <span style={footerDot}>·</span>
                    <Link
                      href={`mailto:${company.supportEmail}`}
                      style={footerLink}
                    >
                      {company.supportEmail}
                    </Link>
                  </Text>

                  <Text style={footerLegal}>
                    Commercial Registration {company.cr} · {company.country}
                  </Text>
                  <Text style={footerCopyright}>
                    © {year} {company.legalName}. All rights reserved.
                  </Text>
                </Section>
              </>
            )}
          </Container>
        </Section>
      </Body>
    </Html>
  );
}

const bodyStyle = {
  margin: 0,
  padding: 0,
  backgroundColor: colors.background,
  fontFamily: fonts.sans,
};

const outer = {
  backgroundColor: colors.background,
  padding: "40px 0",
};

const card = {
  width: "560px",
  maxWidth: "100%",
  backgroundColor: colors.background,
  border: `1px solid ${colors.border}`,
};

const header = {
  padding: "30px 40px 24px",
  borderBottom: `1px solid ${colors.border}`,
};

const logoImg = {
  display: "block",
  border: 0,
  outline: "none",
  textDecoration: "none",
  // Alt-text styling for image-blocked clients: reads as the brand wordmark.
  color: colors.ink,
  fontFamily: fonts.serif,
  fontSize: "24px",
  letterSpacing: "4px",
};

const content = {
  padding: "36px 40px",
};

const rule = {
  borderColor: colors.border,
  margin: 0,
};

const footerSection = {
  padding: "28px 40px 30px",
  textAlign: "center",
};

const monogramImg = {
  display: "block",
  margin: "0 auto 14px",
  border: 0,
  outline: "none",
};

const footerCompany = {
  margin: "0 0 2px",
  fontFamily: fonts.sans,
  fontSize: "12px",
  fontWeight: "500",
  color: colors.ink,
  letterSpacing: "0.2px",
};

const footerTagline = {
  margin: "0 0 16px",
  fontFamily: fonts.serif,
  fontStyle: "italic",
  fontSize: "14px",
  color: colors.muted,
};

const footerLinks = {
  margin: "0 0 14px",
  fontFamily: fonts.sans,
  fontSize: "12px",
  color: colors.muted,
};

const footerLink = {
  color: colors.muted,
  textDecoration: "underline",
};

const footerDot = {
  color: colors.softAccent || colors.border,
  padding: "0 8px",
};

const footerLegal = {
  margin: "0 0 4px",
  fontFamily: fonts.sans,
  fontSize: "11px",
  color: colors.muted,
  letterSpacing: "0.2px",
};

const footerCopyright = {
  margin: 0,
  fontFamily: fonts.sans,
  fontSize: "11px",
  color: colors.muted,
  lineHeight: "16px",
};
