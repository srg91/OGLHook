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

	OPENGL32.glTranslatef(self.x - self.pivot_x, self.y - self.pivot_y, 0)
	OPENGL32.glTranslatef(self.pivot_x, self.pivot_y, 0)
	OPENGL32.glScalef(self.scale_x, self.scale_y, 1)
	OPENGL32.glRotatef(self.rotation, 0, 0, 1)
	OPENGL32.glTranslatef(-self.pivot_x, -self.pivot_y, 0)

	local cr = (self.color & 0x0000ff) / 255
	local cg = ((self.color & 0x00ff00) >> 8) / 255
	local cb = ((self.color & 0xff0000) >> 16) / 255
	OPENGL32.glColor4f(cr, cg, cb, self.alpha)
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
	self:resetPivotPoint()
end


OGLHook_Sprites.RenderObject.getScale = function (self)
	return self.scale_x, self.scale_y
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
	-- local w, h = self:getSize()
	-- self.pivot_x, self.pivot_y = w / 2, h / 2
	self:setPivotPoint(0, 0)
end


OGLHook_Sprites.RenderObject.getColor = function (self)
	return self.color
end


OGLHook_Sprites.RenderObject.setColor = function (self, color)
	self.color = color
end


OGLHook_Sprites.RenderObject.resetColor = function (self)
	self.color = 0xffffff
end


OGLHook_Sprites.RenderObject.getAlpha = function (self)
	return self.alpha
end


OGLHook_Sprites.RenderObject.setAlpha = function (self, alpha)
	if alpha > 1 then
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


OGLHook_Sprites.RenderObject.destory = function (self)
end


OGLHook_Sprites.RenderObject.new = function (cls, x, y, width, height, visible)
	local obj = inherit(OGLHook_Sprites.RenderObject, {})

	obj:setPosition(x, y)
	obj:setSize(width, height)

	obj:resetPivotPoint()
	obj:resetRotation()
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


OGLHook_Sprites.Sprite = {
	texture_l = nil,
	texture_r = nil,
	texture_t = nil,
	texture_b = nil
}


OGLHook_Sprites.Sprite.resetSize = function (self)
	if self.texture then
		self:setSize(self.texture.width, self.texture.height)
	end
end


OGLHook_Sprites.Sprite.getTextureCoordinates = function (self)
	return self.texture_l, self.texture_r, self.texture_t, self.texture_b
end


OGLHook_Sprites.Sprite.setTextureCoordinates = function (self, tl, tr, tt, tb)
	self.texture_l = tl
	self.texture_r = tr
	self.texture_t = tt
	self.texture_b = tb
end


OGLHook_Sprites.Sprite.resetTextureCoordinates = function (self)
	self.texture_l = 0
	self.texture_r = 1
	self.texture_t = 0
	self.texture_b = 1
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
	self:resetTextureCoordinates()
end


OGLHook_Sprites.Sprite.render = function (self)
	if self.texture then
		OPENGL32.glBindTexture(OPENGL32.GL_TEXTURE_2D, self.texture.register_label)
	end

	local points = {
		{self.texture_l, self.texture_t, 0, 0},
		{self.texture_l, self.texture_b, 0, self.height},
		{self.texture_r, self.texture_b, self.width, self.height},
		{self.texture_r, self.texture_t, self.width, 0}
	}

	OPENGL32.glBegin(OPENGL32.GL_QUADS)
		for _,point in ipairs(points) do
			local tx, ty, x, y = unpack(point)
			if self.texture then
				OPENGL32.glTexCoord2f(tx, ty)
			end
			OPENGL32.glVertex2f(x, y)
		end
	OPENGL32.glEnd()
end

setmetatable(
	OGLHook_Sprites.Sprite,
	{
		__call = function (cls, x, y, texture, visible)
			local sprite = OGLHook_Sprites.RenderObject:new(x, y, 0, 0, visible)
			inherit(cls, sprite)

			sprite:assignTexture(texture)

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


OGLHook_Sprites.TextContainer.resetSize = function (self)
end


OGLHook_Sprites.TextContainer.assignFontMap = function (self, font_map)
	self.font_map = font_map
	self:setColor(self.font_map.color)
end


OGLHook_Sprites.TextContainer.setText = function(self, text)
	local font_map = self.font_map

	if OGLHook_Utils.getAddressSilent(self.register_label) ~= 0 then
		OGLHook_Utils.DeallocateRegister(self.register_label)
	end

	-- glInterleavedArrays
	-- GL_T2F_V3F
	-- 20 bytes for one point
	-- 80 bytes for one symbol
	OGLHook_Utils.AllocateRegister(self.register_label, 80*#text)

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

	writeBytes(self.register_label, container_array)
	self.text = text

	self:setSize(text_width, font_map.height)
end


OGLHook_Sprites.TextContainer.render = function (self)
	if not (type(self.text) == 'string' and #self.text > 0) then
		return false
	end

	if OGLHook_Utils.getAddressSilent(self.register_label) == 0 then
		return false
	end

	local dword_count = 4*#self.text

	OPENGL32.glBindTexture(OPENGL32.GL_TEXTURE_2D, self.font_map.texture.register_label)

	OPENGL32.glInterleavedArrays(OPENGL32.GL_T2F_V3F, 20, self.register_label)
	OPENGL32.glDrawArrays(OPENGL32.GL_QUADS, 0, dword_count)
end


setmetatable(
	OGLHook_Sprites.TextContainer,
	{
		__call = function (cls, font_map, x, y, text, visible)
			local container = OGLHook_Sprites.RenderObject:new(x, y, 0, 0, visible)
			inherit(cls, container)

			container.register_label = string.format(
				cls._register_label_template,
				#OGLHook_Sprites.list+1
			)

			container:assignFontMap(font_map)
			if text then
				container:setText(text)
			end

			table.insert(OGLHook_Sprites.list, container)
			return container
		end
	}
)