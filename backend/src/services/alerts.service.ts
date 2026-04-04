import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransport({
  host: process.env.SMTP_HOST,
  port: Number(process.env.SMTP_PORT) || 587,
  auth: {
    user: process.env.SMTP_USER,
    pass: process.env.SMTP_PASS,
  },
});

export async function sendPriceAlert(to: string, cardDetails: object, listingUrl: string, price: number) {
  await transporter.sendMail({
    from: process.env.SMTP_USER,
    to,
    subject: 'Card Vault: Price Alert Triggered',
    text: `A card on your wishlist is available below your target price of $${price}.\n\nListing: ${listingUrl}\n\nCard: ${JSON.stringify(cardDetails)}`,
  });
}
