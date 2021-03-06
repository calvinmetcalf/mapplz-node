geolib = require 'geolib'
csv = require 'fast-csv'

MapPLZ = ->

MapPLZ.standardize = (geo, props) ->
  result = new MapItem
  if typeof geo.lat != "undefined" && typeof geo.lng != "undefined"
    result.lat = geo.lat * 1
    result.lng = geo.lng * 1
  else if geo.path
    result.path = geo.path
  result.properties = props || {}
  result

MapPLZ.prototype.add = (param1, param2, param3, param4) ->
  this.mapitems = [] unless this.mapitems
  this.database = null unless this.database

  callback = (err, items) ->
  callback = param2 if typeof param2 == "function"
  callback = param3 if typeof param3 == "function"
  callback = param4 if typeof param4 == "function"

  # try for lat, lng point
  lat = param1 * 1
  lng = param2 * 1
  unless isNaN(lat) || isNaN(lng)
    pt = MapPLZ.standardize({ lat: lat, lng: lng })
    pt.type = "point"

    if param3 != null
      # allow JSON string of properties
      if typeof param3 == 'string'
        try
          pt.properties = JSON.parse param3
        catch

      if this.isArray param3
        # array
        pt.properties = { property: param3 }
      else if typeof param3 == 'object'
        # object
        for key in Object.keys(param3)
          pt.properties[key] = param3[key]
      else if typeof param3 != 'function'
        # string, number, or other singular property
        pt.properties = { property: param3 }

    this.save pt, callback
    return

  if typeof param1 == 'string'
    # try JSON parse
    try
      param1 = JSON.parse param1
      if this.isGeoJson param1
        result = this.addGeoJson param1, callback
        this.save result, callback if result
        return
    catch
      if param1[param1.length-1] == ')' && (param1.indexOf 'POINT' == 0 || param1.indexOf 'LINESTRING' == 0 || param1.indexOf 'POLYGON' == 0)
        # try WKT
        contents = ''
        if param1.indexOf('POINT') == 0
          contents = param1.replace('POINT', '').replace('(', '').replace(')', '').trim().split(' ').reverse()
        else if param1.indexOf('LINESTRING') == 0
          pts = param1.replace('LINESTRING', '').replace('(', '').replace(')', '').split(',')
          contents = []
          for pt in pts
            contents.push pt.trim().split(' ').reverse()
        else if param1.indexOf('POLYGON') == 0
          pts = param1.replace('POLYGON', '').replace('(', '').replace(')', '').replace('(', '').replace(')', '').split(',')
          contents = []
          for pt in pts
            contents.push pt.trim().split(' ').reverse()

        this.add contents, param2 || callback, callback
        return

      if (param1.indexOf('map') > -1) and (param1.indexOf('plz') > -1)
        # try mapplz code
        this.process_code param1, callback
        return

      else
        # try CSV
        callbacks = 0
        contents = []
        mapstore = this

        records = 0
        finished = false

        csv.fromString(param1, { headers: true })
          .on('record', (data) ->
            records++
            if data.geo || data.geom || data.wkt
              mapstore.add (data.geo || data.geom || data.wkt), data, (err, item) ->
                contents.push item unless err
                callback(err, contents) if finished && contents.length == records
            else
              mapstore.add data, (err, item) ->
                contents.push item unless err
                callback(err, contents) if finished && contents.length == records
          )
          .on('end', ->
            finished = true
            callback(null, contents) if contents.length == records
          )
        return

  if this.isArray param1
    # param1 is an array

    if param1.length >= 2
      lat = param1[0] * 1
      lng = param1[1] * 1
      unless isNaN(lat) || isNaN(lng)
        result = MapPLZ.standardize { lat: lat, lng: lng }
        result.type = 'point'
        for prop in param1.slice(2)
          if typeof prop == 'string'
            try
              prop = JSON.parse prop
            catch
              prop = prop

          if typeof prop == 'object'
            for key in Object.keys(prop)
              result.properties[key] = prop[key]
          else if typeof prop != 'function'
            result.properties = { property: prop }

        this.save result, callback
        return

    if typeof param1[0] == 'object'
      if this.isArray param1[0]
        # param1 contains an array of arrays - probably coordinates
        if this.isArray param1[0][0]
          # polygon
          result = MapPLZ.standardize({ path: param1 })
          result.type = 'polygon'
        else
          # line
          result = MapPLZ.standardize({ path: param1 })
          result.type = 'line'

        if result && param2
          # try JSON parsing
          if typeof param2 == 'string'
            try
              param2 = JSON.parse param2
            catch
              param2 = param2

          if typeof param2 == 'object'
            if this.isArray param2
              result.properties = { property: param2 }
            else
              result.properties = param2
          else if typeof param2 != 'function'
            result.properties = { property: param2 }

        this.save result, callback
        return
      else
        # param1 contains an array of objects to add
        results = []
        for obj in param1
          results.push this.add(obj)
        this.save results, callback
        return


  else if typeof param1 == 'object'
    # regular object
    if param1.lat && param1.lng
      result = MapPLZ.standardize({ lat: param1.lat, lng: param1.lng })
      result.type = "point"
      for key in Object.keys(param1)
        result.properties[key] = param1[key] unless key == 'lat' || key == 'lng'
      this.save result, callback
      return

    else if param1.path
      result = MapPLZ.standardize({ path: param1.path })
      if typeof param1.path[0][0] == 'object'
        result.type = 'polygon'
      else
        result.type = 'line'
      for key in Object.keys(param1)
        result.properties[key] = param1[key] unless key == 'path'

      this.save result, callback
      return

    else if this.isGeoJson param1
      results = this.addGeoJson param1, callback
      this.save results, callback if results
      return

MapPLZ.prototype.count = (query, callback) ->
  if this.database
    this.database.count(query, callback)
  else
    this.query query, (err, results) ->
      callback(err, results.length)

MapPLZ.prototype.embed_html = (callback) ->
  this.query '', (err, results) ->
    embed_code = '<div id="map"></div>\n'
    embed_code += '<link rel="stylesheet" type="text/css" href="http://cdn.leafletjs.com/leaflet-0.7.3/leaflet.css"/>\n'
    embed_code += '<script type="text/javascript" src="http://cdn.leafletjs.com/leaflet-0.7.3/leaflet.js"></script>\n'
    embed_code += '<script type="text/javascript">\n'
    embed_code += 'var map = L.map("map");\n'
    for result in results
      properties = {}
      properties["color"] = result.properties.color if result.properties.color
      properties["opacity"] = result.properties.opacity if typeof(result.properties.opacity) != "undefined"
      properties["fillColor"] = result.properties.fillColor if result.properties.fillColor
      properties["fillOpacity"] = result.properties.fillOpacity if typeof(result.properties.fillOpacity) != "undefined"
      properties["weight"] = result.properties.weight if typeof(result.properties.weight) != "undefined"
      properties["stroke"] = result.properties.stroke if result.properties.stroke

      if result.type == 'point'
        if result.properties.label || result.properties.popup
          embed_code += "L.marker([#{result.lat}, #{result.lng}]).bindPopup('#{result.properties.label || result.properties.popup}').addTo(map);\n"
        else
          embed_code += "L.marker([#{result.lat}, #{result.lng}], { clickable: false }).addTo(map);\n"
      else if result.type == 'line'
        if result.properties.label || result.properties.popup
          properties["clickable"] = true
          embed_code += "L.polyline(#{JSON.stringify(result.path)}, #{properties.to_json}).bindPopup('#{result.properties.label || result.properties.popup}').addTo(map);\n"
        else
          embed_code += "L.polyline(#{JSON.stringify(result.path)}).addTo(map);\n"
      else if result.type == 'polygon'
        if result.properties.label || result.properties.popup
          properties["clickable"] = true
          embed_code += "L.polygon(#{JSON.stringify(result.path)}, #{properties.to_json}).bindPopup('#{result.properties.label || result.properties.popup}').addTo(map);\n"
        else
          embed_code += "L.polygon(#{JSON.stringify(result.path)}).addTo(map);\n"
    embed_code += '</script>\n'
    callback(embed_code)

MapPLZ.prototype.render_html = (callback) ->
  this.embed_html (embed_code) ->
    embed_page = '<!DOCTYPE html>\n<html>\n<head>\n<style>\nhtml, body, #map { width: 100%; height: 100%; padding: 0; margin: 0; }\n</style>\n</head>\n<body>\n'
    embed_page += embed_code
    embed_page += '</body>\n</html>\n'
    callback(embed_page)

MapPLZ.prototype.query = (query, callback) ->
  if this.database
    this.database.query(query, callback)
  else
    if query == null || query == ""
      callback(null, this.mapitems)
    else
      results = []
      for mapitem in this.mapitems
        if mapitem && mapitem.type != "deleted"
          match = true
          for key of query
            match = (mapitem.properties[key] == query[key])
            break unless match
          results.push mapitem if match
      callback(null, results)

MapPLZ.prototype.where = (query, callback) ->
  this.query(query, callback)

MapPLZ.prototype.near = (neargeo, count, callback) ->
  nearpt = neargeo
  if this.isArray(neargeo)
    nearpt = new MapItem
    nearpt.type = "point"
    nearpt.lat = neargeo[0]
    nearpt.lng = neargeo[1]
  else
    if typeof neargeo == 'string'
      neargeo = JSON.parse(neargeo)
    unless typeof neargeo.lat == "undefined" && typeof neargeo.lng == "undefined"
      nearpt = this.addGeoJson(neargeo)

  if this.database
    this.database.near(nearpt, count, callback)
  else
    this.query "", (err, items) ->
      centerpts = []
      for item in items
        center = item.center()
        centerpts.push { latitude: center.lat, longitude: center.lng }
      centerpts = geolib.orderByDistance({ latitude: nearpt.lat, longitude: nearpt.lng }, centerpts)
      for pt, p in centerpts
        centerpts[p] = items[p]
        break if p >= count
      callback(null, centerpts.slice(0, count))

MapPLZ.prototype.inside = (withingeo, callback) ->
  withinpoly = withingeo
  if this.isArray(withingeo)
    withinpoly = new MapItem
    withinpoly.type = "polygon"
    withinpoly.path = withingeo
  else
    if typeof withingeo == 'string'
      withingeo = JSON.parse(withingeo)
    unless withingeo.path
      withinpoly = this.addGeoJson(withingeo)

  if this.database
    this.database.inside(withinpoly, callback)
  else
    this.query "", (err, items) ->
      withinpoly = withinpoly.path[0]
      for pt, p in withinpoly
        withinpoly[p] = { latitude: pt[0], longitude: pt[1] }
      results = []
      for item in items
        center = item.center()
        if geolib.isPointInside({ latitude: center.lat, longitude: center.lng }, withinpoly)
          results.push item
      callback(null, results)

MapPLZ.prototype.save = (items, callback) ->
  if this.database
    if this.isArray(items)
      for item in items
        item.database = this.database
        item.save(callback)
    else
      items.database = this.database
      items.save(callback)
  else
    if this.isArray(items)
      for item in items
        item.mapitems = this.mapitems
      this.mapitems.concat items
    else
      items.mapitems = this.mapitems
      this.mapitems.push items
    callback(null, items)

MapPLZ.prototype.isArray = (inspect) ->
  return (typeof inspect == 'object' && typeof inspect.push == 'function')

MapPLZ.prototype.isGeoJson = (json) ->
  type = json.type
  return (type && (type == "Feature" || type == "FeatureCollection"))

MapPLZ.prototype.addGeoJson = (gj, callback) ->
  if gj.type == "FeatureCollection"
    results = []
    that = this
    iter_callback = (feature_index) ->
      if feature_index < gj.features.length
        feature = that.addGeoJson(gj.features[feature_index])
        that.save feature, (err, saved) ->
          results.push saved
          iter_callback(feature_index + 1)
      else
        callback(null, results)
    iter_callback(0)

  else if gj.type == "Feature"
    geom = gj.geometry
    result = ""
    if geom.type == "Point"
      result = MapPLZ.standardize({ lat: geom.coordinates[1], lng: geom.coordinates[0] })
      result.type = "point"
    else if geom.type == "LineString"
      result = MapPLZ.standardize({ path: this.reverse_path(geom.coordinates) })
      result.type = "line"
    else if geom.type == "Polygon"
      result = MapPLZ.standardize({ path: [this.reverse_path(geom.coordinates[0])] })
      result.type = "polygon"

    result.properties = gj.properties || {}
    result

MapPLZ.prototype.process_code = (code, callback) ->
  code_lines = code.split("\n")
  code_level = "toplevel"
  button_layers = []
  code_button = 0
  code_layers = []
  code_label = ""
  code_color = null
  code_latlngs = []

  finish_add = ->
    added = 0
    for item in code_layers
      item.database = this.database
      item.save (err) ->
        added++
        callback(err, code_layers) if code_layers.length == added

  code_line = (index) ->
    if index >= code_lines.length
      return finish_add()

    line = code_lines[index].trim()
    codeline = line.toLowerCase().split(' ')

    if code_level == 'toplevel'
      code_level = 'map' if line.indexOf('map') > -1
      return code_line(index + 1)

    else if code_level == 'map' || code_level == 'button'
      if codeline.indexOf('button') > -1 || codeline.indexOf('btn') > -1
        code_level = 'button'
        button_layers.push { layers: [] }
        code_button = button_layers.length

      if codeline.indexOf('marker') > -1
        code_level = 'marker'
        code_latlngs = []
        return code_line(index + 1)

      else if codeline.indexOf('line') > -1
        code_level = 'line'
        code_latlngs = []
        return code_line(index + 1)

      else if codeline.indexOf('shape') > -1
        code_level = 'shape'
        code_latlngs = []
        return code_line(index + 1)

      if codeline.indexOf('plz') > -1 || codeline.indexOf('please') > -1
        if code_level == 'map'
          code_level = 'toplevel'
          return finish_add()

        else if code_level == 'button'
          # add button
          code_level = 'map'
          code_button = nil
          return code_line(index + 1)

    else if code_level == 'marker' || code_level == 'line' || code_level == 'shape'
      if codeline.indexOf('plz') > -1 || codeline.indexOf('please') > -1

        if code_level == 'marker'
          geoitem = new MapItem
          geoitem.lat = code_latlngs[0][0]
          geoitem.lng = code_latlngs[0][1]
          geoitem.properties = { label: (code_label || '') }
          code_layers.push geoitem

        else if code_level == 'line'
          geoitem = new MapItem
          geoitem.path = code_latlngs
          geoitem.properties = {
            color: (code_color || ''),
            label: (code_label || '')
          }
          code_layers.push geoitem

        else if code_level == 'shape'
          geoitem = new MapItem
          geoitem.path = [code_latlngs]
          geoitem.properties = {
            color: (code_color || ''),
            fill_color: (code_color || ''),
            label: (code_label || '')
          }
          code_layers.push geoitem

        if code_button
          code_level = 'button'
        else
          code_level = 'map'

        code_latlngs = []
        return code_line(index + 1)

    # geocoding starts with @ - disabled

    # reading a color
    if codeline[0].indexOf('#') == 0
      code_color = codeline.trim()
      if code_color.length != 4 && code_color.length != 7
        # named color
        code_color = code_color.replace('#', '')

      return code_line(index + 1)

    # reading a raw string (probably text for a popup)
    if codeline[0].indexOf('"') == 0
      # check button
      code_label = line.substring( line.indexOf('"') + 1 )
      code_label = code_label.substring(0, code_label.indexOf('"') - 1)

    # reading a latlng coordinate
    if line.indexOf('[') > -1 && line.indexOf(',') > -1 && line.indexOf(']') > -1
      latlng_line = line.replace('[', '').replace(']', '').split(',')
      latlng_line[0] *= 1
      latlng_line[1] *= 1

      # must be a 2D coordinate
      return code_line(index + 1) if latlng_line.length != 2

      code_latlngs.push latlng_line

      return code_line(index + 1)

    code_line(index + 1)
  code_line(0)

MapPLZ.reverse_path = (path) ->
  path_pts = path.slice(0)
  for p, pt in path_pts
    path_pts[pt] = path_pts[pt].slice(0).reverse()
  path_pts

## MapPLZ data is returned as MapItems

MapItem = ->
MapItem.prototype.toGeoJson = ->
  if this.type == "point"
    gj_geo = { type: "Point", coordinates: [this.lng, this.lat] }
  else if this.type == "line"
    linepath = MapPLZ.reverse_path(this.path)
    gj_geo = { type: "LineString", coordinates: linepath }
  else if this.type == 'polygon'
    polypath = [MapPLZ.reverse_path(this.path[0])]
    gj_geo = { type: "Polygon", coordinates: polypath }
  JSON.stringify { type: "Feature", geometry: gj_geo, properties: this.properties }

MapItem.prototype.toWKT = ->
  if this.type == "point"
    "POINT(#{this.lng} #{this.lat})"
  else if this.type == "line"
    linepath = MapPLZ.reverse_path(this.path)
    for p, pt in linepath
      linepath[pt] = linepath[pt].join ' '
    linepath = linepath.join ', '
    "LINESTRING(#{linepath})"
  else if this.type == 'polygon'
    polypath = MapPLZ.reverse_path(this.path[0])
    for p, pt in polypath
      polypath[pt] = polypath[pt].join ' '
    polypath = polypath.join ', '
    "POLYGON((#{polypath}))"

MapItem.prototype.save = (callback) ->
  if this.database
    my_mapitem = this
    this.database.save this, (err, id) ->
      my_mapitem.id = id if id
      callback(err, my_mapitem)
  else
    callback(null, this)

MapItem.prototype.delete = (callback) ->
  if this.database
    my_mapitem = this
    this.database.delete this, (err) ->
      callback(err)
  else
    if this.mapitems.indexOf(this) > -1
      this.mapitems.splice(this.mapitems.indexOf(this), 1)
    this.type = "deleted"
    callback(null)

MapItem.prototype.center = ->
  if this.type == "point"
    { lat: this.lat, lng: this.lng }
  else if this.type == "line"
    avg = { lat: 0, lng: 0 }
    for pt in this.path
      avg.lat += pt[0]
      avg.lng += pt[1]
    avg.lat /= this.path.length
    avg.lng /= this.path.length
    avg
  else if this.type == "polygon"
    avg = { lat: 0, lng: 0 }
    for pt in this.path[0]
      avg.lat += pt[0]
      avg.lng += pt[1]
    avg.lat /= this.path[0].length
    avg.lng /= this.path[0].length
    avg


## Database Drivers

## PostGIS Database Driver

PostGIS = ->
PostGIS.prototype.save = (item, callback) ->
  if item.id
    this.client.query "UPDATE mapplz SET geom = ST_GeomFromText('#{item.toWKT()}'), properties = '#{JSON.stringify(item.properties)}' WHERE id = #{item.id * 1}", (err, result) ->
      console.error err if err
      callback(err, item.id)
  else
    this.client.query "INSERT INTO mapplz (properties, geom) VALUES ('#{JSON.stringify(item.properties)}', ST_GeomFromText('#{item.toWKT()}')) RETURNING id", (err, result) ->
      console.error err if err
      callback(err, result.rows[0].id || null)

PostGIS.prototype.delete = (item, callback) ->
  this.client.query "DELETE FROM mapplz WHERE id = #{item.id * 1}", (err) ->
    item = null
    callback(err)

PostGIS.prototype.count = (query, callback) ->
  condition = "1=1"
  if query && query.length
    condition = query
    where_prop = condition.trim().split(' ')[0]
    condition = condition.replace(where_prop, "json_extract_path_text(properties, '#{where_prop}')")

  this.client.query "SELECT COUNT(*) AS count FROM mapplz WHERE #{condition}", (err, result) ->
    callback(err, result.rows[0].count || null)

PostGIS.prototype.processResults = (err, db, result, callback) ->
  if err
    console.error err
    callback(err, [])
  else
    results = []
    for row in result.rows
      geo = JSON.parse(row.geo)
      result = MapPLZ.prototype.addGeoJson { type: "Feature", geometry: geo, properties: row.properties }
      result.id = row.id
      result.database = db
      results.push result
    callback(err, results)

PostGIS.prototype.query = (query, callback) ->
  condition = "1=1"
  db = this
  if query && query.length
    condition = query
    where_prop = condition.trim().split(' ')[0]
    condition = condition.replace(where_prop, "json_extract_path_text(properties, '#{where_prop}')")

  this.client.query "SELECT ST_AsGeoJSON(geom) AS geo, properties FROM mapplz WHERE #{condition}", (err, result) ->
    db.processResults(err, db, result, callback)

PostGIS.prototype.near = (nearpt, count, callback) ->
  db = this
  this.client.query "SELECT id, ST_AsGeoJSON(geom) AS geo, properties, ST_Distance(start.geom::geography, ST_GeomFromText('#{nearpt.toWKT()}')::geography) AS distance FROM mapplz AS start ORDER BY distance LIMIT #{count}", (err, results) ->
    db.processResults(err, db, results, callback)

PostGIS.prototype.inside = (withinpoly, callback) ->
  db = this
  this.client.query "SELECT id, ST_AsGeoJSON(geom) AS geo, properties FROM mapplz AS start WHERE ST_Contains(ST_GeomFromText('#{withinpoly.toWKT()}'), start.geom)", (err, results) ->
    db.processResults(err, db, results, callback)

## MongoDB Database Driver

MongoDB = ->
MongoDB.prototype.save = (item, callback) ->
  saveobj = {}
  saveobj = JSON.parse(JSON.stringify(item.properties)) if item.properties
  saveobj.geo = JSON.parse(item.toGeoJson()).geometry
  if item.id
    saveobj._id = item.id
    this.collection.save saveobj, (err) ->
      console.error err if err
      callback(err, item.id)
  else
    this.collection.insert saveobj, (err, results) ->
      console.error err if err
      result = results[0] || null
      callback(err, result._id || null)

MongoDB.prototype.delete = (item, callback) ->
  this.collection.remove { _id: item.id }, (err) ->
    item = null
    callback(err)

MongoDB.prototype.count = (query, callback) ->
  condition = query || {}
  this.collection.find query, (err, cursor) ->
    if err
      console.error err
      callback(err, null)
    else
      cursor.count (err, count) ->
        callback(err, count || 0)

MongoDB.prototype.query = (query, callback) ->
  condition = query || {}
  db = this
  this.collection.find(query).toArray (err, rows) ->
    if err
      console.error err
      callback(err, [])
    else
      results = []
      for row in rows
        excluded = {}
        for key of row
          if key != "_id" && key != "geom"
            excluded[key] = row[key]
        result = MapPLZ.prototype.addGeoJson { type: "Feature", geometry: row.geo, properties: excluded }
        result.id = row._id
        result.database = db
        results.push result
      callback(err, results)

MongoDB.prototype.near = (nearpt, count, callback) ->
  max = 40010000000
  nearquery = {
    geo: {
      $nearSphere: {
        $geometry: JSON.parse(nearpt.toGeoJson()).geometry,
      }
    }
  }

  this.query nearquery, (err, results) ->
    callback(err, (results || []).slice(0, count))

MongoDB.prototype.inside = (withinpoly, callback) ->
  withinquery = {
    geo: {
      $geoWithin: {
        $geometry: JSON.parse(withinpoly.toGeoJson()).geometry
      }
    }
  }
  this.query withinquery, callback

## get it working with Node.js!

if exports
  exports.MapPLZ = MapPLZ
  exports.MapItem = MapItem
  exports.PostGIS = PostGIS
  exports.MongoDB = MongoDB
