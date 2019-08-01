local PICTURE_RES = 64
local TILES_PER_NODE = 2
local DRAWING_DISTANCE = 5
local tile_res = PICTURE_RES/TILES_PER_NODE
local inicolor = 0xFFFFFF00
local doCraft = minetest.get_modpath("farming") and minetest.get_modpath("default") and minetest.get_modpath("dye")
local regCraft,regiCraft = function()end,minetest.register_craft
if doCraft then
  regCraft = minetest.register_craft
end

local function pid(x,y)
  if tonumber(x) then
    return x.."_"..y
  else
    return x.x.."_"..x.y
  end
end

local function HSV(h, s, l, a)
	if s<=0 then return l,l,l,a end
	h, s, l = h/256*6, s/255, l/255
	local c = l*s
	local x = (1-math.abs(h%2-1))*c
	local m,r,g,b = (l-c), 0,0,0
	if h < 1     then r,g,b = c,x,0
	elseif h < 2 then r,g,b = x,c,0
	elseif h < 3 then r,g,b = 0,c,x
	elseif h < 4 then r,g,b = 0,x,c
	elseif h < 5 then r,g,b = x,0,c
	else              r,g,b = c,0,x
	end return (r+m)*255,(g+m)*255,(b+m)*255,a
end

local HSL = HSV

local function clamp(x,mi,ma)
  return math.min(ma,math.max(x,mi))
end

local function RGB(r,g,b,a)
  local r,g,b = clamp(r/255,0,1),clamp(g/255,0,1),clamp(b/255,0,1)
  --print("rgb",r,g,b)
  local l = math.max(r,g,b)
  --print("l",l)
  local ld = l
  if l <= 0 then
    return 0,0,0,a
  end
  local rs,gs,bs = r/ld,g/ld,b/ld
  --print("rgbl",rs,gs,bs)
  local s = math.max(rs,gs,bs)-math.min(rs,gs,bs)
  --print("s",s)
  if s <= 0 then
    return 0,0,l*255,a
  end
  rs,gs,bs = (rs-1)/s+1,(gs-1)/s+1,(bs-1)/s+1
  rs,gs,bs = clamp(rs,0,1),clamp(gs,0,1),clamp(bs,0,1)
  --print("rgbls",rs,gs,bs)
  local h = 0
  if rs == 1 and gs >= 0 and bs == 0 then
    h = gs -- 1
  elseif rs >= 0 and gs == 1 and bs == 0 then
    h = 2-rs -- 2
  elseif gs == 1 and bs >= 0 and rs == 0 then
    h = 2+bs -- 3
  elseif gs >= 0 and bs == 1 and rs == 0 then
    h = 4-gs
  elseif bs == 1 and rs >= 0 and gs == 0 then
    h = 4+rs
  elseif bs >= 0 and rs == 1 and gs == 0 then
    h = 6-bs
  end
  --print("hsl",h,s,l)
  --print()
  return h/6*256,s*255,l*255,a
end

local wpid = function(pos) return type(pos) == "string" and pos or minetest.pos_to_string(pos) end

local widp = function(pos) return type(pos) == "string" and minetest.string_to_pos(pos) or pos end

local renderCanvas

local loaded_pictures = {}

local function load_pic(pos)
  if loaded_pictures[wpid(pos)] then
    return loaded_pictures[wpid(pos)]
  end
  local lpic = {}
  local meta = minetest.get_meta(widp(pos))
  if meta:get_int("has_canvas") == 0 then
    loaded_pictures[wpid(pos)] = nil
    return
  end
  local w,h = 
    meta:get_int("canvas_width"),
    meta:get_int("canvas_height")
  w = w > 0 and w or 1
  h = h > 0 and h or 1
  loaded_pictures[wpid(pos)] = lpic
  --print("Loading pic "..wpid(pos))
  for x=0,w*TILES_PER_NODE-1 do
    for y=0,h*TILES_PER_NODE-1 do
      lpic[pid(x,y)] = {tile=anymon.deserialize(meta:get_string("canvas_tile"..pid(x,y)))}
    end
  end
  return lpic
end

local function spd(name,f,...)
  local t1 = os.clock()
  local args = {f(...)}
  local t2 = os.clock()
  print(name.." took "..(t2-t1).." secs")
  return unpack(args)
end

local function get_tile(pos,tpos)
  local lpic = loaded_pictures[wpid(pos)]
  if not lpic then
    return
  end
  lpic[tpos] = lpic[tpos] or {}
  local t = lpic[tpos]
  t.tile = t.tile or anymon.new_array(tile_res,tile_res,inicolor)
  if not t.tile.iss then
    local set = t.tile.set
    function t.tile:set(...)
      t.dirty = true
      return set(self,...)
    end
    t.tile.iss = true
  end
  return lpic[tpos].tile
end

local function set_tile(pos,tpos,tile)
  local lpic = loaded_pictures[wpid(pos)]
  if not lpic then
    return
  end
  lpic[tpos] = {tile = tile}
  local t = lpic[tpos]
  if not t.tile.iss then
    local set = t.tile.set
    function t.tile:set(...)
      t.dirty = true
      return set(self,...)
    end
    t.tile.iss = true
  end
end

local function save_pic(pos)
  local lpic = loaded_pictures[wpid(pos)]
  if not lpic then
    --print("Pic is not loaded: "..wpid(pos))
    return
  end
  local meta = minetest.get_meta(widp(pos))
  if meta:get_int("has_canvas") == 0 then
    return
  end
  --print ("Saving pic "..wpid(pos))
  for k,v in pairs(lpic) do
    if v.dirty then
      meta:set_string("canvas_tile"..k,anymon.serialize(v.tile))
      v.dirty = false
    end
  end
end

local function pictureAccess(pos,snapshot)
  local pic = {pos = pos}
  local function tpos(x,y)
    return math.floor(x/tile_res),math.floor(y/tile_res),x%tile_res,y%tile_res
  end
  pic.tiles = {}
  pic.tiles_alt = {}
  function pic:fetchTile(x,y,isget)
    if snapshot and isget and self.tiles_alt[pid(x,y)] then
      --print("returning tile_alt "..pid(x,y))
      return pic.tiles_alt[pid(x,y)]
    end
    if self.tiles[pid(x,y)] and not (snapshot and isget) then
      --print("returning tile "..pid(x,y))
      return self.tiles[pid(x,y)]
    end
    local tile,tile_alt
    if not loaded_pictures[wpid(self.pos)] then
      local lpic = {}
      loaded_pictures[wpid(self.pos)] = lpic
      local meta = minetest.get_meta(self.pos)
      local tiled = meta:get_string("canvas_tile"..pid(x,y))
      --print("Loading tile "..pid(x,y))
      tile = anymon.deserialize(tiled)
      set_tile(self.pos,pid(x,y),tile)
      if snapshot then
        tile_alt = tile:copy()
        self.tiles_alt[pid(x,y)] = tile_alt
      end
      self.tiles[pid(x,y)] = tile
    else
      tile = get_tile(self.pos,pid(x,y)) or anymon.new_array(tile_res,tile_res,inicolor)
      self.tiles[pid(x,y)] = tile
      if snapshot then
        tile_alt = tile:copy()
        self.tiles_alt[pid(x,y)] = tile_alt
      end
    end
    return (snapshot and isget) and tile_alt or tile
  end
  function pic:reset()
    self.tiles = {}
    self.tiles_alt = {}
    self.changed = {}
  end
  function pic:set(x,y,color)
    local tx,ty,rx,ry = tpos(x,y)
    local tile = self:fetchTile(tx,ty,false)
    tile:set(rx,ry,color)
  end
  function pic:get(x,y)
    local tx,ty,rx,ry = tpos(x,y)
    local tile = self:fetchTile(tx,ty,true)
    return tile:get(rx,ry)
  end
  function pic:get_force(x,y)
    local tx,ty,rx,ry = tpos(x,y)
    local tile = self:fetchTile(tx,ty,false)
    return tile:get(rx,ry)
  end
  return pic
end

local function setCanvas(pos,itemstack)
  local c_meta = itemstack:get_meta()
  local w,h = 
    c_meta:get_int("canvas_width"),
    c_meta:get_int("canvas_height")
  w = w > 0 and w or 1
  h = h > 0 and h or 1
  local meta = minetest.get_meta(pos)
  local node = minetest.get_node(pos)
  meta:set_int("has_canvas",1)
  meta:set_int("canvas_width",w)
  meta:set_int("canvas_height",h)
  local ts = PICTURE_RES/TILES_PER_NODE
  local lpic = {}
  loaded_pictures[wpid(pos)] = lpic
  for x=0,w*TILES_PER_NODE-1 do
    for y=0,w*TILES_PER_NODE-1 do
      local tiled = c_meta:get_string("canvas_tile"..pid(x,y))
      local tile = anymon.deserialize(tiled) or anymon.new_array(ts,ts,inicolor)
      lpic[pid(x,y)] = {tile=tile}
      meta:set_string("canvas_tile"..pid(x,y),anymon.serialize(tile))
      meta:mark_as_private("canvas_tile"..pid(x,y))
    end
  end
  renderCanvas(pos,node.name == "painter:easel",true)
end

local function pullCanvas(pos,player)
  save_pic(pos)
  local inv = player:get_inventory()
  local meta = minetest.get_meta(pos)
  local node = minetest.get_node(pos)
  local stack = ItemStack("painter:canv")
  local c_meta = stack:get_meta()
  if meta:get_int("has_canvas") == 1 then
    local w,h = meta:get_int("canvas_width"),meta:get_int("canvas_height")
    c_meta:set_int("canvas_width",w)
    c_meta:set_int("canvas_height",h)
    for x=0,w*TILES_PER_NODE-1 do
      for y=0,h*TILES_PER_NODE-1 do
        local tiled = meta:get_string("canvas_tile"..pid(x,y))
        print("tile_size",#tiled)
        c_meta:set_string("canvas_tile"..pid(x,y),tiled)
      end
    end
    c_meta:set_string("description","Painting canvas "..w.."x"..h)
  else
    return
  end
  if not inv:room_for_item("main",stack) then
    return
  end
  inv:add_item("main",stack)
  meta:set_int("has_canvas",0)
  local w,h = meta:get_int("canvas_width"),meta:get_int("canvas_height")
  for x=0,w-1 do
    for y=0,h-1 do
      meta:set_string("canvas_tile"..pid(x,y),"")
    end
  end
  meta:set_int("canvas_width",0)
  meta:set_int("canvas_height",0)
  renderCanvas(pos,node.name == "painter:easel",true)
  save_pic(pos)
  load_pic(pos)
  return true
end

-- [[From Display API Mod

local max_pos = 4

local wallmounted_rotations = {
	[0]={x=1, y=0, z=0}, [1]={x=3, y=0, z=0},
	[2]={x=0, y=3, z=0}, [3]={x=0, y=1, z=0},
	[4]={x=0, y=0, z=0}, [5]={x=0, y=2, z=0},
}

local facedir_rotations = {
	[ 0]={x=0, y=0, z=0}, [ 1]={x=0, y=3, z=0},
	[ 2]={x=0, y=2, z=0}, [ 3]={x=0, y=1, z=0},
	[ 4]={x=3, y=0, z=0}, [ 5]={x=0, y=3, z=3},
	[ 6]={x=1, y=0, z=2}, [ 7]={x=0, y=1, z=1},
	[ 8]={x=1, y=0, z=0}, [ 9]={x=0, y=3, z=1},
	[10]={x=3, y=0, z=2}, [11]={x=0, y=1, z=3},
	[12]={x=0, y=0, z=1}, [13]={x=3, y=0, z=1},
	[14]={x=2, y=0, z=1}, [15]={x=1, y=0, z=1},
	[16]={x=0, y=0, z=3}, [17]={x=1, y=0, z=3},
	[18]={x=2, y=0, z=3}, [19]={x=3, y=0, z=3},
	[20]={x=0, y=0, z=2}, [21]={x=0, y=1, z=2},
	[22]={x=0, y=2, z=2}, [23]={x=0, y=3, z=2},
}

-- Compute other useful values depending on wallmounted and facedir param
local wallmounted_values = {}
local facedir_values = {}

local function compute_values(r)
	local function rx(v) return { x=v.x, y=v.z, z=-v.y} end
	local function ry(v) return { x=-v.z, y=v.y, z=v.x} end
	local function rz(v) return { x=v.y, y=-v.x, z=v.z} end

	local function nrx(v) return { x=v.x, y=-v.z, z=v.y} end
	local function nry(v) return { x=v.z, y=v.y, z=-v.x} end
	local function nrz(v) return { x=-v.y, y=v.x, z=v.z} end

	local d = { x = 0, y = 0, z = 1 }
	local w = { x = 1, y = 0, z = 0 }
	local h = { x = 0, y = 1, z = 0 }

	local dn = { x = 0, y = 0, z = 1 }
	local wn = { x = 1, y = 0, z = 0 }
	local hn = { x = 0, y = 1, z = 0 }

	-- Important to keep z rotation first (not same results)
	for _ = 1, r.z do d, w, h = rz(d), rz(w), rz(h) end
	for _ = 1, r.x do d, w, h = rx(d), rx(w), rx(h) end
	for _ = 1, r.y do d, w, h = ry(d), ry(w), ry(h) end

	for _ = 1, r.y do dn, wn, hn = nry(dn), nry(wn), nry(hn) end
	for _ = 1, r.x do dn, wn, hn = nrx(dn), nrx(wn), nrx(hn) end
	for _ = 1, r.z do dn, wn, hn = nrz(dn), nrz(wn), nrz(hn) end

	return {
		rotation=r, depth=d, width=w, height=h,
		neg_depth = dn, neg_width = wn, neg_height = hn,
		restricted=(r.x==0 and r.z==0) }
end

for i, r in pairs(facedir_rotations) do
	facedir_values[i] = compute_values(r)
end

for i, r in pairs(wallmounted_rotations) do
	wallmounted_values[i] = compute_values(r)
end

local function get_orientation_values(node)
	local ndef = minetest.registered_nodes[node.name]

	if ndef then
		local paramtype2 = ndef.paramtype2
		if paramtype2 == "wallmounted" or paramtype2 == "colorwallmounted" then
			return wallmounted_values[node.param2 % 8]
		elseif paramtype2 == "facedir" or paramtype2 == "colorfacedir"  then
			return facedir_values[node.param2 % 32]
		else
			-- No orientation or unknown orientation type
			return facedir_values[0]
		end
	end
end

-- ]]
local function get_light(pos)
  return minetest.get_node_light(pos)
end

renderCanvas = function(pos,easel,dirty)
  local node = minetest.get_node(pos)
  local meta = minetest.get_meta(pos)
  --if meta:get_int("has_canvas") ~= 1 then
  --  return
  --end
  local width = meta:get_int("canvas_width")
  local height = meta:get_int("canvas_height")
  load_pic(pos)
  local pic = pictureAccess(pos)
  local ts = PICTURE_RES/TILES_PER_NODE
  local dirtys = {}
  if type(dirty) == "table" and type(dirty[1]) == "number" then
    for x=math.floor(dirty[1]/ts),math.floor(dirty[2]/ts) do
      for y=math.floor(dirty[3]/ts),math.floor(dirty[4]/ts) do
        dirtys[pid(x,y)] = true
      end
    end
  elseif type(dirty) == "table" and type(dirty[1]) == "string" then
    for k,v in pairs(dirty) do
      dirtys[v] = true
    end
  elseif type(dirty) == "table" and type(dirty[1]) == "table" then
    for k,v in pairs(dirty) do
      dirtys[pid(v[1],v[2])] = true
    end
  elseif dirty then
    for x=0,width-1 do
      for y=0,height-1 do
        dirtys[pid(x,y)] = true
      end
    end
  end
  local function isDirty(x,y)
    return dirtys[pid(x,y)]
  end
  local ov = get_orientation_values(node)
  local pes = {}
  local ces = {}
  local function canvas(ent)
    local epos = ent.pos
    local obj = ent.object
    local z = easel and 0 or 0.5-1/32
    local x = easel and (epos.x-width/2+0.5) or epos.x
    local y = easel and ((height-epos.y-1)+1) or (height-epos.y-1)
    local p = {
		  x = pos.x + ov.depth.x*z + ov.width.x*x + ov.height.x*y,
		  y = pos.y + ov.depth.y*z + ov.width.y*x + ov.height.y*y,
		  z = pos.z + ov.depth.z*z + ov.width.z*x + ov.height.z*y,
		}
		obj:set_pos(p)
		obj:set_rotation({
      x = ov.rotation.x*math.pi/2,
      y = ov.rotation.y*math.pi/2,
		  z = ov.rotation.z*math.pi/2,
		})
	  local prop = obj:get_properties()
		prop.collisionbox = {
		  ov.depth.x*(-1/32) + ov.width.x*(-0.5) + ov.height.x*(-0.5),
		  ov.depth.y*(-1/32) + ov.width.y*(-0.5) + ov.height.y*(-0.5),
		  ov.depth.z*(-1/32) + ov.width.z*(-0.5) + ov.height.z*(-0.5),

		  ov.depth.x*(1/32) + ov.width.x*(0.5) + ov.height.x*(0.5),
		  ov.depth.y*(1/32) + ov.width.y*(0.5) + ov.height.y*(0.5),
		  ov.depth.z*(1/32) + ov.width.z*(0.5) + ov.height.z*(0.5),
		}
		local light = get_light(p)/15
		prop.glow = light
		prop.selectionbox = prop.collisionbox
	  obj:set_properties(prop)
  end
  local function picture(ent)
    local epos = ent.pos
    local obj = ent.object
    local x = (easel and (epos.x-(width*TILES_PER_NODE)/2+0.5) or epos.x-0.5*TILES_PER_NODE+0.5)/TILES_PER_NODE
    local y = easel and (((height)*TILES_PER_NODE-epos.y-1)/TILES_PER_NODE+0.5+1/TILES_PER_NODE/2) or (((height)*TILES_PER_NODE-epos.y-1)/TILES_PER_NODE-0.5+1/TILES_PER_NODE/2)
    local z = easel and -(1/16/2+0.002) or (0.5-(1/16)-0.002)
    local p = {
		  x = pos.x + ov.depth.x*z + ov.width.x*x + ov.height.x*y,
		  y = pos.y + ov.depth.y*z + ov.width.y*x + ov.height.y*y,
		  z = pos.z + ov.depth.z*z + ov.width.z*x + ov.height.z*y,
		}
		obj:set_pos(p)
		obj:set_rotation({
      x = ov.rotation.x*math.pi/2,
      y = ov.rotation.y*math.pi/2 + math.pi,
		  z = ov.rotation.z*math.pi/2,
		})
		local prop = obj:get_properties()
		local light = get_light(p)/15
		prop.glow = light
		obj:set_properties(prop)
  end
  local tran = "aw.png^[opacity:0"
  local function picture_redraw(ent)
    local epos = ent.pos
    local obj = ent.object
    local prop = obj:get_properties()
    local subar = pic:fetchTile(epos.x,epos.y)
    local tex = anymon.render(subar)
    prop.textures = {tran,tran,tran,tran,tex,tran,tran}
    prop.visual_size = {x=1/TILES_PER_NODE,y=1/TILES_PER_NODE,z=0.0002}
    local x = (easel and (epos.x-(width*TILES_PER_NODE)/2+0.5) or epos.x-0.5*TILES_PER_NODE+0.5)/TILES_PER_NODE
    local y = easel and (((height)*TILES_PER_NODE-epos.y-1)/TILES_PER_NODE+0.5+1/TILES_PER_NODE/2) or (((height)*TILES_PER_NODE-epos.y-1)/TILES_PER_NODE-0.5+1/TILES_PER_NODE/2)
    local z = easel and -(1/16/2+0.002) or (0.5-(1/16)-0.002)
    local p = {
		  x = pos.x + ov.depth.x*z + ov.width.x*x + ov.height.x*y,
		  y = pos.y + ov.depth.y*z + ov.width.y*x + ov.height.y*y,
		  z = pos.z + ov.depth.z*z + ov.width.z*x + ov.height.z*y,
		}
		local light = get_light(p)/15
		prop.glow = light
    obj:set_properties(prop)
  end

  for _,objref in ipairs(minetest.get_objects_inside_radius(pos,max_pos)) do
    local ent = objref:get_luaentity()
    if ent and ent.painter_entype and vector.equals(ent.nodepos,pos) then
      --print("Painter entity detected")
      if ent.painter_entype == "canvas" then
        if ces[pid(ent.pos)] or
          ent.pos.x >= width or
          ent.pos.y >= height or
          ent.pos.x < 0 or
          ent.pos.y < 0
        then
          ent.object:remove()
        else
          ces[pid(ent.pos)] = ent
          canvas(ent)
        end
		  elseif ent.painter_entype == "picture" then
        if pes[pid(ent.pos)] or
          ent.pos.x >= width*TILES_PER_NODE or
          ent.pos.y >= height*TILES_PER_NODE or
          ent.pos.x < 0 or
          ent.pos.y < 0
        then
          ent.object:remove()
        else
		      pes[pid(ent.pos)] = ent
		      picture(ent)
		      if isDirty(ent.pos.x,ent.pos.y) then
		        picture_redraw(ent)
		      end
		    end
      end
    end
  end
  if width > 0 and height > 0 then
    for x=0,width-1 do
      for y=0,height-1 do
        local epos = {x=x,y=y,z=0}
        if not ces[pid(epos)] then
          local obj = minetest.add_entity(pos,"painter:canvas",minetest.serialize({
            nodepos = pos,
            pos = epos
          }))
          if obj then
            local ent = obj:get_luaentity()
            canvas(ent)
            ces[pid(epos)] = ent
            --print("spawned canvas ent")
          else
            error("cant spawn canvas ent")
          end
        end
      end
    end
    for x=0,width*TILES_PER_NODE-1 do
      for y=0,height*TILES_PER_NODE-1 do
        local epos = {x=x,y=y,z=0}
        if not pes[pid(epos)] then
          local obj = minetest.add_entity(pos,"painter:picture",minetest.serialize({
            nodepos = pos,
            pos = epos
          }))
          if obj then
            local ent = obj:get_luaentity()
            picture(ent)
            picture_redraw(ent)
            pes[pid(epos)] = ent
            --print("spawned picture ent")
          else
            error("cant spawn picture ent")
          end
        end
      end
    end
  end
end


local ht = 0.5/TILES_PER_NODE
minetest.register_entity("painter:picture",{
  initial_properties = {
    static_save = false,
    use_texture_alpha = true,
    pointable = false,
    --selectionbox = {-ht,-ht,-ht,ht,ht,ht}
  },
  on_activate = function(self, staticdata)
    self.object:set_armor_groups({immortal=1})
    local data = minetest.deserialize(staticdata)
    local obj = self.object
    self.painter_entype = "picture"
    self.nodepos = data.nodepos
    self.pos = data.pos
    local prop = obj:get_properties()
    prop.visual = "cube"
    obj:set_properties(prop)
  end,
})

minetest.register_entity("painter:canvas",{
  initial_properties = {
    static_save = false,
    physical=true,
  },
  on_activate = function(self, staticdata)
    self.object:set_armor_groups({immortal=1})
    local data = minetest.deserialize(staticdata)
    local obj = self.object
    self.painter_entype = "canvas"
    self.nodepos = data.nodepos
    self.pos = data.pos
    local prop = obj:get_properties()
    prop.visual = "cube"
    prop.visual_size = {x = 1, y = 1, z = 1/16}
    local ft,fs,w,c = "painter_wood.png^[resize:16x1","painter_wood.png^[resize:1x16","painter_wood.png","painter_canvas.png"
    prop.textures = {ft,ft,fs,fs,w,c}
    obj:set_properties(prop)
  end,
  on_punch = function(self,puncher)
    local player = puncher
    local prop = player:get_properties()
    local pos = player:get_pos()
    local dir = vector.multiply(player:get_look_dir(),DRAWING_DISTANCE)
    --print(minetest.pos_to_string(dir))
    local ray = minetest.raycast(
      {x=pos.x,y=pos.y+prop.eye_height,z=pos.z},
      {x=pos.x+dir.x,y=pos.y+prop.eye_height+dir.y,z=pos.z+dir.z}
    )
    local firstobj = false
    local pt
    for pointed_thing in ray do
      --print("TRACING OBJECT TYPE: "..pointed_thing.type)
      if firstobj then
        if pointed_thing.type == "object" then
          pt = pointed_thing
        end
        break
      end
      firstobj = true
    end
    if pt and pt.ref and pt.ref:get_luaentity() and puncher:is_player() then
      local node = minetest.get_node(self.nodepos)
      local ndef = minetest.registered_nodes[node.name]
      if ndef.on_canvas_punch then
        ndef.on_canvas_punch(vector.new(self.nodepos),node,puncher,pt)
      end
    end
  end,
  on_rightclick = function(self,puncher)
    local player = puncher
    local prop = player:get_properties()
    local pos = player:get_pos()
    local dir = vector.multiply(player:get_look_dir(),DRAWING_DISTANCE)
    --print(minetest.pos_to_string(dir))
    local ray = minetest.raycast(
      {x=pos.x,y=pos.y+prop.eye_height,z=pos.z},
      {x=pos.x+dir.x,y=pos.y+prop.eye_height+dir.y,z=pos.z+dir.z}
    )
    local firstobj = false
    local pt
    for pointed_thing in ray do
      --print("TRACING OBJECT TYPE: "..pointed_thing.type)
      if firstobj then
        if pointed_thing.type == "object" then
          pt = pointed_thing
        end
        break
      end
      firstobj = true
    end
    if pt and pt.ref and pt.ref:get_luaentity() and puncher:is_player() then
      local node = minetest.get_node(self.nodepos)
      local ndef = minetest.registered_nodes[node.name]
      if ndef.on_canvas_rightclick then
        ndef.on_canvas_rightclick(vector.new(self.nodepos),node,puncher,puncher:get_wielded_item(),pt)
      end
    end
  end
})

minetest.register_node("painter:canv",{
  description = "Painting canvas 1x1",
  drawtype = "airlike",
  paramtype = "light",
  paramtype2 = "facedir",
  inventory_image = "default_dirt.png",
  wield_image = "default_dirt.png",
  walkable = false,
  --groups = {dig_immediate = 2},
  diggable = false,
  pointable = false,
  sunlight_propagates = true,
  after_place_node = function(pos,placer,itemstack,pointed)
    local node = minetest.get_node(pos)
    local ov = get_orientation_values(node)
    local meta = minetest.get_meta(pos)
    setCanvas(pos,itemstack)
    for x=0,meta:get_int("canvas_width")-1 do
      for y=0,meta:get_int("canvas_height")-1 do
        if x~=0 or y~=0 then
          local p = {x=pos.x+ov.height.x*y+ov.width.x*x,
                     y=pos.y+ov.height.y*y+ov.width.y*x,
                     z=pos.z+ov.height.z*y+ov.width.z*x}
          print(minetest.pos_to_string(p))
          local node2 = minetest.get_node(p)
          local ndef = minetest.registered_nodes[node2.name]
          if minetest.is_protected(p,placer:get_player_name()) or not ndef.buildable_to then
            if pullCanvas(pos,placer) then
              renderCanvas(pos,false,true)
              minetest.remove_node(pos)
              return
            end
          end
        end
      end
    end
    for x=0,meta:get_int("canvas_width")-1 do
      for y=0,meta:get_int("canvas_height")-1 do
        if x~=0 or y~=0 then
          local p = {x=pos.x+ov.height.x*y+ov.width.x*x,
                     y=pos.y+ov.height.y*y+ov.width.y*x,
                     z=pos.z+ov.height.z*y+ov.width.z*x}
          minetest.remove_node(p)
        end
      end
    end              
  end,
  on_canvas_punch = function(pos,node,player)
    if minetest.is_protected(pos,player:get_player_name()) then
      return
    end
    if pullCanvas(pos,player) then
      renderCanvas(pos,false,true)
      minetest.remove_node(pos)
    end
  end
})
-- "painter_wood.png^[resize:22x22"

minetest.register_node("painter:easel",{
  description = "Easel",
  drawtype = "mesh",
  paramtype = "light",
  paramtype2 = "facedir",
  tiles = {"painter_wood.png^painter_paint.png"},
  mesh = "easel.obj",
  sunlight_propagates = true,
  diggable = true,
  collision_box = {
    type = "fixed",
    fixed = {
      {-0.5,-0.5,0.0, 0.5,1.5,0.5},
    },
  },
  selection_box = {
    type = "fixed",
    fixed = {
      {-0.5,-0.5,0.0, 0.5,1.5,0.5},
    },
  },
  on_construct = function(pos)
    local meta = minetest.get_meta(pos)
    meta:set_int("has_canvas",0)
    meta:set_int("canvas_width",0)
    meta:set_int("canvas_height",0)
    meta:set_string("canvas_data","")
    meta:mark_as_private({"has_canvas","canvas_width","canvas_height","canvas_data"})
  end,
  on_rightclick = function(pos,node,clicker,itemstack,pointed_thing)
    if minetest.is_protected(pos,clicker:get_player_name()) then
      return
    end
    local meta = minetest.get_meta(pos)
    if itemstack:get_name() == "painter:canv" and meta:get_int("has_canvas") ~= 1 then
      setCanvas(pos,itemstack)
      itemstack:take_item()
      clicker:set_wielded_item(itemstack)
    end
  end,
  on_rotate = function(pos)
    minetest.after(0.01,renderCanvas,pos,true,false)
  end,
  on_punch = function(pos,node,puncher,pointed_thing)
    if minetest.is_protected(pos,puncher:get_player_name()) then
      return
    end
    if minetest.get_item_group(puncher:get_wielded_item():get_name(),"brush") > 0 then
      return
    end
    local meta = minetest.get_meta(pos)
    if meta:get_int("has_canvas") == 1 then
      --print("Trying to pull canvas out")
      pullCanvas(pos,puncher)
      renderCanvas(pos,true,true)
      return
    end
    minetest.node_dig(pos,node,puncher)
  end
})

minetest.register_abm({
  nodenames = {"painter:easel","painter:canv"},
  interval = 1,
  chance = 1,
  action = function(pos, node)
    local ok,err = xpcall(function()
      load_pic(pos)
      renderCanvas(pos,node.name == "painter:easel",false)
    end,debug.traceback)
    if not ok then print(err)end
  end,
})

minetest.register_abm({
  nodenames = {"painter:easel","painter:canv"},
  interval = 5,
  chance = 1,
  catchup = false,
  action = function(pos, node)
    save_pic(pos)
  end,
})

--[[minetest.register_lbm({
  name = "painter:load_canvas",
  nodenames = {"painter:easel"},
  action = function(pos, node)
    renderCanvas(pos,node.name == "painter:easel",false)
  end,
  run_at_every_load = true
})]]

regCraft({
  output = "painter:easel",
  recipe = {
    {"",             "default:stick",""             },
    {"default:stick","default:stick","default:stick"},
    {"default:stick","",             "default:stick"}
  }
})

regCraft({
  output = "painter:canv",
  recipe = {
    {"default:stick","default:stick","default:stick"},
    {"default:stick","group:wool","default:stick"},
    {"default:stick","default:stick","default:stick"}
  }
})

-- From the 20K LightYears Into Space game [[

local function reverse(t)
  local t2 = {}
  for x=#t,1,-1 do
    table.insert(t2,t[x])
  end
  return t2
end

local function line(x1,y1,x2,y2)
  local dx = x2-x1
  local dy = y2-y1
  if math.abs(dx) < math.abs(dy) then
    local l = line(y1,x1,y2,x2)
    for k,v in pairs(l) do
      l[k] = {v[2],v[1]}
    end
    return l
  end

  if ( dx < 0 ) then
    local l = line(x2,y2,x1,y1)
    return reverse(l)
  end

  local direction

  if dy < 0 then
    direction = -1
    dy = -dy
  else
    direction = 1
  end

  local d = ( 2 * dy ) - dx
  local incr_e = 2 * dy
  local incr_ne = 2 * ( dy - dx )
  local y = y1
  local l = {{x1,y}}

  for x = x1, x2 do
    if ( d <= 0 ) then
      d = d + incr_e
    else
      d = d + incr_ne
      y = y + direction
    end
    table.insert(l,{x,y})
  end
    
  if ( y ~= y2 ) then
    table.insert(l,{x2,y2})
  end

  return l
end

--]]

local keydowns = {}

local function citp(i)
  local i2 = i-1
  local x = i2%3+1
  local y = math.floor(i2/3)+1
  return x,y
end

local recipes = {}
for w=1,3 do
  for h=1,3 do
    if w~=1 or h~=1 then
      local recipe = {}
      for y=1,3 do
        recipe[y] = {"","",""}
      end
      for x=1,w do
        for y=1,h do
          recipe[y][x] = "painter:canv"
        end
      end
      table.insert(recipes,{w=w,h=h,r=recipe})
      regiCraft({
        output = "painter:canv",
        recipe = recipe
      })
    end
  end
end
local function on_craft(out,player,grid,inv,isCraft)
  if out:get_name() == "painter:canv" and grid[1]:get_name() ~= "default:stick" then
    local stack
    for _,rec in pairs(recipes) do
      local isGood = true
      for i,stack in pairs(grid) do
        local x,y = citp(i)
        local meta = stack:get_meta()
        local w,h = meta:get_int("canvas_width"),meta:get_int("canvas_height")
        if stack:get_name() ~= rec.r[y][x] or not ((w==0 or w==1) and (h==0 or h==1)) then
          isGood = false
        end
      end
      if isGood then
        stack = ItemStack("painter:canv")
        local meta = stack:get_meta()
        meta:set_string("description","Painting canvas "..rec.w.."x"..rec.h)
        meta:set_int("canvas_width",rec.w)
        meta:set_int("canvas_height",rec.h)
      end
    end
    return stack or ItemStack(nil)
  elseif minetest.get_item_group(out:get_name(),"def_brush") > 0 then
    local meta = out:get_meta()
    meta:set_int("has_color",0)
    meta:set_string("color","#BF6000")
    return out
  end
end

minetest.register_craft_predict(on_craft)
minetest.register_on_craft(function(a,b,c,d)return on_craft(a,b,c,d,true)end)

local function blend(c1,c2)
  local r1,g1,b1,a1 = anymon.hex_to_rgba(c1)
  local r2,g2,b2,a2 = anymon.hex_to_rgba(c2)
  local f=math.floor
  if a2 < 255 then
    local r,g,b,a = f(r1*(1-a2/255)+r2*a2/255), f(g1*(1-a2/255)+g2*a2/255), f(b1*(1-a2/255)+b2*a2/255),f(math.min(255,(a1*(1-a2/255)+a2)))
    return anymon.rgba_to_hex(r,g,b,a)
  else
    return c2
  end
end

local function blend2(c1,c2,a)
  local r1,g1,b1,a1 = anymon.hex_to_rgba(c1)
  local r2,g2,b2,a2 = anymon.hex_to_rgba(c2)
  local f=math.floor
  local r,g,b,a = f(r1*(1-a/255)+r2*a/255), f(g1*(1-a/255)+g2*a/255), f(b1*(1-a/255)+b2*a/255),f(math.min(255,(a1*(1-a/255)+a2*a/255)))
  return anymon.rgba_to_hex(r,g,b,a)
end

local colorPick
local function painter_onplace(item,clicker,pointed)
  --print("onplace")
  if pointed.type ~= "node" then
    --print("notanode")
    return
  end
  if not clicker or not clicker:is_player() then
    --print("notaplayer")
    return
  end
  local pos = pointed.under
  if minetest.is_protected(pos,clicker:get_player_name()) then
    --print("protected")
    return
  end
  local con = clicker:get_player_control()
  local meta = minetest.get_meta(pos)
  if con.sneak then
    --print("sneak")
    if minetest.get_item_group(item:get_name(),"painter_colored") > 0 and minetest.get_node(pos).name=="painter:palette" then
      --print"group"
      local color = item:get_meta():get_string("color")
      if #color > 0 and item:get_meta():get_int("has_color") == 1 then
        --print("color")
        local c = anymon.colorstring_to_hex(color)
        local r,g,b,a = anymon.hex_to_rgba(c)
        local h,s,l = RGB(r,g,b)
        meta:set_int("h",h)meta:set_int("s",s)meta:set_int("l",l)
        meta:set_string("formspec",colorPick(pos))
      end
    end
  end
end

minetest.register_craftitem("painter:bristles",{
  description = "Bristles",
  inventory_image = "painter_bristles.png",
  wield_image = "painter_bristles.png"
})

regCraft({
  output = "painter:bristles",
  recipe = {
    {"farming:string","farming:string","farming:string"},
    {"farming:string","farming:string","farming:string"},
    {"","",""}
  }
})

for n=0,6 do
  minetest.register_tool("painter:brush"..n,{
    description = "Painting brush (size "..n..")",
    inventory_image = "painter_b"..n..".png",
    inventory_overlay = "painter_b"..n.."_over.png",
    wield_image = "painter_b"..n..".png",
    wield_overlay = "painter_b"..n.."_over.png",
    groups = {brush = 1,def_brush = 1,brush_snapshot_left = 1,painter_colored = 1},
    painter_brush = function(player,item,dat)
      local controls = player:get_player_control()
      local size = n
      local meta = item:get_meta()
      local b,x,y,w,h,pic,kd,ss,sg = dat.button,dat.x,dat.y,dat.w,dat.h,dat.pic,dat.data,dat.softset,dat.softget
      kd.store.processed = kd.store.processed or {}
      local ic = false
      if b == "left" and controls.sneak then
        meta:set_string("color",minetest.rgba(anymon.hex_to_rgba(sg(x,y,0))))
        meta:set_int("has_color",1)
        ic = true
      elseif b == "left" then
        local color = meta:get_string("color")
        if meta:get_int("has_color") == 0 then
          return
        end
        local c
        if #color > 0 then
          c = anymon.colorstring_to_hex(color)
        end
        if c then
          ss(x,y,c,size,blend)
        end
      elseif b == "right" then
        local ox,oy = x,y
        local px,py = dat.data.px,dat.data.py
        local b = function(c,c2)return blend2(c,c2,128)end
        if px and py then
          for x=px-size,px+size do
            for y=py-size,py+size do
              if x >= 0 and y >= 0 and x < w and y < h then
                kd.store.processed[pid(x-px,y-py)] = sg(x,y,0)
              end
            end
          end
          for x=ox-size,ox+size do
            for y=oy-size,oy+size do
              if kd.store.processed[pid(x-ox,y-oy)] then
                ss(x,y,kd.store.processed[pid(x-ox,y-oy)],0,b)
              end
            end
          end
        end
      end
      return ic and item
    end,
    on_place = painter_onplace
  })
  local recipe={{"","",""},{"","",""},{"","",""}}
  local my = 1
  local mx = 1
  for i=1,n+1 do
    local x,y = citp(i)
    my = math.max(my,y)
    mx = math.max(mx,x)
    recipe[y][x] = "painter:bristles"
  end
  if n == 6 then
    local x,y = 2,3
    recipe[y][x] = "default:stick"
  else
    local x,y = math.floor((mx-1)/2+1),my+1
    recipe[y][x] = "default:stick"
  end
  --print(dump(recipe))
  regCraft({
    output = "painter:brush"..n,
    recipe = recipe
  })
end

minetest.register_on_shutdown(function()
  for k,v in pairs(loaded_pictures) do
    save_pic(k)
  end
end)

function colorPick(pos)
  local meta = minetest.get_meta(pos)
  local h,s,l = meta:get_int("h"),meta:get_int("s"),meta:get_int("l")
  local formspec = {"size[12,8]"}
  local function tex(x,y,w,tex,name,isSelectd)
    return "image_button["..x..","..y..";"..w..",1;"..tex..";"..name..";"..(isSelectd and minetest.formspec_escape("^") or "").."]"
  end
  local w=31
  local vw = 12
  for x=0,w-1 do
    local v = math.floor(x/(w-1)*255)
    local htex = minetest.formspec_escape("aw.png^[multiply:"..minetest.rgba(HSL(v,s,l,255)))
    local stex = minetest.formspec_escape("aw.png^[multiply:"..minetest.rgba(HSL(h,v,l,255)))
    local ltex = minetest.formspec_escape("aw.png^[multiply:"..minetest.rgba(HSL(h,s,v,255)))
    local hstr = tex(x*vw/w-0.125,0.5,(vw)/w+0.25,htex,"h"..v,math.floor(v/255*(w-1)+.5)==math.floor(h/255*(w-1)+.5))
    local sstr = tex(x*vw/w-0.125,0.5+1,(vw)/w+0.25,stex,"s"..v,math.floor(v/255*(w-1)+.5)==math.floor(s/255*(w-1)+.5))
    local lstr = tex(x*vw/w-0.125,0.5+2,(vw)/w+0.25,ltex,"l"..v,math.floor(v/255*(w-1)+.5)==math.floor(l/255*(w-1)+.5))
    table.insert(formspec,hstr)
    table.insert(formspec,sstr)
    table.insert(formspec,lstr)
  end
  return table.concat(formspec)
end

local function colored(r,g,b,a)
  return "aw.png^[multiply:"..minetest.rgba(r,g,b,a)
end

minetest.register_node("painter:palette",{
  description = "Painting palette",
  groups = {dig_immediate = 3},
  paramtype = "light",
  paramtype2 = "facedir",
  sunlight_propagates = true,
  drawtype = "mesh",
  mesh = "palette.obj",
  selection_box = {
    type="fixed",
    fixed = {
      -0.3,-0.5,-0.4,
      0.3,-0.4,0.4
    }
  },
  collision_box = {
    type="fixed",
    fixed = {
      -0.3,-0.5,-0.4,
      0.3,-0.4,0.4
    }
  },
  tiles = {"painter_wood.png^painter_paint.png^[resize:22x22","painter_palette.png"},
  on_receive_fields = function(pos,form,fields,sender)
    if minetest.is_protected(pos,sender:get_player_name()) then
      return
    end
    local item = sender:get_wielded_item()
    local imeta = item:get_meta()
    local meta = minetest.get_meta(pos)
    local h,s,l = meta:get_int("h"),meta:get_int("s"),meta:get_int("l")
    for n=0,255 do
      if fields["h"..n] then
        h = n
      end
      if fields["s"..n] then
        s = n
      end
      if fields["l"..n] then
        l = n
      end
    end
    h,s,l = RGB(HSL(h,s,l))
    meta:set_int("h",h)meta:set_int("s",s)meta:set_int("l",l)
    meta:set_string("formspec",colorPick(pos))
    if fields.quit and minetest.get_item_group(item:get_name(),"def_brush") > 0 then
      imeta:set_string("color",minetest.rgba(HSL(h,s,l,255)))
      imeta:set_int("has_color",1)
      sender:set_wielded_item(item)
    end
  end,
  on_construct = function(pos)
    local meta = minetest.get_meta(pos)
    meta:set_string("formspec",colorPick(pos))
    meta:set_int("h",0)meta:set_int("s",1)meta:set_int("l",128)
  end
})

regCraft({
  output = "painter:palette",
  recipe = {
    {"","dye:magenta",""},
    {"dye:cyan","group:wood","dye:yellow"},
    {"","dye:black",""}
  }
})

minetest.register_globalstep(function(dtime)
  for _,player in ipairs(minetest.get_connected_players()) do
    local name = player:get_player_name()
    local c = player:get_player_control()
    if c.LMB or c.RMB then
      --print("PLAYER is mbDown!")
      local prop = player:get_properties()
      local pos = player:get_pos()
      local dir = vector.multiply(player:get_look_dir(),DRAWING_DISTANCE)
      --print(minetest.pos_to_string(dir))
      local ray = minetest.raycast(
        {x=pos.x,y=pos.y+prop.eye_height,z=pos.z},
        {x=pos.x+dir.x,y=pos.y+prop.eye_height+dir.y,z=pos.z+dir.z}
      )
      local obj, ipos
      local firstobj = false
      local item = player:get_wielded_item()
      local idef = minetest.registered_items[item:get_name()]
      local pbrush = idef.painter_brush
      local brush = pbrush and function(item,dat)
        local item = pbrush(player,item,dat)
        dat.data.px,dat.data.py = dat.x,dat.y
        if item then
          player:set_wielded_item(item)
        end
      end or function()end
      for pointed_thing in ray do
        --print("TRACING OBJECT TYPE: "..pointed_thing.type)
        if firstobj then
          if pointed_thing.type == "object" then
            obj = pointed_thing.ref
            ipos = pointed_thing.intersection_point
          end
          break
        end
        firstobj = true
      end
      if not obj then
        return
      end
      local ent = obj:get_luaentity()
      if ent and ent.painter_entype then
        --print("ENTITY is CANVAS! :)")
        local npos = ent.nodepos
        if minetest.is_protected(npos,name) then
          minetest.record_protection_violation(npos,name)
          return
        end
        local rpos = vector.subtract(ipos,npos)
        local node = minetest.get_node(npos)
        local meta = minetest.get_meta(npos)
        if node.name == "painter:easel" and meta:get_int("has_canvas") == 1 then
          --print("NODE IS EASEL! :D")
          local width,height = meta:get_int("canvas_width"),meta:get_int("canvas_height")
          local ov = get_orientation_values(node)
          local tpos = {
		        x = ov.neg_depth.x*rpos.z + ov.neg_width.x*rpos.x + ov.neg_height.x*rpos.y,
		        y = ov.neg_depth.y*rpos.z + ov.neg_width.y*rpos.x + ov.neg_height.y*rpos.y,
		        z = ov.neg_depth.z*rpos.z + ov.neg_width.z*rpos.x + ov.neg_height.z*rpos.y,
		      }
		      tpos.y = (tpos.y-0.5)
		      tpos.x = tpos.x+width/2
		      if tpos.z < 0 then
		        --print("Z < 0! xD")
		        local x,y = tpos.x,tpos.y
		        x,y = math.floor(x*PICTURE_RES),math.floor(y*PICTURE_RES)
		        --print(x,y)
		        local w,h = width*PICTURE_RES,height*PICTURE_RES
		        y = (h-1-y)
		        if x >= 0 and y >= 0 and x < w and y < h then
		          --print("Coords in range! xXDD")
		          local lg,rg = minetest.get_item_group(item,"brush_snapshot_left") > 0,minetest.get_item_group(item,"brush_snapshot_right") > 0
		          local pic = keydowns[name] and keydowns[name].pic or pictureAccess(npos,(lg and c.LMB) or (rg and not c.LMB))
		          if not pic then
		            return
		          end
		          local function softset(x,y,c,r,blend)
		            for x=x-r,x+r do
		              for y=y-r,y+r do
                    if x >= 0 and y >= 0 and x < w and y < h then
                      local c1 = pic:get(x,y)
                      pic:set(x,y,blend and blend(c1,c) or c)
                    end
                  end
                end
              end
              local function softget(x,y,ra)
                local r,g,b,a = 0,0,0,0
                local pc = 0
                --print(">",x,y,ra)
                --print("[[")
		            for x=x-ra,x+ra do
		              for y=y-ra,y+ra do
                    if x >= 0 and y >= 0 and x < w and y < h then
                      local rr,gg,bb,aa = anymon.hex_to_rgba(pic:get(x,y))
                      r,g,b,a = r+rr,g+gg,b+bb,a+aa
                      --print(x,y,rr,gg,bb,aa)
                      pc=pc+1
                    else
                      --print("oob",x,y)
                    end
                  end
                end
                --print("]]")
                if pc == 0 then
                  return 0x00000000
                end
                local f = math.floor
                r,g,b,a = f(r/pc),f(g/pc),f(b/pc),f(a/pc)
                --print(r,g,b,a)
                return anymon.rgba_to_hex(r,g,b,a)
              end
              local kd = keydowns[name] or {x=x,y=y,pos=npos,pic=pic,store={},x=x,y=y,w=w,h=h}
              if (not keydowns[name]) or keydowns[name].x ~= x or keydowns[name].y ~= y then
		            if c.LMB and pic then
		              if keydowns[name] and vector.equals(keydowns[name].pos,npos) then
		                local k = keydowns[name]
		                local l = line(k.x,k.y,x,y)
		                for k,p in ipairs(l) do
		                  local x,y = p[1],p[2]
		                  brush(item,{button="left",x=x,y=y,w=w,h=h,picture=pic,data=kd,softset=softset,softget=softget})
		                end
		              else
		                brush(item,{button="left",x=x,y=y,w=w,h=h,picture=pic,data=kd,softset=softset,softget=softget})
		              end
		            elseif pic then
		              if keydowns[name] and vector.equals(keydowns[name].pos,npos) then
		                local k = keydowns[name]
		                local l = line(k.x,k.y,x,y)
		                for k,p in ipairs(l) do
		                  local x,y = p[1],p[2]
		                  brush(item,{button="right",x=x,y=y,w=w,h=h,picture=pic,data=kd,softset=softset,softget=softget})
		                end
		              else
		                brush(item,{button="right",x=x,y=y,w=w,h=h,picture=pic,data=kd,softset=softset,softget=softget})
		              end
		            end
		          end
		          local tiles = {}
		          for k,v in pairs(pic.tiles) do
		            table.insert(tiles,k)
		          end
		          renderCanvas(npos,true,tiles)
		          keydowns[name] = kd
		          kd.x = x
		          kd.y = y
		        end
		      end
        end
      end
    else
      keydowns[name] = nil
    end
  end
end)
