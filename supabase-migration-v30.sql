-- ============================================================
-- Migration v30 — Supabase Storage: skill-photos, skill-videos
-- Run once in Supabase SQL editor.
--
-- Creates two public storage buckets and RLS policies:
--   • Authenticated users can read files (public URLs work without auth too)
--   • Only active coaches / super_users can upload and delete files
--
-- If INSERT INTO storage.buckets fails with a permissions error,
-- create the buckets manually in the Supabase dashboard (Storage → New Bucket):
--   name: skill-photos  public: ON  max size: 10 MB
--   name: skill-videos  public: ON  max size: 200 MB
-- Then run only the CREATE POLICY statements below.
-- ============================================================

-- ---- Buckets ----

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'skill-photos', 'skill-photos', true,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'skill-videos', 'skill-videos', true,
  209715200,
  ARRAY['video/mp4', 'video/quicktime', 'video/mov']
)
ON CONFLICT (id) DO NOTHING;

-- ---- RLS: skill-photos ----

CREATE POLICY "Authenticated users can view skill photos"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'skill-photos');

CREATE POLICY "Coaches can upload skill photos"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'skill-photos' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  )
);

CREATE POLICY "Coaches can delete skill photos"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'skill-photos' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  )
);

-- ---- RLS: skill-videos ----

CREATE POLICY "Authenticated users can view skill videos"
ON storage.objects FOR SELECT TO authenticated
USING (bucket_id = 'skill-videos');

CREATE POLICY "Coaches can upload skill videos"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'skill-videos' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  )
);

CREATE POLICY "Coaches can delete skill videos"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'skill-videos' AND
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE auth_user_id = auth.uid()
      AND role IN ('coach', 'super_user')
      AND status = 'active'
  )
);
