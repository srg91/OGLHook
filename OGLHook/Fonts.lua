if OGLHook_Fonts ~= nil then
	return
end

OGLHook_Fonts = {
	font_maps={},
	texts={},
	_text_register_template = 'oglh_text_container_%d'
}

require([[autorun\OGLHook\Utils]])
require([[autorun\OGLHook\Textures]])
require([[autorun\OGLHook\Commands]])


OGLHook_Fonts._normalizeAlpha = function ()
	OGLHook_Utils.AllocateRegister('o_ebx', 4)
	OGLHook_Utils.AllocateRegister('o_ecx', 4)

	local command = string.format([[
		mov ebx,[oglh_pBitmap+14]

		mov ecx,[oglh_pBitmap+4]
		imul ecx,[oglh_pBitmap+8]

		mov [o_ebx],ebx
		mov [o_ecx],ecx

		@@:
		mov eax,[ebx]
		rol eax,8
		mov al,ah
		mov [ebx],eax

		add ebx,4
		dec ecx
		cmp ecx,0
		jne @b
	]])

	OGLHook_Commands.RunExternalCmd(command)
end


OGLHook_Fonts.generateFontMap = function (font)
	local font_map = {
		color = font.getColor()
	}

	local fm_pic = createPicture()
	local fm_png = fm_pic.PNG

	fm_png.width = 1
	fm_png.height = 1
	fm_png.PixelFormat = pf24bit
	fm_png.canvas.brush.color = 0x000000

	fm_png.canvas.font.assign(font)
	fm_png.canvas.font.color = 0xffffff
	fm_png.canvas.font.quality = 'fqAntialiased'

	local text = ''
	local char_info = {}

	font_map.width = 0
	font_map.letters = {}

	-- sorry, only default ascii symbols
	for i=32,127 do
		local c = string.char(i)
		local char_width = fm_png.canvas.GetTextWidth(c)
		local char_left = font_map.width

		font_map.width = font_map.width + char_width
		font_map.letters[i] = {char_left, char_width} 

		-- for i,current in ipairs({char_left, char_width}) do
		-- 	for j,byte in ipairs(floatToByteTable(current)) do
		-- 		table.insert(char_info, byte)
		-- 	end
		-- end

		text = text .. c
	end

	font_map.height = fm_png.canvas.GetTextHeight(text)

	fm_png.width = font_map.width
	fm_png.height = font_map.height

	fm_png.canvas.TextOut(0, 0, text)

	local file_path = OGLHook_Utils.getTempFileName() .. '.png'

	fm_pic.saveToFile(file_path)
	fm_pic.destroy()

	local file_stream = createMemoryStream()
	file_stream.loadFromFile(file_path)

	os.remove(file_path)

	local font_map_index = #OGLHook_Fonts.font_maps + 1

	local image_label = string.format('oglh_font_map_image_%d', font_map_index)
	font_map.label = string.format('oglh_font_map_%d', font_map_index)

	OGLHook_Utils.AllocateRegister(image_label, file_stream.size+4)
	OGLHook_Utils.AllocateRegister(font_map.label, 4+4+8*#char_info)

	local image_addr = getAddress(image_label)
	font_map.addr = getAddress(font_map.label)

	writeInteger(image_addr, file_stream.size)
	writeBytes(image_addr + 4, file_stream.read(file_stream.size))

	file_stream.destroy()

	-- writePointer(font_map, image_addr)
	-- writeFloat(font_map.addr, font_map.width)
	-- writeFloat(font_map.addr + 4, font_map.height)
	-- writeBytes(font_map.addr + 8, char_info)

	font_map.texture = OGLHook_Textures.LoadTexture(image_addr, OGLHook_Fonts._normalizeAlpha)

	OGLHook_Utils.DeallocateRegister(image_label)

	table.insert(OGLHook_Fonts.font_maps, font_map)
	return font_map
end


OGLHook_Fonts.setContainerText = function(text_container, text)
	local font_map = text_container.font_map

	if OGLHook_Utils.getAddressSilent(text_container.register) ~= 0 then
		OGLHook_Utils.DeallocateRegister(text_container.register)
	end

	-- glInterleavedArrays
	-- GL_T2F_V3F
	-- 20 bytes for one point
	-- 80 bytes for one symbol
	OGLHook_Utils.AllocateRegister(text_container.register, 80*#text)

	local container_array_floats = {}
	local container_array = {}

	local current_pos = 0
	local width_coof = 1 / font_map.width

	for i=1,#text do 
		local char = text:sub(i,i)
		local char_byte = string.byte(char)

		local char_left, char_width = unpack(font_map.letters[char_byte])

		local texture_left = char_left * width_coof
		local texture_width = char_width * width_coof

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

	for i,current in ipairs(container_array_floats) do
		for j,byte in ipairs(floatToByteTable(current)) do
			table.insert(container_array, byte)
		end
	end

	writeBytes(text_container.register, container_array)
	text_container.text = text
end


OGLHook_Fonts.createTextContainer = function (font_map, x, y, text)
	local text_container_register = string.format(
		OGLHook_Fonts._text_register_template, 
		#OGLHook_Fonts.texts+1
	)

	-- TODO: color from font_map
	local text_container = {
		register=text_container_register,
		font_map=font_map,
		x=x,
		y=y,
		visible=true,
		color=font_map.color,
		alpha=1.0,
		text=nil,
		setText = function(self, text_)
			OGLHook_Fonts.setContainerText(self, text_)
		end
	}

	if text then
		text_container:setText(text)
	end

	table.insert(OGLHook_Fonts.texts, text_container)
	return text_container
end


OGLHook_Fonts.renderTextContainer = function (text_container)
	if not (type(text_container.text) == 'string' and #text_container.text > 0) then
		return false
	end

	if OGLHook_Utils.getAddressSilent(text_container.register) == 0 then
		return false
	end

	if not text_container.visible then
		return false
	end

	local dword_count = 4*#text_container.text
	
	OPENGL32.glPushMatrix()	

	local cr, cg, cb = text_container.color & 0x0000ff, text_container.color & 0x00ff00, text_container.color & 0xff0000

	OPENGL32.glColor4f(cr / 255, cg / 255, cb / 255, text_container.alpha)
	OPENGL32.glTranslatef(text_container.x, text_container.y, 0)
	
	OPENGL32.glBindTexture(OPENGL32.GL_TEXTURE_2D, text_container.font_map.texture.register)

	OPENGL32.glInterleavedArrays(OPENGL32.GL_T2F_V3F, 20, text_container.register)
	OPENGL32.glDrawArrays(OPENGL32.GL_QUADS, 0, dword_count)

	OPENGL32.glPopMatrix()
end