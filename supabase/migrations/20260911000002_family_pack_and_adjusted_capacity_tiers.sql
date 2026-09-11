-- =====================================================================
-- Migration: 20260911000002_family_pack_and_adjusted_capacity_tiers.sql
-- Description: Update capacity tiers:
--              1. Family Pack (1–5 Players): Always Free (0 Credits)
--              2. Small Party (6–15 Players): 50 Credits
--              3. Standard Event (16–25 Players): 100 Credits
--              4. Large Gala (26–100 Players): 250 Credits
--              5. Mega Event (101–250 Players): 500 Credits
-- =====================================================================

-- Cleanly refresh the capacity tiers table with the updated tiers structure
TRUNCATE TABLE public."MPT_capacity_tiers" CASCADE;

INSERT INTO public."MPT_capacity_tiers" (name, min_players, max_players, credits_required, display_order, is_active)
VALUES
    ('Family Pack (1–5 Players)', 1, 5, 0, 1, true),
    ('Small Party (6–15 Players)', 6, 15, 50, 2, true),
    ('Standard Event (16–25 Players)', 16, 25, 100, 3, true),
    ('Large Gala (26–100 Players)', 26, 100, 250, 4, true),
    ('Mega Event (101–250 Players)', 101, 250, 500, 5, true);
