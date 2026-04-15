import cron from 'node-cron';
import sql from '../db/db';
import { searchSoldListings } from '../services/ebay.service';
import { sendPriceAlert } from '../services/alerts.service';

export function startAlertJob() {
  // Run every hour
  cron.schedule('0 * * * *', async () => {
    console.log('Running price alert job...');

    const items = await sql`
      SELECT w.*, u.email
      FROM wishlist w
      JOIN auth.users u ON u.id = w.user_id
      WHERE w.alert_status = 'active'`;

    for (const item of items) {
      const listings = await searchSoldListings(JSON.stringify(item.card_details));
      // TODO: Filter active (not sold) listings below target_price and send alerts
      console.log(`Checked alerts for wishlist item ${item.id}:`, listings.items.length, 'results');
    }
  });
}
