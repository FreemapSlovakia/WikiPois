# WikiPois

WikiPois is a server to provide Wikipedia POIs on the map.

## API

HTTP Request:

```http
GET /?bbox=<minX>,<minY>,<maxX>,<maxY>&scale=<scale>
```

Parameter `scale` is roughly computed as area of bounding box divided by number of pixels (`const scale = turf.area(turf.bboxPolygon(bbox))  / (window.innerHeight * window.innerWidth);`).

HTTP Response:
```json
[
  [wikipedia, wikidata, lng, lat, id, name],
  ...
]
```

## Database preparation

Create database:

```bash
sudo su - postgres
createuser wiki
createdb -E UTF8 -O wiki wiki
psql -d wiki -c "CREATE EXTENSION postgis;"
exit
```

Import OSM data (you can also use eg. extracts from Geofabrik):

```bash
PGPASSWORD=wiki osm2pgsql -d wiki -U wiki -H localhost -c -s --flat-nodes flat_nodes --cache 0 -O flex -S wiki.lua planet.osm.pbf
```

Preparation for updates:

```bash
PGPASSWORD=wiki osm2pgsql-replication init -d wiki -U wiki -H localhost --osm-file planet.osm.pbf
```

Running server:

```bash
deno run --allow-net --allow-env server.ts
```

## Updating database

Run daily for Geofabrik extracts.

```crontab
1 4 * * * /path/to/update.sh
```
