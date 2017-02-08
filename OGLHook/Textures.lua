-- https://code.logos.com/blog/2008/09/displaying_a_splash_screen_with_c_part_i.html

OGLHook_Textures = {
	textures = {},
	_image_label = 'oglh_source_image',
	_image_decoder_label = 'oglh_image_decoder',
	_register_label_template = 'oglh_texture_%s'
}

require([[autorun\OGLHook\Utils]])
require([[autorun\OGLHook\Errors]])
require([[autorun\OGLHook\Commands]])


OGLHook_Textures.InitLoadTextures = function()
	if OGLHook_Textures.consts_initialized then
		return true
	end

	if OGLHook_Utils.getAddressSilent('windowscodecs.dll') == 0 then
  		if not injectDLL('windowscodecs.dll') then
    		OGLHook_Errors.setError(OGLHook_Errors.FAIL_TO_LOAD_DLL)
    		return false
  		end
	end

	local guids = {
		CLSID_WICPngDecoder1 = {0x389ea17b, 0x5078, 0x4cde, 0xb6, 0xef, 0x25, 0xc1, 0x51, 0x75, 0xc7, 0x51},
		CLSID_WICPngDecoder2 = {0xe018945b, 0xaa86, 0x4008, 0x9b, 0xd4, 0x67, 0x77, 0xa1, 0xe4, 0x0c, 0x11},
		CLSID_WICBmpDecoder = {0x6b462062, 0x7cbf, 0x400d, 0x9f, 0xdb, 0x81, 0x3d, 0xd1, 0x0f, 0x27, 0x78},
		CLSID_WICIcoDecoder = {0xc61bfcdf, 0x2e0f, 0x4aad, 0xa8, 0xd7, 0xe0, 0x6b, 0xaf, 0xeb, 0xcd, 0xfe},
		CLSID_WICJpegDecoder = {0x9456a480, 0xe88b, 0x43ea, 0x9e, 0x73, 0x0b, 0x2d, 0x9b, 0x71, 0xb1, 0xca},
		CLSID_WICGifDecoder = {0x381dda3c, 0x9ce9, 0x4834, 0xa2, 0x3e, 0x1f, 0x98, 0xf8, 0xfc, 0x52, 0xbe},
		CLSID_WICTiffDecoder = {0x381dda3c, 0x9ce9, 0x4834, 0xa2, 0x3e, 0x1f, 0x98, 0xf8, 0xfc, 0x52, 0xbe},
		CLSID_WICWmpDecoder = {0xa26cec36, 0x234c, 0x4950, 0xae, 0x16, 0xe3, 0x4a, 0xac, 0xe7, 0x1d, 0x0d},
		CLSID_WICDdsDecoder = {0x9053699f, 0xa341, 0x429d, 0x9e, 0x90, 0xee, 0x43, 0x7c, 0xf8, 0x0c, 0x73},
		GUID_WICPixelFormat32bppPBGRA = {0x6fddc324, 0x4e03, 0x4bfe, 0xb1, 0x85, 0x3d, 0x77, 0x76, 0x8d, 0xc9, 0x10},
		GUID_IWICBitmapDecoder = {0x9edde9e7, 0x8dee, 0x47ea, 0x99, 0xdf, 0xe6, 0xfa, 0xf2, 0xed, 0x44, 0xbf},
	}

	for label, guid in pairs(guids) do
		local decoder_label = string.format('OGLH_%s', label)
		local decoder_opcodes = string.format([[
			dd %x
			dw %x
			dw %x
			db %x %x %x %x %x %x %x %x
		]], unpack(guid))

		OGLHook_Utils.AllocateRegister(decoder_label, 16, decoder_opcodes)
	end

	if OGLHook_Utils.getAddressSilent('combase.dll') ~= 0 then
		OGLHook_Textures._com_dll = 'combase'
	else
		OGLHook_Textures._com_dll = 'ole32'
	end

	OGLHook_Textures._InitCreateStreamFromMemoryFunc()
	OGLHook_Textures._InitLoadBitmapFromStream()
	OGLHook_Textures._InitCreateHBITMAP()

	OGLHook_Textures.consts_initialized = true

	return true
end


OGLHook_Textures._InitCreateStreamFromMemoryFunc = function()
	-- incoming args: pointer, size
	OGLHook_Utils.AllocateRegister('oglh_pvSourceResourceData', 4)
	OGLHook_Utils.AllocateRegister('oglh_dwResourceSize', 4)
	OGLHook_Utils.AllocateRegister('oglh_hgblResourceData', 4)
	OGLHook_Utils.AllocateRegister('oglh_pvResourceData', 4)
	OGLHook_Utils.AllocateRegister('oglh_ipStream', 4)

	local func_text = [[
		label(return)

		mov eax,[esp+4]
		mov [oglh_pvSourceResourceData],eax

		mov eax,[esp+8]
		mov [oglh_dwResourceSize],eax

		mov [oglh_ipStream],#0

		push [oglh_dwResourceSize]
		push 2
		call GlobalAlloc
		mov [oglh_hgblResourceData],eax

		cmp [oglh_hgblResourceData],0
		je return

		push [oglh_hgblResourceData]
		call GlobalLock
		mov [oglh_pvResourceData],eax

		cmp [oglh_pvResourceData],0
		je return

		push [oglh_dwResourceSize]
		push [oglh_pvSourceResourceData]
		push [oglh_pvResourceData]
		call memcpy
		add esp,0C

		push [oglh_hgblResourceData]
		call GlobalUnlock

		push oglh_ipStream
		push 1
		push [oglh_hgblResourceData]
		call ]] .. OGLHook_Textures._com_dll .. [[.CreateStreamOnHGlobal

		return:
		mov eax, [oglh_ipStream]

		ret 8
	]]

	OGLHook_Utils.AllocateRegister('OGLH_CreateStreamFromMemoryFunc', 2048, func_text)
end


OGLHook_Textures._InitLoadBitmapFromStream = function ()
	-- pointer for stream, pointer for decoder
	OGLHook_Utils.AllocateRegister('oglh_ipBitmap', 4)
	OGLHook_Utils.AllocateRegister('oglh_ipDecoder', 4)
	OGLHook_Utils.AllocateRegister('oglh_nFrameCount', 4)
	OGLHook_Utils.AllocateRegister('oglh_ipFrame', 4)
	OGLHook_Utils.AllocateRegister('oglh_current_decoder', 4)

	local co_initialize
	if OGLHook_Textures._com_dll == 'combase' then
		co_initialize = [[
			push 0
			push 0
			call combase.CoInitializeEx
		]]
	else
		co_initialize = [[
			push 0
			call CoInitialize
		]]
	end

	local func_text = [[
		label(release_decoder)
		label(return)

		mov eax,[esp+4]
		mov eax,[eax]
		mov [oglh_ipStream],eax

		mov eax,[esp+8]
		mov eax,[eax]
		mov [oglh_current_decoder],eax

		mov [oglh_ipBitmap],0

		]] .. co_initialize .. [[

		push oglh_ipDecoder
		push OGLH_GUID_IWICBitmapDecoder
		push 1
		push 0
		push [oglh_current_decoder]
		call ]] .. OGLHook_Textures._com_dll .. [[.CoCreateInstance

		cmp eax,0
		jne return

		// ipDecoder->Initialize
		mov eax,[oglh_ipDecoder]
		mov ecx,[eax]

		push 1
		push [oglh_ipStream]
		push [oglh_ipDecoder]
		call [ecx+10]

		cmp eax,0
		jne release_decoder

		// ipDecoder->GetFrameCount
		mov eax,[oglh_ipDecoder]
		mov ecx,[eax]

		push oglh_nFrameCount
		push [oglh_ipDecoder]
		call [ecx+30]

		cmp eax,0
		jne release_decoder

		// Frames != 1 so sad
		cmp [oglh_nFrameCount],1
		jne release_decoder

		// ipDecoder->GetFrame
		mov eax,[oglh_ipDecoder]
		mov ecx,[eax]

		push oglh_ipFrame
		push 0
		push [oglh_ipDecoder]
		call [ecx+34]

		cmp eax,0
		jne release_decoder

		// WICConvertBitmapSource
		push oglh_ipBitmap
		push [oglh_ipFrame]
		push OGLH_GUID_WICPixelFormat32bppPBGRA
		call WICConvertBitmapSource

		// ipFrame->Release
		mov eax,[oglh_ipFrame]
		mov ecx,[eax]

		push [oglh_ipFrame]
		call [ecx+08]

		release_decoder:

		// ipDecoder->Release
		mov eax,[oglh_ipDecoder]
		mov ecx,[eax]

		push [oglh_ipDecoder]
		call [ecx+08]

		return:
		mov eax,[oglh_ipBitmap]

		ret 8
	]]

	OGLHook_Utils.AllocateRegister('OGLH_LoadBitmapFromStreamFunc', 2048, func_text)
end


OGLHook_Textures._InitCreateHBITMAP = function ()
	-- pointer for ipBitmap
	OGLHook_Utils.AllocateRegister('oglh_bmWidth', 4)
	OGLHook_Utils.AllocateRegister('oglh_bmHeight', 4)
	OGLHook_Utils.AllocateRegister('oglh_bmInfo', 44, 'dd 0 0 0 0 0 0')
	OGLHook_Utils.AllocateRegister('oglh_pvImageBits', 4)
	OGLHook_Utils.AllocateRegister('oglh_hdcScreen', 4)
	OGLHook_Utils.AllocateRegister('oglh_HBITMAP', 4, 'dd 0')
	OGLHook_Utils.AllocateRegister('oglh_cbStride', 4)
	OGLHook_Utils.AllocateRegister('oglh_cbImage', 4)

	local func_text = [[
		label(return)

		mov eax,[esp+4]
		mov eax,[eax]
		mov [oglh_ipBitmap],eax

		// ipBitmap->GetSize
		mov eax,[oglh_ipBitmap]
		mov ecx,[eax]

		push oglh_bmHeight
		push oglh_bmWidth
		push [oglh_ipBitmap]
		call [ecx+c]

		cmp eax,0
		jne return

		// write bitmap header

		// biSize
		mov [oglh_bmInfo],28
		// biWidth
		push [oglh_bmWidth]
		pop [oglh_bmInfo+4]
		// biHeight
		mov eax,[oglh_bmHeight]
		neg eax
		mov [oglh_bmInfo+8],eax
		// biPlanes
		mov [oglh_bmInfo+c],#1
		// biBitCount
		mov [oglh_bmInfo+e],#32
		// biCompression = BI_RGB
		mov [oglh_bmInfo+10],#0

		push 0
		call GetDC
		mov [oglh_hdcScreen],eax

		push 0
		push 0
		push oglh_pvImageBits
		// DIB_RGB_COLORS
		push 0
		push oglh_bmInfo
		push [oglh_hdcScreen]
		call CreateDIBSection
		mov [oglh_HBITMAP],eax

		push [oglh_hdcScreen]
		push 0
		call ReleaseDC

		cmp [oglh_HBITMAP],0
		je return

		mov eax,[oglh_bmWidth]
		imul eax,4
		mov [oglh_cbStride],eax

		imul eax,[oglh_bmHeight]
		mov [oglh_cbImage],eax

		// ipBitmap->CopyPixels
		mov eax,[oglh_ipBitmap]
		mov ecx,[eax]

		push [oglh_pvImageBits]
		push [oglh_cbImage]
		push [oglh_cbStride]
		push 0
		push [oglh_ipBitmap]
		call [ecx+1c]

		cmp eax,0
		je return

		push oglh_HBITMAP
		call DeleteObject
		mov [oglh_HBITMAP],0

		return:
		mov eax,[oglh_HBITMAP]

		ret 4
	]]
	OGLHook_Utils.AllocateRegister('OGLH_CreateHBITMAP', 2048, func_text)
end


OGLHook_Textures.ConvertTexture = function (texture, image_addr, filter_func)
	local prev_commands = OGLHook_Commands.Flush()

	if type(image_addr) == 'string' then
		image_addr = getAddress(image_addr)
	end

	local image_size = readInteger(image_addr)
	local image_pointer = image_addr + 4
	local decoder_label = OGLHook_Textures._image_decoder_label

	local return_label = 'return'
	local release_stream_label = 'release_stream'

	OGLHook_Utils.AllocateRegister('oglh_pBitmap', 24)

	OGLHook_Commands.RunExternalCmd([[
		label(return)
		label(release_stream)
	]])

	OGLHook_Commands.RunExternalCmd(
		'call OGLH_CreateStreamFromMemoryFunc',
		{string.format('%x', image_pointer), image_size},
		'oglh_ipStream'
	)

	OGLHook_Commands.RunExternalCmd(string.format([[
		cmp [oglh_ipStream],0
		je %s
	]], return_label))

	OGLHook_Commands.RunExternalCmd(
		'call OGLH_LoadBitmapFromStreamFunc',
		{'oglh_ipStream', decoder_label},
		'oglh_ipBitmap'
	)

	OGLHook_Commands.RunExternalCmd(string.format([[
		cmp [oglh_ipBitmap],0
		je %s
	]], release_stream_label))

	OGLHook_Commands.RunExternalCmd(
		'call OGLH_CreateHBITMAP',
		'oglh_ipBitmap',
		'oglh_HBITMAP'
	)

	OGLHook_Commands.RunExternalCmd([[
		mov eax,[oglh_ipBitmap]
		mov ecx,[eax]

		push [oglh_ipBitmap]
		call [ecx+08]
	]])

	OGLHook_Commands.RunExternalCmd(
		'call GetObjectA',
		{'[oglh_HBITMAP]', 24, 'oglh_pBitmap'}
	)

	-- TODO: remove this shit and just split convert and bind
	if type(filter_func) == 'function' then
		filter_func()
	end

	OGLHook_Commands.RunExternalCmd([[
		@@:
		cmp [oglh_thread_context],0
		je @b

		@@:
		cmp [oglh_thread_hdc],0
		je @b
	]])

	OPENGL32.wglMakeCurrent('[oglh_thread_hdc]', '[oglh_thread_context]')

	OPENGL32.glEnable(OPENGL32.GL_TEXTURE_2D)

	OPENGL32.glGenTextures(1, texture.register_label)
	OPENGL32.glBindTexture(OPENGL32.GL_TEXTURE_2D, texture.register_label)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_MIN_FILTER, OPENGL32.GL_NEAREST)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_MAG_FILTER, OPENGL32.GL_NEAREST)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_WRAP_S, OPENGL32.GL_REPEAT)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_WRAP_T, OPENGL32.GL_REPEAT)
	OPENGL32.glTexImage2D(OPENGL32.GL_TEXTURE_2D, 0, OPENGL32.GL_RGBA, '[oglh_pBitmap+4]', '[oglh_pBitmap+8]', 0, OPENGL32.GL_BGRA_EXT, OPENGL32.GL_UNSIGNED_BYTE, '[oglh_pBitmap+14]')

	OGLHook_Commands.RunExternalCmd('call DeleteObject', '[oglh_pBitmap]')

	OPENGL32.glDisable(OPENGL32.GL_TEXTURE_2D)

	OGLHook_Commands.PutLabel(release_stream_label)

	OGLHook_Commands.RunExternalCmd([[
		mov eax,[oglh_ipStream]
		mov ecx,[eax]

		push [oglh_ipStream]
		call [ecx+08]
	]])

	OGLHook_Commands.PutLabel(return_label)

	OPENGL32.wglMakeCurrent(0, 0)

	local load_texture_func = OGLHook_Commands.Flush()
	OGLHook_Commands.SyncRun(load_texture_func)

	local bitmap_addr = getAddress('oglh_pBitmap')
	texture.width = readInteger(bitmap_addr + 4)
	texture.height = readInteger(bitmap_addr + 8)
	texture.bits = readPointer(bitmap_addr + 20)

	OGLHook_Utils.DeallocateRegister('oglh_pBitmap')

	OGLHook_Commands.RunExternalCmd(prev_commands)
end


OGLHook_Textures._GuessDecoder = function (str_header)
	local CLSID_WICPngDecoder
	if OGLHook_Textures._is_win81 then
		CLSID_WICPngDecoder = 'CLSID_WICPngDecoder2'
	else
		CLSID_WICPngDecoder = 'CLSID_WICPngDecoder1'
	end

	local decoder_type = 'CLSID_WICBmpDecoder'
	local decoders_map = {
		[CLSID_WICPngDecoder] = 'PNG',
		CLSID_WICBmpDecoder = 'BM',
		CLSID_WICIcoDecoder = '\000\000\001\000',
		CLSID_WICJpegDecoder = '\255\216',
		CLSID_WICGifDecoder = 'GIF',
		CLSID_WICTiffDecoder = 'II',
		CLSID_WICDdsDecoder = 'DDS',
	}

	for decoder, magic in pairs(decoders_map) do
		if string.find(str_header, magic) then
			return decoder
		end
	end

	return decoder_type
end


OGLHook_Textures._SetupDecoder = function (image_addr)
	local header_bytes = readBytes(image_addr + 4, 5, true)
	local str_header = string.format('%c%c%c%c%c', unpack(header_bytes))

	local decoder = OGLHook_Textures._GuessDecoder(str_header)
	local decoder_label = OGLHook_Textures._image_decoder_label
	local decoder_opcode = string.format('dd OGLH_%s', decoder)
	OGLHook_Utils.AllocateRegister(decoder_label, 4, decoder_opcode)
end


OGLHook_Textures._AllocateImageInGame = function (file_path)
	local file_stream = createMemoryStream()
	file_stream.loadFromFile(file_path)

	local source_image_label = OGLHook_Textures._image_label

	OGLHook_Utils.AllocateRegister(source_image_label, 4+file_stream.size)
	local source_image_addr = getAddress(source_image_label)

	writeInteger(source_image_addr, file_stream.size)
	writeBytes(source_image_addr+4, file_stream.read(file_stream.size))

	file_stream.destroy()

	return source_image_addr
end


OGLHook_Textures.DestroyTexture = function (texture)
	if not texture then
		return
	end

	OGLHook_Utils.DeallocateRegister(texture.register_label)
	OGLHook_Textures.textures[texture.register_label] = nil
end


OGLHook_Textures.LoadTexture = function (file_path_or_memory_address, filter_func)
	if not OGLHook_Textures.consts_initialized then
		if not OGLHook_Textures.InitLoadTextures() then
			return false
		end
	end

	local texture = {
		destroy = OGLHook_Textures.DestroyTexture,
	}

	local image_addr = file_path_or_memory_address
	local deallocate_memory_image = false

	if type(image_addr) == 'string' then
		deallocate_memory_image = true
		image_addr = OGLHook_Textures._AllocateImageInGame(file_path_or_memory_address)
		if image_addr == 0 then
			return false
		end
	end

	OGLHook_Textures._SetupDecoder(image_addr)

	texture.register_label = string.format(
		OGLHook_Textures._register_label_template,
		OGLHook_Utils.UniqueSuffix()
	)
	OGLHook_Utils.AllocateRegister(texture.register_label, 4, 'dd 0')

	OGLHook_Textures.ConvertTexture(texture, image_addr, filter_func)

	if deallocate_memory_image then
		OGLHook_Utils.DeallocateRegister(OGLHook_Textures._image_label)
	end
	OGLHook_Utils.DeallocateRegister(OGLHook_Textures._image_decoder_label)

	OGLHook_Textures.textures[texture.register_label] = texture
	return texture
end


OGLHook_Textures.destroy = function (self)
	for _,texture in pairs(self.textures) do
		if texture then
			texture:destroy()
		end
	end

	self.consts_initialized = false
end
