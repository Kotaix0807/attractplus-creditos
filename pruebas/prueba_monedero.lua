-- Pruebas de la contabilidad del monedero, sin MAME de por medio.
local M = dofile('/home/eloy/groovyarcade-creditos/monedero.lua')

local RUTA = os.getenv('TMPDIR') and (os.getenv('TMPDIR') .. '/monedero_prueba.txt')
	or '/tmp/monedero_prueba.txt'

local fallos, pasadas = 0, 0

local function ok(titulo, cond, detalle)
	if cond then
		pasadas = pasadas + 1
		print('  ok    ' .. titulo)
	else
		fallos = fallos + 1
		print('  FALLO ' .. titulo .. '  -> ' .. tostring(detalle))
	end
end

local function igual(titulo, obtenido, esperado)
	ok(titulo, obtenido == esperado,
		string.format('esperaba <%s> y llego <%s>', tostring(esperado), tostring(obtenido)))
end

os.remove(RUTA)

print('\n1. escribir y leer la cuenta')
ok('escribe', M.escribir(RUTA, 4, 1))
local saldo, inserta = M.leer(RUTA)
igual('saldo', saldo, 4)
igual('inserta', inserta, 1)

print('\n2. el fichero es legible por un humano')
local f = io.open(RUTA, 'r')
igual('contenido', f:read('*a'), 'saldo 4\ninserta 1\n')
f:close()

print('\n3. formatos raros')
os.remove(RUTA)
igual('fichero que no existe', M.leer(RUTA), nil)

local function escribir_crudo(texto)
	local g = io.open(RUTA, 'w'); g:write(texto); g:close()
end

escribir_crudo('3\n')
saldo, inserta = M.leer(RUTA)
igual('un numero suelto es "inserta"', inserta, 3)
igual('y el saldo queda a cero', saldo, 0)

escribir_crudo('saldo 7\n')
saldo, inserta = M.leer(RUTA)
igual('solo saldo', saldo, 7)
igual('sin inserta', inserta, 0)

escribir_crudo('saldo -5\ninserta -2\n')
saldo, inserta = M.leer(RUTA)
igual('negativos se recortan a cero', saldo, 0)
igual('tambien inserta', inserta, 0)

escribir_crudo('basura ilegible\n')
igual('basura se descarta', M.leer(RUTA), nil)

escribir_crudo('saldo 2\ninser')     -- escritura cortada a media
saldo, inserta = M.leer(RUTA)
igual('fichero cortado: se salva lo legible', saldo, 2)

print('\n4. no deja temporales tirados')
M.escribir(RUTA, 1, 0)
local tmp = io.open(RUTA .. '.tmp', 'r')
ok('sin .tmp despues de escribir', tmp == nil, 'existe ' .. RUTA .. '.tmp')
if tmp then tmp:close() end

print('\n5. el pulsador cuenta flancos, no frames')
do
	local pulsado = false
	local p = M.pulsador(function() return pulsado end)

	igual('sin pulsar no cuenta', p.frame(), false)

	pulsado = true
	igual('la pulsacion se ve una vez', p.frame(), true)
	igual('mantener pulsado no repite', p.frame(), false)
	igual('ni al tercer frame', p.frame(), false)

	pulsado = false; p.frame()
	pulsado = true
	igual('soltar y volver a pulsar cuenta otra vez', p.frame(), true)
	igual('total de pulsaciones', p.veces, 2)
end

print('\n6. el monedero paga por lo que se juega, no por lo que se mete')
do
	local guardados = {}
	local c = M.cuenta{
		base = 5,                                  -- 4 en el monedero + 1 que entro al lanzar
		guardar = function(n) table.insert(guardados, n) end,
	}

	igual('empieza con todo', c.saldo(), 5)

	-- El jugador mete tres monedas dentro de la partida: no cuesta nada,
	-- los creditos solo se mueven del monedero a la maquina
	igual('meter monedas no descuenta', c.saldo(), 5)
	igual('y no se guarda nada', #guardados, 0)

	c.consume(1)
	igual('jugar una partida si descuenta', c.saldo(), 4)
	igual('y se guarda', guardados[#guardados], 4)

	c.consume(2)                                   -- partida de dos jugadores
	igual('la de dos jugadores cuesta dos', c.saldo(), 2)
end

print('\n7. la cuenta nunca queda negativa')
do
	local c = M.cuenta{ base = 1 }
	c.consume(1)
	igual('a cero', c.saldo(), 0)
	c.consume(5)                                   -- creditos gratis, sin saldo
	igual('sigue en cero', c.saldo(), 0)
end

print('\n8. el caso que arruinaba al jugador despistado')
do
	-- Entra a un juego con 1 credito, se pone a pulsar la moneda pensando que
	-- acumula para otros juegos, juega UNA partida y sale.
	local c = M.cuenta{ base = 10 }                -- 9 en el monedero + 1 insertado
	local monedas = M.pulsador(function() return true end)

	monedas.frame()                                -- ocho pulsaciones locas
	for i = 1, 8 do
		monedas.antes = false
		monedas.frame()
	end

	igual('las monedas no le cuestan nada', c.saldo(), 10)
	c.consume(1)                                   -- juega una partida
	igual('solo paga la partida que jugo', c.saldo(), 9)
end

os.remove(RUTA)
print('\n8. se pueden devolver creditos cobrados de mas')
do
	local guardado = nil
	local c = M.cuenta{ base = 5, guardar = function(n) guardado = n end }

	c.consume(2)
	igual('cobra dos', c.saldo(), 3)
	igual('y lo deja escrito', guardado, 3)

	c.devuelve(1)
	igual('devuelve uno', c.saldo(), 4)
	igual('tambien por escrito', guardado, 4)

	c.devuelve(0)
	igual('devolver cero no hace nada', c.saldo(), 4)

	c.devuelve(99)
	igual('no se puede devolver mas de lo cobrado', c.saldo(), 5)

	c.consume(1)
	igual('y despues sigue cobrando bien', c.saldo(), 4)
end

print('\n9. el pulsador tiene antirrebote')
do
	local abajo = false
	local p = M.pulsador(function() return abajo end, 8)

	-- una moneda de verdad
	abajo = true;  igual('el flanco cuenta', p.frame(), true)
	abajo = false; p.frame()

	-- rebote: los contactos vuelven a cerrar enseguida
	abajo = true;  igual('el rebote no', p.frame(), false)
	abajo = false; p.frame()
	abajo = true;  igual('ni el siguiente', p.frame(), false)
	abajo = false; p.frame()

	igual('una sola moneda contada', p.veces, 1)
	igual('y dos rebotes apuntados', p.rebotes, 2)

	-- pasado el hueco, otra moneda de verdad
	for i = 1, 10 do abajo = false; p.frame() end
	abajo = true
	igual('la siguiente moneda si', p.frame(), true)
	igual('van dos', p.veces, 2)
end

print('\n10. sin antirrebote se comporta como antes')
do
	local abajo = false
	local p = M.pulsador(function() return abajo end)

	for i = 1, 3 do
		abajo = true;  p.frame()
		abajo = false; p.frame()
	end
	igual('cuenta todos los flancos', p.veces, 3)
	igual('y no apunta rebotes', p.rebotes, 0)
end

print(string.format('\n=== monedero: %d ok, %d fallos ===', pasadas, fallos))
os.exit(fallos == 0 and 0 or 1)
