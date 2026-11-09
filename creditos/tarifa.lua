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

-- Valor que hay que escribir en el DIP para "monedas moneda(s) = creditos
-- credito(s)", o nil si este juego no ofrece esa tarifa. Devuelve valor, texto,
-- sin_premio.
--
-- Elige la tarifa sin premio si existe y, a igualdad, el valor mas bajo:
-- pairs() no garantiza orden y sin esto cada pasada podia elegir otro ajuste.
function M.valor_tarifa(dip, monedas, creditos)
	local mejor, mejor_texto, mejor_limpia = nil, nil, false

	for valor, texto in pairs(dip.campo.settings) do
		local m, c, gratis = M.partir(texto)
		if not gratis and m == monedas and c == creditos then
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

-- 1 moneda = 1 credito (lo mas comun). Atajo del de arriba.
function M.valor_1c1c(dip)
	return M.valor_tarifa(dip, 1, 1)
end

-- N monedas = 1 credito, para la tarifa global en pesos (N = pesos / 100).
function M.valor_monedas(dip, n)
	return M.valor_tarifa(dip, n, 1)
end

-- Valor del ajuste "Free Play" del DIP de tarifa, o nil si este juego no lo
-- ofrece. Muchas placas lo traen como una opcion mas del propio Coinage.
function M.valor_freeplay(dip)
	for valor, texto in pairs(dip.campo.settings) do
		local _, _, gratis = M.partir(texto)
		if gratis then return valor, texto end
	end
	return nil
end

-- Pone el juego en FREE PLAY por DIP alla donde la placa lo ofrezca, no solo en
-- el DIP de tarifa elegido por buscar_dip(). Cubre los tres casos vistos:
--   - un dipswitch SUELTO llamado "Free Play" (On): NeoGeo, CPS, qbert...
--   - la opcion "Free Play" dentro de un Coinage que no era el elegido
--     (rampage, wboy, zaxxon la tienen en un campo distinto del de mas tarifas)
--   - "Free Play (if the other too)" en Coin A Y Coin B a la vez
--     (goldnaxe, outrun, nemesis: hay que poner los dos)
-- Devuelve true si toco algun campo.
function M.aplicar_freeplay()
	local tocado = false
	for _, port in pairs(manager.machine.ioport.ports) do
		for nombre, campo in pairs(port.fields) do
			if campo.type_class == 'dipswitch' and campo.settings then
				for valor, texto in pairs(campo.settings) do
					local suelto = (nombre == 'Free Play')
						and (texto == 'On' or texto == 'Yes')
					local _, _, gratis = M.partir(texto)
					if suelto or gratis then
						campo.user_value = valor
						tocado = true
					end
				end
			end
		end
	end
	return tocado
end

-- Inversa de aplicar_freeplay: quita el FREE PLAY del DIP SUELTO (un campo llamado
-- "Free Play": Neo Geo/KOF, CPS, qbert...), poniendolo a Off/No. Los Coinage con
-- una opcion "Free Play" NO se tocan aqui: de esos se encarga la tarifa normal
-- (1c1c / N monedas), que elige otro valor del MISMO campo. Devuelve true si toco
-- algo. Hace falta porque, al salir de free play, el DIP suelto se quedaba en On
-- para siempre (los KOF seguian gratis aunque la tarifa fuera de pago).
function M.quitar_freeplay()
	local tocado = false
	for _, port in pairs(manager.machine.ioport.ports) do
		for nombre, campo in pairs(port.fields) do
			if campo.type_class == 'dipswitch' and campo.settings
					and nombre == 'Free Play' then
				for valor, texto in pairs(campo.settings) do
					if (texto == 'Off' or texto == 'No')
							and campo.user_value ~= valor then
						campo.user_value = valor
						tocado = true
					end
				end
			end
		end
	end
	return tocado
end

return M
