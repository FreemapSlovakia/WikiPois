# WikiPois

WikiPois is a server to provide Wikipedia POIs on the map.

## Prepare data

```
sudo su - postgres
createuser wiki
createdb -E UTF8 -O wiki wiki
psql -d wiki -c "CREATE EXTENSION postgis;"
exit
PGPASSWORD=wiki osm2pgsql -d wiki -U wiki -H localhost -c -s --flat-nodes flat_nodes --cache 0 -O flex -S wiki.lua planet.osm.pbf
```

```
PGPASSWORD=wiki osm2pgsql-replication init -d wiki -U wiki -H localhost --osm-file planet.osm.pbf
```

```
PGPASSWORD=wiki osm2pgsql-replication update -d wiki -U wiki -H localhost -- -a -s --flat-nodes flat_nodes --cache 0 -O flex -S wiki.lua
```
