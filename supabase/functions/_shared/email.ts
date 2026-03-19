
import { createTransport } from "npm:nodemailer@6.9.7";

/** Strip HTML tags and decode common entities to produce a plain-text version */
function htmlToPlainText(html: string): string {
    return html
        .replace(/<br\s*\/?>/gi, '\n')
        .replace(/<\/tr>/gi, '\n')
        .replace(/<\/p>/gi, '\n\n')
        .replace(/<\/h[1-6]>/gi, '\n\n')
        .replace(/<\/div>/gi, '\n')
        .replace(/<\/td>/gi, '  ')
        .replace(/<style[^>]*>[\s\S]*?<\/style>/gi, '')
        .replace(/<[^>]+>/g, '')
        .replace(/&amp;/g, '&')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"')
        .replace(/&#39;/g, "'")
        .replace(/&nbsp;/g, ' ')
        .replace(/\n{3,}/g, '\n\n')
        .trim();
}

/** Wrap HTML body content in a proper HTML5 document for better deliverability */
function wrapHtmlDocument(body: string): string {
    return `<!DOCTYPE html>
<html lang="es" xmlns="http://www.w3.org/1999/xhtml">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
  <title>Imagine Access</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f4f4;">
${body}
</body>
</html>`;
}

export const sendEmail = async (
    to: string,
    subject: string,
    html: string,
    attachments?: Array<Record<string, unknown>>,
) => {
    const SMTP_HOST = Deno.env.get("SMTP_HOST") || "smtp.hostinger.com";
    const SMTP_DEBUG = (Deno.env.get("SMTP_DEBUG") ?? "false").toLowerCase() === "true";

    let SMTP_PORT = Number.parseInt(Deno.env.get("SMTP_PORT") ?? "587", 10);
    if (!Number.isFinite(SMTP_PORT) || SMTP_PORT <= 0) {
        SMTP_PORT = 587;
    }

    const SMTP_USER = Deno.env.get("SMTP_USER");
    const SMTP_PASS = Deno.env.get("SMTP_PASS");

    if (!SMTP_USER) {
        throw new Error("SMTP_USER is missing in Edge Function secrets");
    }
    if (!SMTP_PASS) {
        throw new Error("SMTP_PASS is missing in Edge Function secrets");
    }

    console.log(`Configuring Shared SMTP Transport: Host=${SMTP_HOST} Port=${SMTP_PORT}`);

    const transporter = createTransport({
        host: SMTP_HOST,
        port: SMTP_PORT,
        secure: SMTP_PORT === 465,
        auth: {
            user: SMTP_USER,
            pass: SMTP_PASS,
        },
        logger: SMTP_DEBUG,
        debug: SMTP_DEBUG,
        connectionTimeout: 10000,
        greetingTimeout: 5000,
        socketTimeout: 10000,
        tls: {
            minVersion: 'TLSv1.2'
        }
    });

    console.log(`Sending email via ${SMTP_HOST}...`);

    try {
        const fromDomain = SMTP_USER.split('@')[1] || 'imaginelab.shop';
        const info = await transporter.sendMail({
            from: `"Imagine Access" <${SMTP_USER}>`,
            to,
            subject,
            html: wrapHtmlDocument(html),
            text: htmlToPlainText(html),
            messageId: `<${crypto.randomUUID()}@${fromDomain}>`,
            attachments,
        });
        console.log("Email sent: %s", info.messageId);
        return info;
    } catch (error) {
        console.error("Error sending email:", error);
        throw error;
    }
};
