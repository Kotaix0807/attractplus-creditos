-- Pruebas del lector de creditos en memoria, sin MAME de por medio.
local M = dofile('/home/eloy/groovyarcade-creditos/memoria.lua')

local fallos, pasadas = 0, 0
local function ok(t, c, d)
	if c then pasadas = pasadas + 1; print('  ok    ' .. t)
	else fallos = fallos + 1; print('  FALLO ' .. t .. '  -> ' .. tostring(d)) end
end
local function igual(t, o, e)
	ok(t, o == e, string.format('esperaba <%s> y llego <%s>', tostring(e), tostring(o)))
end

local RUTA = '/tmp/creditos_prueba.dat'

print('\n1. leer la tabla')
do
	local f = io.open(RUTA, 'w')
	f:write('# comentario que hay que ignorar\n')
	f:write('pacman @:maincpu,program,4e6e\n')
	f:write('dkong @:maincpu,program,6001\n')
	f:write('\n')
	f:close()

	local e = M.entrada(RUTA, 'pacman')
	ok('encuentra pacman', e ~= nil, 'nil')
	igual('la cpu', e.cpu, ':maincpu')
	igual('el espacio', e.espacio, 'program')
	igual('la direccion en hexadecimal', e.dir, 0x4e6e)

	igual('y el otro juego', M.entrada(RUTA, 'dkong').dir, 0x6001)
	igual('un juego que no esta', M.entrada(RUTA, 'galaga'), nil)

	-- Las lineas que vienen de la coleccion de cheats llevan marca al final
	local g = io.open(RUTA, 'a')
	g:write('galaga @:maincpu,program,9a12   # (cheat)\n')
	g:close()
	igual('lee las importadas, con marca y todo', M.entrada(RUTA, 'galaga').dir, 0x9a12)
	igual('y sabe que no esta comprobada', M.entrada(RUTA, 'galaga').comprobada, false)
	igual('las medidas si lo estan', M.entrada(RUTA, 'pacman').comprobada, true)

	-- Hay juegos que guardan varias copias del contador y pintan desde una que
	-- no es la primera: hay que escribir en todas (Q*bert lleva tres).
	local h = io.open(RUTA, 'a')
	h:write('qbert @:maincpu,program,b60+bbd+1100\n')
	h:close()
	local q = M.entrada(RUTA, 'qbert')
	igual('lee de la primera copia', q.dir, 0xb60)
	igual('pero conoce las tres', #q.dirs, 3)
	igual('la segunda', q.dirs[2], 0xbbd)
	igual('la tercera', q.dirs[3], 0x1100)
	igual('una direccion sola tambien da lista', M.entrada(RUTA, 'pacman').dirs[1], 0x4e6e)
	igual('un fichero que no existe', M.entrada('/no/existe.dat', 'pacman'), nil)
	os.remove(RUTA)
end

print('\n2. el contador reparte subidas y bajadas')
do
	local valor = 0
	local c = M.contador{ leer = function() return valor end }

	c.frame()                       -- primera lectura: solo toma referencia
	igual('empieza a cero', c.dentro(), 0)

	valor = 1; c.frame()
	igual('una moneda entra', c.entrado, 1)
	igual('nada consumido', c.consumido, 0)
	igual('y hay uno dentro', c.dentro(), 1)

	valor = 3; c.frame()            -- dos creditos de golpe (tarifa 1C/2C)
	igual('sube de dos en dos tambien', c.entrado, 3)

	valor = 2; c.frame()
	igual('una partida consume uno', c.consumido, 1)

	valor = 0; c.frame()            -- partida de dos jugadores
	igual('la de dos jugadores consume dos', c.consumido, 3)
	igual('la maquina queda vacia', c.dentro(), 0)
end

print('\n3. un reset de la placa no se cobra')
do
	local valor = 9
	local c = M.contador{ leer = function() return valor end }
	c.frame()

	valor = 0; c.frame()            -- la placa se reinicia: 9 -> 0 de golpe
	igual('el salto grande se ignora', c.consumido, 0)
	ok('y queda apuntado como raro', c.raros == 1, c.raros)
end

print('\n4. si no se puede leer, no revienta')
do
	local c = M.contador{ leer = function() error('sin memoria') end }
	c.frame(); c.frame()
	igual('no cuenta nada', c.consumido, 0)

	local d = M.contador{ leer = function() return nil end }
	d.frame()
	-- nil, no 0: si no se puede leer no lo sabemos, y quien pregunta prefiere
	-- volver a su estimacion antes que creerse un cero inventado.
	igual('con nil dice que no lo sabe', d.dentro(), nil)
end

print('\n5. el sincronizador escribe el monedero en el juego')
do
	local ram = 0
	local escrituras = 0
	local sinc = M.sincronizador{
		leer = function() return ram end,
		escribir = function(v) ram = v; escrituras = escrituras + 1 end,
		valor = 7, cada = 1,
	}

	igual('primer intento: escribe', sinc.frame(), 'pendiente')
	igual('y la RAM ya lo tiene', ram, 7)
	igual('al comprobarlo, hecho', sinc.frame(), 'hecho')
	igual('no escribe de mas', escrituras, 1)
	igual('y no sigue trabajando', sinc.frame(), 'hecho')
end

print('\n6. si la placa machaca el valor, reintenta y se rinde')
do
	local escrituras = 0
	local sinc = M.sincronizador{
		leer = function() return 0 end,             -- la placa lo borra siempre
		escribir = function() escrituras = escrituras + 1 end,
		valor = 3, intentos = 4, cada = 1,
	}

	local r
	for i = 1, 20 do r = sinc.frame() end
	igual('acaba rindiendose', r, 'rendido')
	igual('tras los intentos pedidos', escrituras, 4)
end

print('\n7. una lectura que revienta no lo tumba')
do
	local sinc = M.sincronizador{
		leer = function() error('sin memoria') end,
		escribir = function() end,
		valor = 1, intentos = 2, cada = 1,
	}
	local r
	for i = 1, 10 do r = sinc.frame() end
	igual('se rinde limpiamente', r, 'rendido')
end

print('\n8. la placa se deja asentar antes de contar')
do
	local v = 176            -- basura de la RAM sin inicializar
	local c = M.contador{ leer = function() return v end, asentar = 3 }

	c.frame()
	igual('durante el asentamiento no se sabe', c.dentro(), nil)
	v = 4; c.frame()
	v = 0; c.frame()
	igual('y no cuenta esos cambios como consumo', c.consumido, 0)
	igual('ni como entradas', c.entrado, 0)

	c.frame()                -- aqui termina de asentarse
	igual('ya asentado, se puede preguntar', c.dentro(), 0)

	v = 2; c.frame()
	igual('y a partir de ahi cuenta bien', c.entrado, 2)
	v = 1; c.frame()
	igual('tambien lo que se lleva el juego', c.consumido, 1)
end

print('\n9. al asentarse se quitan los creditos que nadie ha pagado')
do
	local ram = 3            -- el pillo colo monedas antes de que corramos
	local limpiado = nil

	local c = M.contador{
		leer = function() return ram end,
		asentar = 1,
		al_asentar = function(n)
			limpiado = n
			ram = 0
		end,
	}

	c.frame()
	igual('todavia no', limpiado, nil)
	c.frame()
	igual('avisa de lo que encontro', limpiado, 3)
	igual('y la maquina queda a cero', c.dentro(), 0)

	-- lo importante: esa bajada de 3 a 0 es NUESTRA, no una partida jugada
	igual('la limpieza no se cuenta como consumo', c.consumido, 0)

	ram = 1; c.frame()
	igual('a partir de ahi cuenta normal', c.entrado, 1)
end

print(string.format('\n=== memoria: %d ok, %d fallos ===', pasadas, fallos))
os.exit(fallos == 0 and 0 or 1)
