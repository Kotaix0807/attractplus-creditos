-- aviso.lua - el cuadro que avisa de creditos que se quedan dentro del juego.
--
-- El monedero paga por lo que se juega, no por lo que se mete (ver
-- monedero.lua), asi que meter monedas dentro de una partida ya no arruina a
-- nadie. Pero sigue habiendo algo que explicar: esos creditos solo valen en
-- esta maquina, y al salir se quedan aqui.
--
-- El cuadro aparece SOLO si el jugador ha metido monedas durante la partida y
-- quedan sin gastar. Entrar a mirar un juego y salir no molesta a nadie: para
-- eso esta la condicion de "metido > 0".
--
-- CUANTOS CREDITOS HAY DENTRO: exacto si el juego esta en creditos.dat, y si
-- no, una estimacion.
--
-- Con la direccion de memoria del contador (ver memoria.lua) se lee el numero
-- de verdad. Sin ella se estima asi:
--
--   dentro = (creditos que han entrado) - (creditos que el juego se ha llevado)
--
-- Lo que entra lo sabemos exactamente: lo insertamos nosotros al arrancar y
-- contamos las monedas que mete el jugador. Lo que el juego consume se estima
-- mirando el boton de START: cada pulsacion de "1 jugador" gasta un credito y
-- la de "2 jugadores" gasta dos. Es lo que hacen casi todas las placas clasicas
-- pero no es una ley: hay juegos que cobran dos creditos por partida, y ahi la
-- cuenta se queda corta. Por eso el cuadro dice "pueden quedar" y no "quedan".
--
-- Aqui no se habla con MAME: son datos y una maquina de estados, para poder
-- probarlo con lua a secas. Ver pruebas/prueba_aviso.lua

local M = {}

-- op.entrado   creditos que ya han entrado en la maquina
-- op.espera    frames que el cuadro se queda en pantalla antes de rendirse
-- op.log       funcion de diagnostico
function M.nuevo(op)
	op = op or {}

	local a = {
		-- Si nos dan una funcion para leer los creditos de verdad, se usa esa
		-- y la estimacion se queda de reserva.
		exacto    = op.dentro,
		se_pierden = op.se_pierden and true or false,
		entrado   = math.max(0, math.floor(op.entrado or 0)),
		metido    = 0,   -- lo que ha metido el jugador, aparte del lanzamiento
		consumido = 0,
		espera    = math.max(1, math.floor(op.espera or 300)),   -- ~5 s a 60 Hz
		estado    = 'jugando',
		reloj     = 0,
		salir_antes = false,
		log       = op.log or function() end,
	}

	-- Creditos que mete el jugador durante la partida
	function a.entra(n)
		n = math.max(0, math.floor(n or 0))
		a.entrado = a.entrado + n
		a.metido = a.metido + n
	end

	function a.dentro()
		if a.exacto then
			local ok, n = pcall(a.exacto)
			if ok and (type(n) == 'number') then
				return (n > 0) and math.floor(n) or 0
			end
		end

		local d = a.entrado - a.consumido
		return (d > 0) and d or 0
	end

	-- Creditos que el juego se ha llevado. Quien detecta las pulsaciones de
	-- start es creditos.lua, que ya tiene un contador de flancos.
	function a.consume(n)
		a.consumido = a.consumido + math.max(0, math.floor(n or 0))
	end

	-- Devuelve la accion para este frame:
	--   nil          no hacer nada, dejar que MAME siga a lo suyo
	--   'bloquear'   comerse las teclas de UI y pintar el cuadro
	--   'salir'      el jugador ha confirmado: salir de verdad
	function a.frame(salir, seguir)
		salir = salir and true or false
		local flanco_salir = salir and not a.salir_antes
		a.salir_antes = salir

		if a.estado == 'jugando' then
			-- Solo molesta si el jugador ha metido monedas aqui dentro y le
			-- quedan sin gastar. Entrar a mirar y salir no dispara nada.
			if flanco_salir and (a.dentro() > 0) and (a.metido > 0) then
				a.estado = 'avisando'
				a.reloj = 0
				local n = a.dentro()
				a.log('salida frenada: %s en la maquina', (n == 1) and 'puede quedar 1 credito'
					or string.format('pueden quedar %d creditos', n))
				return 'bloquear'
			end
			return nil
		end

		-- avisando
		a.reloj = a.reloj + 1

		-- Segunda pulsacion de salir: adelante, es su decision
		if flanco_salir then
			a.estado = 'jugando'
			a.log('salida confirmada')
			return 'salir'
		end

		-- Sigue jugando: lo pide, o ya no queda nada que perder, o se cansa
		-- de mirar el cuadro. El caso por defecto es NO salir.
		if seguir then
			a.estado = 'jugando'
			a.log('el jugador sigue jugando')
			return 'bloquear'
		end

		if a.dentro() <= 0 then
			a.estado = 'jugando'
			a.log('ya no queda nada dentro, quito el cuadro')
			return 'bloquear'
		end

		if a.reloj >= a.espera then
			a.estado = 'jugando'
			a.log('nadie contesta, quito el cuadro')
			return 'bloquear'
		end

		return 'bloquear'
	end

	function a.visible()
		return a.estado == 'avisando'
	end

	-- Las lineas del cuadro, para que quien dibuje no tenga que pensar.
	--
	-- saldo es lo que le queda al jugador en el monedero. Que se pierdan o no
	-- los creditos de dentro depende de CUANDO se cobraron (op.se_pierden):
	--
	--   cobro al jugar  -> meter la moneda no costo nada, el monedero esta
	--                      intacto y el aviso puede prometerlo.
	--   cobro al meter  -> el credito ya salio del monedero, asi que lo que se
	--                      queda dentro de la maquina SE PIERDE de verdad.
	--
	-- En modo manual no hay monedero (saldo nil) y tampoco se puede prometer
	-- nada.
	function a.lineas(saldo)
		local n = a.dentro()
		local tercera

		if a.se_pierden then
			tercera = saldo
				and ('SI SALES AHORA LOS PIERDES. MONEDERO: ' .. tostring(saldo))
				or 'SI SALES AHORA LOS PIERDES'
		elseif saldo then
			tercera = 'SOLO VALEN AQUI. TU MONEDERO NO SE TOCA: ' .. tostring(saldo)
		else
			tercera = 'SI SALES AHORA LOS PIERDES'
		end

		return {
			'OJO',
			(n == 1) and 'DEJAS 1 CREDITO DENTRO DE ESTA MAQUINA'
				or string.format('DEJAS %d CREDITOS DENTRO DE ESTA MAQUINA', n),
			tercera,
			'',
			'SALIR otra vez para salir',
			'START para seguir jugando',
		}
	end

	return a
end

return M
