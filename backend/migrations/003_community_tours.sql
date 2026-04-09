-- Community tours: public sharing
ALTER TABLE tours ADD COLUMN is_public INTEGER NOT NULL DEFAULT 0;
ALTER TABLE tours ADD COLUMN community_rating REAL;
ALTER TABLE tours ADD COLUMN community_rating_count INTEGER NOT NULL DEFAULT 0;

CREATE INDEX idx_tours_community ON tours(is_public, center_lat, center_lng) WHERE is_public = 1;
