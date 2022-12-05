#!/bin/bash
set -e
export PGPASSWORD=wiki
cd /home/martin/WikiPois
osm2pgsql-replication update -d wiki -U wiki -H localhost -- -a -s --flat-nodes /fm/sdata/WikiPois/flat_nodes --cache 0 -O flex -S wiki.lua
echo "REFRESH MATERIALIZED VIEW wiki_mv;" | psql -U wiki wiki -h localhost
