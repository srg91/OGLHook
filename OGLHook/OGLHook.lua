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

OPENGL32 = {}

OPENGL32_COMMAND_STACK = {}
OPENGL32_COMMAND_STACK_TEXT = ""


local function OGLHook_MakeCall(func_name)
	return string.format('call %s.%s', OPENGL32_NAME, func_name)
end


local function OGLHook_GetValueType(value, func_name)
	if func_name ~= nil and type(value) == 'number' then
		-- TODO: Fix this uhly hack with glOrtho
		if string.find(func_name, 'glOrtho') ~= nil then
			return 'double'
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
		value_ph = '(float)%0.6f'
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
		local command = OGLHook_MakeCall(k)

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


local function OGLHook_BaseFakeAccess(t, k)
	-- Maybe not only OPENGL32.. But we can merge all constants i think
	if string.upper(k) == k then
		return OPENGL32_CONSTS[k]
	end

	return OGLHook_AccessMakeFakeFunc(t, k)
end

setmetatable(OPENGL32, {__index=OGLHook_BaseFakeAccess})

-- Private --

local OGLH_ADDR_NAME = OPENGL32_NAME .. '.wglSwapBuffers'
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
	-- registerAutoAssemblerCommand('OGLH_WRITE_STACK', _OGLHook_WriteStack)

	return autoAssemble([[
    	alloc(oglh_hook_code,2048)
    	alloc(oglh_window_hdc, 4)
		alloc(oglh_parent_context, 4)
		alloc(oglh_context, 4)
		alloc(is_context_created, 1)

		registersymbol(oglh_hook_code)
		registersymbol(oglh_window_hdc)
		registersymbol(oglh_parent_context)
		registersymbol(oglh_context)
		registersymbol(is_context_created)
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

	OPENGL32.glMatrixMode(OPENGL32.GL_PROJECTION)
	OPENGL32.glLoadIdentity()

	local wx, wy, ww, wh = unpack(OGL_HOOK.size)
	OPENGL32.glOrtho(wx, ww, wh, wy, 1.0, -1.0)

	OPENGL32.glMatrixMode(OPENGL32.GL_MODELVIEW)
	OPENGL32.glLoadIdentity()

	OPENGL32.glClearColor(0, 0, 0, 1)

	OGLHook_PutLabel('initialized')
	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_context]')
end


local function OGLHook_AfterUpdate()
	OPENGL32.wglMakeCurrent('[oglh_window_hdc]', '[oglh_parent_context]')

	OGLHook_RunExternalCmd([[
		mov edi,edi
		push ebp
		mov ebp,esp
	]])
end


local function _get_self(...)
	local self, _ = ...
	if self == nil then
		self = OGL_HOOK
	end

	return self, _
end


local function OGLHook_Update(...)
	local self = _get_self(...)
	if self == nil then
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


local function OGLHook_Init(...)
	local self = _get_self(...)
	if self == nil then
		return 0
	end

	local error_exit_status = self._hot_inject and 0 or 1

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
end


local function OGLHook_Destroy(...)
	self = _get_self(...)
	if self == nil then
		return
	end

end


-- Public --


function OGLHook_Create(hot_inject, size, force)
	reinitializeSymbolhandler()

	local hook_address = getAddressSilent(OGLH_ADDR_NAME)
	if hook_address == 0 then
		return -1
	end

	-- if force ~= true and OGL_HOOK ~= nil then
	-- 	return OGL_HOOK
	-- end
	autoAssemble([[
		unregistersymbol(oglh_hook_code)
		unregistersymbol(oglh_window_hdc)
		unregistersymbol(oglh_parent_context)
		unregistersymbol(oglh_context)
		unregistersymbol(is_context_created)
	]])

	if not OGLHook_InitMemory() then
		return -2
	end

	if window_size == nil then
		window_size = {0, 0, 640, 480}
	end

	OGL_HOOK = {
		_hot_inject=(not not hot_inject),
		size=window_size,
		update_funcs={},

		init = OGLHook_Init,
		update = OGLHook_Update,
		registerUpdateFunc = function(self, update_func)
			table.insert(self.update_funcs, update_func)
		end
	}

	if hot_inject then
		if not OGL_HOOK.init() then
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
