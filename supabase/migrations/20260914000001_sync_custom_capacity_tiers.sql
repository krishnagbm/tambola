-- =====================================================================
-- Migration: 20260914000001_sync_custom_capacity_tiers.sql
-- Description: Sets the exact 6 capacity tiers and credit costs:
--              1. Family Pack (1–5 Players): Always Free (0 Credits)
--              2. Small Party (6–15 Players): 15 Credits
--              3. Medium Group (16–25 Players): 25 Credits
--              4. Large Group (26–50 Players): 50 Credits
--              5. Club Event (51–100 Players): 100 Credits
--              6. Mega Event (101–250 Players): 250 Credits
-- =====================================================================

TRUNCATE TABLE public."MPT_capacity_tiers" CASCADE;

INSERT INTO public."MPT_capacity_tiers" (name, min_players, max_players, credits_required, display_order, is_active)
VALUES
    ('Family Pack (1–5 Players)', 1, 5, 0, 1, true),
    ('Small Party (6–15 Players)', 6, 15, 15, 2, true),
    ('Medium Group (16–25 Players)', 16, 25, 25, 3, true),
    ('Large Group (26–50 Players)', 26, 50, 50, 4, true),
    ('Club Event (51–100 Players)', 51, 100, 100, 5, true),
    ('Mega Event (101–250 Players)', 101, 250, 250, 6, true);
