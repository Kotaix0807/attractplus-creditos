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

local WARN_EXIT_SFX = "cape-fly-hurt.wav"
local WARN_EXIT_SFX_2 = "peach-help.wav"
local CONTINUE = "checkpoint.wav"

local M = {}

-- Obtener dinamicamente el directorio del script
local source = debug.getinfo(1, "S").source
local script_dir = source:match("@?(.*)/") or "."
local function playSound(soundID)
    -- 1. Ruta limpia (sin comillas) para que Lua pueda verificar que existe
    local rawPath = script_dir .. "/sfx/" .. soundID
    local file = io.open(rawPath, "r")

    if file then
        file:close()
    else
        print("Error: No se encontró el sonido " .. rawPath)
        return
    end

    -- 2. Ruta formateada: comillas simples y el & para no bloquear el frame.
    -- '-D default': se usa el PCM 'default' de ALSA, que en la cabina es un
    -- dmix (mezclador software). Es imprescindible para que suene A LA VEZ que
    -- MAME: si MAME abriera el hw: crudo en exclusiva ('sound sdl'), aplay daria
    -- "device or resource busy". Por eso mame.ini va con 'sound portaudio', que
    -- hace que MAME tambien pase por el default/dmix y comparta la tarjeta.
    local comando_sfx = "aplay -q -D default '" .. rawPath .. "' &"
    os.execute(comando_sfx)
end

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
		-- Combinacion de confirmacion para salir (ARRIBA ABAJO IZQUIERDA DERECHA
		-- y luego el boton de salir). combo = cuantos pasos lleva hechos; combo_on
		-- = si este frame nos pasaron las direcciones (si no, se exige salir dos
		-- veces, como antes). dir_antes guarda el estado anterior para ver flancos.
		combo     = 0,
		combo_on  = false,
		dir_antes = {},
		-- Frames sin tocar ninguna direccion. El cuadro se rinde por INACTIVIDAD,
		-- no por tiempo total: mientras el jugador avanza la combinacion el cuadro
		-- se queda (si no, se iba antes de que llegara a pulsar salir).
		inactivo  = 0,
		log       = op.log or function() end,
	}

	-- El orden de la combinacion. Cambiarlo aqui lo cambia todo (logica y cuadro).
	local ORDEN = { 'arriba', 'abajo', 'izquierda', 'derecha' }

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
	-- Avanza la combinacion segun las direcciones de ESTE frame (flancos: solo
	-- cuenta pasar de no-pulsado a pulsado). La direccion esperada avanza un
	-- paso; cualquier otra direccion reinicia (a 1 si es el inicio, 'arriba').
	local function avanzar_combo(dirs)
		local flanco = {}
		local alguno = false
		for _, d in ipairs(ORDEN) do
			local p = dirs[d] and true or false
			flanco[d] = p and not a.dir_antes[d]
			if flanco[d] then alguno = true end
			a.dir_antes[d] = p
		end
		if alguno then a.inactivo = 0 end   -- sigue activo: no se rinde el cuadro
		local esperado = ORDEN[a.combo + 1]
		if esperado and flanco[esperado] then
			a.combo = a.combo + 1
			return
		end
		for _, d in ipairs(ORDEN) do
			if flanco[d] then
				a.combo = (d == 'arriba') and 1 or 0
				return
			end
		end
	end

	--   dirs  tabla {arriba,abajo,izquierda,derecha} de booleanos, o nil para
	--         volver al modo viejo (salir dos veces, sin combinacion).
	function a.frame(salir, seguir, dirs)
		salir = salir and true or false
		local flanco_salir = salir and not a.salir_antes
		a.salir_antes = salir
		a.combo_on = dirs ~= nil

		if a.estado == 'jugando' then
			-- Solo molesta si el jugador ha metido monedas aqui dentro y le
			-- quedan sin gastar. Entrar a mirar y salir no dispara nada.
			if flanco_salir and (a.metido > 0) and a.puede_quedar() then
				a.estado = 'avisando'
				a.reloj = 0
				a.combo = 0
				a.inactivo = 0
				-- Si el jugador tiene una direccion pulsada al aparecer el cuadro
				-- (venia jugando), no debe contar como el primer paso: se guarda
				-- el estado actual para que solo cuenten pulsaciones NUEVAS.
				a.dir_antes = {}
				if dirs then
					for _, d in ipairs(ORDEN) do a.dir_antes[d] = dirs[d] and true or false end
				end

				playSound(WARN_EXIT_SFX_2)

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
		a.inactivo = a.inactivo + 1

		if dirs then avanzar_combo(dirs) end

		-- Confirmacion de salida. Con combinacion: hay que haber hecho los 4 pasos
		-- (ARRIBA ABAJO IZQUIERDA DERECHA) y ADEMAS pulsar salir. Sin ella, basta
		-- con pulsar salir otra vez. En ambos casos se ignoran los primeros frames:
		-- ahi no es una confirmacion, es el rebote de la primera pulsacion.
		if flanco_salir then
			if a.reloj <= a.guarda then
				a.log('rebote de la tecla de salir (%d frames), no lo tomo por confirmacion',
					a.reloj)
			elseif dirs and (a.combo < #ORDEN) then
				a.log('salir pulsado, pero la combinacion va por %d/%d', a.combo, #ORDEN)
			else
				a.estado = 'jugando'
				a.log('salida confirmada')
				playSound(WARN_EXIT_SFX)
				return 'salir'
			end
		end

		-- Sigue jugando: lo pide, o ya no queda nada que perder, o se cansa
		-- de mirar el cuadro. El caso por defecto es NO salir.
		if seguir then
			a.estado = 'jugando'
			a.log('el jugador sigue jugando')
			playSound(CONTINUE)
			return 'bloquear'
		end

		if not a.puede_quedar() then
			a.estado = 'jugando'
			a.log('ya no queda nada dentro, quito el cuadro')
			return 'bloquear'
		end

		if a.inactivo >= a.espera then
			a.estado = 'jugando'
			a.log('nadie contesta, quito el cuadro')
			return 'bloquear'
		end

		return 'bloquear'
	end

	function a.visible()
		return a.estado == 'avisando'
	end

	-- Pista para el demonio de LEDs del panel mientras el cuadro de salida esta
	-- puesto: 'off' = apaga todos los botones (aun falta la combinacion), 'salir'
	-- = ya hizo las 4 direcciones y solo falta el boton de salir -> que parpadee;
	-- nil = no hay cuadro (LEDs normales). Pura: no toca el sistema, la escribe
	-- creditos.lua como el resto de senales.
	function a.led_estado()
		if a.estado ~= 'avisando' then return nil end
		if a.combo >= #ORDEN then return 'salir' end
		return 'off'
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

		-- La combinacion (arriba-abajo-izq-der) la dibuja el pintor como flechas
		-- de colores, no como texto. En modo combinacion el pintor reusa la
		-- segunda linea (los creditos en juego) y dibuja el resto el mismo.
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
