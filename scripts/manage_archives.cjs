#!/usr/bin/env node

/**
 * manage_archives.cjs
 * 
 * Utility script for DabHousie game data archiving and 30-day purge management.
 * 
 * Usage:
 *   node scripts/manage_archives.cjs --list
 *   node scripts/manage_archives.cjs --archive-all
 *   node scripts/manage_archives.cjs --purge 30
 */

const fs = require('fs');
const path = require('path');

// Read environment
let SUPABASE_URL = process.env.SUPABASE_URL || 'https://itfcnurjrnyalauwwdkj.supabase.co';
let SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SERVICE_KEY && fs.existsSync(path.resolve('.env'))) {
  const env = fs.readFileSync(path.resolve('.env'), 'utf-8').split('\n').reduce((acc, line) => {
    const idx = line.indexOf('=');
    if (idx !== -1) acc[line.slice(0, idx).trim()] = line.slice(idx + 1).trim();
    return acc;
  }, {});
  SUPABASE_URL = env.SUPABASE_URL || SUPABASE_URL;
  SERVICE_KEY = env.SUPABASE_SERVICE_ROLE_KEY;
}

if (!SERVICE_KEY) {
  SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczNjA5MTE2MSwiZXhwIjoyMDUxNjY3MTYxfQ.E_i0aJ03tvmzuUq1_gi_Q1JsgG67VlrkwWVuYKsH8d8';
}

const args = process.argv.slice(2);
const command = args[0] || '--list';

async function listArchives() {
  console.log('Fetching live archives and completed games...');
  
  // 1. Fetch archives
  const aRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_game_archives?select=*&order=completed_at.desc.nullslast`, {
    headers: { 'apikey': SERVICE_KEY, 'Authorization': `Bearer ${SERVICE_KEY}` }
  });
  const archives = await aRes.json();
  console.log(`\n======================================================`);
  console.log(` 🏆 DabHousie Hall of Fame Archives (${archives.length} Records)`);
  console.log(`======================================================`);
  for (const a of archives) {
    console.log(`• [${a.invite_code}] "${a.name}"`);
    console.log(`  Players: ${a.player_count} | Calls: ${a.numbers_called_count} | Duration: ${a.duration_seconds}s | Completed: ${a.completed_at || a.created_at}`);
    if (a.organization_name) {
      console.log(`  🏢 Organization: ${a.organization_name} (Logo: ${a.organization_logo_approved ? 'Approved' : 'Unapproved/None'})`);
    }
    if (a.winners_roster && a.winners_roster.length > 0) {
      a.winners_roster.forEach(w => {
        console.log(`    🏅 ${w.prize_type.padEnd(12)}: ${w.winner_name || 'Player'} (Ref: ${w.claim_reference || 'N/A'})`);
      });
    }
  }

  // 2. Fetch live games count
  const gRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?select=id,invite_code,name,status,created_at`, {
    headers: { 'apikey': SERVICE_KEY, 'Authorization': `Bearer ${SERVICE_KEY}` }
  });
  const games = await gRes.json();
  console.log(`\n======================================================`);
  console.log(` 🎮 Active / Concluded Live Games in DB (${games.length} Records)`);
  console.log(`======================================================`);
  for (const g of games) {
    console.log(`• [${g.status}] Code: ${g.invite_code} | "${g.name}" | Created: ${g.created_at}`);
  }
}

async function archiveAll() {
  console.log('Running MPT_backfill_all_archives RPC...');
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_backfill_all_archives`, {
    method: 'POST',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({})
  });
  const result = await res.json();
  console.log('Backfill result:', result);
  await listArchives();
}

async function purgeOld(days = 30) {
  console.log(`Running MPT_purge_old_games(${days} days) RPC...`);
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_purge_old_games`, {
    method: 'POST',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ p_older_than_days: parseInt(days, 10) })
  });
  const result = await res.json();
  console.log('Purge result:', result);
  await listArchives();
}

async function approveBrand(inviteCode) {
  if (!inviteCode) {
    console.error('Error: Please specify invite code. Example: node scripts/manage_archives.cjs --approve-brand ABC123');
    process.exit(1);
  }
  const code = inviteCode.toUpperCase().trim();
  console.log(`[Admin Override] Approving corporate branding for game ${code}...`);

  const now = new Date().toISOString();

  // 1. Update MPT_games
  const gRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?invite_code=eq.${code}`, {
    method: 'PATCH',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    },
    body: JSON.stringify({
      organization_logo_approved: true,
      brand_approved_at: now,
      brand_approver_ip: 'admin-cli-override'
    })
  });
  const updatedGames = await gRes.json();

  // 2. Update MPT_game_archives if exists
  await fetch(`${SUPABASE_URL}/rest/v1/MPT_game_archives?invite_code=eq.${code}`, {
    method: 'PATCH',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      organization_logo_approved: true
    })
  });

  if (Array.isArray(updatedGames) && updatedGames.length > 0) {
    const g = updatedGames[0];
    console.log(`✅ Successfully APPROVED branding for "${g.name}" (${g.invite_code})`);
    console.log(`   Organization: ${g.organization_name}`);
    console.log(`   Logo URL: ${g.organization_logo_url}`);
  } else {
    console.log(`⚠️ No active game found with invite code ${code}. Checked archives.`);
  }
}

async function revokeBrand(inviteCode) {
  if (!inviteCode) {
    console.error('Error: Please specify invite code. Example: node scripts/manage_archives.cjs --revoke-brand ABC123');
    process.exit(1);
  }
  const code = inviteCode.toUpperCase().trim();
  console.log(`[Admin Override] REVOKING corporate branding for game ${code}...`);

  // 1. Update MPT_games
  const gRes = await fetch(`${SUPABASE_URL}/rest/v1/MPT_games?invite_code=eq.${code}`, {
    method: 'PATCH',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation'
    },
    body: JSON.stringify({
      organization_logo_approved: false,
      brand_approved_at: null,
      brand_approver_ip: 'admin-cli-revocation'
    })
  });
  const updatedGames = await gRes.json();

  // 2. Update MPT_game_archives if exists
  await fetch(`${SUPABASE_URL}/rest/v1/MPT_game_archives?invite_code=eq.${code}`, {
    method: 'PATCH',
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      organization_logo_approved: false
    })
  });

  if (Array.isArray(updatedGames) && updatedGames.length > 0) {
    const g = updatedGames[0];
    console.log(`🚫 Successfully REVOKED branding for "${g.name}" (${g.invite_code})`);
  } else {
    console.log(`⚠️ No active game found with invite code ${code}. Checked archives.`);
  }
}

async function main() {
  if (command === '--archive-all') {
    await archiveAll();
  } else if (command === '--purge') {
    const days = args[1] || 30;
    await purgeOld(days);
  } else if (command === '--approve-brand') {
    await approveBrand(args[1]);
  } else if (command === '--revoke-brand') {
    await revokeBrand(args[1]);
  } else {
    await listArchives();
  }
}

main().catch(console.error);
