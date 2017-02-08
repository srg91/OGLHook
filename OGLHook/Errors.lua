OGLHook_Errors = {
	LAST = nil,

	--Commnon
	INCOMPATIBLE_PARAMS = -100,
	NOT_ALL_PARAMS = -101,

    -- Textures
	FAIL_TO_LOAD_DLL = -1000,

	-- Utils
	ADDRESS_NOT_FOUND = -1100,
	LOCK_REGISTER_ERROR = -1101,
	UNLOCK_REGISTER_ERROR = -1102,
	ALLOCATE_REGISTER_ERROR = -1103,
	DEALLOCATE_REGISTER_ERROR = -1104,
}


OGLHook_Errors.setError = function(error_code)
	OGLHook_Errors.LAST = error_code
end


OGLHook_Errors.clearError = function()
	OGLHook_Errors.LAST = nil
end


OGLHook_Errors.getLastError = function()
	return OGLHook_Errors.LAST
end
