-- Individual community ratings
CREATE TABLE IF NOT EXISTS community_ratings (
  id TEXT PRIMARY KEY,
  tour_id TEXT NOT NULL REFERENCES tours(id) ON DELETE CASCADE,
  user_id TEXT NOT NULL,
  rating INTEGER NOT NULL CHECK(rating >= 1 AND rating <= 5),
  review TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(tour_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_community_ratings_tour ON community_ratings(tour_id);
