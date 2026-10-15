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

Create the materialized view the server reads:

```bash
PGPASSWORD=wiki psql -U wiki -h localhost wiki -f schema.sql
```

Preparation for updates, with daily diffs to match the daily schedule below. Freemap imports the Geofabrik Europe extract:

```bash
PGPASSWORD=wiki osm2pgsql-replication init -d wiki -U wiki -H localhost --osm-file europe.osm.pbf --server https://download.geofabrik.de/europe-updates
```

For the planet, use `--server https://planet.openstreetmap.org/replication/day`.

Running server:

```bash
deno task start
```

It reads the standard `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER` and `PGPASSWORD` variables (defaulting to `wiki` on `localhost`) and listens on `127.0.0.1:$PORT` (default `8040`).

## Updating database

`update.sh` applies replication diffs, refreshes `wiki_mv` (concurrently, so the server keeps answering) and mails the result to admins via Mailgun. Mail settings go to `update.conf` (see `update.conf.example`).

It runs daily from a systemd timer:

```bash
cp update.conf.example update.conf && chmod 600 update.conf # then fill it in
sudo cp systemd/* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wikipois.service wikipois-update.timer
```

Run an update by hand with `sudo systemctl start wikipois-update`; its log is in `journalctl -u wikipois-update`.
