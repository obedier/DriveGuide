-- v2.11 Featured Tours — system-owned curated tours
--
-- Dedicated "wAIpoint Featured" system user owns pre-generated, professionally
-- curated tours that surface at the top of the public library (2.10 sort=top).
--
-- Surface mechanism: add an `is_featured` boolean on tours. The public-list
-- endpoint orders `is_featured DESC` first in the `top` sort so featured tours
-- always lead the Top list regardless of the community_rating. This keeps
-- featured content discoverable even before real users rate them.

INSERT OR IGNORE INTO users (id, firebase_uid, email, display_name, preferred_language)
VALUES (
  'waipoint-featured-system',
  'waipoint-featured-system',
  'featured@waipoint.app',
  'wAIpoint Featured',
  'en'
);

ALTER TABLE tours ADD COLUMN is_featured INTEGER NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_tours_public_featured
  ON tours(is_public, is_featured DESC, community_rating DESC)
  WHERE is_public = 1;
