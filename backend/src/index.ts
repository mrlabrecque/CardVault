import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import cardsRouter from './routes/cards';
import compsRouter from './routes/comps';
import wishlistRouter from './routes/wishlist';
import ebayRouter from './routes/ebay';
import { startAlertJob } from './jobs/alertJob';

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.use('/api/cards', cardsRouter);
app.use('/api/comps', compsRouter);
app.use('/api/wishlist', wishlistRouter);
app.use('/api/ebay', ebayRouter);

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// Serve Angular app in production
const frontendDist = path.join(__dirname, '../../frontend/dist/frontend/browser');
app.use(express.static(frontendDist));
app.get('*', (_req, res) => {
  res.sendFile(path.join(frontendDist, 'index.html'));
});

startAlertJob();

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));

export default app;
