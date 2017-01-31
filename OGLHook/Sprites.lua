if OGLHook_Sprites ~= nil then
	return
end

OGLHook_Sprites = {
	list = {}
}


local OGLHook_RenderObject = {
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


local _apply = function (cls, obj)
	for k, v in pairs(cls) do
		obj[k] = v
	end

	return obj
end


setmetatable(
	OGLHook_Sprite,
	{__call =
		function (cls, x, y, texture, visible)
			local sprite = OGLHook_RenderObject(x, y, 0, 0, visible)
			sprite = _apply(OGLHook_Sprite, sprite)

			table.insert(OGLHook_Sprites.list, sprite)
			-- sprite:assignTexture(texture)
			return sprite
		end
	}
)


-- OGLHook_TextContainer = {}

-- setmetatable(
-- 	OGLHook_TextContainer,
-- 	{__call =
-- 		function (cls, font_map, x, y, text)
-- 			local container = OGLHook_RenderObject(x, y, 0, 0, visible)
-- 			table.insert(OGLHook_Sprites.list, cls:_new(container))

-- 			-- container:asdasdasd
-- 			return container
-- 		end
-- 	}
-- )

-- cls, x, y, width, height, visible
-- cls, x, y, width, height, color, visible
-- cls, x, y, texture, visible


-- TODO: Move it to Sprite and TextContainer
OGLHook_RenderObject.resetSize = function (self)
	local tw, th = self.texture.width, self.texture.height

	if tw > 0 and th > 0 then
		self:setSize(tw, th)
	end
end

OGLHook_RenderObject.onBeforeRender = nil
OGLHook_RenderObject.onAfterRender = nil


OGLHook_RenderObject.render = function (self)
	return
end


OGLHook_RenderObject.getPosition = function (self)
	return self.x, self.y
end


OGLHook_RenderObject.setPosition = function (self, x, y)
	self.x = x
	self.y = y
end


OGLHook_RenderObject.getSize = function (self)
	return self.width, self.height
end


OGLHook_RenderObject.setSize = function (self, width, height)
	self.width = width
	self.height = height
end


OGLHook_RenderObject.getScale = function (self)
	return self.width, self.height
end


OGLHook_RenderObject.setScale = function (self, scale_x, scale_y)
	self.scale_x = scale_x
	self.scale_y = scale_y
end


OGLHook_RenderObject.resetScale = function (self)
	self:setScale(1, 1)
end


OGLHook_RenderObject.getRotation = function (self)
	return self.rotation
end


OGLHook_RenderObject.setRotation = function (self, rotation)
	self.rotation = rotation
end


OGLHook_RenderObject.resetRotation = function (self)
	self:setRotation(0)
end


OGLHook_RenderObject.getPivotPoint = function (self)
	return self.pivot_x, self.pivot_y
end


OGLHook_RenderObject.setPivotPoint = function (self, x, y)
	self.pivot_x = x
	self.pivot_y = y
end


OGLHook_RenderObject.resetPivotPoint = function (self)
	local w, h = self:getSize()
	self.pivot_x, self.pivot_y = w / 2, h / 2
end


OGLHook_RenderObject.getColor = function (self)
	return self.color
end


OGLHook_RenderObject.setColor = function (self, color)
	return self.color
end


OGLHook_RenderObject.resetColor = function (self)
	self.color = 0xffffff
end


OGLHook_RenderObject.getAlpha = function (self)
	return self.alpha
end


OGLHook_RenderObject.setAlpha = function (self, alpha)
	if alpha > 0 then
		alpha = 1
	elseif alpha < 0 then
		alpha = 0
	end

	self.alpha = alpha
end


OGLHook_RenderObject.resetAlpha = function (self, alpha)
	self:setAlpha(1)
end


OGLHook_RenderObject.getVisible = function (self)
	return self.visible
end


OGLHook_RenderObject.setVisible = function (self, visible)
	if visible then
		self.visible = true
	else
		self.visible = false
	end
end


OGLHook_RenderObject.new = function (cls, x, y, width, height, visible)
	local obj = _apply(OGLHook_RenderObject, {})

	obj:setPosition(x, y)
	obj:setSize(width, height)

	obj:resetPivotPoint()
	obj:resetScale()
	obj:resetColor()
	obj:resetAlpha()
	obj:setVisible(visible)

	return obj
end


setmetatable(OGLHook_RenderObject, {__call=OGLHook_RenderObject.new})