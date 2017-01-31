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
	local command = string.format([[
		mov ebx,[oglh_pBitmap+14]

		mov ecx,[oglh_pBitmap+4]
		imul ecx,[oglh_pBitmap+8]

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
