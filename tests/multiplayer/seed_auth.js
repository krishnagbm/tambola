import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const AUTH_CACHE_FILE = path.join(__dirname, '.auth_cache.json');

const SUPABASE_URL = 'https://itfcnurjrnyalauwwdkj.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI';

const REAL_NAMES = [
  'Aarav', 'Priya', 'Rohan', 'Maya', 'Liam', 'Sophia', 'Noah', 'Ananya',
  'Kabir', 'Emma', 'Oliver', 'Diya', 'Carlos', 'Chloe', 'Arjun', 'Sneha',
  'Vikram', 'Aisha', 'Ethan', 'Mia', 'Rahul', 'Zara', 'Siddharth', 'Elena',
  'Kavya', 'Leo', 'Tara', 'Aditya', 'Meera', 'Sam', 'Rhea', 'Lucas',
  'Dev', 'Anika', 'Kiran', 'Nisha', 'Neil', 'Pooja', 'Tanvi', 'Varun',
  'Isha', 'Reyansh', 'Saanvi', 'Vivaan', 'Advait', 'Myra', 'Dhruv', 'Kiara',
  'Armaan', 'Navya'
];

function loadCache() {
  try {
    if (fs.existsSync(AUTH_CACHE_FILE)) {
      return JSON.parse(fs.readFileSync(AUTH_CACHE_FILE, 'utf8'));
    }
  } catch (_) {}
  return {};
}

function saveCache(cache) {
  try {
    fs.writeFileSync(AUTH_CACHE_FILE, JSON.stringify(cache, null, 2), 'utf8');
  } catch (err) {
    console.error('Failed to save cache:', err.message);
  }
}

async function performSignup(playerId, name, avatar = 'avatar_lion') {
  let retries = 30;
  let delay = 2500;

  while (retries > 0) {
    try {
      const res = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON,
          'Authorization': `Bearer ${SUPABASE_ANON}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          data: {
            full_name: name,
            avatar: avatar,
          },
        }),
      });

      if (res.status === 429) {
        retries--;
        process.stdout.write(`\n⏳ Player ${playerId} (${name}) rate limited (HTTP 429). Waiting ${Math.round(delay / 1000)}s... `);
        await new Promise(r => setTimeout(r, delay + Math.random() * 500));
        delay = Math.min(delay * 1.5, 30000);
        continue;
      }

      if (!res.ok) {
        const errText = await res.text().catch(() => '');
        throw new Error(`HTTP ${res.status}: ${errText}`);
      }

      const authRes = await res.json();
      if (authRes?.access_token && authRes?.user?.id) {
        const now = Math.floor(Date.now() / 1000);
        return {
          playerId,
          name,
          avatar,
          userId: authRes.user.id,
          accessToken: authRes.access_token,
          refreshToken: authRes.refresh_token,
          expiresAt: authRes.expires_at || (now + (authRes.expires_in || 3600)),
        };
      }
      throw new Error('No token in response');
    } catch (err) {
      retries--;
      if (retries === 0) throw err;
      await new Promise(r => setTimeout(r, delay));
      delay = Math.min(delay * 1.5, 30000);
    }
  }
  throw new Error('Max retries exceeded');
}

async function main() {
  const args = process.argv.slice(2);
  let targetCount = 50;
  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--count=')) targetCount = parseInt(args[i].split('=')[1], 10) || 50;
    else if (args[i] === '--count' && args[i + 1]) targetCount = parseInt(args[++i], 10) || 50;
  }

  console.log(`===================================================================`);
  console.log(`🔐 DABHOUSIE MULTIPLAYER AUTH POOL GENERATOR`);
  console.log(`===================================================================`);
  console.log(`Target Pool Size : ${targetCount} synthetic accounts`);
  console.log(`Cache Location   : ${AUTH_CACHE_FILE}`);
  console.log(`===================================================================\n`);

  const cache = loadCache();
  const existingCount = Object.keys(cache).length;
  console.log(`Currently cached accounts: ${existingCount}/${targetCount}`);

  if (existingCount >= targetCount) {
    console.log(`✅ Auth pool already contains ${existingCount} accounts! No new accounts needed.`);
    return;
  }

  for (let i = 1; i <= targetCount; i++) {
    if (cache[i] && cache[i].userId && cache[i].accessToken) {
      console.log(`[Slot ${i}/${targetCount}] Player ${i} (${cache[i].name}) -> Already cached (UUID: ${cache[i].userId.substring(0, 8)}...)`);
      continue;
    }

    const name = REAL_NAMES[(i - 1) % REAL_NAMES.length];
    process.stdout.write(`[Slot ${i}/${targetCount}] Creating account for Player ${i} (${name})... `);

    try {
      const session = await performSignup(i, name);
      cache[i] = session;
      saveCache(cache);
      console.log(`✅ OK (UUID: ${session.userId.substring(0, 8)}...)`);
      // Gentle throttle to avoid triggering rate limit bursts
      await new Promise(r => setTimeout(r, 1200));
    } catch (err) {
      console.log(`❌ FAILED: ${err.message}`);
    }
  }

  const finalCount = Object.keys(cache).length;
  console.log(`\n===================================================================`);
  console.log(`🎉 Auth Pool Generation Complete: ${finalCount}/${targetCount} accounts ready!`);
  console.log(`===================================================================\n`);
}

main().catch(console.error);
