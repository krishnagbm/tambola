const SUPABASE_URL = 'https://itfcnurjrnyalauwwdkj.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Iml0ZmNudXJqcm55YWxhdXd3ZGtqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzYwOTExNjEsImV4cCI6MjA1MTY2NzE2MX0.Rjfu9AEmNZJAEUVUDEj6GTC41HZPx1AiiVoMZTBEOOI';
const GAME_ID = 'b6972a5b-b59f-416e-a625-9595fad52241';

async function waitSec(s) {
  return new Promise(resolve => setTimeout(resolve, s * 1000));
}

async function setIndex(idx) {
  await fetch(`${SUPABASE_URL}/rest/v1/MPT_game_trivia_rounds?game_id=eq.${GAME_ID}`, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
      Authorization: `Bearer ${SUPABASE_ANON}`,
      Prefer: 'return=minimal'
    },
    body: JSON.stringify({ current_question_index: idx })
  });
}

async function finalize() {
  await fetch(`${SUPABASE_URL}/rest/v1/rpc/MPT_finalize_game_trivia`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      apikey: SUPABASE_ANON,
      Authorization: `Bearer ${SUPABASE_ANON}`
    },
    body: JSON.stringify({ p_game_id: GAME_ID })
  });
}

async function run() {
  console.log('--- Question 2 is ACTIVE right now (Answer: 72) ---');
  console.log('Giving 20 seconds for Question 2...');
  await waitSec(20);

  console.log('Advancing to Question 3 (Index 2): "Which prize pattern was claimed first in the room?" (Answer: EARLY FIVE)...');
  await setIndex(2);
  console.log('Giving 20 seconds for Question 3...');
  await waitSec(20);

  console.log('Advancing to Question 4 (Index 3): "Who successfully claimed the Top Line prize?" (Answer: Sneha)...');
  await setIndex(3);
  console.log('Giving 22 seconds for Question 4...');
  await waitSec(22);

  console.log('Finalizing Trivia round and generating Official Podium...');
  await finalize();
  console.log('TRIVIA ROUND FINALIZED! PODIUM IS LIVE ON SCREEN!');
}

run().catch(console.error);
