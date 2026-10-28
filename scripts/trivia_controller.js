const readline = require('readline');

const SUPABASE_URL = 'https://itfcnurjrnyalauwwdkj.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI';

const GAME_ID = process.argv[2] || 'b6972a5b-b59f-416e-a625-9595fad52241';

async function getTriviaRound() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/MPT_game_trivia_rounds?game_id=eq.${GAME_ID}&select=*`, {
    headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
  });
  const data = await res.json();
  return data && data[0];
}

async function resetTrivia() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_reset_game_trivia`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
      Authorization: `Bearer ${SUPABASE_ANON}`
    },
    body: JSON.stringify({ p_game_id: GAME_ID })
  });
  // Fallback if RPC not yet run in SQL editor
  if (!res.ok) {
    await fetch(`${SUPABASE_URL}/rest/v1/MPT_trivia_winners?game_id=eq.${GAME_ID}`, {
      method: 'DELETE',
      headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
    });
    await fetch(`${SUPABASE_URL}/rest/v1/MPT_trivia_responses?game_id=eq.${GAME_ID}`, {
      method: 'DELETE',
      headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
    });
    await fetch(`${SUPABASE_URL}/rest/v1/MPT_game_trivia_rounds?game_id=eq.${GAME_ID}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        apikey: SUPABASE_ANON,
        Authorization: `Bearer ${SUPABASE_ANON}`
      },
      body: JSON.stringify({ status: 'ACTIVE', current_question_index: 0, completed_at: null })
    });
  }
}

async function advanceToQuestion(nextIdx) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_advance_trivia_question`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
      Authorization: `Bearer ${SUPABASE_ANON}`
    },
    body: JSON.stringify({ p_game_id: GAME_ID, p_next_index: nextIdx })
  });
  // Fallback if RPC not yet run in SQL editor
  if (!res.ok) {
    await fetch(`${SUPABASE_URL}/rest/v1/MPT_game_trivia_rounds?game_id=eq.${GAME_ID}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        apikey: SUPABASE_ANON,
        Authorization: `Bearer ${SUPABASE_ANON}`
      },
      body: JSON.stringify({ current_question_index: nextIdx, status: 'ACTIVE' })
    });
  }
}

async function finalizeTrivia() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_finalize_game_trivia`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
      Authorization: `Bearer ${SUPABASE_ANON}`
    },
    body: JSON.stringify({ p_game_id: GAME_ID })
  });
  return res.ok;
}

async function getWinners() {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/MPT_trivia_winners?game_id=eq.${GAME_ID}&order=rank.asc&select=*`, {
    headers: { apikey: SUPABASE_ANON, Authorization: `Bearer ${SUPABASE_ANON}` }
  });
  return res.json();
}

async function main() {
  console.log(`=====================================================`);
  console.log(`🎮 DABHOUSIE RECALL TRIVIA MANUAL/AUTO CONTROLLER`);
  console.log(`Target Game ID: ${GAME_ID}`);
  console.log(`=====================================================`);

  console.log('🔄 Resetting Trivia round to fresh ACTIVE state (Question 1)...');
  await resetTrivia();

  const round = await getTriviaRound();
  if (!round) {
    console.error('No trivia round found for game:', GAME_ID);
    process.exit(1);
  }

  const questions = round.questions || [];
  const total = questions.length;
  let curIdx = 0;

  console.log(`Total Questions: ${total}`);
  console.log(`Active Question: #1/${total}: "${questions[0]?.question}"`);

  const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout
  });

  const promptUser = () => {
    if (curIdx < total - 1) {
      rl.question(`\n[PRESS ENTER] to advance to Question #${curIdx + 2}/${total} (or type 'auto' to auto-advance every 15s): `, async (ans) => {
        if (ans.trim().toLowerCase() === 'auto') {
          console.log('\n🚀 Starting Auto-Advancer (15 seconds per question)...');
          for (let i = curIdx + 1; i < total; i++) {
            console.log(`⏳ Waiting 15s for current question...`);
            await new Promise(r => setTimeout(r, 15000));
            console.log(`➡️ Advancing to Question #${i + 1}/${total}: "${questions[i].question}"`);
            await advanceToQuestion(i);
          }
          console.log('\n⏳ Waiting 15s for final question responses...');
          await new Promise(r => setTimeout(r, 15000));
          console.log('🏁 Finalizing Trivia...');
          await finalizeTrivia();
          const winners = await getWinners();
          console.log('\n🏆 TRIVIA WINNERS PODIUM:', winners);
          rl.close();
          return;
        }

        curIdx++;
        console.log(`\n➡️ Advancing to Question #${curIdx + 1}/${total}: "${questions[curIdx].question}"`);
        await advanceToQuestion(curIdx);
        promptUser();
      });
    } else {
      rl.question(`\n[PRESS ENTER] to FINALIZE Trivia Round and calculate official Podium: `, async () => {
        console.log('\n🏁 Finalizing Trivia Round...');
        await finalizeTrivia();
        const winners = await getWinners();
        console.log(`
=====================================================
🏆 DABHOUSIE RECALL TRIVIA PODIUM
=====================================================`);
        if (winners && winners.length > 0) {
          winners.forEach(w => {
            const medal = w.rank === 1 ? '🥇' : (w.rank === 2 ? '🥈' : '🥉');
            console.log(`  ${medal} Rank ${w.rank}: ${w.user_name} (${w.title}) — ${w.total_score} pts`);
          });
        } else {
          console.log('No winner records found.');
        }
        rl.close();
      });
    }
  };

  promptUser();
}

main().catch(console.error);
