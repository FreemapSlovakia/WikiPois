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

const server = Deno.listen({ port: 8040 });

for await (const conn of server) {
  serveHttp(conn);
}

async function serveHttp(conn: Deno.Conn) {
  const httpConn = Deno.serveHttp(conn);

  for await (const requestEvent of httpConn) {
    const bbox = (
      new URL(requestEvent.request.url).searchParams.get("bbox") ?? ""
    )
      .split(",")
      .map((a) => Number(a));

    if (bbox.length != 4 || bbox.some((a) => isNaN(a))) {
      requestEvent.respondWith(new Response(null, { status: 400 }));

      continue;
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
      FROM (
        SELECT
          wikipedia,
          wikidata,
          ST_Collect(geom) AS coll,
          MIN(type || id) AS id,
          MAX(COALESCE(name, '')) AS name,
          SUM(area) AS sarea,
          SUM(ST_Length(geom)) AS slen
        FROM
          wiki
        WHERE
          geom && (SELECT * FROM bbox) AND
          area < ST_Area((SELECT * FROM bbox))
        GROUP BY wikipedia, wikidata
      ) foo
      WHERE
        ST_Area((SELECT * FROM bbox)) < 200000000 OR
        sarea > ST_Area((SELECT * FROM bbox)) / 200 OR
        slen > sqrt(ST_Area((SELECT * FROM bbox)))
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
      new Response(JSON.stringify(res.rows.filter(row => row[2] !== 'POINT EMPTY')), {
        status: 200,
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*",
        },
      })
    );
  }
}

// await client.end();
