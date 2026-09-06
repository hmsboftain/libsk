/**
 * Production render entry. esbuild bundles this (+ React + react-dom/server +
 * all templates) into emails/dist/render.cjs, which index.js requires at send
 * time. This keeps the deployed Cloud Functions runtime plain CommonJS — no JSX
 * transform needed in production.
 *
 * Each render fn returns { html, text }: the text part is the multipart
 * text/plain alternative, which improves deliverability and spam scoring.
 */
import { render } from "@react-email/render";
import OrderConfirmation from "./OrderConfirmation.jsx";
import Welcome from "./Welcome.jsx";
import PasswordReset from "./PasswordReset.jsx";

async function renderBoth(element) {
  const [html, text] = await Promise.all([
    render(element, { pretty: false }),
    render(element, { plainText: true }),
  ]);
  return { html, text };
}

export function renderOrderConfirmation(props) {
  return renderBoth(<OrderConfirmation {...props} />);
}

export function renderWelcome(props) {
  return renderBoth(<Welcome {...props} />);
}

export function renderPasswordReset(props) {
  return renderBoth(<PasswordReset {...props} />);
}
