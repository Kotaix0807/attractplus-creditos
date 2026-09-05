-- volcar.lua - lee de la RAM el bloque de puntuaciones que declara hiscore.dat
-- y lo imprime en hexadecimal.
--
-- Hace falta porque el plugin hiscore SOLO escribe su .hi cuando la tabla
-- CAMBIA respecto a como estaba al arrancar (init.lua: 'checksum ~=
-- default_checksum'). O sea que arrancar un juego sin jugarlo no genera nada, y
-- sin datos no se puede ni deducir el formato ni apuntar la tabla de fabrica.
--
--   GA_D_BLOQUES="maincpu,program,4e88,4;maincpu,program,43ed,6"
--   GA_D_FRAME=2400   en que frame volcar (por defecto 2400)
local ESPEC = os.getenv('GA_D_BLOQUES') or ''
local CUANDO = tonumber(os.getenv('GA_D_FRAME') or '2400')
local frame = 0

GA_D_SUB = emu.add_machine_frame_notifier(function ()
	frame = frame + 1
	if frame ~= CUANDO then return end
	local trozos = {}
	for spec in ESPEC:gmatch('[^;]+') do
		local cpu, espacio, dir, largo =
			spec:match('([^,]*),([^,]*),([^,]*),([^,]*)')
		local d = manager.machine.devices[':' .. cpu]
		if d then
			local sp = d.spaces[espacio]
			if sp then
				local base, n = tonumber(dir, 16), tonumber(largo, 16)
				local i = 0
				while i < n do
					trozos[#trozos + 1] = string.format('%02x', sp:read_u8(base + i))
					i = i + 1
				end
			end
		end
	end
	print('[volcado] ' .. table.concat(trozos))
	io.stdout:flush()
	manager.machine:exit()
end)
