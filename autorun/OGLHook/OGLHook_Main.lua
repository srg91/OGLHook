--[[
Plugin for Cheat Engine what provide for you small interface to OpenGL

tested with
	Cheat Engine 6.6
by srg91
]]--

require([[autorun\OGLHook\OGLHook_Const]])
require([[autorun\OGLHook\OGLHook_Utils]])
require([[autorun\OGLHook\OGLHook_Commands]])

-- Private --
local OPENGL32_NAME = 'OPENGL32'
local OGLH_ADDR_NAME = OPENGL32_NAME .. '.wglSwapBuffers'
OGL_HOOK = nil


local function OGLHook_InitMemory()
	return autoAssemble([[
    	globalalloc(oglh_hook_code,16384)
    	globalalloc(oglh_window_hdc, 4)
		globalalloc(oglh_parent_context, 4)
		globalalloc(oglh_context, 4)
		globalalloc(oglh_initialized, 1)
		globalalloc(oglh_window_rect, 20)
		globalalloc(oglh_image_handle, 4)
		globalalloc(oglh_image_ptr, 4)
	]])
end


local function OGLHook_RewriteHook()
	local command = [[
		label(oglh_return)

		OPENGL32.wglSwapBuffers:
		jmp oglh_hook_code
		oglh_return:

		oglh_hook_code:
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

	OGLHook_Commands.RunExternalCmd([[
		push [esp+4]
		pop [oglh_window_hdc]
	]])

	OPENGL32.wglGetCurrentContext('->', 'oglh_parent_context')

	if OGL_HOOK._initialization_part ~= nil then
		OGLHook_Commands.RunExternalCmd(OGL_HOOK._initialization_part)
	end

	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_context]')
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


local function OGLHook_Init(...)
	local self = _getSelf(...)
	if self == nil then
		return 0
	end

	local error_exit_status = self._hot_inject and 0 or 1
	self._orig_opcodes = OGLHook_GetOpcodesText(OGLH_ADDR_NAME, 5)

	OGLHook_Commands.RunExternalCmd(self._orig_opcodes)
	OGLHook_Commands.Flush()

	if not OGLHook_RewriteHook() then
		return error_exit_status
	end

	OGLHook_Commands.RunExternalCmd([[
		cmp [oglh_initialized], 0
		jnz initialized
	]])

	OPENGL32.wglCreateContext('[oglh_window_hdc]', '->', 'oglh_context')
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
		return error_exit_status
	end

	if not self._hot_inject and self._hot_inject ~= 0 then
		debug_removeBreakpoint(OGLH_ADDR_NAME)
		return 0
	end

	return true
end


local function OGLHook_Destroy(...)
	local self = _getSelf(...)
	if self == nil then
		return
	end

	local symbols = {
		'oglh_hook_code', 'oglh_window_hdc', 'oglh_parent_context',
		'oglh_context', 'oglh_initialized', 'oglh_window_rect',
		'oglh_image_handle', 'oglh_image_ptr'
	}

	local destroy_cmd = [[
		dealloc(%s)
		unregistersymbol(%s)
	]]

	for i, v in ipairs(symbols) do
		if OGLHook_Utils.getAddressSilent(v) ~= 0 then
			autoAssemble(string.format(destroy_cmd, v, v))
		end
	end

	OGLHook_Utils.DeallocateRegisters()
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


function OGLHook_Create(hot_inject, onInit)
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
		_hot_inject=(not not hot_inject),
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
	}

	if hot_inject then
		if not OGL_HOOK:init() then
			return -3
		end
	else
		OGLHook_Textures.InitLoadTextures()
		if not debug_isDebugging() then
			debugProcess()
		end
		debug_setBreakpoint(hook_address, 0, bptExecute, OGL_HOOK.init)
	end

	return OGL_HOOK
end
