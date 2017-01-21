--[[
Plugin for Cheat Engine what provide for you small interface to OpenGL

tested with
	Cheat Engine 6.6
by srg91
]]--

require('autorun\\OGLHookConst')

-- OpenGL --

local OPENGL32_NAME = 'OPENGL32'
local OPENGL32_DLL_NAME = OPENGL32_NAME .. 'DLL'
-- local OPENGL32_RET_REGISTER = 'oglh_last_result'

OPENGL32 = {_dll_name='OPENGL32'}
GLU32 = {_dll_name='GLU32'}

OPENGL32_COMMAND_STACK = {}
OPENGL32_COMMAND_STACK_TEXT = ""


local function OGLHook_MakeCall(func_name, namespace)
	local call_function = func_name

	if namespace ~= nil then
		call_function = string.format('%s.%s', namespace, call_function)
	end

	return 'call ' .. call_function
end


local function OGLHook_GetValueType(value, func_name)
	if func_name ~= nil then
		-- TODO: Fix this uhly hack with glOrtho
		if string.find(func_name, 'glOrtho') ~= nil then
			return 'double'
		end

		if string.find(func_name, 'gluPerspective') ~= nil then
			return 'double'
		end

		if string.find(func_name, 'glClearDepth') ~= nil then
			return 'double'
		end

		if type(value) == 'number' then
			if string.find(func_name, 'glRotatef') ~= nil then
				return 'float'
			end

			if string.find(func_name, 'glTranslatef') ~= nil then
				return 'float'
			end

			local type_map = {
				s = 'int',
				i = 'int',
				f = 'float',
				d = 'double'
			}

			for k,v in pairs(type_map) do
				local pattern = string.format('%%d%s$', k)
				if string.match(func_name, pattern) then
					return v
				end
			end
		end
	end

	if value == nil then
		return
	elseif type(value) == 'number' then
		if math.floor(value) == value then
			return 'int'
		else
			return 'float'
		end
	else
		return 'other'
	end
end


local function OGLHook_FormatPush(value, value_type)
	if value_type == nil then
		value_type = OGLHook_GetValueType(value)
	end

	local value_ph = '%s'
	if value_type == 'double' or value_type == 'float' then
		if type(value) == 'number' then
			value_ph = '(float)%0.6f'
		end
	elseif value_type == 'int' then
		value_ph = '%x'
	end

	local command_ph = 'push ' .. value_ph
	if value_type == 'double' then
		command_ph = string.format([[
			push 0
			push %s
			fld [esp]
			fstp qword ptr [esp]
		]], value_ph)
	end

	return string.format(command_ph, value)
end


local function OGLHook_MakePush(values, func_name)
	local args = ''

	for i,v in ipairs(values) do
		local vt = OGLHook_GetValueType(v, func_name)
		local push_cmd = OGLHook_FormatPush(v, vt)
		args = push_cmd .. '\r\n' .. args
	end

	return args
end


-- TODO: Move it to public?
function OGLHook_RunExternalCmd(command, args, result_reg)
	local args_str = ''
	if args ~= nil then
		if type(args) ~= 'table' then
			args = {args}
		end

		if #args > 0 then
			args_str = OGLHook_MakePush(args, command) .. '\r\n'
		end
	end

	local result_cmd = ''
	if result_reg ~= nil and result_reg ~= '' then
		result_cmd = '\r\nmov [%s], eax'
		result_cmd = string.format(result_cmd, result_reg)
	end

	table.insert(
		OPENGL32_COMMAND_STACK,
		args_str .. command .. result_cmd
	)
end


function OGLHook_PutLabel(label)
	label = string.format('%s: ', label, label)
	OGLHook_RunExternalCmd(label)
end


local function OGLHook_AccessMakeFakeFunc(t, k)
	function OGLHook_FakeOpenGLFunc(...)
		local command = OGLHook_MakeCall(k, t._dll_name)

		local args = {}
		local rregs = {}
		local insert_table = args

		for i, v in ipairs({...}) do
			if v == '->' then
				insert_table = rregs
			else
				table.insert(insert_table, v)
			end
		end

		if #rregs > 0 then
			rregs = rregs[1]
		else
			rregs = nil
		end

		OGLHook_RunExternalCmd(command, args, rregs)
	end

	return OGLHook_FakeOpenGLFunc
end

local function OGLHook_BaseFakeAccess(consts_table)
	local function inner(t, k)
		if type(consts_table) == 'table' and string.upper(k) == k then
			return consts_table[k]
		end

		return OGLHook_AccessMakeFakeFunc(t, k)
	end

	return inner
end

setmetatable(OPENGL32, {__index=OGLHook_BaseFakeAccess(OPENGL32_CONSTS)})
setmetatable(GLU32, {__index=OGLHook_BaseFakeAccess(GLU32_CONSTS)})

-- Private --

local OGLH_ADDR_NAME = OPENGL32_NAME .. '.wglSwapBuffers'
local OGLH_USED_REGISTERS = {}
OGL_HOOK = nil


function getAddressSilent(address_str)
	local prev_error_state = errorOnLookupFailure(false)

	local address = getAddress(address_str)

	errorOnLookupFailure(prev_error_state)

	if address ~= nil and address ~= 0 then
		return address
	else
		return 0
	end
end


local function _OGLHook_UseRegister(register)
	if not OGLH_USED_REGISTERS[register] then
		OGLH_USED_REGISTERS[register] = true
	end
end

local function OGLHook_Flush()
	local buffered_opcodes = ""

	for idx = 1,#OPENGL32_COMMAND_STACK do
		current_opcode = OPENGL32_COMMAND_STACK[idx]
		buffered_opcodes = buffered_opcodes .. '\r\n' .. current_opcode
	end

	-- TODO: normal remove?
	OPENGL32_COMMAND_STACK = {}
	OPENGL32_COMMAND_STACK_TEXT = buffered_opcodes
	return buffered_opcodes
end


local function OGLHook_InitMemory()
	return autoAssemble([[
    	globalalloc(oglh_hook_code,16384)
    	globalalloc(oglh_window_hdc, 4)
		globalalloc(oglh_parent_context, 4)
		globalalloc(oglh_context, 4)
		globalalloc(is_context_created, 1)
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
	]] .. OPENGL32_COMMAND_STACK_TEXT .. '\r\n' .. [[
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
	]] .. OPENGL32_COMMAND_STACK_TEXT .. '\r\n' .. [[
		jmp oglh_return
	]]
	return autoAssemble(command)
end


function OGLHook_UpdateWindowSize()
	OGLHook_RunExternalCmd([[
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
	OGLHook_RunExternalCmd([[
		label(initialized)
		label(initialization)
	]])

	OGLHook_RunExternalCmd([[
		push [esp+4]
		pop [oglh_window_hdc]
	]])

	OPENGL32.wglGetCurrentContext('->', 'oglh_parent_context')

	OGLHook_RunExternalCmd([[
		cmp [is_context_created], 0
		jnz initialized
	]])

	OPENGL32.wglCreateContext('[oglh_window_hdc]', '->', 'oglh_context')
	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_context]')

	OGLHook_PutLabel('initialization')
	OGLHook_RunExternalCmd('mov [is_context_created],#1')

	OGLHook_UpdateWindowSize()

	local is_context_created = readBytes(getAddress('is_context_created'), 1, false)
	if is_context_created ~= 1 and type(OGL_HOOK.onInit) == 'function' then
		OGL_HOOK:onInit()
	end

	OGLHook_PutLabel('initialized')
	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_context]')
end


local function OGLHook_AfterUpdate()
	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_parent_context]')
	OGLHook_RunExternalCmd(OGL_HOOK._orig_opcodes)
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

	if not self.initialized then
		return
	end

	OGLHook_BeforeUpdate()

	for i,k in ipairs(self.update_funcs) do
		k()
	end

	OGLHook_AfterUpdate()
	OGLHook_Flush()

	return OGLHook_RewriteBody()
end


local function OGLHook_GetOpcodesText(address, size)
	local start_address

	if type(address) == 'number' then
		start_address = address
	elseif type(address) == 'string' and getAddressSilent(address) ~= 0 then
		start_address = getAddressSilent(address)
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

		_, opcode_text, _ = splitDisassembledString(disassemble(start_address + opcodes_len))

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
	self.initialized = true

	OGLHook_RunExternalCmd(self._orig_opcodes)
	OGLHook_Flush()

	if not OGLHook_RewriteHook() then
		return error_exit_status
	end

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
	self = _getSelf(...)
	if self == nil then
		return
	end

	if not self.initialized then
		return
	end

	local symbols = {
		'oglh_hook_code', 'oglh_window_hdc', 'oglh_parent_context',
		'oglh_context', 'is_context_created', 'oglh_window_rect',
		'oglh_image_handle', 'oglh_image_ptr'
	}

	for k, v in pairs(OGLH_USED_REGISTERS) do
		table.insert(symbols, k)
	end

	local destroy_cmd = [[
		dealloc(%s)
		unregistersymbol(%s)
	]]

	for i, v in ipairs(symbols) do
		if getAddressSilent(v) ~= 0 then
			autoAssemble(string.format(v, v))
		end
	end
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


function OGLHook_LoadBMPTexture(file_path, texture_reg)
	-- TODO: Add load image with non-ascii symbols in path
	local texture_file_path = string.format('oglh_%s_file_path', texture_reg)

	_OGLHook_UseRegister(texture_file_path)
	_OGLHook_UseRegister(texture_reg)

	OGLHook_RunExternalCmd(string.format([[
		cmp dword ptr [%s],0
		jne @f
	]], texture_reg))


	autoAssemble(string.format([[
		globalalloc(%s, 4)
		globalalloc(%s, 1024)

		%s:
		db '%s',0
	]], texture_reg, texture_file_path, texture_file_path, file_path))

	OPENGL32.glEnable(OPENGL32.GL_TEXTURE_2D)

	OGLHook_RunExternalCmd(
		'call LoadImageA',
		{0, texture_file_path, 0, 0, 0, (0x00002000 | 0x00000010)},
		'oglh_image_handle'
	)

	OGLHook_RunExternalCmd(
		'call GetObjectA',
		{'[oglh_image_handle]', 24, 'oglh_image_ptr'}
	)

	OPENGL32.glGenTextures(1, texture_reg)
	OPENGL32.glBindTexture(OPENGL32.GL_TEXTURE_2D, texture_reg)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_MIN_FILTER, OPENGL32.GL_NEAREST)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_MAG_FILTER, OPENGL32.GL_NEAREST)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_WRAP_S, OPENGL32.GL_REPEAT)
	OPENGL32.glTexParameteri(OPENGL32.GL_TEXTURE_2D, OPENGL32.GL_TEXTURE_WRAP_T, OPENGL32.GL_REPEAT)
	OPENGL32.glTexImage2D(OPENGL32.GL_TEXTURE_2D, 0, OPENGL32.GL_RGB, '[oglh_image_ptr+4]', '[oglh_image_ptr+8]', 0, OPENGL32.GL_BGR_EXT, OPENGL32.GL_UNSIGNED_BYTE, '[oglh_image_ptr+14]')

	OGLHook_RunExternalCmd('call DeleteObject', '[oglh_image_handle]')

	OPENGL32.glDisable(OPENGL32.GL_TEXTURE_2D)

	OGLHook_PutLabel('@@')
end


function OGLHook_Create(hot_inject, onInit)
	reinitializeSymbolhandler()

	local hook_address = getAddressSilent(OGLH_ADDR_NAME)
	if hook_address == 0 then
		return -1
	end

	if OGL_HOOK ~= nil then
		OGL_HOOK:destroy()
		OGLH_USED_REGISTERS = {}
	end

	if not OGLHook_InitMemory() then
		return -2
	end

	OGL_HOOK = {
		_hot_inject=(not not hot_inject),
		_orig_opcodes=nil,
		initialized=false,

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
		if not debug_isDebugging() then
			debugProcess()
		end
		debug_setBreakpoint(hook_address, 0, bptExecute, OGL_HOOK.init)
	end

	return OGL_HOOK
end