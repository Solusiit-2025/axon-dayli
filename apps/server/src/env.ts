import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  DATABASE_URL: z.string().min(1, 'DATABASE_URL wajib diisi'),
  JWT_SECRET: z.string().min(16, 'JWT_SECRET minimal 16 karakter'),
  ACCESS_TOKEN_TTL: z.string().default('15m'),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  PORT: z.coerce.number().int().positive().default(4000),
  HOST: z.string().default('0.0.0.0'),
  CORS_ORIGIN: z.string().default('*'),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  AXON_WEB_BASE_URL: z.string().default('https://axon.solusiit.id'),
  AXON_WEB_API_KEY: z.string().optional(),
});

export const env = schema.parse(process.env);
