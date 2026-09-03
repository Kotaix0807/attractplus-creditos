-- Envoltorio de MAME para las pruebas: carga creditos.lua, saca una captura
-- de pantalla y, si se le pide, finge que el jugador mete una moneda a mitad
-- de la partida.
--
-- La moneda fingida se hace sustituyendo la funcion que el vigilante usa para
-- leer el boton (monedero.lua no habla con MAME justamente para esto), y ademas
-- se pulsa la entrada de verdad con set_value, para que el juego conceda el
-- credito igual que se lo concederia a una persona.
--
-- GA_SNAP          fichero de la captura
-- GA_SNAP_FRAMES   en que frame sacarla
-- GA_PRUEBA_MONEDA frames en los que finge una moneda, separados por comas
-- GA_PRUEBA_SALIR  frames en los que finge pulsar la tecla de salir
-- GA_PRUEBA_START  frames en los que finge pulsar el start

-- MAME ejecuta esto con SU directorio de trabajo, no el nuestro, asi que
-- la ruta se saca del propio fichero (igual que creditos.lua con sus modulos).
local MI_DIR = (debug.getinfo(1, 'S').source or ''):match('^@(.*[/\\])') or ''
dofile(MI_DIR .. '../../creditos.lua')

local destino = os.getenv('GA_SNAP') or '/tmp/captura.png'
local objetivo = tonumber(os.getenv('GA_SNAP_FRAMES') or '300')

local n = 0
GA_PRUEBA_SUB = emu.add_machine_frame_notifier(function()
	n = n + 1
	if n == objetivo then
		for _, scr in pairs(manager.machine.screens) do
			scr:snapshot(destino)
			break
		end
		print('[prueba] captura en ' .. destino)
	end
end)

-- Moneda fingida del jugador: se sustituye la funcion que el contador usa para
-- leer el boton (monedero.lua no habla con MAME justamente para esto) y ademas
-- se pulsa la entrada de verdad con set_value, para que el juego conceda el
-- credito igual que se lo concederia a una persona.
local frames = {}
for f in (os.getenv('GA_PRUEBA_MONEDA') or ''):gmatch('%d+') do
	frames[#frames + 1] = tonumber(f)
end

if (#frames > 0) and GA_ESTADO and GA_ESTADO.pulso_moneda then
	local VENTANA = 8        -- frames que se mantiene "pulsado"
	local m = 0
	local real = GA_ESTADO.campo

	GA_ESTADO.pulso_moneda.leer = function()
		m = m + 1            -- el contador llama a esto una vez por frame

		if GA_ESTADO.fase ~= 'fin' then
			return false     -- mientras se insertan los creditos del lanzamiento
		end

		local dentro = false
		for _, f in ipairs(frames) do
			if (m >= f) and (m < f + VENTANA) then dentro = true end
		end

		real:set_value(dentro and 1 or 0)
		if dentro and (m % VENTANA == 0) then
			print('[prueba] fingiendo moneda del jugador en el frame ' .. m)
		end
		return dentro
	end

	print('[prueba] monedas fingidas en los frames: ' .. table.concat(frames, ','))
end

-- Fingir la tecla de salir y el start, para poder probar el cuadro de aviso
-- sin teclado. Se sustituyen las funciones que creditos.lua usa para leerlas.
-- Busca un campo de entrada por su token, para poder pulsarlo de verdad
local function campo_de(token)
	local io_ = manager.machine.ioport
	local ok, tipo = pcall(function() return io_:token_to_input_type(token) end)
	if not ok or not tipo then return nil end
	for _, port in pairs(io_.ports) do
		for _, c in pairs(port.fields) do
			if c.type == tipo then return c end
		end
	end
end

local function fingidor(lista, nombre, campo)
	local frames = {}
	for f in (lista or ''):gmatch('%d+') do frames[#frames + 1] = tonumber(f) end
	if #frames == 0 then return nil end

	local VENTANA = 10
	local m = 0
	print('[prueba] ' .. nombre .. ' fingido en los frames: ' .. table.concat(frames, ','))

	return function()
		m = m + 1
		local dentro = false
		for _, f in ipairs(frames) do
			if (m >= f) and (m < f + VENTANA) then dentro = true end
		end
		-- Ademas de contarselo a nuestra maquina de estados, se pulsa la
		-- entrada de verdad: si no, el juego no reacciona y no gasta credito.
		if campo then campo:set_value(dentro and 1 or 0) end
		return dentro
	end
end

if GA_ESTADO then
	-- Los lectores de salir y start se leen por nombre en cada frame, asi que
	-- basta con sustituirlos aqui.
	local salir = fingidor(os.getenv('GA_PRUEBA_SALIR'), 'salir', nil)
	local start = fingidor(os.getenv('GA_PRUEBA_START'), 'start', campo_de('START1'))
	if salir then GA_ESTADO.leer_salir = salir end
	if start then GA_ESTADO.leer_start1 = start end
end
