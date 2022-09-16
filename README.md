# WikiPois

WikiPois is a server to provide Wikipedia POIs on the map.

## Prepare data

```
sudo su - postgres
createuser wiki
createdb -E UTF8 -O wiki wiki
psql -d wiki -c "CREATE EXTENSION postgis;"
exit
osm2pgsql -d wiki -U wiki -W -H localhost -c -O flex -S wiki.lua planet.osm.pbf
```
