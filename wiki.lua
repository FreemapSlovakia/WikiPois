-- Geometries are in web mercator (the osm2pgsql default); schema.sql computes
-- areas and lengths from them.

local wiki = osm2pgsql.define_table({
  name = 'wiki',
  ids = { type = 'any', id_column = 'id', type_column = 'type' },
  columns = {
    { column = 'wikipedia', type = 'text' },
    { column = 'wikidata', type = 'text' },
    { column = 'name', type = 'text' },
    { column = 'admin_centre', type = 'int8' },
    -- Null when a relation's geometry can't be built; it may still have an
    -- admin_centre to show it at.
    { column = 'geom', type = 'geometry' },
  },
})

-- Lets schema.sql show a boundary at its admin_centre node. Resolved in SQL
-- because during updates the node is rarely in the same diff as the relation.
local places = osm2pgsql.define_table({
  name = 'places',
  ids = { type = 'node', id_column = 'id' },
  columns = {
    { column = 'name', type = 'text', not_null = true },
    { column = 'geom', type = 'point', not_null = true },
  },
})

local multiline_types = {
  waterway = true,
  route = true,
  superroute = true,
  route_master = true,
  network = true,
}

local function has_wiki(tags)
  return tags.wikipedia or tags.wikidata
end

local function insert(object, geom, admin_centre)
  wiki:insert({
    wikipedia = object.tags.wikipedia,
    wikidata = object.tags.wikidata,
    name = object.tags.name,
    admin_centre = admin_centre,
    geom = geom,
  })
end

function osm2pgsql.process_node(object)
  local tags = object.tags

  if tags.place and tags.name then
    places:insert({ name = tags.name, geom = object:as_point() })
  end

  if has_wiki(tags) then
    insert(object, object:as_point())
  end
end

function osm2pgsql.process_way(object)
  local tags = object.tags

  if not has_wiki(tags) then
    return
  end

  local is_area = object.is_closed
    and tags.area ~= 'no'
    and (tags.area == 'yes' or not (tags.highway or tags.barrier))

  insert(object, is_area and object:as_polygon() or object:as_linestring())
end

function osm2pgsql.process_relation(object)
  local tags = object.tags

  if not has_wiki(tags) then
    return
  end

  local admin_centre

  for _, member in ipairs(object.members) do
    if member.role == 'admin_centre' and member.type == 'n' then
      admin_centre = member.ref
      break
    end
  end

  local geom

  if tags.type == 'multipolygon' or tags.type == 'boundary' then
    geom = object:as_multipolygon()
  elseif multiline_types[tags.type] then
    geom = object:as_multilinestring()
  else
    -- associatedStreet, bridge, group, region, site, treaty, …
    geom = object:as_geometrycollection()
  end

  insert(object, geom, admin_centre)
end
