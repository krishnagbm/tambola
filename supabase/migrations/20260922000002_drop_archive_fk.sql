-- Drop foreign key cascade constraint on MPT_game_archives so archives persist after raw game rows are purged
ALTER TABLE public."MPT_game_archives" DROP CONSTRAINT IF EXISTS "MPT_game_archives_game_id_fkey";
