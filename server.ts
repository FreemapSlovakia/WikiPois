import { Client } from "https://deno.land/x/postgres@v0.16.1/mod.ts";

const client = new Client({
  user: "wiki",
  database: "wiki",
  hostname: "localhost",
  password: "wiki",
  port: 5432,
  tls: {
    enforce: false,
  },
});

await client.connect();

await client.queryArray`
  CREATE MATERIALIZED VIEW IF NOT EXISTS wiki_mv AS
  SELECT
    wikipedia,
    wikidata,
    ST_Collect(ST_SimplifyPreserveTopology(geom, 10)) AS coll,
    MIN(type || id) AS id,
    MAX(COALESCE(name, '')) AS name,
    SUM(area) AS sarea,
    SUM(ST_Length(geom)) AS slen
  FROM
    wiki
  GROUP BY wikipedia, wikidata
`;

await client.queryArray(
  "CREATE INDEX IF NOT EXISTS wiki_mv_geom_idx ON wiki_mv using gist(coll)"
);

await client.queryArray(
  "CREATE INDEX IF NOT EXISTS wiki_mv_sarea_idx ON wiki_mv(sarea)"
);

await client.queryArray(
  "CREATE INDEX IF NOT EXISTS wiki_mv_slen_idx ON wiki_mv(slen)"
);

const server = Deno.listen({ port: 8040 });

for (;;) {
  try {
    for await (const conn of server) {
      console.log("Connection opened.");

      try {
        serveHttp(conn);
      } catch (e) {
        console.error(e);
      }

      console.log("Connection closed.");
    }
  } catch (e) {
    console.error(e);
  }
}

async function serveHttp(conn: Deno.Conn) {
  const httpConn = Deno.serveHttp(conn);

  for await (const requestEvent of httpConn) {
    console.log("Request: " + requestEvent.request.url);

    try {
      await handleRequestEvent(requestEvent);
    } catch (e) {
      console.error(e);

      requestEvent.respondWith(new Response(null, { status: 500 }));
    }
  }
}

async function handleRequestEvent(requestEvent: Deno.RequestEvent) {
  const { searchParams } = new URL(requestEvent.request.url);

  const bbox = (searchParams.get("bbox") ?? "")
    .split(",")
    .map((a) => Number(a));

  const scale = Number(searchParams.get("scale"));

  if (bbox.length != 4 || bbox.some((a) => isNaN(a)) || !scale) {
    requestEvent.respondWith(new Response(null, { status: 400 }));

    return;
  }

  const res = await client.queryArray`
    WITH bbox AS (SELECT ST_Transform(ST_MakeEnvelope(${bbox[0]}, ${bbox[1]}, ${bbox[2]}, ${bbox[3]}, 4326), 3857))
    SELECT
      wikipedia,
      wikidata,
      ST_AsText(
        ST_Transform(
          ST_PointOnSurface(
            ST_ClipByBox2D(
              coll,
              (SELECT * FROM bbox)
            )
          ),
          4326
        )
      ) AS point,
      NULL,
      id,
      name
    FROM
      wiki_mv
    WHERE
      coll && (SELECT * FROM bbox) AND
      sarea < ST_Area((SELECT * FROM bbox)) AND
      (
        ${scale} < 100.0 OR
        sarea > ${scale} * 50000.0 OR
        slen > sqrt(${scale}) * 1000.0
      )
    ORDER BY
      id DESC
    LIMIT 1000
  `;

  for (const row of res.rows) {
    const m = /^POINT\(([^ ]*) (.*)\)$/.exec(String(row[2]));

    if (m) {
      row[2] = Number(m[1]);
      row[3] = Number(m[2]);
    }
  }

  requestEvent.respondWith(
    new Response(
      JSON.stringify(res.rows.filter((row) => row[2] !== "POINT EMPTY")),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      }
    )
  );
}

// await client.end();
