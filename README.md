# WikiPois

WikiPois is a server to provide Wikipedia POIs on the map.

## API

HTTP Request:

```http
GET /?bbox=<minX>,<minY>,<maxX>,<maxY>&scale=<scale>
```

HTTP Response:
```json
[
  [wikipedia, wikidata, lng, lat, id, name],
  ...
]
```


## Prepare data

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

Updating data (run daily for Geofabrik):

```bash
PGPASSWORD=wiki osm2pgsql-replication update -d wiki -U wiki -H localhost -- -a -s --flat-nodes flat_nodes --cache 0 -O flex -S wiki.lua
```

Running server:

```bash
deno run --allow-net --allow-env server.ts
```
