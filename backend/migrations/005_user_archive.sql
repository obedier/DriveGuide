-- Add archive support for user tours
ALTER TABLE tours ADD COLUMN is_archived INTEGER DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_tours_user_archive ON tours(user_id, is_archived);
