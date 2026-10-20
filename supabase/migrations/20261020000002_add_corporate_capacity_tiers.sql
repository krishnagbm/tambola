-- =====================================================================
-- Migration: 20261020000002_add_corporate_capacity_tiers.sql
-- Description: Expand capacity tiers table to support Corporate & Enterprise
--              custom group games (251–500, 501–1000, 1001–2500 participants)
-- =====================================================================

INSERT INTO public."MPT_capacity_tiers" (id, name, min_players, max_players, credits_required, display_order, is_active)
VALUES
    ('38978e8f-f5f3-40b3-80e2-9c31c2b04d02', 'Corporate League (251–500 Players)', 251, 500, 500, 7, true),
    ('c7b9ff1e-3ba0-4a8d-98c4-e0360335391b', 'Enterprise Gala (501–1000 Players)', 501, 1000, 1000, 8, true),
    ('2a7955e1-6932-43b1-84b1-0675d182db26', 'Coliseum / Global (1001–2500 Players)', 1001, 2500, 2500, 9, true)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    min_players = EXCLUDED.min_players,
    max_players = EXCLUDED.max_players,
    credits_required = EXCLUDED.credits_required,
    display_order = EXCLUDED.display_order,
    is_active = EXCLUDED.is_active;
