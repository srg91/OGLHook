OGLHook_Commands = {
	commands_stack = {},
	commands_stack_text = '',
	_run_sync_label = 'oglh_sync_run_func',
	_run_sync_flag_label = 'oglh_sync_run_flag'
}

require([[autorun\OGLHook\Const]])
require([[autorun\OGLHook\Utils]])

OPENGL32 = {_dll_name='OPENGL32'}
GLU32 = {_dll_name='GLU32'}


OGLHook_Commands._SyncWait = function (timeout)
	if timeout == nil then
		timeout = 30
	end

	local flag_label = OGLHook_Commands._run_sync_flag_label
	local flag_addr = OGLHook_Utils.getAddressSilent(flag_label)

	if flag_addr == 0 then
		return false
	end

	local start_clock = os.clock()

	while readBytes(flag_addr, 1) == 1 and not timeout_raised do
		local current_clock = os.clock()
		while os.clock() - current_clock <= 0.001 do
		end

		if os.clock() - start_clock >= timeout then
			timeout_raised = true
		end
	end
end


OGLHook_Commands.SyncRun = function (func_text, timeout)
	local flag_label = OGLHook_Commands._run_sync_flag_label
	local flag_addr = OGLHook_Utils.getAddressSilent(flag_label)

	if flag_addr ~= 0 then
		OGLHook_Utils.DeallocateRegister(flag_label)
	end

	OGLHook_Utils.AllocateRegister(flag_label, 1, 'db 0')
	flag_addr = getAddress(flag_label)

	local run_label = OGLHook_Commands._run_sync_label
	local run_text = string.format([[
		%s

		mov byte ptr [%s],#0
		ret

		createthread(%s)
	]], func_text, flag_label, run_label)

	writeBytes(flag_addr, 1)
	if OGLHook_Utils.AllocateRegister(run_label, 16384, run_text) then
		if not debug_isDebugging() then
			OGLHook_Commands._SyncWait(timeout)
		    OGLHook_Utils.DeallocateRegister(run_label)
		end

		return true
	else
		writeBytes(flag_addr, 0)
		return false
	end
end


OGLHook_Commands.MakeCall = function (func_name, namespace)
	local call_function = func_name

	if namespace ~= nil then
		call_function = string.format('%s.%s', namespace, call_function)
	end

	return 'call ' .. call_function
end


OGLHook_Commands.GetValueType = function (value, func_name)
	if func_name ~= nil then
		for _,fn in ipairs({'glOrtho', 'gluPerspective', 'glClearDepth'}) do
			if string.find(func_name, fn) ~= nil then
				return 'double'
			end
		end

		if type(value) == 'number' then
			for _,fn in ipairs({'glRotatef', 'glTranslatef', 'glScalef'}) do
				if string.find(func_name, fn) ~= nil then
					return 'float'
				end
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


OGLHook_Commands.FormatPush = function (value, value_type)
	if value_type == nil then
		value_type = OGLHook_Commands.GetValueType(value)
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


OGLHook_Commands.MakePush = function (values, func_name)
	local args = ''

	for i,v in ipairs(values) do
		local vt = OGLHook_Commands.GetValueType(v, func_name)
		local push_cmd = OGLHook_Commands.FormatPush(v, vt)
		args = push_cmd .. '\r\n' .. args
	end

	return args
end


OGLHook_Commands.RunExternalCmd = function (command, args, result_reg)
	local args_str = ''
	if args ~= nil then
		if type(args) ~= 'table' then
			args = {args}
		end

		if #args > 0 then
			args_str = OGLHook_Commands.MakePush(args, command) .. '\r\n'
		end
	end

	local result_cmd = ''
	if result_reg ~= nil and result_reg ~= '' then
		result_cmd = '\r\nmov [%s], eax'
		result_cmd = string.format(result_cmd, result_reg)
	end

	local command = args_str .. command .. result_cmd
	table.insert(
		OGLHook_Commands.commands_stack,
		command
	)

	return command
end


OGLHook_Commands.PutLabel = function (label)
	label = string.format('%s: ', label, label)
	OGLHook_Commands.RunExternalCmd(label)
end


OGLHook_Commands.Flush = function ()
	local buffered_opcodes = ""

	for idx = 1,#OGLHook_Commands.commands_stack do
		local current_opcode = OGLHook_Commands.commands_stack[idx]
		buffered_opcodes = buffered_opcodes .. '\r\n' .. current_opcode
	end

	-- TODO: normal remove?
	OGLHook_Commands.commands_stack = {}
	OGLHook_Commands.commands_stack_text = buffered_opcodes

	return buffered_opcodes
end


OGLHook_Commands._AccessMakeFakeFunc = function(t, k)
	function inner(...)
		local command = OGLHook_Commands.MakeCall(k, t._dll_name)

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

		OGLHook_Commands.RunExternalCmd(command, args, rregs)
	end

	return inner
end


OGLHook_Commands._BaseFakeAccess = function (consts_table)
	local function inner(t, k)
		if type(consts_table) == 'table' and string.upper(k) == k then
			return consts_table[k]
		end

		return OGLHook_Commands._AccessMakeFakeFunc(t, k)
	end

	return inner
end

setmetatable(OPENGL32, {__index=OGLHook_Commands._BaseFakeAccess(OGLHook_Const.OPENGL32)})
setmetatable(GLU32, {__index=OGLHook_Commands._BaseFakeAccess(OGLHook_Const.GLU32)})


OGLHook_Commands.isWin81 = function()
	OGLHook_Utils.AllocateRegister('oglh_osvi_struct', 284)
	OGLHook_Utils.AllocateRegister('oglh_is_win_81', 4)

	local func_text = [[
		push #284
		push 0
		push oglh_osvi_struct
		call memset
		add esp,0C

		mov [oglh_osvi_struct],#284
		mov [oglh_osvi_struct+4],#6
		mov [oglh_osvi_struct+8],#3

		// VER_GREATER_EQUAL for VER_MAJORVERSION and VER_MINORVERSION
		push 80000000
		push 0000001B
		// VER_MAJORVERSION | VER_MINORVERSION
		push #3
		push oglh_osvi_struct
		call VerifyVersionInfoW
		mov [oglh_is_win_81],eax
	]]

	OGLHook_Commands.SyncRun(func_text)

	local result = readInteger(getAddress('oglh_is_win_81')) == 1

	-- OGLHook_Utils.DeallocateRegisters({'oglh_osvi_struct', 'oglh_is_win_81'})
	return result
end