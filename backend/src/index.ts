import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import path from 'path';
import cardsRouter from './routes/cards';
import compsRouter from './routes/comps';
import wishlistRouter from './routes/wishlist';
import ebayRouter from './routes/ebay';
import cardsightRouter from './routes/cardsight';
import gradingRouter from './routes/grading';
import { startScheduler } from './jobs/scheduler';

dotenv.config();

// Warn on startup if required env vars are missing
const REQUIRED_ENV = ['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY', 'CARDSIGHT_API_KEY'];
for (const key of REQUIRED_ENV) {
  if (!process.env[key]) console.warn(`[startup] WARNING: environment variable ${key} is not set`);
}

const app = express();
const PORT = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

app.use('/api/cards', cardsRouter);
app.use('/api/comps', compsRouter);
app.use('/api/wishlist', wishlistRouter);
app.use('/api/ebay', ebayRouter);
app.use('/api/cardsight', cardsightRouter);
app.use('/api/grading', gradingRouter);

app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// Serve Angular app in production
const frontendDist = path.join(__dirname, '../../frontend/dist/frontend/browser');
app.use(express.static(frontendDist));
app.get('*', (_req, res) => {
  res.sendFile(path.join(frontendDist, 'index.html'));
});

startScheduler();

app.listen(PORT, () => console.log(`Server running on port ${PORT}`));

export default app;
