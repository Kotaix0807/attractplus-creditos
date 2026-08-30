-- cerrojo.lua - el boton de moneda solo responde mientras quede monedero.
--
-- El problema: MAME lee el boton de moneda directamente del teclado, asi que
-- un jugador puede quedarse pulsando dentro de la partida y regalarse creditos
-- que nadie ha pagado. El monedero del frontend se queda mirando.
--
-- La regla: durante una partida se pueden meter tantas monedas como creditos
-- tenia el jugador en el monedero al lanzar (SALDO). Ni una mas.
--
-- Como se bloquea, que es lo delicado: NO con set_input_seq, que escribe
-- "NONE" en el .cfg del juego (ioport.cpp:2894) y ese fichero se guarda ANTES
-- de que se llame a los notificadores de salida (machine.cpp:440 vs :480), o
-- sea que salir con el cerrojo echado dejaria el boton muerto para siempre.
-- Se usa set_default_input_seq, que cambia m_seq y no toca live().cfg, que es
-- lo unico que se guarda. Al cerrar MAME no queda ni rastro.
--
-- Este modulo no habla con MAME a proposito: recibe las funciones de bloquear
-- y de soltar, asi que su contabilidad se prueba con 'lua' a secas.

local M = {}

-- op.limite    monedas que el jugador puede meter (su saldo al lanzar)
-- op.bloquear  deja el campo sin secuencia
-- op.soltar    se la devuelve
-- op.log
function M.nuevo(op)
	op = op or {}

	local c = {
		-- Sin monedero (monedas de verdad) no hay limite que aplicar: el
		-- cerrojo sigue existiendo solo para tener el boton cerrado mientras
		-- la placa arranca, que es cuando el juego tira las monedas o las
		-- acumula a lo bestia.
		ilimitado = op.ilimitado and true or false,
		limite   = math.max(0, math.floor(op.limite or 0)),
		metidas  = 0,
		echado   = nil,      -- nil: todavia no se ha decidido nada
		-- Segunda razon para tener el boton cerrado, aparte de quedarse sin
		-- monedero: la placa todavia esta arrancando. Durante su test de
		-- RAM/ROM el juego IGNORA las monedas, asi que dejar pulsar ahi seria
		-- cobrarle al jugador por nada.
		listo    = (op.listo ~= false),
		rechazadas = 0,
		bloquear = op.bloquear or function() end,
		soltar   = op.soltar or function() end,
		log      = op.log or function() end,
	}

	function c.disponible()
		if c.ilimitado then return math.huge end
		local n = c.limite - c.metidas
		return (n > 0) and n or 0
	end

	-- El jugador ha pulsado la moneda. Devuelve true si la moneda vale (el
	-- boton estaba suelto y MAME la ha visto), false si se rechaza.
	--
	-- Importante: esto se llama aunque el cerrojo este echado, porque el
	-- detector de flanco lee la secuencia ORIGINAL que se guardo al arrancar,
	-- no la del campo. Asi se puede avisar al jugador de por que no pasa nada.
	function c.moneda()
		if c.echado then
			c.rechazadas = c.rechazadas + 1
			return false
		end

		if not c.listo then
			c.rechazadas = c.rechazadas + 1
			return false
		end

		c.metidas = c.metidas + 1
		return true
	end

	-- Una vez por frame: ajusta el cerrojo al estado actual. Solo llama a
	-- bloquear/soltar cuando la situacion cambia, no en cada frame.
	function c.frame()
		local hace_falta = ( not c.listo ) or ( c.disponible() <= 0 )

		if c.echado ~= hace_falta then
			c.echado = hace_falta

			if hace_falta then
				c.bloquear()
				if not c.listo then
					c.log('la maquina esta arrancando: boton de moneda cerrado')
				elseif c.ilimitado then
					c.log('boton de moneda cerrado')
				else
					c.log('sin monedero: bloqueo el boton de moneda (%d metidas de %d)',
						c.metidas, c.limite)
				end
			else
				c.soltar()
				c.log('el boton de moneda vuelve a funcionar (quedan %d)',
					c.disponible())
			end
		end
	end

	-- Por que no pasa la moneda, para poder explicarselo al jugador.
	function c.motivo()
		if not c.listo then return 'arrancando' end
		if c.disponible() <= 0 then return 'sin creditos' end
		return nil
	end

	-- El log del arranque enseña el limite, y con ilimitado no hay numero
	function c.cuantas()
		return c.ilimitado and 'las que quiera' or (tostring(c.limite) .. ' moneda(s)')
	end

	-- Se llama al terminar. Deja el boton como estaba, pase lo que pase.
	function c.soltar_todo()
		if c.echado then
			c.echado = false
			c.soltar()
			c.log('suelto el boton de moneda al salir')
		end
	end

	return c
end

return M
