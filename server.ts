import { Pool } from "@db/postgres";

const env = (name: string, fallback: string) => Deno.env.get(name) ?? fallback;

const pool = new Pool(
  {
    hostname: env("PGHOST", "localhost"),
    port: Number(env("PGPORT", "5432")),
    database: env("PGDATABASE", "wiki"),
    user: env("PGUSER", "wiki"),
    password: env("PGPASSWORD", "wiki"),
    tls: { enabled: false },
  },
  5,
  true,
);

Deno.serve(
  { hostname: "127.0.0.1", port: Number(env("PORT", "8040")) },
  async (request) => {
    try {
      return await handleRequest(request);
    } catch (e) {
      console.error(request.url, e);

      return new Response(null, { status: 500 });
    }
  },
);

async function handleRequest(request: Request): Promise<Response> {
  const { searchParams } = new URL(request.url);

  const bbox = (searchParams.get("bbox") ?? "").split(",").map(Number);

  const scale = Number(searchParams.get("scale"));

  if (
    bbox.length !== 4 || !bbox.every(Number.isFinite) ||
    !Number.isFinite(scale) || scale <= 0
  ) {
    return new Response(null, { status: 400 });
  }

  const [west, south, east, north] = bbox;

  using client = await pool.connect();

  // The order mirrors the scale filter, so when the limit cuts in, the
  // features that would survive zooming out the longest are kept.
  const { rows } = await client.queryArray`
    WITH
      bbox AS (
        SELECT ST_Transform(ST_MakeEnvelope(${west}, ${south}, ${east}, ${north}, 4326), 3857) AS geom
      ),
      pois AS (
        SELECT
          wikipedia,
          wikidata,
          ST_Transform(ST_PointOnSurface(ST_ClipByBox2D(coll, bbox.geom)), 4326) AS point,
          id,
          name
        FROM wiki_mv, bbox
        WHERE
          coll && bbox.geom AND
          sarea < ST_Area(bbox.geom) AND
          (
            ${scale} < 100.0 OR
            sarea > ${scale} * 50000.0 OR
            slen > sqrt(${scale}) * 1000.0
          )
        ORDER BY GREATEST(sarea / 50000.0, slen * slen / 1000000.0) DESC, id
        LIMIT 1000
      )
    SELECT wikipedia, wikidata, ST_X(point), ST_Y(point), id, name
    FROM pois
    WHERE NOT ST_IsEmpty(point)
  `;

  // The driver decodes float8 as a string.
  return Response.json(
    rows.map(([wikipedia, wikidata, lng, lat, id, name]) => [
      wikipedia,
      wikidata,
      Number(lng),
      Number(lat),
      id,
      name,
    ]),
  );
}
