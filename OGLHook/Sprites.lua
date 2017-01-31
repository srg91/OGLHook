if OGLHook_Sprites ~= nil then
	return
end

OGLHook_Sprites = {
	list = {}
}


require([[autorun\OGLHook\Commands]])
require([[autorun\OGLHook\Textures]])
require([[autorun\OGLHook\Utils]])

OGLHook_Sprites.RenderObject = {
	x = nil,
	y = nil,

	width = nil,
	height = nil,

	scale_x = nil,
	scale_y = nil,

	rotation = nil,
	pivot_x = nil,
	pivot_y = nil,

	color = nil,
	alpha = nil,

	visible = nil,
}


OGLHook_Sprite = {}


local inherit = function (cls, obj)
	if obj == nil then
		obj = {}
	end

	for k, v in pairs(cls) do
		obj[k] = v
	end

	return obj
end


OGLHook_Sprites.RenderObject.before_render = function (self)
	OPENGL32.glPushMatrix()

	OPENGL32.glTranslatef(self.x, self.y, 0)
	OPENGL32.glRotatef(self.rotation, 0, 0, 1)
	OPENGL32.glTranslatef(self.x + self.pivot_x, self.y + self.pivot_y, 0)

	local cr = bit32.band(self.color, 0x0000ff) / 255
	local cg = bit32.band(self.color, 0x00ff00) / 255
	local cb = bit32.band(self.color, 0xff0000) / 255
	OPENGL32.glColor4f(cr, cg, cb, self.alpha)

--	local nx = self.x + self.pivot_x
--	local ny = self.y + self.pivot_y
--	local a = self.rotation * math.pi / 180
--
--	local px = nx * math.cos(a) - ny * math.sin(a)
--	local py = ny * math.cos(a) + ny * math.sin(a)
--	OPENGL32.glTranslatef(px, py, 0)
end


OGLHook_Sprites.RenderObject.render = nil


OGLHook_Sprites.RenderObject.after_render = function (self)
	OPENGL32.glPopMatrix()
end


OGLHook_Sprites.RenderObject.getPosition = function (self)
	return self.x, self.y
end


OGLHook_Sprites.RenderObject.setPosition = function (self, x, y)
	self.x = x
	self.y = y
end


OGLHook_Sprites.RenderObject.getSize = function (self)
	return self.width, self.height
end


OGLHook_Sprites.RenderObject.setSize = function (self, width, height)
	self.width = width
	self.height = height
end


OGLHook_Sprites.RenderObject.getScale = function (self)
	return self.width, self.height
end


OGLHook_Sprites.RenderObject.setScale = function (self, scale_x, scale_y)
	self.scale_x = scale_x
	self.scale_y = scale_y
end


OGLHook_Sprites.RenderObject.resetScale = function (self)
	self:setScale(1, 1)
end


OGLHook_Sprites.RenderObject.getRotation = function (self)
	return self.rotation
end


OGLHook_Sprites.RenderObject.setRotation = function (self, rotation)
	self.rotation = rotation
end


OGLHook_Sprites.RenderObject.resetRotation = function (self)
	self:setRotation(0)
end


OGLHook_Sprites.RenderObject.getPivotPoint = function (self)
	return self.pivot_x, self.pivot_y
end


OGLHook_Sprites.RenderObject.setPivotPoint = function (self, x, y)
	self.pivot_x = x
	self.pivot_y = y
end


OGLHook_Sprites.RenderObject.resetPivotPoint = function (self)
	local w, h = self:getSize()
	self.pivot_x, self.pivot_y = w / 2, h / 2
end


OGLHook_Sprites.RenderObject.getColor = function (self)
	return self.color
end


OGLHook_Sprites.RenderObject.setColor = function (self, color)
	return self.color
end


OGLHook_Sprites.RenderObject.resetColor = function (self)
	self.color = 0xffffff
end


OGLHook_Sprites.RenderObject.getAlpha = function (self)
	return self.alpha
end


OGLHook_Sprites.RenderObject.setAlpha = function (self, alpha)
	if alpha > 0 then
		alpha = 1
	elseif alpha < 0 then
		alpha = 0
	end

	self.alpha = alpha
end


OGLHook_Sprites.RenderObject.resetAlpha = function (self, alpha)
	self:setAlpha(1)
end


OGLHook_Sprites.RenderObject.getVisible = function (self)
	return self.visible
end


OGLHook_Sprites.RenderObject.setVisible = function (self, visible)
	if visible then
		self.visible = true
	else
		self.visible = false
	end
end


OGLHook_Sprites.RenderObject.new = function (cls, x, y, width, height, visible)
	local obj = inherit(OGLHook_Sprites.RenderObject, {})

	obj:setPosition(x, y)
	obj:setSize(width, height)

	obj:resetPivotPoint()
	obj:resetScale()
	obj:resetColor()
	obj:resetAlpha()
	obj:setVisible(visible)

	return obj
end

setmetatable(
	OGLHook_Sprites.RenderObject,
	{__call=OGLHook_Sprites.RenderObject.new}
)


OGLHook_Sprites.Sprite = inherit(OGLHook_Sprites.RenderObject)


OGLHook_Sprites.Sprite.resetSize = function (self)
	if self.texture then
		self:setSize(self.texture.width, self.texture.height)
	end
	self:resetPivotPoint()
end


OGLHook_Sprites.Sprite.assignTexture = function (self, texture)
	if not texture then
		return
	end

	if type(texture) == 'string' then
		texture = OGLHook_Textures.LoadTexture(texture)
	end

	self.texture = texture
	self:resetSize()
end

setmetatable(
	OGLHook_Sprites.Sprite,
	{
		__call = function (cls, x, y, texture, visible)
			local sprite = cls(x, y, 0, 0, visible)

			sprite:assingTexture(texture)

			table.insert(OGLHook_Sprites.list, sprite)
			return sprite
		end
	}
)


OGLHook_Sprites.TextContainer = {
--	background_color = nil,
--	background_alpha = nil,

	_register_label_template = 'oglh_text_container_%d',
}


OGLHook_Sprites.TextContainer =
	inherit(OGLHook_Sprites.RenderObject, OGLHook_Sprites.TextContainer)

-- TODO: Move it to Sprite and TextContainer
OGLHook_Sprites.TextContainer.resetSize = function (self)
--	local tw, th = self.texture.width, self.texture.height
--
--	if tw > 0 and th > 0 then
--		self:setSize(tw, th)
--	end
--	self:resetPivotPoint()
end


OGLHook_Sprites.TextContainer.setText = function(self, text)
	local font_map = self.font_map

	if OGLHook_Utils.getAddressSilent(self.register) ~= 0 then
		OGLHook_Utils.DeallocateRegister(self.register)
	end

	-- glInterleavedArrays
	-- GL_T2F_V3F
	-- 20 bytes for one point
	-- 80 bytes for one symbol
	OGLHook_Utils.AllocateRegister(self.register, 80*#text)

	local container_array_floats = {}
	local container_array = {}

	local current_pos = 0
	local width_coof = 1 / font_map.width

	local text_width = 0

	for i=1,#text do
		local char = text:sub(i,i)
		local char_byte = string.byte(char)

		local char_left, char_width = unpack(font_map.letters[char_byte])

		local texture_left = char_left * width_coof
		local texture_width = char_width * width_coof

		text_width = text_width + char_width

		-- Texture 0,0
		table.insert(container_array_floats, texture_left)
		table.insert(container_array_floats, 0)

		-- Vertex 0,0,0
		table.insert(container_array_floats, current_pos)
		table.insert(container_array_floats, 0)
		table.insert(container_array_floats, 0)

		-- Texutre 0,1
		table.insert(container_array_floats, texture_left)
		table.insert(container_array_floats, 1)

		-- Vertex 0,1,0
		table.insert(container_array_floats, current_pos)
		table.insert(container_array_floats, font_map.height)
		table.insert(container_array_floats, 0)

		-- Texutre 1,1
		table.insert(container_array_floats, texture_left + texture_width)
		table.insert(container_array_floats, 1)

		-- Vertex 1,1,0
		table.insert(container_array_floats, current_pos + char_width)
		table.insert(container_array_floats, font_map.height)
		table.insert(container_array_floats, 0)

		-- Texutre 1,0
		table.insert(container_array_floats, texture_left + texture_width)
		table.insert(container_array_floats, 0)

		-- Vertex 1,0,0
		table.insert(container_array_floats, current_pos + char_width)
		table.insert(container_array_floats, 0)
		table.insert(container_array_floats, 0)

		current_pos = current_pos + char_width
	end

	for _,current in ipairs(container_array_floats) do
		for _,byte in ipairs(floatToByteTable(current)) do
			table.insert(container_array, byte)
		end
	end

	writeBytes(self.register, container_array)
	self.text = text

	self:setSize(text_width, font_map.height)
end


OGLHook_Sprites.TextContainer.render = function (self)
	if not (type(self.text) == 'string' and #self.text > 0) then
		return false
	end

	if OGLHook_Utils.getAddressSilent(self.register) == 0 then
		return false
	end

	if not self.visible then
		return false
	end

	local dword_count = 4*#self.text

	OPENGL32.glPushMatrix()

	local cr, cg, cb = self.color & 0x0000ff, self.color & 0x00ff00, self.color & 0xff0000

	OPENGL32.glColor4f(cr / 255, cg / 255, cb / 255, self.alpha)
	OPENGL32.glTranslatef(self.x, text_container.y, 0)

	OPENGL32.glBindTexture(OPENGL32.GL_TEXTURE_2D, self.font_map.texture.register)

	OPENGL32.glInterleavedArrays(OPENGL32.GL_T2F_V3F, 20, self.register)
	OPENGL32.glDrawArrays(OPENGL32.GL_QUADS, 0, dword_count)

	OPENGL32.glPopMatrix()
end


setmetatable(
	OGLHook_Sprites.TextContainer,
	{
		__call = function (cls, font_map, x, y, text, visible)
			local container = cls(x, y, 0, 0, visible)

			container.register_label = string.format(
				cls._register_label_template,
				#OGLHook_Sprites.list+1
			)

			container:setColor(font_map.color)
			if text then
				container:setText(text)
			end

			table.insert(OGLHook_Sprites.list, container)
			return container
		end
	}
)