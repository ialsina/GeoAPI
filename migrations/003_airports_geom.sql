-- Airport point geometry for spatial nearby queries.
ALTER TABLE airports
    ADD COLUMN IF NOT EXISTS geom GEOMETRY(Point, 4326);

UPDATE airports
SET geom = ST_SetSRID(ST_MakePoint(longitude, latitude), 4326)
WHERE latitude IS NOT NULL
  AND longitude IS NOT NULL
  AND geom IS NULL;

CREATE INDEX IF NOT EXISTS airports_geom_idx ON airports USING GIST (geom);
