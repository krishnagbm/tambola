-- =====================================================================
-- Migration: 20261025000001_drop_mpt_submit_claim_jsonb_overload.sql
-- Description:
--   Drops the ambiguous JSONB overload of MPT_submit_claim so PostgREST
--   does not throw PGRST203 (HTTP 300 Multiple Choices).
--   The canonical INT[] overload handles claim submissions for all clients.
-- =====================================================================

DROP FUNCTION IF EXISTS public."MPT_submit_claim"(uuid, text, jsonb, text) CASCADE;
