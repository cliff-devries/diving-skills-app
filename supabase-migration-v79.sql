-- ============================================================
-- Migration v79 — DiveManager VTO (Vision/Traction Organizer)
-- Run once in the Supabase SQL editor. Safe to re-run. Requires v53.
--
-- One row per club. Content stored as JSONB so each VTO section
-- (core values, core focus, 10-year target, etc.) can evolve without
-- further migrations. Coaches read and write; divers/parents have no access.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.vto_data (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content     JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_by  UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Only one VTO row ever (the club's). Enforce with a single-row constraint.
CREATE UNIQUE INDEX IF NOT EXISTS idx_vto_data_singleton ON public.vto_data ((TRUE));

ALTER TABLE public.vto_data ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.vto_data FROM anon;

DROP POLICY IF EXISTS "vto_data: coach select" ON public.vto_data;
DROP POLICY IF EXISTS "vto_data: coach insert" ON public.vto_data;
DROP POLICY IF EXISTS "vto_data: coach update" ON public.vto_data;
CREATE POLICY "vto_data: coach select" ON public.vto_data
  FOR SELECT TO authenticated USING (public.crm_is_coach());
CREATE POLICY "vto_data: coach insert" ON public.vto_data
  FOR INSERT TO authenticated WITH CHECK (public.crm_is_coach());
CREATE POLICY "vto_data: coach update" ON public.vto_data
  FOR UPDATE TO authenticated USING (public.crm_is_coach()) WITH CHECK (public.crm_is_coach());

GRANT SELECT, INSERT, UPDATE ON public.vto_data TO authenticated;


-- Upsert helper: merges the supplied patch into the existing content JSONB.
-- Called from manager.html as a coach-authed RPC.
CREATE OR REPLACE FUNCTION public.vto_upsert(p_patch JSONB)
RETURNS JSONB
LANGUAGE plpgsql SECURITY INVOKER SET search_path = public AS $$
DECLARE
  v_row public.vto_data%ROWTYPE;
BEGIN
  IF NOT public.crm_is_coach() THEN
    RAISE EXCEPTION 'Only coaches can edit the VTO';
  END IF;

  SELECT * INTO v_row FROM public.vto_data LIMIT 1;

  IF NOT FOUND THEN
    INSERT INTO public.vto_data (content, updated_by)
    VALUES (p_patch, auth.uid())
    RETURNING * INTO v_row;
  ELSE
    UPDATE public.vto_data
    SET content    = v_row.content || p_patch,
        updated_by = auth.uid(),
        updated_at = NOW()
    WHERE id = v_row.id
    RETURNING * INTO v_row;
  END IF;

  RETURN v_row.content;
END;
$$;
REVOKE ALL ON FUNCTION public.vto_upsert(JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.vto_upsert(JSONB) TO authenticated;
