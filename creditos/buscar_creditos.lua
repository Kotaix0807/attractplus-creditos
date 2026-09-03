-- buscar_creditos.lua - encuentra en que direccion guarda el juego sus creditos.
--
-- La idea es la de un buscador de trucos, y la del plugin hiscore de MAME: si
-- no hay forma general de saber cuantos creditos tiene una placa, se localiza
-- una vez por juego donde los guarda y se apunta en una tabla.
--
-- El metodo: una secuencia de monedas y STARTs, comprobando en cada paso que
-- el byte se mueve como tiene que moverse.
--
--   moneda -> sube d,  moneda -> sube d,  moneda -> sube d,  START -> baja
--
-- Tres monedas en vez de dos, porque con dos aparecian falsos positivos que se
-- movian por casualidad y la respuesta cambiaba de una pasada a otra
-- (centiped, mwalk). Y un solo START: el segundo no serviria de nada, porque
-- con la partida ya en marcha el juego lo ignora y no gasta credito. Eso mismo
-- descartaba al candidato bueno cuando lo intente.
--
-- Y al final, una prueba FUNCIONAL de cada candidato, que es la unica que de
-- verdad demuestra cual es el contador: se reinicia la placa, se le escriben
-- creditos al candidato y se pulsa START. Si el juego arranca la partida, ese
-- byte es el bueno; si no pasa nada, era una copia.
--
-- Hizo falta porque sin ella Q*bert quedaba mal apuntado: de sus tres
-- candidatos con el mismo valor se elegia uno que el juego ni mira, y la
-- pantalla seguia marcando CREDITS 0 mientras nosotros creiamos haber
-- sincronizado 4.
--
-- Si ningun candidato pasa la prueba no se apunta nada: es mejor quedarse sin
-- direccion y estimar, que apuntar una direccion equivocada.
--
-- La RAM se saca del mapa de memoria de CADA procesador de la maquina
-- (map.entries con handlertype 'ram'), asi que vale para cualquier
-- arquitectura y tambien para los juegos donde la cuenta la lleva un segundo
-- chip y no la CPU principal.
--
-- Imprime una linea por juego, lista para creditos.dat:
--   CREDITOS juego=pacman cpu=:maincpu espacio=program dir=4e6e
--   CREDITOS juego=xxx estado=sin-candidatos
--
-- Uso: lanzalo con buscar_creditos.sh, que recorre la lista de juegos.

local ESPERA = tonumber(os.getenv('GA_BUSCA_ESPERA') or '45')
local MAX_DELTA = 4        -- creditos por moneda que se consideran plausibles

local juego = emu.romname and emu.romname() or '?'

local function decir(txt) print('CREDITOS juego=' .. juego .. ' ' .. txt) end

-- Todos los procesadores con espacio de programa, no solo :maincpu
local cpus = {}
for tag, dev in pairs(manager.machine.devices) do
	local ok, sp = pcall(function() return dev.spaces and dev.spaces['program'] end)
	if ok and sp then
		cpus[#cpus + 1] = { tag = tag, sp = sp }
	end
end

table.sort(cpus, function(a, b)
	-- la principal primero: si el contador esta en dos sitios, mejor el suyo
	if (a.tag == ':maincpu') ~= (b.tag == ':maincpu') then return a.tag == ':maincpu' end
	return a.tag < b.tag
end)

if #cpus == 0 then decir('estado=sin-cpu'); manager.machine:exit(); return end

-- De donde se lee: los tramos de RAM del mapa de cada CPU, mas los "shares"
-- que declare el driver. Hacen falta los dos: la RAM de trabajo de Pac-Man no
-- es un share, y la de Simpsons no aparece como 'ram' en el mapa porque va
-- detras de un delegate.
local bloques, total = {}, 0

-- Primero el mapa de cada CPU. De paso se apunta que direccion ocupa cada
-- share, que hace falta justo despues.
local base_de_share = {}

for _, c in ipairs(cpus) do
	for _, e in ipairs(c.sp.map.entries) do
		local r, w = tostring(e.read.handlertype), tostring(e.write.handlertype)
		local etiqueta = tostring(e.share)

		if etiqueta ~= 'nil' then
			local clave = c.tag .. '/' .. etiqueta
			if not base_de_share[etiqueta] then
				base_de_share[etiqueta] = { cpu = c.tag, ini = e.address_start }
			end
		end

		if (r == 'ram') or (w == 'ram') then
			local n = e.address_end - e.address_start + 1
			if (n > 0) and (n <= 262144) then
				local sp, ini = c.sp, e.address_start
				bloques[#bloques + 1] = {
					nombre = c.tag .. '@' .. string.format('%06x', ini),
					cpu = c.tag,
					share = etiqueta,
					tam = n,
					leer = function(i) return sp:read_u8(ini + i) end,
					dir = function(i) return ini + i end,
				}
				total = total + n
			end
		end
	end
end

-- Y los shares. Un share solo sirve si sabemos en que direccion lo ve alguna
-- CPU: si no, no habria forma de apuntarlo en creditos.dat.
for tag, share in pairs(manager.machine.memory.shares) do
	local base = base_de_share[tag]
	local n = share.size
	if base and n and (n > 0) and (n <= 262144) then
		bloques[#bloques + 1] = {
			nombre = 'share:' .. tag,
			cpu = base.cpu,
			share = tag,
			tam = n,
			leer = function(i) return share:read_u8(i) end,
			dir = function(i) return base.ini + i end,
		}
		total = total + n
	end
end

local io_ = manager.machine.ioport
local function campo_de(token)
	local ok, tipo = pcall(function() return io_:token_to_input_type(token) end)
	if not ok or not tipo then return nil end
	for _, port in pairs(io_.ports) do
		for _, c in pairs(port.fields) do
			if c.type == tipo then return c end
		end
	end
end

local MONEDA = campo_de('COIN1')
local START  = campo_de('START1')

if not MONEDA then decir('estado=sin-moneda'); manager.machine:exit(); return end
if not START  then decir('estado=sin-start');  manager.machine:exit(); return end

local function instantanea()
	local f = {}
	for _, b in ipairs(bloques) do
		for i = 0, b.tam - 1 do
			f[b.nombre .. '|' .. i] = b.leer(i)
		end
	end
	return f
end

-- De la clave "bloque|offset" a algo que se pueda apuntar en creditos.dat
local function traducir(clave)
	local nombre, i = clave:match('^(.*)|(%d+)$')
	i = tonumber(i)
	for _, b in ipairs(bloques) do
		if b.nombre == nombre then
			return b.dir(i), b.share, b.cpu
		end
	end
	return nil
end

-- La secuencia: que se pulsa y como tiene que reaccionar el contador.
local ESCRIBO = 7          -- numero distintivo para la prueba funcional

local GUION = {
	{ boton = MONEDA, espera = 'primera'  },
	{ boton = MONEDA, espera = 'sube'     },
	{ boton = MONEDA, espera = 'sube'     },
	{ boton = nil,    espera = 'marcar'   },
	{ boton = START,  espera = 'responde' },
}

local paso, reloj, pulsando = 0, 0, 0
local foto, deltas
local foto_inicial          -- la placa arranca sin creditos: ahi el contador vale 0
local terminado = false

local function pulsar(campo)
	if not campo then return end
	campo:set_value(1)
	pulsando = 8
end

local function escribir_en(clave, v)
	local dir, _, cpu = traducir(clave)
	if not dir then return end
	local dev = manager.machine.devices[cpu]
	local esp = dev and dev.spaces['program']
	if esp then pcall(function() esp:write_u8(dir, v) end) end
end

GA_BUSCA = emu.add_machine_frame_notifier(function()
	if terminado then return end

	reloj = reloj + 1

	if pulsando > 0 then
		pulsando = pulsando - 1
		if pulsando == 0 then MONEDA:set_value(0); START:set_value(0) end
		return
	end

	if reloj < ESPERA then return end
	reloj = 0

	if paso == 0 then
		foto = instantanea()
		foto_inicial = foto
		paso = 1
		pulsar(GUION[1].boton)
		return
	end

	local etapa = GUION[paso]
	local ahora = instantanea()

	if etapa.espera == 'primera' then
		-- Cualquier byte que suba entre 1 y MAX_DELTA es candidato, y su
		-- subida queda fijada como "creditos por moneda" de ese candidato.
		deltas = {}
		for k, v in pairs(ahora) do
			local d = v - (foto[k] or v)
			if (d >= 1) and (d <= MAX_DELTA) then deltas[k] = d end
		end

	elseif etapa.espera == 'sube' then
		local quedan = {}
		for k, d in pairs(deltas) do
			if (ahora[k] - foto[k]) == d then quedan[k] = d end
		end
		deltas = quedan

	elseif etapa.espera == 'marcar' then
		-- A todos el mismo numero: el juego solo hara caso al suyo
		for k in pairs(deltas) do escribir_en(k, ESCRIBO) end

	elseif etapa.espera == 'responde' then
		local quedan = {}
		for k, d in pairs(deltas) do
			local v = ahora[k]
			if (v == ESCRIBO - 1) or (v == ESCRIBO - 2) then quedan[k] = d end
		end
		deltas = quedan
	end

	foto = ahora
	paso = paso + 1

	if paso <= #GUION then
		pulsar(GUION[paso].boton)
		return
	end

	-- --- resultado ---
	terminado = true

	local finalistas = {}
	for k, d in pairs(deltas) do
		local dir, share, cpu = traducir(k)
		-- La maquina acaba de arrancar sin creditos, asi que el contador valia
		-- 0 en la primera foto. Lo que empezo en otro numero es otra cosa.
		if dir and (foto_inicial[k] == 0) then
			finalistas[#finalistas + 1] =
				{ dir = dir, delta = d, valor = foto[k], share = share, cpu = cpu }
		end
	end

	-- El mismo byte puede aparecer dos veces (en el mapa y en un share): eso no
	-- es ambiguedad, es la misma direccion contada dos veces.
	local distintas = {}
	for _, c in ipairs(finalistas) do distintas[c.cpu .. ':' .. c.dir] = c end

	local orden = {}
	for _, c in pairs(distintas) do orden[#orden + 1] = c end
	table.sort(orden, function(x, y)
		local vx = (x.share:find('video') or x.share:find('color')) and 1 or 0
		local vy = (y.share:find('video') or y.share:find('color')) and 1 or 0
		if vx ~= vy then return vx < vy end
		return x.dir < y.dir
	end)

	if #orden == 0 then
		decir('estado=ninguno-responde')
		manager.machine:exit()
		return
	end

	-- Si responden varios, son copias que el juego mantiene a la vez: hay que
	-- escribir en todas, porque puede pintar el marcador desde cualquiera. Se
	-- apuntan juntas con '+'. Mas de cuatro huele a que algo se colo.
	local mismo_cpu = true
	for _, c in ipairs(orden) do
		if c.cpu ~= orden[1].cpu then mismo_cpu = false end
	end

	if (#orden > 4) or not mismo_cpu then
		local lista = {}
		for _, c in ipairs(orden) do
			lista[#lista + 1] = string.format('%s@%x', c.cpu, c.dir)
		end
		decir('estado=demasiados candidatos=' .. table.concat(lista, ','))
		manager.machine:exit()
		return
	end

	local dirs = {}
	for _, c in ipairs(orden) do dirs[#dirs + 1] = string.format('%x', c.dir) end

	decir(string.format('cpu=%s espacio=program dir=%s creditos_por_moneda=%d valor=%d copias=%d',
		orden[1].cpu, table.concat(dirs, '+'), orden[1].delta, orden[1].valor, #orden))

	manager.machine:exit()
end)
