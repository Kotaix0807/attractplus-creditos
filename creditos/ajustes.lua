-- ajustes.lua - ajustes de arranque, globales y por juego.
--
-- El fichero (arranque.dat, al lado de este) tiene una linea por juego, con el
-- mismo espiritu que creditos.dat: nombre del set y pares clave=valor.
--
--   defecto   velocidad=0 arranque=5 max=30
--   pacman    arranque=7
--   simpsons  velocidad=2 arranque=15 fijo=1
--
-- 'defecto' vale para todos los juegos que no tengan linea propia. Lo que ponga
-- el juego manda sobre 'defecto', y una variable de entorno manda sobre las dos
-- (asi las pruebas pueden forzar lo que necesiten sin tocar el fichero).
--
-- Los tiempos van en SEGUNDOS, que es como piensa una persona. Dentro se
-- trabaja en frames, porque es la unidad del notificador de MAME.

local M = {}

-- Convierte texto a numero, o nil si no es un numero
local function numero(t)
	return tonumber(t)
end

-- Lee el fichero y devuelve { defecto = {...}, juegos = { pacman = {...} } }
function M.leer(ruta)
	local r = { defecto = {}, juegos = {}, avisos = {} }

	local f = io.open(ruta, 'r')
	if not f then return r, 'no se puede abrir ' .. tostring(ruta) end

	for linea in f:lines() do
		-- Fuera comentarios y espacios de los bordes
		linea = linea:gsub('#.*$', ''):match('^%s*(.-)%s*$')

		if linea ~= '' then
			local nombre = linea:match('^(%S+)')
			local ajustes = {}

			for clave, valor in linea:gmatch('(%w+)%s*=%s*([%w%.%-]+)') do
				ajustes[clave:lower()] = numero(valor) or valor
			end

			-- Un nombre con '=' dentro significa que la linea no tiene un
			-- separador de verdad ("pacman?arranque=5" en vez de
			-- "pacman arranque=5"). Sin avisar, esa linea se apuntaria como un
			-- juego que no existe y sus ajustes no se aplicarian NUNCA, en
			-- silencio. Paso una vez y costo encontrarlo.
			if nombre and nombre:find('=', 1, true) then
				r.avisos[#r.avisos + 1] = 'linea sin separador: ' .. linea
			elseif nombre == 'defecto' then
				r.defecto = ajustes
			elseif nombre then
				r.juegos[nombre:lower()] = ajustes
			end
		end
	end

	f:close()
	return r
end

-- Un consultor con la precedencia ya resuelta.
--
--   tabla   lo que devolvio M.leer
--   juego   nombre del set (emu.romname())
--   entorno funcion nombre -> valor de la variable de entorno, o nil
function M.para(tabla, juego, entorno)
	tabla = tabla or { defecto = {}, juegos = {}, avisos = {} }
	entorno = entorno or function() return nil end

	local a = {
		propios = tabla.juegos[(juego or ''):lower()] or {},
		defecto = tabla.defecto or {},
		hay_linea = (tabla.juegos[(juego or ''):lower()] ~= nil),
	}

	-- clave: nombre en el fichero. var: variable de entorno que lo pisa.
	function a.valor(clave, var, defecto)
		if var then
			local v = numero(entorno(var))
			if v then return v, 'entorno' end
		end

		local v = a.propios[clave]
		if type(v) == 'number' then return v, 'juego' end

		v = a.defecto[clave]
		if type(v) == 'number' then return v, 'defecto' end

		return defecto, 'interno'
	end

	-- Igual, pero en segundos: se devuelve en frames
	function a.frames(clave, var, defecto_frames, hz)
		hz = hz or 60

		-- La variable de entorno va en FRAMES, que es como estaban antes y
		-- como las usan las pruebas. El fichero va en segundos.
		if var then
			local v = numero(entorno(var))
			if v then return math.floor(v), 'entorno' end
		end

		local v = a.propios[clave]
		if type(v) ~= 'number' then v = a.defecto[clave] end

		if type(v) == 'number' then
			return math.floor(v * hz + 0.5), a.propios[clave] and 'juego' or 'defecto'
		end

		return defecto_frames, 'interno'
	end

	return a
end

return M
