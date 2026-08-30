-- monedero.lua - la cuenta compartida entre el frontend y MAME.
--
-- El fichero (por defecto $HOME/.attract/creditos.txt) dejo de ser una nota de
-- un solo viaje y es ahora la cuenta que leen y escriben las dos partes:
--
--   saldo    creditos que le quedan al jugador en el monedero
--   inserta  creditos que MAME debe meter en la partida al arrancar
--
-- El frontend escribe las dos cifras justo antes de lanzar. MAME consume
-- "inserta" (lo pone a 0 en cuanto lo lee, para que un segundo arranque no
-- regale creditos) y mantiene "saldo" al dia durante la partida. Al salir, el
-- frontend lee "saldo" y ensena lo que queda.
--
-- LA REGLA: el monedero paga por lo que se JUEGA, no por lo que se mete.
--
-- Meter una moneda dentro de la partida no cuesta nada: mueve un credito del
-- monedero a la maquina, y si no se gasta vuelve al monedero al salir. Lo que
-- descuenta es pulsar START, que es cuando el juego se lleva el credito.
--
--     saldo = base - consumido       base = saldo al lanzar + lo insertado
--
-- Antes se descontaba al meter la moneda, y eso arruinaba a quien entraba a un
-- juego y se ponia a pulsar la moneda pensando que acumulaba para otros: cada
-- pulsacion le vaciaba el monedero y al salir lo perdia. Con esta regla eso no
-- puede pasar.
--
-- Aqui no se toca MAME: son funciones puras y una maquinita de estados, para
-- poder probar la contabilidad con lua a secas. Ver pruebas/prueba_monedero.lua

local M = {}

-- Tolerante a proposito. Un numero suelto se interpreta como "inserta N",
-- que es el formato viejo y sigue siendo lo mas comodo para probar a mano:
--     echo 3 > ~/.attract/creditos.txt
function M.leer(ruta)
	local f = io.open(ruta, 'r')
	if not f then return nil end

	local saldo, inserta = nil, nil

	for linea in f:lines() do
		local clave, valor = linea:match('^%s*(%a+)%s+(%-?%d+)%s*$')
		if clave == 'saldo' then
			saldo = tonumber(valor)
		elseif clave == 'inserta' then
			inserta = tonumber(valor)
		else
			local suelto = linea:match('^%s*(%d+)%s*$')
			if suelto then inserta = tonumber(suelto) end
		end
	end

	f:close()

	if not saldo and not inserta then return nil end

	return math.max(0, math.floor(saldo or 0)), math.max(0, math.floor(inserta or 0))
end

-- Se escribe a un temporal y se renombra: en POSIX el renombrado es atomico,
-- asi que matar MAME a media escritura no puede dejar la cuenta a medias.
function M.escribir(ruta, saldo, inserta)
	local tmp = ruta .. '.tmp'
	local f = io.open(tmp, 'w')
	if not f then return false end

	f:write(string.format('saldo %d\ninserta %d\n',
		math.max(0, math.floor(saldo or 0)),
		math.max(0, math.floor(inserta or 0))))
	f:close()

	local ok = os.rename(tmp, ruta)
	if not ok then os.remove(tmp) end
	return ok and true or false
end

-- Contador de pulsaciones de un boton. Cuenta en el flanco, que es cuando MAME
-- apunta la moneda o el start; mantener pulsado no dispara una lluvia.
--
-- Recibe la funcion que lee el boton en vez de hablar con MAME, para poder
-- probarlo sin emulador.
-- Detector de flancos con antirrebote.
--
-- Los contactos de una chauchera (o de un boton) REBOTAN al cerrarse: durante
-- unos milisegundos abren y cierran varias veces. Muestreando una vez por frame
-- ese rebote se lee como varias pulsaciones, y una moneda da tres creditos.
--
-- 'hueco' son los frames que hay que esperar antes de admitir otro flanco. Con
-- 8 (~130 ms a 60 Hz) no se pierde nada real: ni una persona ni una chauchera
-- meten dos monedas tan seguidas.
function M.pulsador(leer, hueco)
	local p = {
		veces = 0,
		rebotes = 0,
		antes = false,
		espera = 0,
		hueco = math.max(0, math.floor(hueco or 0)),
		leer = leer,
	}

	-- Devuelve true en el frame en que se acaba de pulsar
	function p.frame()
		if p.espera > 0 then p.espera = p.espera - 1 end

		local ahora = p.leer() and true or false
		local flanco = ahora and not p.antes
		p.antes = ahora

		if not flanco then return false end

		if p.espera > 0 then
			p.rebotes = p.rebotes + 1
			return false
		end

		p.espera = p.hueco
		p.veces = p.veces + 1
		return true
	end

	return p
end

-- La cuenta del monedero durante la partida.
--
--   base       lo que el jugador tiene, contando lo que ya va dentro del juego
--   consumido  creditos que el juego se ha llevado de verdad
--
-- Se guarda en cada cambio, no al salir: si matan MAME de un golpe, el fichero
-- ya tiene el numero bueno.
function M.cuenta(op)
	op = op or {}

	local c = {
		base      = math.max(0, math.floor(op.base or 0)),
		consumido = 0,
		guardar   = op.guardar or function() end,
		log       = op.log or function() end,
	}

	-- Se guarda ya de entrada. El credito que acabamos de meter en la maquina
	-- sigue siendo del jugador mientras el juego no se lo lleve: si sale sin
	-- jugar, se lo encuentra en el monedero.
	function c.guardar_ahora()
		c.guardar(c.saldo())
	end

	function c.saldo()
		local s = c.base - c.consumido
		return (s > 0) and s or 0
	end

	-- El juego se lleva n creditos (una partida, normalmente)
	function c.consume(n)
		n = math.max(0, math.floor(n or 0))
		if n == 0 then return end

		c.consumido = c.consumido + n
		c.guardar(c.saldo())
		c.log('el juego se lleva %d credito%s, quedan %d en el monedero',
			n, (n == 1) and '' or 's', c.saldo())
	end

	-- Se devuelve lo cobrado. Hace falta porque el credito se cobra al meter la
	-- moneda, antes de saber si el juego la ha recogido: si la placa todavia
	-- estaba arrancando la tira, y entonces habria que devolverla.
	--
	-- Se cobra primero y se devuelve despues, y no al reves, por el mismo
	-- motivo que en el lanzamiento: si algo se cae por el camino, el error
	-- seguro es tener cobrado de mas, nunca regalar creditos.
	function c.devuelve(n)
		n = math.max(0, math.floor(n or 0))
		if n == 0 then return end

		c.consumido = c.consumido - n
		if c.consumido < 0 then c.consumido = 0 end

		c.guardar(c.saldo())
		c.log('devuelvo %d credito%s, el juego no lo recogio: quedan %d en el monedero',
			n, (n == 1) and '' or 's', c.saldo())
	end

	return c
end

return M
