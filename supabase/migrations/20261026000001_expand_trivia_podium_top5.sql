-- ==============================================================================
-- Migration: Expand DabHousie Recall Trivia Podium to Top 5
-- Date: 2026-10-26
-- Description: Awards titles and podium rankings to top 5 players based on trivia score & speed
-- ==============================================================================

CREATE OR REPLACE FUNCTION public."MPT_finalize_game_trivia"(
    p_game_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_titles TEXT[] := ARRAY[
        'Observation Champion 🥇',
        'Recall Runner-Up 🥈',
        'Focus Master 🥉',
        'Sharp Mind 🎖️',
        'Memory Ace 🌟'
    ];
    v_rank INT := 1;
    v_row RECORD;
    v_winners JSONB := '[]'::jsonb;
BEGIN
    -- Clear previous winners if re-finalizing
    DELETE FROM public."MPT_trivia_winners" WHERE game_id = p_game_id;

    -- Aggregate Leaderboard (Top 5)
    FOR v_row IN
        SELECT 
            user_id,
            COALESCE(MAX(user_name), 'Player') as user_name,
            MAX(user_avatar) as user_avatar,
            SUM(score_points) as total_score,
            COUNT(*) FILTER (WHERE is_correct = true) as correct_count,
            ROUND(AVG(response_time_ms))::INT as avg_time_ms
        FROM public."MPT_trivia_responses"
        WHERE game_id = p_game_id
        GROUP BY user_id
        ORDER BY total_score DESC, avg_time_ms ASC
        LIMIT 5
    LOOP
        INSERT INTO public."MPT_trivia_winners" (
            game_id,
            user_id,
            user_name,
            user_avatar,
            rank,
            total_score,
            correct_count,
            avg_response_time_ms,
            title
        )
        VALUES (
            p_game_id,
            v_row.user_id,
            v_row.user_name,
            v_row.user_avatar,
            v_rank,
            v_row.total_score,
            v_row.correct_count,
            v_row.avg_time_ms,
            v_titles[v_rank]
        );

        v_winners := v_winners || jsonb_build_object(
            'rank', v_rank,
            'title', v_titles[v_rank],
            'user_name', v_row.user_name,
            'total_score', v_row.total_score,
            'correct_count', v_row.correct_count
        );

        v_rank := v_rank + 1;
    END LOOP;

    -- Update round status to COMPLETED
    UPDATE public."MPT_game_trivia_rounds"
    SET status = 'COMPLETED',
        updated_at = NOW()
    WHERE game_id = p_game_id;

    RETURN jsonb_build_object(
        'success', true,
        'winners_count', v_rank - 1,
        'winners', v_winners
    );
END;
$$;
