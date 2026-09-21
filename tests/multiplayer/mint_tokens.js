import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const AUTH_CACHE_FILE = path.join(__dirname, '.auth_cache.json');

const SUPABASE_URL = 'https://itfcnurjrnyalauwwdkj.supabase.co';

const REAL_NAMES = [
  'Aarav', 'Priya', 'Rohan', 'Maya', 'Liam', 'Sophia', 'Noah', 'Ananya',
  'Kabir', 'Emma', 'Oliver', 'Diya', 'Carlos', 'Chloe', 'Arjun', 'Sneha',
  'Vikram', 'Aisha', 'Ethan', 'Mia', 'Rahul', 'Zara', 'Siddharth', 'Elena',
  'Kavya', 'Leo', 'Tara', 'Aditya', 'Meera', 'Sam', 'Rhea', 'Lucas',
  'Dev', 'Anika', 'Kiran', 'Nisha', 'Neil', 'Pooja', 'Tanvi', 'Varun',
  'Isha', 'Reyansh', 'Saanvi', 'Vivaan', 'Advait', 'Myra', 'Dhruv', 'Kiara',
  'Armaan', 'Navya', 'Ishaan', 'Avani', 'Advik', 'Anvi', 'Rudra', 'Sara',
  'Reyan', 'Siya', 'Pranav', 'Ahana', 'Vihaan', 'Shanaya', 'Shaurya', 'Ira',
  'Atharv', 'Anaya', 'Kush', 'Navi', 'Veer', 'Mira', 'Samar', 'Avni',
  'Devansh', 'Kritika', 'Rishi', 'Shruti', 'Yash', 'Riddhi', 'Ayush', 'Siddhi',
  'Jai', 'Bhavya', 'Harsh', 'Trisha', 'Tejas', 'Ishani', 'Kunal', 'Dia',
  'Manish', 'Ritika', 'Naveen', 'Nandini', 'Raj', 'Simran', 'Akash', 'Shreya'
];

const AVATARS = [
  'avatar_lion', 'avatar_tiger', 'avatar_bear', 'avatar_eagle',
  'avatar_fox', 'avatar_wolf', 'avatar_owl', 'avatar_panda',
  'avatar_deer', 'avatar_koala'
];

function base64UrlEncode(str) {
  return Buffer.from(str)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function generateDeterministicUUID(id) {
  const hash = crypto.createHash('sha256').update(`tambola-synthetic-player-v1-${id}`).digest('hex');
  return [
    hash.substring(0, 8),
    hash.substring(8, 12),
    '4' + hash.substring(13, 16), // version 4 UUID
    'a' + hash.substring(17, 20), // variant
    hash.substring(20, 32),
  ].join('-');
}

function signJwt(payload, secret) {
  const header = {
    alg: 'HS256',
    typ: 'JWT'
  };

  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signatureInput = `${encodedHeader}.${encodedPayload}`;

  const signature = crypto
    .createHmac('sha256', secret)
    .update(signatureInput)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');

  return `${signatureInput}.${signature}`;
}

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

async function main() {
  const args = process.argv.slice(2);
  let targetCount = 250;
  let jwtSecret = process.env.SUPABASE_JWT_SECRET || null;

  for (let i = 0; i < args.length; i++) {
    if (args[i].startsWith('--count=')) {
      targetCount = parseInt(args[i].split('=')[1], 10) || 250;
    } else if (args[i] === '--count' && args[i + 1]) {
      targetCount = parseInt(args[++i], 10) || 250;
    } else if (args[i].startsWith('--secret=')) {
      jwtSecret = args[i].split('=')[1].trim();
    } else if (args[i] === '--secret' && args[i + 1]) {
      jwtSecret = args[++i].trim();
    }
  }

  console.log('===================================================================');
  console.log('⚡ DABHOUSIE HIGH-SPEED OFFLINE JWT TOKEN MINTER');
  console.log('===================================================================');
  console.log(`Target Count     : ${targetCount} synthetic accounts`);
  console.log(`Cache Destination: ${AUTH_CACHE_FILE}`);
  console.log('===================================================================\n');

  if (!jwtSecret) {
    console.error('❌ ERROR: Missing Supabase JWT Secret!');
    console.log('\n📖 How to get your JWT Secret in 10 seconds:');
    console.log('1. Go to your Supabase Dashboard: https://supabase.com/dashboard/project/itfcnurjrnyalauwwdkj');
    console.log('2. Click on Project Settings ⚙️ (bottom left) ➔ API');
    console.log('3. Under "JWT Settings", copy the "JWT Secret" string.');
    console.log('\nThen run:');
    console.log('  npm run test:mint -- --secret=<YOUR_JWT_SECRET> --count=250\n');
    process.exit(1);
  }

  const cache = loadCache();
  const startTime = Date.now();
  const now = Math.floor(Date.now() / 1000);
  // Token valid for 10 years (315,360,000 seconds)
  const exp = now + 315360000;

  for (let i = 1; i <= targetCount; i++) {
    const name = REAL_NAMES[(i - 1) % REAL_NAMES.length];
    const avatar = AVATARS[(i - 1) % AVATARS.length];
    const userId = generateDeterministicUUID(i);
    const sessionId = crypto.randomUUID();

    const payload = {
      iss: `${SUPABASE_URL}/auth/v1`,
      sub: userId,
      aud: 'authenticated',
      exp: exp,
      iat: now,
      email: '',
      phone: '',
      app_metadata: {},
      user_metadata: {
        avatar: avatar,
        full_name: name,
      },
      role: 'authenticated',
      aal: 'aal1',
      amr: [
        {
          method: 'anonymous',
          timestamp: now,
        }
      ],
      session_id: sessionId,
      is_anonymous: true,
    };

    const token = signJwt(payload, jwtSecret);

    cache[i] = {
      playerId: i,
      name: name,
      avatar: avatar,
      userId: userId,
      accessToken: token,
      refreshToken: crypto.randomBytes(16).toString('hex'),
      expiresAt: exp,
    };
  }

  saveCache(cache);
  const elapsedMs = Date.now() - startTime;

  console.log(`✅ Successfully minted ${targetCount} offline authenticated tokens in ${elapsedMs}ms!`);
  console.log(`💾 Saved to: ${AUTH_CACHE_FILE}`);
  console.log(`🎉 You can now instantly run 50, 100, or 250 players with zero rate limits.\n`);
}

main().catch(console.error);
