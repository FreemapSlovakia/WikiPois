local wiki_table = osm2pgsql.define_table({
  name = 'wiki',
  ids = { type = 'any', id_column = 'id', type_column = 'type' },
  columns = {
    { column = 'wikipedia', type = 'text' },
    { column = 'wikidata', type = 'text' },
    { column = 'area', type = 'real', not_null = true },
    { column = 'name', type = 'text' },
    { column = 'geom', type = 'geometry', not_null = true }
  }
})

local node_table = {};

function osm2pgsql.process_node(object)
  if object.tags.place then
    node_table[object.id] = { point = object:as_point(), name = object.tags.name }
  end

  if not(object.tags.wikipedia or object.tags.wikidata) then
    return
  end

  wiki_table:insert({
    wikipedia = object.tags.wikipedia,
    wikidata = object.tags.wikidata,
    name = object.tags.name,
    geom = object:as_point(),
    area = 0
  })
end

function osm2pgsql.process_way(object)
  if not(object.tags.wikipedia or object.tags.wikidata) then
    return
  end

  if object.is_closed and object.tags.area ~= 'no' and not ((object.tags.highway or object.tags.barrier) and object.tags.area ~= 'yes') then
    wiki_table:insert({
      wikipedia = object.tags.wikipedia,
      wikidata = object.tags.wikidata,
      name = object.tags.name,
      geom = object:as_polygon(),
      area = 0
    })
  else
    wiki_table:insert({
      wikipedia = object.tags.wikipedia,
      wikidata = object.tags.wikidata,
      name = object.tags.name,
      geom = object:as_linestring():simplify(0.0001),
      area = 0
    })
  end
end

function osm2pgsql.process_relation(object)
  if (not(object.tags.wikipedia or object.tags.wikidata)) then
    return
  end

  local type = object.tags.type;

  -- if admin area is represented by a node (is admin_centre and has same name) then for geometry use that node, but keep the area
  for _, member in ipairs(object.members) do
    if member.role == 'admin_centre' and member.type == 'n' then -- TODO only if name equals; otherwise it may be a capital for a country
      local node = node_table[member.ref]

      if node and node.name and node.name == object.tags.name then
        wiki_table:insert({
          wikipedia = object.tags.wikipedia,
          wikidata = object.tags.wikidata,
          name = object.tags.name,
          geom = node.point,
          area = (type == 'multipolygon' or type == 'boundary') and object:as_multipolygon():transform(3857):area() or 0
        })

        return
      end
    end
  end

  if type == 'multipolygon' or type == 'boundary' then
    wiki_table:insert({
      wikipedia = object.tags.wikipedia,
      wikidata = object.tags.wikidata,
      name = object.tags.name,
      geom = object:as_multipolygon(),
      area = object:as_multipolygon():transform(3857):area()
    })
  elseif type == 'waterway' or type == 'route' or type == 'superroute' or type == 'route_master' or type == 'network' then
    wiki_table:insert({
      wikipedia = object.tags.wikipedia,
      wikidata = object.tags.wikidata,
      name = object.tags.name,
      geom = object:as_multilinestring(),
      area = 0
    })
  else
    -- print(object.tags.type or "??")
    -- associatedStreet, bridge, group, region, site, treaty

    wiki_table:insert({
      wikipedia = object.tags.wikipedia,
      wikidata = object.tags.wikidata,
      name = object.tags.name,
      geom = object:as_geometrycollection(),
      area = 0
    })
  end
end
