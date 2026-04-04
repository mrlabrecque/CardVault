import { Request, Response, NextFunction } from 'express';
import { supabase } from '../db/supabase';

export interface AuthRequest extends Request {
  userId?: string;
}

// Use this type inside route handlers where requireAuth is guaranteed to have run
export interface AuthenticatedRequest extends Request {
  userId: string;
}

export async function requireAuth(req: AuthRequest, res: Response, next: NextFunction) {
  const token = req.headers.authorization?.replace('Bearer ', '');
  if (!token) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    res.status(401).json({ error: 'Invalid token' });
    return;
  }

  req.userId = user.id;
  next();
}
