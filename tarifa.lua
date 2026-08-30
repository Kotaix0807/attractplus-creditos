-- tarifa.lua - lo que se sabe del DIP de tarifa de la maquina en marcha.
--
-- Aqui solo hay HECHOS sobre la maquina; la politica (forzar 1C/1C, compensar,
-- no tocar nada) vive en creditos.lua y en poner_1c1c.lua, que cargan este
-- modulo con dofile para no tener dos copias del mismo analisis.
--
-- Comprobado ejecutandolo: campo.settings es una tabla valor -> texto, y en
-- Pac-Man el DIP de tarifa es :DSW1 [Coinage] con
--   1 = 1 Coin/1 Credit, 2 = 1 Coin/2 Credits, 3 = 2 Coins/1 Credit, 0 = Free Play

local M = {}

-- Los textos de los ajustes vienen TRADUCIDOS por MAME, asi que esto solo
-- acierta con la interfaz en ingles. De ahi que creditos.lua tenga
-- GA_TARIFA=off como escape.
--
-- Devuelve monedas, creditos, es_gratis. Nil si el texto no es una tarifa.
-- De textos compuestos ("1 Coin/1 Credit, 5 Coins/6 Credits") se queda con
-- el primer tramo, que es el que aplica a la primera moneda.
function M.partir(texto)
	if type(texto) ~= 'string' then return nil end

	local t = texto:lower()
	if t:find('free play', 1, true) then
		return 0, 0, true
	end

	-- Forma larga, la mas comun: "1 Coin/2 Credits", "2 Coins/1 Credit"
	local monedas, creditos = t:match('(%d+)%s*coins?%s*/%s*(%d+)%s*credits?')
	if monedas then
		return tonumber(monedas), tonumber(creditos), false
	end

	-- Forma compacta de Konami/Sega, comprobada en Frogger:
	-- "A 1/1 B 1/1 C 1/1". La ranura A es la de COIN1, que es la que pulsamos.
	monedas, creditos = t:match('^a%s+(%d+)%s*/%s*(%d+)')
	if monedas then
		return tonumber(monedas), tonumber(creditos), false
	end

	-- Y por si acaso, un "1/1" pelado
	monedas, creditos = t:match('^(%d+)%s*/%s*(%d+)$')
	if monedas then
		return tonumber(monedas), tonumber(creditos), false
	end

	return nil
end

-- Busca el DIP de tarifa: el campo con mas ajustes que parezcan "N Coin/M
-- Credit". Se ordena la busqueda porque pairs() no garantiza el orden y hay
-- juegos con Coin A y Coin B: sin ordenar, cada arranque podria elegir otro.
function M.buscar_dip()
	local candidatos = {}

	for etiqueta, port in pairs(manager.machine.ioport.ports) do
		for nombre, campo in pairs(port.fields) do
			if campo.type_class == 'dipswitch' and campo.settings then
				local n = 0
				for _, texto in pairs(campo.settings) do
					if M.partir(texto) then n = n + 1 end
				end
				if n > 0 then
					candidatos[#candidatos + 1] = {
						clave = etiqueta .. '/' .. nombre,
						etiqueta = etiqueta,
						nombre = nombre,
						campo = campo,
						aciertos = n,
					}
				end
			end
		end
	end

	if #candidatos == 0 then return nil end

	table.sort(candidatos, function(a, b)
		if a.aciertos ~= b.aciertos then return a.aciertos > b.aciertos end
		return a.clave < b.clave
	end)

	return candidatos[1]
end

-- Texto del ajuste que la maquina tiene puesto ahora mismo.
function M.ajuste_actual(dip)
	return dip.campo.settings[dip.campo.user_value]
end

-- Hay tarifas con premio por acumular monedas: "1 Coin/1 Credit, 2/3" da un
-- credito por la primera moneda pero tres por dos monedas. Para que el
-- contador del frontend sea exacto interesa la version sin premio.
-- Comprobado en mwalk (Sega System 18), que tiene cuatro ajustes distintos
-- cuyo texto empieza por "1 Coin/1 Credit".
function M.con_premio(texto)
	return type(texto) == 'string' and texto:find(',', 1, true) ~= nil
end

-- Valor que hay que escribir en el DIP para 1 moneda = 1 credito, o nil si
-- este juego no ofrece esa tarifa. Devuelve valor, texto, sin_premio.
--
-- Elige la tarifa sin premio si existe y, a igualdad, el valor mas bajo:
-- pairs() no garantiza orden y sin esto cada pasada podia elegir otro ajuste.
function M.valor_1c1c(dip)
	local mejor, mejor_texto, mejor_limpia = nil, nil, false

	for valor, texto in pairs(dip.campo.settings) do
		local m, c, gratis = M.partir(texto)
		if not gratis and m == 1 and c == 1 then
			local limpia = not M.con_premio(texto)
			if mejor == nil
					or (limpia and not mejor_limpia)
					or (limpia == mejor_limpia and valor < mejor) then
				mejor, mejor_texto, mejor_limpia = valor, texto, limpia
			end
		end
	end

	return mejor, mejor_texto, mejor_limpia
end

return M
