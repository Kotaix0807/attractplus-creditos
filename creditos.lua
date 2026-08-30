-- creditos.lua - el lado MAME del monedero de la cabina.
--
-- Hace tres cosas:
--   1. al arrancar el juego, mete los creditos que el frontend haya pedido
--   2. durante la partida lleva la cuenta del monedero: descuenta lo que el
--      juego se lleva de verdad (las pulsaciones de START), no lo que se mete
--   3. si el jugador va a salir dejando creditos dentro de la maquina, frena la
--      salida y le avisa con un cuadro en pantalla (ver aviso.lua)
--
-- La segunda es la que evita perder creditos: el monedero vive en un fichero
-- (ver monedero.lua) que leen y escriben tanto el plugin del frontend como
-- este script, asi que al salir de la partida el saldo que queda es el bueno.
--
-- Uso desde el frontend (Attract-Mode Plus + plugin Creditos.nut):
--   mame pacman -autoboot_script creditos.lua -autoboot_delay 6
--
-- Uso a mano:
--   GA_CREDITOS=3 mame pacman -autoboot_script creditos.lua -autoboot_delay 6
--   echo 3 > ~/.attract/creditos.txt   # equivalente, por el fichero
--
-- IMPORTANTE, comprobado midiendo con Pac-Man:
--   * -autoboot_delay 6 o mas. Con 3 el juego aun estaba inicializando y se
--     perdian monedas silenciosamente (entraban 1 de 3, o ninguna).
--   * Un pulso de 4-8 frames basta. No hace falta mas.
--   * MONEDAS NO SON CREDITOS. Pac-Man venia con el DIP en 1 moneda = 2
--     creditos, asi que 3 monedas daban CREDIT 6. De eso se encarga GA_TARIFA.
--
-- Variables de entorno (todas opcionales):
--   GA_MONEDERO  1 para el monedero compartido con el frontend. Apagado por
--                defecto: la cabina va a MONEDAS DE VERDAD, que entran solas
--                en el emulador. Con 0 este script solo tapa el arranque y
--                avisa al salir con creditos dentro
--   GA_CREDITOS  creditos a insertar. Si no esta, se lee del fichero
--   GA_ARCHIVO   fichero del monedero        ($HOME/.attract/creditos.txt)
--   GA_TARIFA    1c1c | auto | off           (por defecto 1c1c)
--   GA_VIGILAR   0 para no descontar las monedas del jugador
--   GA_AVISO     0 para no avisar de creditos perdidos al salir
--   GA_AVISO_ESPERA  frames que el cuadro aguanta en pantalla (por defecto 300)
--   GA_SINCRONIZAR   0 para no escribir los creditos en la RAM del juego
--   GA_TOPE          maximo que se escribe en el contador (por defecto 9)
--   GA_TABLA         fichero de direcciones (por defecto creditos.dat de al lado)
--   GA_PULSO     frames con la moneda pulsada       (por defecto 8)
--   GA_HUECO     frames de separacion entre monedas (por defecto 8)
--   GA_ESPERA    frames extra de espera al inicio   (por defecto 0)
--   GA_ARRANQUE  frames MINIMOS de arranque tapado (300)
--   GA_ARRANQUE_MAX  tope de ese arranque, por si no se puede detectar (1800)
--   GA_ARRANQUE_SIN  frames de arranque en juegos sin contador conocido (900)
--   GA_ESTABLE   frames que el contador debe estar quieto para darlo por listo (120)
--   GA_COMPROBAR frames de gracia para ver si la moneda llego; si no, se devuelve (90)
--   GA_ANTIRREBOTE frames que se ignoran tras una moneda, contra el rebote (8)
--   GA_VELOCIDAD velocidad del emulador al arrancar: 0 sin freno, 2 el doble...
--   GA_FIJO      1 para usar GA_ARRANQUE tal cual, sin deteccion
--   GA_AJUSTES   ruta del fichero de ajustes por juego (arranque.dat)
--
-- Casi todo esto se puede poner por juego en arranque.dat, en segundos.
-- La variable de entorno manda sobre el fichero.
--   GA_TURBO     0 para no acelerar el emulador durante ese arranque
--   GA_ASENTAR   frames que se deja asentar la RAM antes de contar (180)
--   GA_LIMPIAR   0 para no quitar los creditos que la maquina trae puestos
--   GA_COBRO     'meter' (por defecto) o 'jugar': cuando se cobra el credito
--   GA_CERROJO   0 para no limitar las monedas del jugador al monedero
--   GA_MONEDA    token de entrada a usar            (por defecto COIN1)
--   GA_VERBOSO   1 para mensajes de diagnostico
--
-- GA_TARIFA:
--   1c1c  deja el DIP de tarifa en 1 moneda/1 credito y ademas compensa las
--         monedas de ESTA partida con la tarifa que la placa ya leyo al
--         arrancar. Es decir: el primer arranque de un juego puede regalar
--         algun credito, y del segundo en adelante el numero es exacto.
--         MAME guarda ese DIP en su .cfg, asi que el cambio es permanente.
--         Para que hasta el primer arranque sea exacto, pasa una vez el
--         script poner_1c1c.lua sobre la lista de juegos.
--   auto  no toca el DIP; lee la tarifa que haya y ajusta las monedas.
--   off   una moneda por credito, sin mirar los DIP.
--
-- Nota: -autoboot_delay ya espera N segundos antes de ejecutar este script.
-- Usalo para dar tiempo al test de RAM/ROM de la placa. GA_ESPERA es un ajuste
-- fino adicional por si algun juego concreto necesita mas margen.

local function num(nombre, defecto)
	local v = tonumber(os.getenv(nombre) or '')
	return v and math.floor(v) or defecto
end

local PULSO   = math.max(1, num('GA_PULSO', 8))
local HUECO   = math.max(1, num('GA_HUECO', 8))
local ESPERA  = math.max(0, num('GA_ESPERA', 0))
local TOKEN   = os.getenv('GA_MONEDA') or 'COIN1'
local VERBOSO = os.getenv('GA_VERBOSO') == '1'
local TARIFA  = (os.getenv('GA_TARIFA') or '1c1c'):lower()
-- Monedas de verdad (por defecto) o monedero compartido con el frontend
local MONEDERO = os.getenv('GA_MONEDERO') == '1'
local VIGILAR = os.getenv('GA_VIGILAR') ~= '0'
local AVISAR  = os.getenv('GA_AVISO') ~= '0'
local ESPERA_AVISO = math.max(30, num('GA_AVISO_ESPERA', 300))
local MENSAJE_FRAMES = math.max(30, num('GA_MENSAJE', 150))   -- ~2,5 s a 60 Hz
-- Quien paga el credito, y cuando. Es la decision de fondo del sistema:
--   'meter': el monedero se descuenta AL METER la moneda. Es el diseno con
--            contador fisico: el jugador ve bajar el numero, asi que gastar al
--            meter es honesto y ademas es lo que hace una recreativa.
--   'jugar': el monedero se descuenta cuando el juego se lleva el credito.
--            Era lo correcto MIENTRAS el gasto era invisible.
local ASENTAR = math.max(0, num('GA_ASENTAR', 180))   -- ~3 s a 60 Hz
-- El arranque tapado no puede ser un plazo fijo: cada placa tarda lo suyo, y
-- abrir el boton antes de tiempo es cobrarle al jugador monedas que el juego
-- todavia tira. Asi que ARRANQUE es el MINIMO, ARRANQUE_MAX el tope, y entre
-- los dos se espera a que el contador de creditos del juego se quede quieto,
-- que es la senal de que la placa ya inicializo su RAM.
--
-- Como el emulador va sin freno durante ese rato, ser generoso no cuesta
-- tiempo real: 20 segundos emulados son un parpadeo.
local COMPROBAR = math.max(0, num('GA_COMPROBAR', 90))      -- ~1,5 s de gracia
local REBOTE = math.max(0, num('GA_ANTIRREBOTE', 8))        -- ~130 ms a 60 Hz
local LIMPIAR = os.getenv('GA_LIMPIAR') ~= '0'
local COBRO = (os.getenv('GA_COBRO') or 'meter'):lower()
if COBRO ~= 'jugar' then COBRO = 'meter' end

-- En modo 'meter' no se escribe el monedero en la RAM del juego: eso metería
-- todos los creditos de golpe y el boton de moneda dejaria de pintar nada.
local SINCRONIZAR = (os.getenv('GA_SINCRONIZAR') ~= '0') and (COBRO ~= 'meter')
local CERROJO = os.getenv('GA_CERROJO') ~= '0'
local TOPE = math.max(1, num('GA_TOPE', 9))   -- casi ninguna placa clasica pasa de 9

-- Colores del cuadro y del mensaje (formato 0xAARRGGBB de MAME)
local COLOR_BORDE  = 0xffffaa00
local COLOR_FONDO  = 0xf4000000
local COLOR_TEXTO  = 0xffffffff
local COLOR_TITULO = 0xffffdd44
local COLOR_NEGRO  = 0xff000000
local PASO = 0.075          -- alto de linea, en fraccion de pantalla

local BUZON = os.getenv('GA_ARCHIVO')
if not BUZON or BUZON == '' then
	local casa = os.getenv('HOME') or '.'
	BUZON = casa .. '/.attract/creditos.txt'
end

local fin_del_arranque   -- se define mas abajo, cuando ya hay estado

local function log(fmt, ...)
	if VERBOSO then
		print(string.format('[creditos] ' .. fmt, ...))
	end
end

-- ---------------------------------------------------------------
-- Modulos de al lado. La ruta sale del propio script: comprobado que
-- debug.getinfo funciona en el contexto de -autoboot_script.
-- ---------------------------------------------------------------
-- --- si la placa se reinicio, MAME vuelve a lanzar este script ---
--
-- Comprobado con elevator: la placa se reinicia durante el arranque y MAME
-- relanza el autoboot. Las globales de Lua SOBREVIVEN, asi que aqui todavia
-- esta el estado de la ejecucion anterior.
--
-- Hay que deshacer lo suyo ANTES de tomar nota de como esta todo. Si no, esta
-- ejecucion guardaria como "original" lo que dejo la anterior -- el freno ya
-- quitado y la secuencia de la moneda ya vacia -- y al terminar restauraria
-- eso: emulador sin freno y boton de moneda muerto, para siempre.
if GA_ESTADO and GA_ESTADO.deshaceres then
	log('la placa se reinicio: deshago lo de la ejecucion anterior')

	for i = #GA_ESTADO.deshaceres, 1, -1 do
		local ok, err = pcall(GA_ESTADO.deshaceres[i])
		if not ok then log('  no pude deshacer algo: %s', tostring(err)) end
	end

	GA_ESTADO.deshaceres = {}
end

local MI_DIR = (debug.getinfo(1, 'S').source or ''):match('^@(.*[/\\])') or ''

local function vecino(nombre)
	local ok, mod = pcall(dofile, MI_DIR .. nombre)
	if ok and type(mod) == 'table' then return mod end
	log('no puedo cargar %s (%s)', nombre, tostring(mod))
	return nil
end

local T   = vecino('tarifa.lua')     -- analisis del DIP de tarifa
local MON = vecino('monedero.lua')   -- la cuenta compartida
local AV  = vecino('aviso.lua')      -- el cuadro de creditos dentro de la maquina
local MEM = vecino('memoria.lua')    -- leer los creditos de la RAM del juego
local CER = vecino('cerrojo.lua')    -- el cerrojo del boton de moneda
local AJU = vecino('ajustes.lua')    -- ajustes de arranque por juego

-- Los valores salen de arranque.dat (por juego, en segundos), y una variable
-- de entorno pisa lo que diga el fichero (en frames, que es como estaban antes
-- y como las usan las pruebas).
local AJUSTES = AJU and AJU.para(
	AJU.leer(os.getenv('GA_AJUSTES') or (MI_DIR .. 'arranque.dat')),
	emu.romname and emu.romname() or '',
	os.getenv) or nil

local function ajuste(clave, var, defecto)
	if AJUSTES then return (AJUSTES.valor(clave, var, defecto)) end
	return num(var, defecto)
end

local function ajuste_frames(clave, var, defecto)
	if AJUSTES then return (AJUSTES.frames(clave, var, defecto)) end
	return num(var, defecto)
end

local ARRANQUE = math.max(0, ajuste_frames('arranque', 'GA_ARRANQUE', 300))
local ARRANQUE_MAX = math.max(0, ajuste_frames('max', 'GA_ARRANQUE_MAX', 1800))
local ARRANQUE_SIN = math.max(0, ajuste_frames('sin', 'GA_ARRANQUE_SIN', 900))
local ESTABLE = math.max(1, ajuste_frames('estable', 'GA_ESTABLE', 120))
local FIJO = ajuste('fijo', 'GA_FIJO', 0) ~= 0
-- Velocidad del emulador durante el arranque: 0 = sin freno
local VELOCIDAD = math.max(0, ajuste('velocidad', 'GA_VELOCIDAD', 0))
local TURBO = (os.getenv('GA_TURBO') ~= '0') and (ajuste('turbo', nil, 1) ~= 0)

-- ---------------------------------------------------------------
-- 1. La cuenta: cuanto hay que meter y cuanto queda en el monedero
-- ---------------------------------------------------------------
local SALDO, INSERTA = 0, 0
local HAY_MONEDERO = false     -- sin fichero y sin GA_CREDITOS: modo manual

-- El monedero compartido con el frontend esta APAGADO por defecto desde el
-- 2026-08-29: la cabina va a monedas de verdad, que entran directamente en el
-- emulador como en una recreativa. GA_MONEDERO=1 lo vuelve a encender (el
-- sistema entero sigue montado y probado, ver la rama monedero-frontend).
if MON and MONEDERO then
	local s, i = MON.leer(BUZON)
	if s then
		SALDO, INSERTA, HAY_MONEDERO = s, i, true
		log('monedero %s: saldo %d, a insertar %d', BUZON, SALDO, INSERTA)
	else
		log('no hay monedero en %s: modo manual, las monedas las mete el jugador',
			BUZON)
	end
end

if MONEDERO and os.getenv('GA_CREDITOS') then
	INSERTA = math.max(0, num('GA_CREDITOS', 0))
	HAY_MONEDERO = true
	log('GA_CREDITOS=%d manda sobre el fichero', INSERTA)
end

-- La orden de insertar se consume EN CUANTO se lee. Si no, un segundo arranque
-- del mismo juego (o uno a mano desde la consola) volveria a meter los mismos
-- creditos de regalo.
if MON and (INSERTA > 0) then
	MON.escribir(BUZON, SALDO, 0)
end

-- En modo 'meter' el frontend no inserta nada: el jugador entra con la maquina
-- a cero y mete los creditos que quiera con el boton, viendolos salir de su
-- monedero en el contador fisico.
if (COBRO == 'meter') and not os.getenv('GA_CREDITOS') then
	if INSERTA > 0 then
		log('modo meter: los %d creditos del lanzamiento NO se insertan, '
			.. 'los mete el jugador con el boton', INSERTA)
	end
	INSERTA = 0
end

-- ---------------------------------------------------------------
-- 2. La entrada de moneda de esta maquina
-- ---------------------------------------------------------------

-- Se recorren todos los puertos comparando por TIPO. No se puede indexar por
-- nombre: port.fields se indexa por el nombre traducido, asi que "Coin 1" no
-- existiria en una MAME en espanol.
local function buscar_moneda()
	local ioport = manager.machine.ioport
	local ok, tipo = pcall(function()
		local t = ioport:token_to_input_type(TOKEN)   -- devuelve (tipo, jugador)
		return t
	end)
	if not ok or not tipo then
		log('token desconocido: %s', TOKEN)
		return nil
	end
	for etiqueta, port in pairs(ioport.ports) do
		for _, campo in pairs(port.fields) do
			if campo.type == tipo then
				log('encontrado %s en el puerto %s', TOKEN, etiqueta)
				return campo
			end
		end
	end
	return nil
end

local CAMPO = buscar_moneda()
if not CAMPO then
	-- No es un error: consolas y ordenadores no tienen ranura de monedas.
	log('esta maquina no tiene entrada "%s", no hay nada que hacer', TOKEN)
	return
end

-- ---------------------------------------------------------------
-- 3. La tarifa que la placa tiene en ESTE arranque
-- ---------------------------------------------------------------

-- Deja el DIP en 1 moneda/1 credito para los PROXIMOS arranques. Comprobado
-- midiendo con Pac-Man: la placa lee la tarifa al arrancar, asi que cambiarla
-- ahora no afecta a esta partida, pero MAME la guarda en su .cfg y desde el
-- siguiente arranque los creditos del frontend son exactos.
local function fijar_1c1c(dip, gratis)
	if gratis then
		log('el juego esta en partida gratis, no le toco el DIP')
		return
	end

	local valor = T.valor_1c1c(dip)
	if not valor then
		log('este juego no ofrece 1 moneda/1 credito, solo compenso')
		return
	end

	if dip.campo.user_value == valor then
		log('el DIP ya estaba en 1 moneda/1 credito')
		return
	end

	dip.campo.user_value = valor
	log('DIP dejado en 1 moneda/1 credito (valor %s). Esta partida usa todavia '
		.. 'la tarifa vieja; desde el siguiente arranque sera exacta',
		tostring(valor))
end

-- Devuelve monedas_por_tanda, creditos_por_tanda, es_gratis
local function tarifa_vigente()
	if (TARIFA == 'off') or not T then
		return 1, 1, false
	end

	local dip = T.buscar_dip()
	if not dip then
		log('no encuentro DIP de tarifa, una moneda por credito')
		return 1, 1, false
	end

	local texto = T.ajuste_actual(dip)
	log('DIP de tarifa: %s [%s] = [%s]', dip.etiqueta, dip.nombre, tostring(texto))

	local monedas_por, creditos_por, gratis = T.partir(texto)

	if TARIFA == '1c1c' then
		fijar_1c1c(dip, gratis)
	end

	if gratis then
		log('partida gratis')
		return 1, 1, true
	end

	if not monedas_por or (creditos_por == 0) then
		log('ajuste actual no interpretable, una moneda por credito')
		return 1, 1, false
	end

	if T.con_premio(texto) then
		log('ojo: esta tarifa premia acumular monedas, el juego puede dar mas '
			.. 'creditos de los pedidos. Pasa poner_1c1c.lua sobre este juego')
	end

	return monedas_por, creditos_por, false
end

local MONEDAS_POR, CREDITOS_POR, GRATIS = tarifa_vigente()

-- Cuantas monedas hay que meter para conseguir los creditos pedidos.
-- Redondeo hacia arriba: preferimos regalar un credito antes que comerselo.
local MONEDAS = 0
if INSERTA > 0 then
	if GRATIS then
		log('partida gratis, no hacen falta monedas')
	else
		MONEDAS = math.ceil(INSERTA * MONEDAS_POR / CREDITOS_POR)
		log('%d creditos a esa tarifa son %d monedas', INSERTA, MONEDAS)
	end
end

-- ---------------------------------------------------------------
-- 4. Estado, global a proposito: si estas variables fueran locales del chunk,
-- el recolector de basura podria llevarse la suscripcion al notificador y los
-- callbacks dejarian de dispararse.
-- ---------------------------------------------------------------
GA_ESTADO = {
	campo     = CAMPO,
	restantes = MONEDAS,
	reloj     = 0,
	fase      = (MONEDAS > 0) and ((ESPERA > 0) and 'espera' or 'pulso') or 'fin',
	sub       = nil,
	cuenta    = nil,
	aviso     = nil,
	memoria   = nil,   -- contador leido de la RAM del juego, si se conoce
	a_prueba  = nil,   -- direccion importada pendiente de comprobar
	sincro    = nil,   -- escritura del monedero en esa misma direccion
	leer_ram  = nil,
	escribir_ram = nil,
	consumido_visto = 0,
	cerrojo   = nil,   -- limita las monedas del jugador a su monedero
	metidos   = 0,     -- creditos que el jugador ha pagado en esta partida
	deshaceres = {},   -- para dejarlo todo como estaba si la placa se reinicia
	arranque  = false, -- true mientras la maquina esta arrancando
	arranque_frames = 0,
	estable   = 0,     -- frames que el contador de creditos lleva quieto
	ultimo_ram = nil,
	pendiente = nil,   -- moneda cobrada a la espera de aparecer en el juego
	turbo     = nil,   -- ajustes de velocidad guardados para restaurarlos
	pulso_moneda = nil,
	pulso_start1 = nil,
	pulso_start2 = nil,
	mensaje   = nil,
	mensaje_reloj = 0,
	leer_salir  = nil,   -- se pueden sustituir para probar sin teclado
	leer_start1 = nil,
	leer_start2 = nil,
}

-- --- insercion automatica al arrancar ---
local function insertar(e)
	e.reloj = e.reloj + 1

	if e.fase == 'espera' then
		if e.reloj >= ESPERA then
			e.fase, e.reloj = 'pulso', 0
		end

	elseif e.fase == 'pulso' then
		e.campo:set_value(1)
		if e.reloj >= PULSO then
			e.campo:set_value(0)
			e.restantes = e.restantes - 1
			e.fase, e.reloj = 'hueco', 0
			log('moneda insertada, quedan %d', e.restantes)
		end

	elseif e.fase == 'hueco' then
		e.campo:set_value(0)
		if e.reloj >= HUECO then
			if e.restantes > 0 then
				e.fase, e.reloj = 'pulso', 0
			else
				e.fase = 'fin'
				e.campo:set_value(0)   -- garantiza soltar la moneda
				log('insercion terminada')
			end
		end
	end
end

-- Cuando la placa esta lista de verdad.
--
-- Medido con Pac-Man trazando el byte 4e6e frame a frame: durante su test de
-- RAM ese byte va cambiando de patron (3, 10, 1, 8, 15...), a partir del frame
-- 90 se queda en 176 -- ojo, QUIETO pero todavia arrancando -- y en el frame
-- 250 la placa termina y lo pone a 0, donde se queda.
--
-- O sea que "lleva un rato quieto" NO vale como senal: la RAM sin inicializar
-- tambien esta quieta, y con esa regla el boton se abria en el frame 302 con la
-- placa a medio arrancar. La senal buena es que el contador este a CERO y se
-- quede, que es lo que hace una placa que ha terminado de inicializarse.
--
-- La segunda regla (quieto mucho mas rato) es para los juegos con NVRAM, que
-- arrancan con los creditos de la sesion anterior y nunca pasan por cero. El
-- plazo es largo a proposito: la meseta de 176 de Pac-Man dura 160 frames y no
-- debe colarse por ahi.
local function ya_arranco(e)
	if e.arranque_frames < ARRANQUE then return false end

	-- 'fijo=1' en arranque.dat: el plazo lo pone el usuario y no se discute.
	-- Es la valvula de escape para un juego que se porte raro.
	if FIJO then return true end

	if e.arranque_frames >= ARRANQUE_MAX then
		log('arranque: se acabo el plazo de %d frames, abro el boton', ARRANQUE_MAX)
		return true
	end

	-- Sin contador conocido no hay nada que mirar: solo queda el reloj, y por
	-- eso se espera bastante mas. Con el emulador sin freno no cuesta tiempo
	-- real, y cobrarle al jugador una moneda que el juego tira es peor.
	if not e.leer_ram then
		return e.arranque_frames >= ARRANQUE_SIN
	end

	if (e.ultimo_ram == 0) and (e.estable >= ESTABLE) then
		log('arranque: el contador lleva %d frames a cero, la placa esta lista', e.estable)
		return true
	end

	if e.estable >= (ESTABLE * 3) then
		log('arranque: el contador lleva %d frames quieto en %s, lo doy por listo',
			e.estable, tostring(e.ultimo_ram))
		return true
	end

	return false
end

local function por_frame()
	local e = GA_ESTADO

	if e.arranque then
		e.arranque_frames = e.arranque_frames + 1

		if e.leer_ram then
			local okr, v = pcall(e.leer_ram)
			if okr and (type(v) == 'number') then
				if v == e.ultimo_ram then
					e.estable = e.estable + 1
				else
					e.estable, e.ultimo_ram = 0, v
				end
			end
		end

		if ya_arranco(e) then
			log('arranque terminado en el frame %d', e.arranque_frames)
			fin_del_arranque()
		end
	end

	-- Comprobar que la moneda que se cobro llego de verdad al juego. Si la
	-- placa la tiro (todavia no estaba lista, o el pulso se perdio), se
	-- devuelve el credito: cobrar por nada es el peor error de todos.
	if e.pendiente then
		local p = e.pendiente
		local okv, v = pcall(e.leer_ram)

		if okv and (type(v) == 'number') then
			if v > p.visto then p.visto = v end

			if (p.visto - p.antes) >= p.creditos then
				e.pendiente = nil              -- llegaron todos
			else
				p.plazo = p.plazo - 1

				if p.plazo <= 0 then
					local llegados = p.visto - p.antes
					if llegados < 0 then llegados = 0 end
					local perdidos = p.creditos - llegados

					if perdidos > 0 then
						if e.cuenta and (COBRO == 'meter') then
							e.cuenta.devuelve(perdidos)
						end
						if e.aviso then e.aviso.consume(perdidos) end
						if e.cerrojo then
							e.cerrojo.metidas = math.max(0, e.cerrojo.metidas - perdidos)
						end
						e.metidos = math.max(0, e.metidos - perdidos)

						e.mensaje = 'LA MAQUINA NO LA COGIO. CREDITO DEVUELTO'
						e.mensaje_reloj = MENSAJE_FRAMES
						log('la maquina no recogio %d credito(s): devueltos', perdidos)
					end

					e.pendiente = nil
				end
			end
		else
			-- Sin poder leer no se devuelve nada: quedarse cobrado es el
			-- error seguro, regalar creditos no.
			e.pendiente = nil
		end
	end

	if (e.fase ~= 'fin') and (e.fase ~= 'inactivo') then
		insertar(e)
	end

	-- La cuenta corre toda la partida, tambien cuando no se ha insertado nada:
	-- el jugador puede meter monedas y jugar en cualquier momento.
	if e.pulso_moneda and e.pulso_moneda.frame() then
		-- El detector lee la secuencia original, asi que esto salta tambien
		-- con el cerrojo echado: es la unica forma de poder explicarle al
		-- jugador por que el boton no hace nada.
		if e.cerrojo and not e.cerrojo.moneda() then
			if e.cerrojo.motivo() == 'arrancando' then
				e.mensaje = 'ESPERA, LA MAQUINA ESTA ARRANCANDO'
				log('moneda rechazada: la placa todavia esta arrancando y la tiraria')
			else
				e.mensaje = 'SIN CREDITOS. VUELVE AL MENU PARA ANADIR'
				log('moneda rechazada: el jugador ya metio sus %d creditos', e.cerrojo.limite)
			end
			e.mensaje_reloj = MENSAJE_FRAMES
		else
			-- Meter una moneda no cuesta nada: mueve un credito del monedero a
			-- la maquina. Pero hay que decirselo, o el jugador cree que esta
			-- acumulando creditos para otros juegos.
			if e.aviso then e.aviso.entra(CREDITOS_POR) end
			e.metidos = e.metidos + CREDITOS_POR

			-- Se apunta para comprobar que el juego la recoge de verdad
			if (COMPROBAR > 0) and e.leer_ram and e.memoria and e.memoria.asentado then
				local okp, v = pcall(e.leer_ram)

				if okp and (type(v) == 'number') then
					if e.pendiente then
						e.pendiente.creditos = e.pendiente.creditos + CREDITOS_POR
						e.pendiente.plazo = COMPROBAR
					else
						e.pendiente = { antes = v, visto = v,
							creditos = CREDITOS_POR, plazo = COMPROBAR }
					end
				end
			end

			-- En modo 'meter' la moneda SE COBRA aqui: sale del monedero y
			-- entra en la maquina, y el contador fisico lo ensena al momento.
			if e.cuenta and (COBRO == 'meter') then
				e.cuenta.consume(CREDITOS_POR)
			end

			e.mensaje = e.cuenta
				and ('CREDITO PARA ESTE JUEGO. MONEDERO: ' .. tostring(e.cuenta.saldo()))
				or nil
			if e.mensaje then e.mensaje_reloj = MENSAJE_FRAMES end
			log('moneda del jugador: entra en la maquina%s',
				e.cuenta
					and ((COBRO == 'meter')
						and (', quedan ' .. tostring(e.cuenta.saldo()) .. ' en el monedero')
						or ', el monedero no se toca')
					or '')
		end
	end

	-- El cerrojo se ajusta DESPUES de contar la moneda, para que la ultima que
	-- le queda al jugador entre y el bloqueo empiece en ese mismo frame.
	if e.cerrojo then e.cerrojo.frame() end

	local s1 = e.pulso_start1 and e.pulso_start1.frame() or false
	local s2 = e.pulso_start2 and e.pulso_start2.frame() or false

	if e.sincro then
		-- Mientras se escribe el monedero en la RAM no se cuenta nada: los
		-- cambios de esos frames son nuestros, no del jugador.
		local r = e.sincro.frame()
		if r ~= 'pendiente' then
			if (r == 'rendido') and (e.restantes == 0) and (MONEDAS > 0) then
				-- No se pudo escribir: se vuelve al metodo de siempre
				log('vuelvo a insertar monedas')
				e.restantes = MONEDAS
				e.fase = (ESPERA > 0) and 'espera' or 'pulso'
			end
			e.sincro = nil
		end

	elseif e.a_prueba then
		-- Direccion importada a prueba: cuando terminen de entrar las monedas
		-- se mira si ese byte ha subido.
		if e.fase == 'fin' then
			local ok, ahora = pcall(e.leer_ram)
			local antes = e.a_prueba.antes

			if ok and antes and (ahora > antes) then
				log('la direccion importada %04x subio de %d a %d con las monedas: '
					.. 'me fio, a partir de ahora la leo',
					e.a_prueba.dir, antes, ahora)
				e.memoria.anterior = ahora        -- desde aqui se cuenta
			else
				log('la direccion importada %04x no se movio con las monedas '
					.. '(%s -> %s): la descarto y estimo por los START',
					e.a_prueba.dir, tostring(antes), tostring(ok and ahora or '?'))
				e.memoria = nil
			end

			e.a_prueba = nil
		end

	elseif e.memoria then
		-- Sabemos donde guarda el juego sus creditos: lo que baja el contador
		-- es lo que el juego se ha llevado de verdad. Nada de estimar.
		e.memoria.frame()

		if e.memoria.consumido > e.consumido_visto then
			local n = e.memoria.consumido - e.consumido_visto
			e.consumido_visto = e.memoria.consumido
			-- En modo 'meter' el credito ya se cobro al entrar la moneda:
			-- cobrarlo otra vez al gastarlo seria cobrar dos veces.
			if e.cuenta and (COBRO == 'jugar') then e.cuenta.consume(n) end
		end

	elseif s1 or s2 then
		-- Sin la direccion, se estima: cada START gasta un credito, y el de
		-- dos jugadores gasta dos.
		local n = (s1 and 1 or 0) + (s2 and 2 or 0)
		if e.cuenta and (COBRO == 'jugar') then e.cuenta.consume(n) end
		if e.aviso then e.aviso.consume(n) end
	end

	if e.mensaje_reloj > 0 then
		e.mensaje_reloj = e.mensaje_reloj - 1
		if e.mensaje_reloj == 0 then e.mensaje = nil end
	end

	if e.aviso then
		-- "seguir jugando" es cualquier cosa que signifique que el jugador
		-- esta a lo suyo: darle a start.
		local accion = e.aviso.frame(e.leer_salir(), s1 or s2)

		if accion == 'bloquear' then
			-- Esto es lo que frena la salida sin tocar ningun mapeo de
			-- controles: reset() deja los eventos de UI en SEQ_PRESSED_RESET y
			-- check_ui_inputs(), que corre despues que nosotros dentro del
			-- render (src/frontend/mame/ui/ui.cpp:970), ya no los vuelve a
			-- poner a true mientras la tecla siga pulsada
			-- (src/emu/uiinput.cpp:95).
			manager.machine.uiinput:reset()

		elseif accion == 'salir' then
			manager.machine:exit()
		end
	end
end

-- --- la cuenta del monedero y los botones que la mueven ---
if VIGILAR and MON then
	-- input_seq('standard') + input:seq_pressed() leen el boton FISICO, aparte
	-- de nuestros set_value. Hace falta asi porque set_value es un OR con la
	-- secuencia fisica (src/emu/ioport.cpp: m_digital_value || seq_pressed),
	-- o sea que no se pueden distinguir mirando el campo.
	-- Copia explicita: el cerrojo cambia la secuencia del campo, y si esto
	-- fuera una referencia a la de dentro se quedaria vacia justo cuando
	-- hace falta para detectar la pulsacion rechazada.
	local ok, seq = pcall(function() return emu.input_seq(CAMPO:input_seq('standard')) end)

	if ok and seq then
		local entrada = manager.machine.input

		-- El contador de monedas del jugador hace falta siempre, tambien en
		-- modo manual: es lo que sabe el aviso de salida.
		GA_ESTADO.pulso_moneda = MON.pulsador(function() return entrada:seq_pressed(seq) end, REBOTE)

		-- El cerrojo: el jugador solo puede meter tantas monedas como creditos
		-- tenia en el monedero. Se monta con la secuencia POR DEFECTO del
		-- campo, no con la efectiva, porque es la que set_default_input_seq
		-- cambia sin dejar rastro en el .cfg del juego.
		-- El cerrojo se monta SIEMPRE, tambien sin monedero: aunque no haya
		-- limite que aplicar, hace falta para tener el boton cerrado mientras
		-- la placa arranca. Sin eso, pulsar la moneda durante la carga
		-- acumula creditos que nadie ha pagado (Q*bert llegaba a 52).
		if CERROJO and CER then
			local okd, orig = pcall(function()
				return emu.input_seq(CAMPO:default_input_seq('standard'))
			end)

			if okd and orig then
				local vacia = emu.input_seq()

				local avisado = false

				GA_ESTADO.cerrojo = CER.nuevo{
					ilimitado = not HAY_MONEDERO,
					limite   = SALDO,
					bloquear = function()
						CAMPO:set_default_input_seq('standard', vacia)

						-- Se comprueba que de verdad surtio efecto: si el juego
						-- (o el .cfg del usuario) tiene una secuencia propia en
						-- live().seq, seq() la devuelve y defseq no manda
						-- (ioport.cpp: seq()). Mejor enterarse que creerselo.
						local okc, ef = pcall(function()
							return CAMPO:input_seq('standard').length
						end)

						if okc and (ef ~= 0) and not avisado then
							avisado = true
							log('AVISO: el cerrojo no ha surtido efecto '
								.. '(la secuencia sigue con %d codigos). '
								.. 'El boton de moneda no queda bloqueado.', ef)
						end
					end,
					soltar = function()
						CAMPO:set_default_input_seq('standard', orig)
					end,
					log = log,
				}

				-- Se apunta como devolver el boton a como estaba. La copia
				-- local es importante: cuando esto se ejecute, la global
				-- GA_ESTADO ya sera la de la ejecucion siguiente.
				local suelta = function() CAMPO:set_default_input_seq('standard', orig) end
				local d = GA_ESTADO.deshaceres
				d[#d + 1] = suelta

				log('cerrojo puesto: el jugador puede meter %s',
					GA_ESTADO.cerrojo.cuantas())
			else
				log('no puedo leer la secuencia por defecto de la moneda (%s): sin cerrojo',
					tostring(orig))
			end
		end

		if not HAY_MONEDERO then
			-- Modo manual: no hay nada que cobrar ni que devolver. Las monedas
			-- se siguen contando, pero solo para el aviso de salida.
			log('sin monedero: cuento las monedas para el aviso, pero no cobro nada')
		else
			GA_ESTADO.cuenta = MON.cuenta{
				base = SALDO + INSERTA,   -- lo suyo, contando lo que va dentro
				guardar = function(n) MON.escribir(BUZON, n, 0) end,
				log = log,
			}

			-- Importante: se guarda ya. Si el jugador sale sin jugar, el credito
			-- del lanzamiento vuelve al monedero en vez de quedar cobrado.
			GA_ESTADO.cuenta.guardar_ahora()

			log('monedero al dia: %d creditos (%d en el bolsillo y %d dentro del juego)',
				SALDO + INSERTA, SALDO, INSERTA)
		end
	else
		log('no puedo leer la secuencia del boton (%s), no llevo la cuenta', tostring(seq))
	end
end

-- --- botones de start: son los que gastan creditos de verdad ---
do
	local io_ = manager.machine.ioport

	local function lector(token)
		local ok, tipo = pcall(function() return io_:token_to_input_type(token) end)
		if not ok or not tipo then
			log('token %s desconocido, ese boton no se vigila', token)
			return function() return false end
		end
		return function() return io_:type_pressed(tipo) end
	end

	GA_ESTADO.leer_salir  = lector('UI_CANCEL')
	GA_ESTADO.leer_start1 = lector('START1')
	GA_ESTADO.leer_start2 = lector('START2')

	if MON then
		GA_ESTADO.pulso_start1 = MON.pulsador(function() return GA_ESTADO.leer_start1() end)
		GA_ESTADO.pulso_start2 = MON.pulsador(function() return GA_ESTADO.leer_start2() end)
	end
end

-- --- leer los creditos de la RAM del juego, si sabemos donde estan ---
if MEM then
	local juego = emu.romname and emu.romname() or ''
	local tabla = os.getenv('GA_TABLA')
	if not tabla or (tabla == '') then tabla = MI_DIR .. 'creditos.dat' end

	local entrada = MEM.entrada(tabla, juego)

	if not entrada then
		log('%s no esta en creditos.dat: estimare por las pulsaciones de START', juego)
	else
		local dev = manager.machine.devices[entrada.cpu]
		local esp = dev and dev.spaces[entrada.espacio]

		if not esp then
			log('creditos.dat apunta a %s/%s y no existe en esta maquina',
				entrada.cpu, entrada.espacio)
		else
			-- Una direccion importada no se ha comprobado nunca, y no vale con
			-- mirar si arranca a 0: hay placas con NVRAM que guardan los
			-- creditos de la sesion anterior (Tapper lo hace). Se comprueba
			-- por comportamiento: se insertan las monedas de siempre y se mira
			-- si ese byte sube. Si sube, la direccion es buena y se pasa a
			-- leerla; si no, se descarta.
			if not entrada.comprobada then
				log('direccion importada (sin comprobar): la pruebo con las monedas')
			end

		end

		if esp and entrada then
			GA_ESTADO.leer_ram = function() return esp:read_u8(entrada.dir) end

			-- Se escribe en TODAS las copias: hay juegos que guardan varias y
			-- pintan el marcador desde una que no es la primera.
			GA_ESTADO.escribir_ram = function(v)
				for _, d in ipairs(entrada.dirs or { entrada.dir }) do
					esp:write_u8(d, v)
				end
			end

			-- La limpieza cierra el agujero del jugador pillo: aunque el
			-- cerrojo se monte en el frame 0, cualquier credito que la
			-- maquina traiga puesto sin haberse pagado (una moneda colada
			-- antes de que corramos, o la NVRAM de la sesion anterior) se
			-- quita en cuanto la RAM se puede leer con confianza. Una
			-- recreativa arranca sin creditos.
			--
			-- Solo en direcciones comprobadas: en las importadas de la
			-- coleccion de cheats NUNCA se escribe.
			local limpiar = nil

			if LIMPIAR and entrada.comprobada then
				limpiar = function(v)
					-- Lo que el jugador haya metido mientras la placa se
					-- asentaba es SUYO, ya se lo hemos cobrado: solo se quita
					-- lo que sobra por encima de eso.
					local suyos = GA_ESTADO.metidos

					if v > suyos then
						log('la maquina trae %d credito(s) y solo %d estan pagados: '
							.. 'quito el resto', v, suyos)
						pcall(GA_ESTADO.escribir_ram, suyos)
					end
				end
			end

			-- Con arranque tapado, quien decide cuando la RAM es de fiar es
			-- el fin del arranque (llama a asentar_ya). El contador de frames
			-- se deja como red por detras del tope, nunca por delante: si se
			-- asentara antes, el barrido escribiria un 0 en plena
			-- inicializacion y la deteccion de "listo" se creeria ese cero.
			GA_ESTADO.memoria = MEM.contador{
				leer = GA_ESTADO.leer_ram,
				asentar = (ARRANQUE > 0) and (ARRANQUE_MAX + ESTABLE + 120) or ASENTAR,
				al_asentar = limpiar,
				log = log,
			}
			if entrada.comprobada then
				log('creditos leidos de la memoria del juego: %s %s %04x',
					entrada.cpu, entrada.espacio, entrada.dir)
			else
				-- Todavia no nos fiamos: hasta que las monedas demuestren que
				-- ese byte es el contador, no se usa para nada.
				local ok, v = pcall(GA_ESTADO.leer_ram)
				GA_ESTADO.a_prueba = { antes = ok and v or nil, dir = entrada.dir }
			end

			-- Sabiendo escribir ahi, no hace falta simular monedas: se pone el
			-- monedero entero en el contador del juego y los dos numeros pasan
			-- a ser el mismo. De paso desaparecen tres fuentes de error: los
			-- pulsos que se pierden, la espera de arranque y la tarifa del DIP.
			if SINCRONIZAR and not GRATIS and entrada.comprobada and HAY_MONEDERO then
				local quiero = SALDO + INSERTA
				if quiero > TOPE then
					log('el monedero tiene %d pero solo escribo %d: mas podria '
						.. 'confundir al juego', quiero, TOPE)
					quiero = TOPE
				end

				GA_ESTADO.sincro = MEM.sincronizador{
					leer = GA_ESTADO.leer_ram,
					escribir = GA_ESTADO.escribir_ram,
					valor = quiero,
					log = log,
				}

				-- Nada de monedas: el contador se pone a mano
				GA_ESTADO.restantes = 0
				GA_ESTADO.fase = 'fin'
				log('sincronizando %d creditos por escritura, sin insertar monedas', quiero)
			end
		end
	end
end

-- --- arranque tapado ---
--
-- Idea de Eloy. Durante su test de RAM/ROM la placa IGNORA las monedas: es lo
-- que hacia que con -autoboot_delay 3 se perdieran en silencio. Ahora que el
-- script arranca en el frame 0 (para que el cerrojo exista desde el principio),
-- ese tramo queda dentro de nuestro turno, y dejar pulsar ahi seria cobrarle al
-- jugador un credito que el juego tira a la basura.
--
-- Asi que durante el arranque: boton cerrado, pantalla en negro, y el emulador
-- a toda velocidad para que dure un suspiro de tiempo real en vez de 4 segundos.
if ARRANQUE > 0 then
	GA_ESTADO.arranque = true

	if GA_ESTADO.cerrojo then
		GA_ESTADO.cerrojo.listo = false
	end

	if TURBO then
		local ok, v = pcall(function() return manager.machine.video end)
		if ok and v then
			GA_ESTADO.turbo = {
				video = v,
				throttled = v.throttled,
				rate = v.throttle_rate,
			}

			-- El sonido tambien: el test de arranque pita, y a toda velocidad
			-- pitaria en agudo.
			local oks, sn = pcall(function() return manager.machine.sound end)
			if oks and sn then
				GA_ESTADO.turbo.sonido = sn
				GA_ESTADO.turbo.mudo = sn.system_mute
				pcall(function() sn.system_mute = true end)
			end

			if VELOCIDAD == 0 then
				pcall(function() v.throttled = false end)
			else
				pcall(function() v.throttle_rate = VELOCIDAD end)
			end

			-- Copias locales, por lo mismo que en el cerrojo
			local t = GA_ESTADO.turbo
			local d = GA_ESTADO.deshaceres
			d[#d + 1] = function()
				pcall(function() t.video.throttled = t.throttled end)
				pcall(function() t.video.throttle_rate = t.rate end)
				if t.sonido then pcall(function() t.sonido.system_mute = t.mudo end) end
			end
		end
	end

	log('arranque tapado: %s%d frames, tope %d%s',
		FIJO and 'fijo ' or 'minimo ', ARRANQUE, ARRANQUE_MAX,
		GA_ESTADO.turbo
			and ((VELOCIDAD == 0) and ', emulador sin freno'
				or string.format(', emulador al %d00%%', VELOCIDAD))
			or '')
end

-- Deja el emulador como estaba y abre el boton. Se llama una sola vez.
function fin_del_arranque()
	local e = GA_ESTADO
	if not e.arranque then return end
	e.arranque = false

	-- Ahora que la placa esta lista, su RAM ya es de fiar: se cierra el
	-- asentamiento del contador (que dispara la limpieza de creditos no
	-- pagados) en el momento bueno, no a un numero fijo de frames.
	if e.memoria then pcall(e.memoria.asentar_ya) end

	if e.turbo then
		pcall(function() e.turbo.video.throttled = e.turbo.throttled end)
		pcall(function() e.turbo.video.throttle_rate = e.turbo.rate end)
		if e.turbo.sonido then
			pcall(function() e.turbo.sonido.system_mute = e.turbo.mudo end)
		end
		e.turbo = nil
	end

	if e.cerrojo then e.cerrojo.listo = true end
	log('arranque terminado: la maquina acepta monedas')
end

-- --- cuadro de aviso de creditos dentro de la maquina ---
if AVISAR and AV then
	GA_ESTADO.aviso = AV.nuevo{
		-- Con monedas de verdad, lo que se queda dentro de la maquina es
		-- dinero perdido; con monedero y cobro al meter, tambien.
		se_pierden = (not HAY_MONEDERO) or (COBRO == 'meter'),
		entrado = GRATIS and 0 or INSERTA,
		espera = ESPERA_AVISO,
		-- Si sabemos leer los creditos de la RAM, el cuadro dice el numero
		-- exacto en vez de una estimacion.
		dentro = GA_ESTADO.memoria and function() return GA_ESTADO.memoria.dentro() end or nil,
		log = log,
	}
	log('aviso de creditos dentro de la maquina activo')
end

-- --- lo que se pinta encima del juego ---
--
-- Va en frame_done, que es el sitio para superponer cosas (luaengine.cpp:809),
-- y hay que repintarlo en cada frame.
--
-- Y va al contenedor de la INTERFAZ (render.ui_container), no al de la
-- pantalla: el de la pantalla se rota con el juego, asi que en un vertical como
-- Pac-Man el texto salia tumbado. El de la interfaz es donde MAME pinta sus
-- propios menus y siempre se lee derecho. Sus coordenadas son 0..1.
GA_ESTADO.pintor = function()
	local e = GA_ESTADO

	local ok, contenedor = pcall(function() return manager.machine.render.ui_container end)
	if not ok or not contenedor then return end

	-- Arranque: se tapa la pantalla entera. El juego esta haciendo su test de
	-- RAM/ROM y no hay nada que ver; ademas asi el jugador no se pone a pulsar
	-- la moneda contra una placa que la va a ignorar.
	if e.arranque then
		contenedor:draw_box(0.0, 0.0, 1.0, 1.0, COLOR_NEGRO, COLOR_NEGRO)
		return
	end

	-- Mensaje corto al meter una moneda. Es la pieza que de verdad evita el
	-- malentendido: el jugador ve en el momento que ese credito es para este
	-- juego y que su monedero sigue intacto.
	if e.mensaje then
		-- Un poco por encima del borde: abajo del todo esta el contador de
		-- creditos del propio juego, y conviene que se vean los dos.
		contenedor:draw_box(0.02, 0.855, 0.98, 0.935, COLOR_BORDE, COLOR_FONDO)
		contenedor:draw_text('center', 0.875, e.mensaje, COLOR_TEXTO)
	end

	local a = e.aviso
	if not a or not a.visible() then return end

	local lineas = a.lineas(e.cuenta and e.cuenta.saldo() or nil)
	local alto = PASO * (#lineas + 1)
	local y0 = (1.0 - alto) / 2

	contenedor:draw_box(0.06, y0, 0.94, y0 + alto, COLOR_BORDE, COLOR_FONDO)

	for i, texto in ipairs(lineas) do
		if texto ~= '' then
			contenedor:draw_text('center', y0 + (PASO * (i - 0.5)) + (PASO * 0.25),
				texto, (i == 1) and COLOR_TITULO or COLOR_TEXTO)
		end
	end
end

-- register_frame_done ACUMULA callbacks (luaengine.cpp, register_function) y no
-- hay forma de quitarlos, asi que si la placa se reinicia se irian sumando
-- pintores. Se registra uno solo, que siempre llama al del estado vigente.
if not GA_PINTOR_PUESTO then
	emu.register_frame_done(function()
		if GA_ESTADO and GA_ESTADO.pintor then GA_ESTADO.pintor() end
	end)
	GA_PINTOR_PUESTO = true
end

if (GA_ESTADO.fase == 'fin') and not GA_ESTADO.cuenta and not GA_ESTADO.aviso
		and not GA_ESTADO.memoria then
	log('nada que insertar y nada que vigilar')
	return
end

GA_ESTADO.sub = emu.add_machine_frame_notifier(por_frame)

-- Si la placa se reinicia hay que cancelar esta suscripcion: si no, el
-- notificador viejo seguiria vivo y correria por_frame DOS veces por frame
-- sobre el estado nuevo (lee GA_ESTADO, que para entonces ya es otro).
do
	local sub = GA_ESTADO.sub
	local d = GA_ESTADO.deshaceres
	d[#d + 1] = function()
		if sub and sub.unsubscribe then sub:unsubscribe() end
	end
end

if (MONEDAS > 0) and not GA_ESTADO.sincro then
	log('insertando %d monedas para %d creditos (pulso=%d hueco=%d espera=%d)',
		MONEDAS, INSERTA, PULSO, HUECO, ESPERA)
end
