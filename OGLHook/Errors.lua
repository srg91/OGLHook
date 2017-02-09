OGLHook_Errors = {}


OGLHook_Errors.raiseError = function (message, ...)
	error(string.format(message, ...), 2)
end


OGLHook_Errors.raiseWarning = function (message, ...)
	local warn_message = string.format(message, ...)
	local warn_text = debug.traceback(warn_message, 2)

	print(string.gsub(warn_text, '\n', '\r\n'))
end
