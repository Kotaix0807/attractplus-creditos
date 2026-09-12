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
		-- Antirrebote de la tecla de salir. El boton de moneda ya lo tenia
		-- (monedero.lua, M.pulsador) y este no: un microinterruptor abre y
		-- cierra varias veces en unos milisegundos al pulsarlo, asi que la
		-- misma pulsacion daba DOS flancos -- el primero pintaba el cuadro y
		-- el segundo lo confirmaba tres frames despues. El jugador veia que no
		-- avisaba, cuando lo que pasaba es que aviso y se contesto solo.
		guarda    = math.max(0, math.floor(op.guarda or 15)),    -- ~250 ms
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

	-- Lo que dice la RAM del juego, o nil si aqui hay que estimar. Devuelve nil
	-- tambien mientras la placa se asienta o la direccion esta a prueba: quien
	-- pregunta prefiere estimar antes que anunciar un numero inventado.
	local function leido()
		if a.exacto then
			local ok, n = pcall(a.exacto)
			if ok and (type(n) == 'number') then
				return (n > 0) and math.floor(n) or 0
			end
		end
		return nil
	end

	function a.dentro()
		local n = leido()
		if n then return n end

		local d = a.entrado - a.consumido
		return (d > 0) and d or 0
	end

	-- true cuando el numero de dentro() sale de la RAM y no de una estimacion
	function a.seguro()
		return leido() ~= nil
	end

	-- Hay algo de que avisar?
	--
	-- Con lectura exacta es un si o un no. SIN ella se avisa siempre que el
	-- jugador haya metido monedas en esta partida, aunque la estimacion diga
	-- cero -- decision de Eloy (2026-09-12), y el motivo es que los dos errores
	-- posibles no cuestan lo mismo:
	--
	--   callarse de mas   -> el jugador se deja creditos pagados y no se entera.
	--   molestar de mas   -> sale un cuadro que se quita pulsando salir otra vez.
	--
	-- La estimacion no puede distinguir un START que empieza partida de otro que
	-- el juego tira por tener una ya en marcha, asi que con la partida larga se
	-- iba a cero sola y se callaba. Aqui se elige el error barato.
	function a.puede_quedar()
		local n = leido()
		if n then return n > 0 end
		return a.metido > 0
	end

	-- Creditos que el juego se ha llevado. Quien detecta las pulsaciones de
	-- start es creditos.lua, que ya tiene un contador de flancos.
	--
	-- NUNCA se consume mas de lo que ha entrado: una placa no puede gastar un
	-- credito que no esta dentro. Sin este tope, cada START que el juego
	-- IGNORA -- y con la partida ya en marcha los ignora todos, esta medido --
	-- dejaba una deuda que se comia las monedas siguientes, y el aviso de
	-- salida se callaba teniendo creditos de verdad dentro de la maquina.
	function a.consume(n)
		local tope = a.entrado - a.consumido
		if tope <= 0 then return end
		a.consumido = a.consumido + math.min(tope, math.max(0, math.floor(n or 0)))
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
			if flanco_salir and (a.metido > 0) and a.puede_quedar() then
				a.estado = 'avisando'
				a.reloj = 0
				local n = a.dentro()
				if a.seguro() then
					a.log('salida frenada: %s en la maquina', (n == 1) and 'queda 1 credito'
						or string.format('quedan %d creditos', n))
				else
					a.log('salida frenada: el jugador metio %d moneda(s) y no se puede '
						.. 'saber cuantos creditos quedan', a.metido)
				end
				return 'bloquear'
			end
			return nil
		end

		-- avisando
		a.reloj = a.reloj + 1

		-- Segunda pulsacion de salir: adelante, es su decision. Pero no en los
		-- primeros frames: ahi no es una segunda pulsacion, es el rebote de la
		-- primera. Una persona que lee el cuadro tarda mucho mas que esto.
		if flanco_salir then
			if a.reloj <= a.guarda then
				a.log('rebote de la tecla de salir (%d frames), no lo tomo por confirmacion',
					a.reloj)
			else
				a.estado = 'jugando'
				a.log('salida confirmada')
				return 'salir'
			end
		end

		-- Sigue jugando: lo pide, o ya no queda nada que perder, o se cansa
		-- de mirar el cuadro. El caso por defecto es NO salir.
		if seguir then
			a.estado = 'jugando'
			a.log('el jugador sigue jugando')
			return 'bloquear'
		end

		if not a.puede_quedar() then
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
		local segunda

		if a.se_pierden then
			tercera = saldo
				and ('SI SALES AHORA LOS PIERDES. MONEDERO: ' .. tostring(saldo))
				or 'SI SALES AHORA LOS PIERDES'
		elseif saldo then
			tercera = 'SOLO VALEN AQUI. TU MONEDERO NO SE TOCA: ' .. tostring(saldo)
		else
			tercera = 'SI SALES AHORA LOS PIERDES'
		end

		-- Con el numero leido de la RAM se afirma; estimando, no. El cuadro
		-- puede salir con la estimacion a cero (ver puede_quedar), asi que
		-- decir "DEJAS 0 CREDITOS" seria mentira y ademas absurdo.
		if a.seguro() then
			segunda = (n == 1) and 'DEJAS 1 CREDITO DENTRO DE ESTA MAQUINA'
				or string.format('DEJAS %d CREDITOS DENTRO DE ESTA MAQUINA', n)
		elseif n == 1 then
			segunda = 'PUEDE QUEDAR 1 CREDITO DENTRO DE ESTA MAQUINA'
		elseif n > 1 then
			segunda = string.format('PUEDEN QUEDAR %d CREDITOS DENTRO DE ESTA MAQUINA', n)
		else
			segunda = 'PUEDEN QUEDAR CREDITOS DENTRO DE ESTA MAQUINA'
		end

		return {
			'OJO',
			segunda,
			tercera,
			'',
			'SALIR otra vez para salir',
			'START para seguir jugando',
		}
	end

	return a
end

return M
