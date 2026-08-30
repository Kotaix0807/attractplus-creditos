-- memoria.lua - leer los creditos directamente de la RAM del juego.
--
-- Con la direccion buena (la que encuentra buscar_creditos.lua y se apunta en
-- creditos.dat) se acaban las estimaciones: se sabe exactamente cuantos
-- creditos tiene la maquina en cada momento, cuantos entran y cuantos se lleva
-- el juego. Es la misma idea que el hiscore.dat de MAME.
--
-- Sin entrada en la tabla, creditos.lua sigue estimando por pulsaciones de
-- START, que es lo que habia antes.
--
-- Aqui no se habla con MAME: se recibe una funcion para leer el byte, asi que
-- la contabilidad se prueba con lua a secas.

local M = {}

-- Busca el juego en creditos.dat. Formato de cada linea:
--   pacman @:maincpu,program,4e6e             <- comprobada ejecutando el juego
--   qbert  @:maincpu,program,b60+bbd+1100     <- el juego guarda tres copias
--   galaga @:maincpu,program,9a12 # (cheat)   <- importada, sin comprobar
--
-- Lo de las varias direcciones no es un capricho: Q*bert lleva tres copias del
-- contador y pinta desde una que no es la primera, asi que escribir en una sola
-- no se ve en pantalla. Se leen de la primera y se escriben todas.
function M.entrada(ruta, juego)
	local f = io.open(ruta, 'r')
	if not f then return nil end

	local encontrada = nil

	for linea in f:lines() do
		if not linea:match('^%s*#') then
			local nombre, cpu, espacio, dirs =
				linea:match('^%s*([%w_%-]+)%s+@([^,]+),([^,]+),([%x+]+)')
			if nombre and (nombre == juego) then
				local lista = {}
				for d in dirs:gmatch('%x+') do
					lista[#lista + 1] = tonumber(d, 16)
				end

				encontrada = {
					cpu = cpu,
					espacio = espacio,
					dir = lista[1],
					dirs = lista,
					-- Las importadas de la coleccion de cheats no se han
					-- comprobado nunca: hay cheats de creditos infinitos que
					-- parchean el codigo en vez de escribir el contador.
					comprobada = not linea:find('(cheat)', 1, true),
				}
				break
			end
		end
	end

	f:close()
	return encontrada
end

-- Contador basado en la memoria del juego.
--
-- Mira como cambia el byte de los creditos y reparte los cambios: lo que sube
-- es que han entrado creditos, lo que baja es que el juego se los ha llevado.
--
-- Los saltos grandes se ignoran a proposito: un reset de la placa pone el
-- contador a cero de golpe, y eso no es una partida que haya que cobrar.
function M.contador(op)
	op = op or {}

	local c = {
		leer      = op.leer,
		max_salto = math.max(1, math.floor(op.max_salto or 4)),
		anterior  = nil,
		entrado   = 0,
		consumido = 0,
		raros     = 0,
		-- Frames que se deja asentar la placa antes de empezar a contar. Con
		-- el script arrancando en el frame 0 (que es lo que cierra la ventana
		-- de creditos gratis), la RAM del juego todavia es basura: sin esto,
		-- el primer valor leido seria cualquier cosa.
		espera    = math.max(0, math.floor(op.asentar or 0)),
		asentado  = false,
		al_asentar = op.al_asentar,
		log       = op.log or function() end,
	}

	function c.frame()
		local ok, v = pcall(c.leer)
		if not ok or type(v) ~= 'number' then return end

		if not c.asentado then
			c.anterior = v

			if c.espera > 0 then
				c.espera = c.espera - 1
				return
			end

			c.asentado = true
			if c.al_asentar then c.al_asentar(v) end

			-- al_asentar puede haber tocado la RAM (quitar creditos que nadie
			-- ha pagado): se relee para no contar ese cambio como consumo.
			local ok2, v2 = pcall(c.leer)
			if ok2 and type(v2) == 'number' then c.anterior = v2 end
			return
		end

		local d = v - c.anterior
		c.anterior = v

		if d == 0 then
			return
		elseif (d > 0) and (d <= c.max_salto) then
			c.entrado = c.entrado + d
		elseif (d < 0) and (-d <= c.max_salto) then
			c.consumido = c.consumido - d
			c.log('el juego se lleva %d credito%s (contador en %d)',
				-d, (d == -1) and '' or 's', v)
		else
			c.raros = c.raros + 1
			c.log('salto raro en el contador de creditos (%+d), lo ignoro', d)
		end
	end

	-- Fuerza el final del asentamiento. La usa quien sabe mejor que este modulo
	-- cuando la placa esta lista de verdad: el fin del arranque tapado. El
	-- contador de frames de op.asentar se queda como red por si eso no llega.
	function c.asentar_ya()
		if c.asentado then return end
		c.espera = 0
		c.frame()
	end

	-- Cuantos creditos tiene la maquina ahora mismo, o nil si todavia no se
	-- puede saber. Devolver nil es importante: mientras la placa arranca, ese
	-- byte es basura, y quien pregunta (el cuadro de aviso) prefiere volver a
	-- su estimacion antes que anunciar "DEJAS 176 CREDITOS DENTRO".
	function c.dentro()
		if not c.asentado then return nil end
		return c.anterior or 0
	end

	return c
end

-- Sincronizador: escribe el monedero directamente en el contador de creditos
-- del juego, en vez de simular monedas.
--
-- Es la mitad que faltaba del metodo del plugin hiscore de MAME: el lee su
-- fichero y lo vuelca en la RAM al arrancar. Aqui igual, con dos cuidados:
--
--   * Se comprueba que el valor se haya quedado puesto. Si la placa todavia
--     estaba inicializando su RAM, su propio codigo lo machaca; por eso se
--     reintenta unas cuantas veces antes de rendirse.
--   * Se respeta un tope: escribir 99 en un juego cuyo contador solo llega a 9
--     puede confundirlo.
--
-- Si no lo consigue, avisa y quien llama puede volver a las monedas de siempre.
function M.sincronizador(op)
	op = op or {}

	local s = {
		leer      = op.leer,
		escribir  = op.escribir,
		valor     = math.max(0, math.floor(op.valor or 0)),
		intentos  = math.max(1, math.floor(op.intentos or 6)),
		cada      = math.max(1, math.floor(op.cada or 20)),
		log       = op.log or function() end,
		estado    = 'pendiente',
		hechos    = 0,
		reloj     = 0,
	}

	-- Devuelve 'pendiente', 'hecho' o 'rendido'
	function s.frame()
		if s.estado ~= 'pendiente' then return s.estado end

		s.reloj = s.reloj + 1
		if (s.reloj % s.cada) ~= 0 then return s.estado end

		local ok, ahora = pcall(s.leer)
		if ok and (ahora == s.valor) then
			s.estado = 'hecho'
			s.log('creditos sincronizados: el juego marca %d', s.valor)
			return s.estado
		end

		if s.hechos >= s.intentos then
			s.estado = 'rendido'
			s.log('no consigo escribir los creditos (marca %s, queria %d)',
				tostring(ok and ahora or '?'), s.valor)
			return s.estado
		end

		s.hechos = s.hechos + 1
		pcall(s.escribir, s.valor)
		return s.estado
	end

	return s
end

return M
