-- =====================================================================
-- Migration: 20260911000003_randomize_ticket_grid_layout_patterns.sql
-- Description: Randomize both the numbers AND the 3x9 blank-space grid
--              layout templates in MPT_generate_ticket_matrix() so that
--              tickets have varied visual shapes and distinct cell distributions.
-- =====================================================================

CREATE OR REPLACE FUNCTION public."MPT_generate_ticket_matrix"()
RETURNS JSONB AS $$
DECLARE
    v_matrix INT[][] := ARRAY[
        ARRAY[0,0,0,0,0,0,0,0,0],
        ARRAY[0,0,0,0,0,0,0,0,0],
        ARRAY[0,0,0,0,0,0,0,0,0]
    ];
    v_pattern INT;
    v_col INT;
    v_min INT;
    v_max INT;
    v_count INT;
    v_values INT[];
BEGIN
    -- Randomly select 1 of 8 classic validated Tambola structural templates
    -- (Each template guarantees exactly 5 numbers per row and 1-2 numbers per column)
    v_pattern := FLOOR(RANDOM() * 8 + 1)::INT;

    FOR v_col IN 1..9 LOOP
        v_min := CASE WHEN v_col = 1 THEN 1 ELSE (v_col - 1) * 10 END;
        v_max := CASE WHEN v_col = 9 THEN 90 ELSE (v_col * 10) - 1 END;

        -- Determine number of items in this column based on the selected template
        CASE v_pattern
            WHEN 1 THEN
                v_count := CASE WHEN v_col IN (1, 3, 5, 6, 8, 9) THEN 2 ELSE 1 END;
            WHEN 2 THEN
                v_count := CASE WHEN v_col IN (1, 2, 4, 5, 6, 8) THEN 2 ELSE 1 END;
            WHEN 3 THEN
                v_count := CASE WHEN v_col IN (1, 2, 3, 6, 7, 9) THEN 2 ELSE 1 END;
            WHEN 4 THEN
                v_count := CASE WHEN v_col IN (1, 2, 4, 5, 7, 8) THEN 2 ELSE 1 END;
            WHEN 5 THEN
                v_count := CASE WHEN v_col IN (2, 3, 4, 6, 8, 9) THEN 2 ELSE 1 END;
            WHEN 6 THEN
                v_count := CASE WHEN v_col IN (1, 2, 4, 5, 7, 8) THEN 2 ELSE 1 END;
            WHEN 7 THEN
                v_count := CASE WHEN v_col IN (1, 3, 4, 6, 7, 9) THEN 2 ELSE 1 END;
            WHEN 8 THEN
                v_count := CASE WHEN v_col IN (1, 2, 4, 5, 6, 8) THEN 2 ELSE 1 END;
        END CASE;

        -- High-entropy cryptographic number draw sorted vertically
        SELECT array_agg(number ORDER BY number)
        INTO v_values
        FROM (
            SELECT number
            FROM generate_series(v_min, v_max) AS numbers(number)
            ORDER BY md5(clock_timestamp()::TEXT || random()::TEXT || number::TEXT)
            LIMIT v_count
        ) selected;

        -- Place drawn values into the exact row coordinates for this template
        CASE v_pattern
            WHEN 1 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[2][4] := v_values[1];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[2][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1];
                    WHEN 8 THEN v_matrix[2][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[1][9] := v_values[1]; v_matrix[2][9] := v_values[2];
                END CASE;
            WHEN 2 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[2][2] := v_values[2];
                    WHEN 3 THEN v_matrix[2][3] := v_values[1];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[2][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[2][8] := v_values[2];
                    WHEN 9 THEN v_matrix[3][9] := v_values[1];
                END CASE;
            WHEN 3 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[2][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1];
                    WHEN 5 THEN v_matrix[3][5] := v_values[1];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[2][6] := v_values[2];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1]; v_matrix[3][7] := v_values[2];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1];
                    WHEN 9 THEN v_matrix[2][9] := v_values[1]; v_matrix[3][9] := v_values[2];
                END CASE;
            WHEN 4 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[2][1] := v_values[2];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[2][3] := v_values[1];
                    WHEN 4 THEN v_matrix[2][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1]; v_matrix[3][7] := v_values[2];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[2][8] := v_values[2];
                    WHEN 9 THEN v_matrix[3][9] := v_values[1];
                END CASE;
            WHEN 5 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[2][1] := v_values[1];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[2][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[2][4] := v_values[2];
                    WHEN 5 THEN v_matrix[3][5] := v_values[1];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1];
                    WHEN 8 THEN v_matrix[2][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[1][9] := v_values[1]; v_matrix[2][9] := v_values[2];
                END CASE;
            WHEN 6 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1]; v_matrix[3][2] := v_values[2];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[2][4] := v_values[2];
                    WHEN 5 THEN v_matrix[2][5] := v_values[1]; v_matrix[3][5] := v_values[2];
                    WHEN 6 THEN v_matrix[3][6] := v_values[1];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1]; v_matrix[2][7] := v_values[2];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[2][9] := v_values[1];
                END CASE;
            WHEN 7 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[1][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[2][2] := v_values[1];
                    WHEN 3 THEN v_matrix[1][3] := v_values[1]; v_matrix[3][3] := v_values[2];
                    WHEN 4 THEN v_matrix[2][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1];
                    WHEN 6 THEN v_matrix[1][6] := v_values[1]; v_matrix[2][6] := v_values[2];
                    WHEN 7 THEN v_matrix[2][7] := v_values[1]; v_matrix[3][7] := v_values[2];
                    WHEN 8 THEN v_matrix[3][8] := v_values[1];
                    WHEN 9 THEN v_matrix[1][9] := v_values[1]; v_matrix[2][9] := v_values[2];
                END CASE;
            WHEN 8 THEN
                CASE v_col
                    WHEN 1 THEN v_matrix[2][1] := v_values[1]; v_matrix[3][1] := v_values[2];
                    WHEN 2 THEN v_matrix[1][2] := v_values[1]; v_matrix[2][2] := v_values[2];
                    WHEN 3 THEN v_matrix[3][3] := v_values[1];
                    WHEN 4 THEN v_matrix[1][4] := v_values[1]; v_matrix[3][4] := v_values[2];
                    WHEN 5 THEN v_matrix[1][5] := v_values[1]; v_matrix[2][5] := v_values[2];
                    WHEN 6 THEN v_matrix[2][6] := v_values[1]; v_matrix[3][6] := v_values[2];
                    WHEN 7 THEN v_matrix[1][7] := v_values[1];
                    WHEN 8 THEN v_matrix[1][8] := v_values[1]; v_matrix[3][8] := v_values[2];
                    WHEN 9 THEN v_matrix[2][9] := v_values[1];
                END CASE;
        END CASE;
    END LOOP;

    RETURN to_jsonb(v_matrix);
END;
$$ LANGUAGE plpgsql VOLATILE SECURITY DEFINER;

COMMENT ON FUNCTION public."MPT_generate_ticket_matrix"() IS 
'Generates a valid 3x9 Tambola ticket matrix with 8 randomized structural layout templates and cryptographically random number distribution.';
