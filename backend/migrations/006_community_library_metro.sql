-- Community tour library (v2.10): metro area filter + top-sort index
--
-- Note: is_public, community_rating, and community_rating_count were introduced
-- in migration 003_community_tours.sql. This migration adds the metro_area
-- column used by the public browse endpoint and an index that covers the
-- default "top" sort (is_public, community_rating DESC).

ALTER TABLE tours ADD COLUMN metro_area TEXT;

CREATE INDEX IF NOT EXISTS idx_tours_public_rating
  ON tours(is_public, community_rating DESC, community_rating_count DESC)
  WHERE is_public = 1;

CREATE INDEX IF NOT EXISTS idx_tours_public_metro
  ON tours(is_public, metro_area)
  WHERE is_public = 1;
