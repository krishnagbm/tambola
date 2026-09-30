# Gravity Agent Prompt: Recent Games Visibility Incident and Follow-Up

## Assignment

Work in `C:\dev\Tambola`. First inspect the current repository and deployment configuration, then implement a safe separation of the public Recent Games API from the payment gateway backend. Preserve current production behavior until a replacement endpoint is verified. Do not deploy to production, alter production data, or change payment configuration without explicit approval.

The immediate production symptom has been resolved manually. This task is the durable architecture and correctness follow-up, not an emergency data repair.

## Product Goal

Cancelled games must not appear on the public Recent Games page. The owner also needs an administrative way to hide an otherwise completed game from that page. A completed game with no winners is not necessarily cancelled; do not label it cancelled unless its actual status says so.

Payment checkout and Stripe webhook processing are business-critical. Changes to Recent Games must not require rebuilding or deploying payment functions.

## What Happened

1. The public page is `web/recent-games.html`. When it loads, it posts `{ "action": "get_recent_games" }` to the API URL configured in that page.
2. That URL is currently `https://6uvajebdr2.execute-api.us-east-2.amazonaws.com/Prod/email/private-party`. Despite its path, it is not an email-only operation. API Gateway routes it to `backend/functions/send_email.py`, whose handler dispatches multiple actions, including `get_recent_games` and several email-related operations.
3. Public visibility filtering was added to the `get_recent_games` handler and the static prerender script. A Supabase migration added `is_publicly_visible` to `MPT_games` and `MPT_game_archives`, and updated archive behavior. The game cancellation repository operation sets the live game's visibility to false.
4. Amplify successfully built and deployed the frontend, but Amplify's `amplify.yml` only builds Flutter web artifacts. It does not deploy the SAM backend Lambda. Consequently, the live API initially returned archived records without `status` or visibility fields; those records continued to appear.
5. A separate `sam deploy` was required to publish the Lambda change. However, the SAM template `template.yaml` defines checkout, Stripe webhook, and email/API functions in one stack (`dabhousie-payments-backend`). The changeset therefore modified payment Lambdas and shared API Gateway resources as well. This creates unnecessary payment regression risk for a Recent Games-only change.
6. After the backend deployment, the live API returned the three records `6DDDAF`, `1922DD`, and `5E1E5B` as `status: COMPLETED`, `is_publicly_visible: true`, and with zero winners. These were not marked cancelled in the database. The page displayed the text “Game cancelled / ended early without winners” for any record whose `winners_roster` was empty, which was misleading.
7. The owner manually ran SQL setting `is_publicly_visible = FALSE` in both `MPT_games` and `MPT_game_archives` for those three invite codes. The owner confirmed this fixed the public page. Do not repeat or reverse those updates.
8. A separate Flutter web build failure on `main` was fixed in `lib/features/gameplay/screens/player_ticket_screen.dart`; commit `4ec219c` is PR #2 and is now included in `origin/main` at merge commit `8a28c2d`. The optimized `flutter build web --release` passed locally. This build fix is separate from the visibility/API architecture work.

## Relevant Existing Files

- `web/recent-games.html`: public page, initial static cards, client-side API call and rendering.
- `scripts/prerender_recent_games.cjs`: builds static Recent Games markup using the public API.
- `backend/functions/send_email.py`: current multi-action Lambda, including `get_recent_games` and email actions.
- `backend/functions/email_ses.py`: SES email helper used by the current handler.
- `backend/requirements.txt`: current shared Python requirements; SAM build succeeded locally once, while an earlier attempt failed resolving a transitive `multidict` wheel. Docker is not installed in the development environment.
- `template.yaml`: shared SAM stack with `CreateCheckoutFunction`, `StripeWebhookFunction`, and `SendEmailFunction`.
- `samconfig.toml`: current stack name `dabhousie-payments-backend`, region `us-east-2`, production parameter overrides. Treat all parameter values as secrets; do not print or copy them into new files.
- `supabase/migrations/20260929000001_add_public_visibility_controls.sql`: visibility schema and archive function changes.
- `lib/repositories/game_repository.dart`: cancellation updates game status and public visibility.
- `backend/tests/test_recent_games_visibility.py`: existing visibility unit tests.
- `amplify.yml`: frontend build only; does not deploy SAM.

## Required Work

### 1. Map the current contract before editing

Trace the Recent Games page, prerender script, API Gateway route, Lambda action dispatch, Supabase archive schema, migration history, and deployment settings. Verify the currently active API/stack resources from configuration and code; do not infer production state from stale local branches. Avoid reading or exposing credentials.

### 2. Separate public game history from payments

Design and implement a dedicated Recent Games Lambda/API deployment that does not contain, import, package, or update checkout or Stripe webhook functions. Prefer a standalone SAM template/stack and independently scoped Python dependencies/configuration. Give it a descriptive route that is not under `/email/`, for example `/public/recent-games` or `/recent-games`.

Update `web/recent-games.html` and `scripts/prerender_recent_games.cjs` to use the new endpoint consistently. Preserve CORS, response shape, environment configuration, and required public-page behavior. Document the independent build/deploy command and how the endpoint URL is configured. Do not make Amplify deploy the payment stack.

Before implementation, report any endpoint/API Gateway compatibility implications. Avoid replacing the existing shared API or changing payment routes, environment variables, IAM policies, or Stripe settings as part of this work.

### 3. Enforce correct visibility semantics

Apply server-side filtering to archive and live-game fallback records:

- Hide `is_private = true`.
- Hide `is_publicly_visible = false` (including explicit false values; handle absent fields deliberately and safely).
- Hide cancelled and non-public lifecycle statuses.
- Do not treat a completed game with no winners as cancelled.
- Retain visible completed games with zero winners if that is the intended product rule, but render an accurate neutral status such as “No verified winners” rather than “Game cancelled / ended early without winners.”

Ensure the archive function preserves the admin visibility choice and cancellation state on insert/upsert; a later re-archive must not accidentally turn an explicitly hidden record public. Consider nullable/legacy archive state carefully and test it.

### 4. Tests and documentation

Add or update focused tests covering visible completed-with-winners, visible completed-without-winners, cancelled, private, explicitly hidden, missing visibility fields, and fallback live-game records. Add a deployment boundary check or documented manual verification demonstrating that the Recent Games stack has no payment resources.

Document:

- which stack/API owns Recent Games;
- which stack/API owns payments and email;
- exact build/deploy commands for each;
- required Supabase/API environment values without embedding secrets;
- a rollback procedure for the Recent Games endpoint/page;
- production smoke checks and the procedure for administratively hiding a game.

### 5. Validate without touching production

Run relevant unit tests, SAM template validation/build, and the Flutter/web checks only if affected. Inspect the synthesized change set or templates to prove a Recent Games deployment cannot update payment Lambdas or Stripe resources. Do not run `sam deploy`, AWS CLI mutation commands, Supabase writes, or production migrations. Provide a rollout checklist for the owner to execute and wait for approval before any production operation.

## Safety / Scope Constraints

- Do not alter payment behavior, Stripe secrets, checkout routes, webhook routes, SES policies, or payment database logic.
- Do not reset, switch destructively, or clean the dirty worktree. Preserve all user changes, including the currently untracked documentation/tests and deleted `test/New folder/sourcecode.txt` if present.
- Do not commit or push unless explicitly asked.
- Do not deploy or run SQL against production.
- Avoid broad refactors. Keep payment functions byte-for-byte/configuration-equivalent if separation can be achieved without modifying them.
- Never assume an empty `winners_roster` means a cancelled game.

## Acceptance Criteria

1. The public API filters genuinely cancelled, private, and admin-hidden records server-side.
2. The three manually hidden invite codes (`6DDDAF`, `1922DD`, `5E1E5B`) remain hidden; no SQL is re-run to expose them.
3. A completed zero-winner game is not falsely described as cancelled.
4. Recent Games builds and deploys independently of checkout and Stripe webhook functions.
5. Payment API routes and configuration remain unchanged.
6. Tests cover the visibility rules and pass.
7. Documentation includes safe, separate deployment and rollback steps.
8. No production AWS/Supabase changes are performed by the agent.

## Final Report Requested

Return a concise summary of architecture changes, files changed, tests/builds run, how separation from payments was verified, deployment commands for owner review, and any remaining manual production steps. Explicitly state that production was not modified.
