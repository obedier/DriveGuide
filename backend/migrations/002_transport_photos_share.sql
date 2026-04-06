-- Transport mode, speed, custom prompt, sharing, photos

ALTER TABLE tours ADD COLUMN transport_mode TEXT NOT NULL DEFAULT 'car';
ALTER TABLE tours ADD COLUMN speed_mph REAL;
ALTER TABLE tours ADD COLUMN custom_prompt TEXT;
ALTER TABLE tours ADD COLUMN share_id TEXT;

ALTER TABLE tour_stops ADD COLUMN photo_url TEXT;

CREATE UNIQUE INDEX idx_tours_share_id ON tours(share_id) WHERE share_id IS NOT NULL;
