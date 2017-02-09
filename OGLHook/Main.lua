--[[
Plugin for Cheat Engine what provide for you small interface to OpenGL

tested with
	Cheat Engine 6.6
by srg91
]]--

require([[autorun\OGLHook\Const]])
require([[autorun\OGLHook\Utils]])
require([[autorun\OGLHook\Commands]])
require([[autorun\OGLHook\Textures]])
require([[autorun\OGLHook\Sprites]])
require([[autorun\OGLHook\Fonts]])

-- Private --
local OPENGL32_NAME = 'OPENGL32'
local OGLH_ADDR_NAME = OPENGL32_NAME .. '.wglSwapBuffers'
OGL_HOOK = nil


local function OGLHook_InitMemory()
	OGLHook_Utils.AllocateRegister('oglh_hook_code', 16384)
	OGLHook_Utils.AllocateRegister('oglh_window_hdc', 4)

	OGLHook_Utils.AllocateRegister('oglh_parent_context', 4)
	OGLHook_Utils.AllocateRegister('oglh_context', 4)
	OGLHook_Utils.AllocateRegister('oglh_thread_context', 4)

	OGLHook_Utils.AllocateRegister('oglh_initialized', 1, 'db 0')

	OGLHook_Utils.AllocateRegister('oglh_image_ptr', 4)
	OGLHook_Utils.AllocateRegister('oglh_image_handle', 4)
	OGLHook_Utils.AllocateRegister('oglh_window_rect', 20)

	return true
end


local function OGLHook_ClearHook(ogl_hook)
	local command = [[
		OPENGL32.wglSwapBuffers:
	]] .. ogl_hook._orig_opcodes
	return autoAssemble(command)
end


local function OGLHook_RewriteHook()
	local command = [[
		label(oglh_return)

		OPENGL32.wglSwapBuffers:
		jmp oglh_hook_code
		oglh_return:

		oglh_hook_code:
		push [esp+4]
		pop [oglh_window_hdc]
	]] .. OGLHook_Commands.commands_stack_text .. '\r\n' .. [[
		jmp oglh_return
	]]
	return autoAssemble(command)
end


local function OGLHook_RewriteBody()
	local command = [[
		label(oglh_return)

		OPENGL32.wglSwapBuffers+5:
		oglh_return:

		oglh_hook_code:
		push [esp+4]
		pop [oglh_window_hdc]
	]] .. OGLHook_Commands.commands_stack_text .. '\r\n' .. [[
		jmp oglh_return
	]]
	return autoAssemble(command)
end


function OGLHook_UpdateWindowSize()
	OGLHook_Commands.RunExternalCmd([[
		push [oglh_window_hdc]
		call WindowFromDC

		push oglh_window_rect
		push eax
		call GetClientRect

		fild [oglh_window_rect]
		fstp dword ptr [oglh_window_rect]

		fild [oglh_window_rect+4]
		fstp dword ptr [oglh_window_rect+4]

		fild [oglh_window_rect+8]
		fstp dword ptr [oglh_window_rect+8]

		fild [oglh_window_rect+c]
		fstp dword ptr [oglh_window_rect+c]

		fld [oglh_window_rect+8]
		fld [oglh_window_rect+c]
		fdivp
		fstp [oglh_window_rect+10]
	]])
end

local function OGLHook_BeforeUpdate()
	OGLHook_Commands.RunExternalCmd([[
		label(initialized)
		label(initialization)
	]])

	OPENGL32.wglGetCurrentContext('->', 'oglh_parent_context')

	if OGL_HOOK._initialization_part ~= nil then
		OGLHook_Commands.RunExternalCmd(OGL_HOOK._initialization_part)
	end

	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_context]')

	OPENGL32.glBlendFunc(OPENGL32.GL_SRC_ALPHA, OPENGL32.GL_ONE_MINUS_SRC_ALPHA)
end


local function OGLHook_AfterUpdate()
	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_parent_context]')
	OGLHook_Commands.RunExternalCmd(OGL_HOOK._orig_opcodes)
end


local function _getSelf(...)
	local self, _ = ...
	if self == nil then
		self = OGL_HOOK
	end

	return self, _
end


local function OGLHook_Update(...)
	local self = _getSelf(...)
	if self == nil then
		return
	end

	if self._orig_opcodes == nil then
		return
	end

	OGLHook_BeforeUpdate()

	for _,sprite in ipairs(OGLHook_Sprites.list) do
		if sprite and sprite.visible then
			sprite:before_render()
			sprite:render()
			sprite:after_render()
		end
	end

	for i,k in ipairs(self.update_funcs) do
		k()
	end

	OGLHook_AfterUpdate()
	OGLHook_Commands.Flush()

	return OGLHook_RewriteBody()
end


local function OGLHook_GetOpcodesText(address, size)
	local start_address

	if type(address) == 'number' then
		start_address = address
	elseif type(address) == 'string' and OGLHook_Utils.getAddressSilent(address) ~= 0 then
		start_address = OGLHook_Utils.getAddressSilent(address)
	else
		return
	end

	local opcodes_len = 0
	local result = ''

	repeat
		local current_opcode_size = getInstructionSize(start_address + opcodes_len)
		if current_opcode_size == nil or current_opcode_size == 0 then
			break
		end

		local _, opcode_text, _ = splitDisassembledString(disassemble(start_address + opcodes_len))

		if #result > 0 then
			result = result .. '\r\n'
		end
		result = result .. opcode_text

		opcodes_len = opcodes_len + current_opcode_size
	until opcodes_len >= size

	return result
end


local function OLGHook_CreteFakeWindow()
	OGLHook_Utils.AllocateRegister(
		'oglh_wnd_class_name', 256, [[db 'OGLHookFakeWindowClass',0]]
	)

	OGLHook_Utils.AllocateRegister('oglh_fake_wnd_class', 48, [[
		// cbSize
		dd #48
		// style
		dd 0
		// lpfnWndProc
		dd DefWindowProcA
		// cbClsExtra
		dd 0
		// cbWndExtra
		dd 0
		// hinstance
		dd 0
		// hIcon
		dd 0
		// hCursor
		dd 0
		// hbrBackground
		dd 0
		// lpszMenuName
		dd 0
		// lpszClassName
		dd oglh_wnd_class_name
		// hIconSm
		dd 0
	]])

	OGLHook_Utils.AllocateRegister('oglh_fake_wnd_pf', 40, [[
		// nSize
		dw #40
		// nVersion
		dw 1
		// dwFlags
		// PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER
		dd #37
		// PFD_TYPE_RGBA, 32 bit framebuffer
		db 0 #32
		// ...
		dd 0 0 0
		db 0
		// 24 bit depthbuffer, 8 bit stencilbuffer, 0 aux buffers
		db #24 #8 0
		// PFD_MAIN_PLANE
		db 0
		// ...
		dd 0
	]])

	OGLHook_Utils.AllocateRegister('oglh_current_hinstance', 4)
	OGLHook_Utils.AllocateRegister('oglh_thread_hwnd', 4)
	OGLHook_Utils.AllocateRegister('oglh_thread_hdc', 4)

	OGLHook_Commands.RunExternalCmd('call GetModuleHandleA', 0, 'oglh_current_hinstance')

	OGLHook_Commands.RunExternalCmd([[
		push [oglh_current_hinstance]
		pop [oglh_fake_wnd_class+24]
	]])

	OGLHook_Commands.RunExternalCmd('call RegisterClassExA', 'oglh_fake_wnd_class')

	OGLHook_Commands.RunExternalCmd(
		'call CreateWindowExA',
		{0, 'oglh_wnd_class_name', 0, 0, 100, 100, 1, 1, 0, 0, '[oglh_current_hinstance]', 0},
		'oglh_thread_hwnd'
	)

	OGLHook_Commands.RunExternalCmd('call GetDC', '[oglh_thread_hwnd]', 'oglh_thread_hdc')

	OGLHook_Commands.RunExternalCmd('call ChoosePixelFormat', {'[oglh_thread_hdc]', 'oglh_fake_wnd_pf'})

	OGLHook_Commands.RunExternalCmd('call SetPixelFormat', {'[oglh_thread_hdc]', 'eax', 'oglh_fake_wnd_pf'})
end


local function OGLHook_Destroy_Fake_Window()
	if OGLHook_Utils.getAddressSilent('oglh_wnd_class_name') == 0 then
		return
	end

	local command = [[
		push [oglh_thread_hwnd]
		call DestroyWindow

		push [oglh_current_hinstance]
		push oglh_fake_wnd_class
		call UnregisterClassA
	]]

	OGLHook_Commands.SyncRun(command)
end


local function OGLHook_Init(...)
	local self = _getSelf(...)
	if self == nil then
		return false
	end

	self._orig_opcodes = OGLHook_GetOpcodesText(OGLH_ADDR_NAME, 5)

	OGLHook_Commands.RunExternalCmd(self._orig_opcodes)
	OGLHook_Commands.Flush()

	if not OGLHook_RewriteHook() then
		return false
	end

	OGLHook_Commands.RunExternalCmd([[
		cmp [oglh_initialized], 0
		jnz initialized
	]])

	OLGHook_CreteFakeWindow()

	OPENGL32.wglCreateContext('[oglh_window_hdc]', '->', 'oglh_context')
	OPENGL32.wglCreateContext('[oglh_thread_hdc]', '->', 'oglh_thread_context')

	OPENGL32.wglShareLists('[oglh_parent_context]', '[oglh_thread_context]')
	OPENGL32.wglShareLists('[oglh_thread_context]', '[oglh_context]')

	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_context]')

	OGLHook_Commands.PutLabel('initialization')
	OGLHook_Commands.RunExternalCmd('mov [oglh_initialized],#1')

	OGLHook_UpdateWindowSize()

	if type(OGL_HOOK.onInit) == 'function' then
		OGL_HOOK:onInit()
	else
		OGLHook_SimpleOrtho()
	end

	OGLHook_Commands.PutLabel('initialized')
	self._initialization_part = OGLHook_Commands.Flush()

	if not OGLHook_Update() then
		return false
	end

	return true
end


local function OGLHook_Destroy(...)
	local self = _getSelf(...)
	if self == nil then
		return
	end

	OGLHook_ClearHook(self)
	OGLHook_Destroy_Fake_Window()

	local units = {
		'Sprites', 'Textures', 'Fonts', 'Commands', 'Utils', 'Errors', 'Const'
	}

	for _,unit_name in ipairs(units) do
		local olgh_unit_name = 'OGLHook_' .. unit_name
		local unit_table = _G[olgh_unit_name]

		if unit_table.destroy then
			unit_table:destroy()
		end

		_G[olgh_unit_name] = nil
	end

	for i=#units,1,-1 do
		local oglh_unit_path = [[autorun\OGLHook\]] .. units[i]
		package.loaded[oglh_unit_path] = nil
		require(oglh_unit_path)
	end
end


function OGLHook_isActive(self)
	local init_addr = OGLHook_Utils.getAddressSilent('oglh_initialized')
	if init_addr == 0 then
		return false
	end

	return readBytes(init_addr, 1, false) == 1
end

-- Public --
function OGLHook_SimpleOrtho(x, y, width, height, znear, zfar)
	local x = x or '[oglh_window_rect]'
	local y = y or '[oglh_window_rect+4]'
	local width = width or '[oglh_window_rect+8]'
	local height = height or '[oglh_window_rect+c]'
	local znear = znear or 1.0
	local zfar = zfar or -1.0

	OPENGL32.glMatrixMode(OPENGL32.GL_PROJECTION)
	OPENGL32.glLoadIdentity()

	OPENGL32.glOrtho(x, width, height, y, znear, zfar)

	OPENGL32.glMatrixMode(OPENGL32.GL_MODELVIEW)
	OPENGL32.glLoadIdentity()

	OPENGL32.glClearColor(0, 0, 0, 1)
end


function OGLHook_SimplePerspective(fov, aspect_ratio, znear, zfar)
	local fov = fov or 45
	local aspect_ratio = aspect_ratio or '[oglh_window_rect+10]'
	local znear = znear or 0.1
	local zfar = zfar or 100

	OPENGL32.glMatrixMode(OPENGL32.GL_PROJECTION)
	OPENGL32.glLoadIdentity()

	GLU32.gluPerspective(fov, aspect_ratio, znear, zfar)

	OPENGL32.glMatrixMode(OPENGL32.GL_MODELVIEW)
	OPENGL32.glLoadIdentity()

	OPENGL32.glClearColor(0, 0, 0, 1)

	OPENGL32.glShadeModel(OPENGL32.GL_SMOOTH)
	OPENGL32.glClearDepth('(float)1')
	OPENGL32.glEnable(OPENGL32.GL_DEPTH_TEST)
	OPENGL32.glDepthFunc(OPENGL32.GL_LEQUAL)
	OPENGL32.glHint(OPENGL32.GL_PERSPECTIVE_CORRECTION_HINT, OPENGL32.GL_NICEST)
end


function OGLHook_Create(onInit)
	reinitializeSymbolhandler()

	local hook_address = OGLHook_Utils.getAddressSilent(OGLH_ADDR_NAME)
	if hook_address == 0 then
		return -1
	end

	if OGL_HOOK ~= nil then
		OGL_HOOK:destroy()
	end

	if not OGLHook_InitMemory() then
		return -2
	end

	OGL_HOOK = {
		_orig_opcodes=nil,
		_initialization_part=nil,

		update_funcs={},

		init = OGLHook_Init,
		onInit = onInit,
		update = OGLHook_Update,
		registerUpdateFunc = function(self, update_func)
			table.insert(self.update_funcs, update_func)
		end,
		destroy = OGLHook_Destroy,

		loadTexture = OGLHook_Textures.LoadTexture,
		createSprite = OGLHook_Sprites.Sprite,

		generateFontMap = OGLHook_Fonts.generateFontMap,
		createTextContainer = OGLHook_Sprites.TextContainer,

		isActive = OGLHook_isActive,
	}

	if not OGL_HOOK:init() then
		return -3
	end

	return OGL_HOOK
end
