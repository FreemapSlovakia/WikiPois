-- Run once after the import: psql -U wiki -h localhost wiki -f schema.sql

\set ON_ERROR_STOP on

-- One row per wikipedia/wikidata pair. A boundary is shown at its admin_centre
-- node when the node has the same name, but keeps the boundary's area.
CREATE MATERIALIZED VIEW IF NOT EXISTS wiki_mv AS
SELECT
  w.wikipedia,
  w.wikidata,
  ST_Collect(ST_SimplifyPreserveTopology(COALESCE(p.geom, w.geom), 10)) AS coll,
  MIN(w.type || w.id) AS id,
  MAX(COALESCE(w.name, '')) AS name,
  SUM(COALESCE(ST_Area(w.geom), 0)) AS sarea,
  SUM(ST_Length(COALESCE(p.geom, w.geom))) AS slen
FROM
  wiki w
  LEFT JOIN places p ON p.id = w.admin_centre AND p.name = w.name
WHERE COALESCE(p.geom, w.geom) IS NOT NULL
GROUP BY w.wikipedia, w.wikidata;

-- Required by REFRESH MATERIALIZED VIEW CONCURRENTLY in update.sh.
CREATE UNIQUE INDEX IF NOT EXISTS wiki_mv_id_idx ON wiki_mv (id);

CREATE INDEX IF NOT EXISTS wiki_mv_geom_idx ON wiki_mv USING gist (coll);
CREATE INDEX IF NOT EXISTS wiki_mv_sarea_idx ON wiki_mv (sarea);
CREATE INDEX IF NOT EXISTS wiki_mv_slen_idx ON wiki_mv (slen);
