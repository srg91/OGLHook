if OGLHook_Utils ~= nil then
	return
end

OGLHook_Utils = {
	_allocated_registers_list = {},
}

require([[autorun\OGLHook\Errors]])


OGLHook_Utils.getAddressSilent = function (address_str)
	local prev_error_state = errorOnLookupFailure(false)

	local address = getAddress(address_str)
	errorOnLookupFailure(prev_error_state)

	if address ~= nil and address ~= 0 then
		OGLHook_Errors.clearError()
		return address
	else
		OGLHook_Errors.setError(OGLHook_Errors.ADDRESS_NOT_FOUND)
		return 0
	end
end


OGLHook_Utils.getTempFileName = function ()
	local ce_dir = getCheatEngineDir()
	local temp_name = os.tmpname()
	local current_time = os.time()

	temp_name = temp_name:sub(2)

	return ce_dir .. temp_name .. tostring(current_time)
end


-- Registers
OGLHook_Utils.LockRegister = function(register)
	if not OGLHook_Utils._allocated_registers_list[register] then
		OGLHook_Utils._allocated_registers_list[register] = true

		OGLHook_Errors.clearError()
		return true
	else
		OGLHook_Errors.setError(OGLHook_Errors.LOCK_REGISTER_ERROR)
		return false
	end
end


OGLHook_Utils.UnlockRegister = function(register)
	if not OGLHook_Utils._allocated_registers_list[register] then
		OGLHook_Errors.setError(OGLHook_Errors.UNLOCK_REGISTER_ERROR)
		return false
	else
		OGLHook_Utils._allocated_registers_list[register] = nil

		OGLHook_Errors.clearError()
		return true
	end
end


OGLHook_Utils.AllocateRegister = function(register, size, data)
	if not (register and size) then
		OGLHook_Errors.setError(OGLHook_Errors.NOT_ALL_PARAMS)
		return false
	end

	if not OGLHook_Utils.LockRegister(register) then
		return false
	end

	local command = string.format('globalalloc(%s, %d)', register, size)

	if data ~= nil then
		command = string.format([[
			%s

			%s:
			%s
		]], command, register, data)
	end

	if not autoAssemble(command) then
		OGLHook_Utils.UnlockRegister(register)
		OGLHook_Errors.setError(OGLHook_Errors.ALLOCATE_REGISTER_ERROR)
		return false
	else
		OGLHook_Errors.clearError()
		return true
	end
end


OGLHook_Utils.DeallocateRegister = function(register)
	if not OGLHook_Utils.UnlockRegister(register) then
		return false
	end

	local command = string.format([[
		dealloc(%s)
		unregistersymbol(%s)
	]], register, register)

	if not autoAssemble(command) then
		OGLHook_Errors.setError(OGLHook_Errors.DEALLOCATE_REGISTER_ERROR)
		return false
	else
		OGLHook_Errors.clearError()
		return true
	end
end


OGLHook_Utils.DeallocateRegisters = function(registers)
	if type(registers) == 'table' then
		for i, register in ipairs(registers) do
			OGLHook_Utils.DeallocateRegister(register)
		end
	else
		for register, is_allocated in pairs(OGLHook_Utils._allocated_registers_list) do
			if is_allocated and OGLHook_Utils.getAddressSilent(register) ~= 0 then
				OGLHook_Utils.DeallocateRegister(register)
			end
		end
		OGLHook_Utils._allocated_registers_list = {}
	end
end
