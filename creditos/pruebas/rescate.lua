-- Prueba de extremo a extremo del rescate de puntajes.
--
-- Cambia un byte del bloque que declara hiscore.dat, para que la tabla deje de
-- ser la de fabrica. Eso es lo unico que hace que el plugin hiscore escriba su
-- .hi al salir (init.lua: 'checksum ~= default_checksum'), o sea que es
-- exactamente el disparador del rescate en una partida de verdad.
--
--   GA_D_BLOQUES  igual que volcar.lua
--   GA_D_FRAME    en que frame tocar (por defecto 1800)
local ESPEC = os.getenv('GA_D_BLOQUES') or ''
local CUANDO = tonumber(os.getenv('GA_D_FRAME') or '1800')
local frame = 0

local function espacio_de(cpu, espacio)
	local nombre, clase = espacio:match('([^/]*)/?([^/]*)')
	if clase == 'share' then return manager.machine.memory.shares[nombre] end
	local d = manager.machine.devices[':' .. cpu]
	return d and d.spaces[espacio]
end

GA_R_SUB = emu.add_machine_frame_notifier(function ()
	frame = frame + 1
	if frame ~= CUANDO then return end
	local antes, despues = {}, {}
	local primero = true
	for spec in ESPEC:gmatch('[^;]+') do
		local cpu, esp, dir, largo = spec:match('([^,]*),([^,]*),([^,]*),([^,]*)')
		local sp = espacio_de(cpu, esp)
		if sp then
			dir, largo = tonumber(dir, 16), tonumber(largo, 16)
			for i = 0, largo - 1 do antes[#antes+1] = sp:read_u8(dir + i) end
			if primero then
				-- Se toca el ULTIMO byte del bloque, no el primero: en muchas
				-- placas el primero es el digito mas significativo y ponerlo a
				-- 9 da una puntuacion absurda que el filtro tirararia.
				local d = dir + largo - 1
				local v = sp:read_u8(d)
				sp:write_u8(d, (v == 1) and 2 or 1)
				primero = false
			end
			for i = 0, largo - 1 do despues[#despues+1] = sp:read_u8(dir + i) end
		end
	end
	local function hex(t)
		local s = {}
		for _, b in ipairs(t) do s[#s+1] = string.format('%02x', b) end
		return table.concat(s)
	end
	print('[rescate] antes=' .. hex(antes))
	print('[rescate] despues=' .. hex(despues))
end)
