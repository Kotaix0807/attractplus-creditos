-- Pruebas del cuadro de advertencia, sin MAME de por medio.
local A = dofile('/home/eloy/groovyarcade-creditos/aviso.lua')

local fallos, pasadas = 0, 0

local function ok(titulo, cond, detalle)
	if cond then pasadas = pasadas + 1; print('  ok    ' .. titulo)
	else fallos = fallos + 1; print('  FALLO ' .. titulo .. '  -> ' .. tostring(detalle)) end
end

local function igual(titulo, obtenido, esperado)
	ok(titulo, obtenido == esperado,
		string.format('esperaba <%s> y llego <%s>', tostring(esperado), tostring(obtenido)))
end

-- Pulsar y soltar: el flanco es lo que cuenta
local function pulsar(a, cual)
	local salir = (cual == 'salir')
	local seguir = (cual == 'seguir')
	local r = a.frame(salir, seguir)
	a.frame(false, false)
	return r
end

print('\n1. la cuenta de lo que hay dentro')
do
	local a = A.nuevo{ entrado = 1 }
	igual('empieza con lo insertado', a.dentro(), 1)

	a.entra(2)
	igual('el jugador mete dos monedas', a.dentro(), 3)
	igual('y se apunta que fue el', a.metido, 2)

	a.consume(1)
	igual('una partida gasta un credito', a.dentro(), 2)

	a.consume(2)
	igual('la de dos jugadores gasta dos', a.dentro(), 0)

	a.consume(1)
	igual('nunca baja de cero', a.dentro(), 0)
end

print('\n2. entrar a mirar un juego y salir NO molesta')
do
	-- Solo esta dentro el credito del lanzamiento: el jugador no ha metido
	-- nada, asi que no hay leccion que darle.
	local a = A.nuevo{ entrado = 1 }
	igual('hay un credito dentro', a.dentro(), 1)
	igual('pero no lo metio el', a.metido, 0)
	igual('la salida no se frena', a.frame(true, false), nil)
	igual('y no hay cuadro', a.visible(), false)
end

print('\n3. sin creditos dentro, salir no molesta')
do
	local a = A.nuevo{ entrado = 1 }
	a.consume(1)
	igual('todo consumido', a.dentro(), 0)
	igual('la salida no se frena', pulsar(a, 'salir'), nil)
	igual('y no hay cuadro', a.visible(), false)
end

print('\n4. si el jugador metio monedas, la primera salida se frena')
do
	local a = A.nuevo{ entrado = 1 }
	a.entra(2)                             -- dos monedas suyas
	igual('se bloquea', a.frame(true, false), 'bloquear')
	igual('y aparece el cuadro', a.visible(), true)

	-- mientras la tecla sigue pulsada no cuenta como segunda pulsacion
	igual('mantener pulsado no confirma', a.frame(true, false), 'bloquear')
	igual('sigue el cuadro', a.visible(), true)

	a.frame(false, false)                  -- suelta
	igual('segunda pulsacion: sale', a.frame(true, false), 'salir')
	igual('y el cuadro se va', a.visible(), false)
end

print('\n5. START cancela y se sigue jugando')
do
	local a = A.nuevo{ entrado = 1 }
	a.entra(1)
	a.frame(true, false); a.frame(false, false)
	igual('cuadro arriba', a.visible(), true)
	igual('start lo quita', a.frame(false, true), 'bloquear')
	igual('sin cuadro', a.visible(), false)
end

print('\n6. si nadie contesta, NO se sale')
do
	local a = A.nuevo{ entrado = 1, espera = 5 }
	a.entra(1)
	a.frame(true, false); a.frame(false, false)
	igual('cuadro arriba', a.visible(), true)
	for i = 1, 10 do
		local r = a.frame(false, false)
		ok('nunca devuelve salir esperando (' .. i .. ')', r ~= 'salir', tostring(r))
	end
	igual('el cuadro se rinde solo', a.visible(), false)
end

print('\n7. si el credito se gasta con el cuadro puesto, se quita')
do
	local a = A.nuevo{ entrado = 0 }
	a.entra(1)
	a.frame(true, false); a.frame(false, false)
	igual('cuadro arriba', a.visible(), true)
	a.consume(1)                           -- el jugador pulsa start
	a.frame(false, false)
	igual('ya no queda nada que perder', a.dentro(), 0)
	igual('cuadro fuera', a.visible(), false)
end

print('\n8. el texto dice la verdad')
do
	local a = A.nuevo{ entrado = 0 }
	a.entra(1)
	a.frame(true, false)
	local l = a.lineas(7)
	igual('singular bien escrito', l[2], 'DEJAS 1 CREDITO DENTRO DE ESTA MAQUINA')
	ok('tranquiliza sobre el monedero', l[3]:find('NO SE TOCA: 7') ~= nil, l[3])

	local b = A.nuevo{ entrado = 0 }
	b.entra(4)
	b.frame(true, false)
	igual('plural bien escrito', b.lineas(2)[2], 'DEJAS 4 CREDITOS DENTRO DE ESTA MAQUINA')
	ok('no dice que se pierdan', b.lineas(2)[3]:find('PIERDES') == nil, b.lineas(2)[3])

	-- En modo manual no hay monedero: ahi los creditos SI se pierden y el
	-- cuadro no puede prometer lo contrario.
	local c = A.nuevo{ entrado = 0 }
	c.entra(2)
	c.frame(true, false)
	igual('sin monedero avisa de la perdida', c.lineas(nil)[3], 'SI SALES AHORA LOS PIERDES')
end

print('\n9. con la direccion de memoria, el numero es exacto')
do
	-- Cuando el juego esta en creditos.dat se lee el contador de verdad, y la
	-- estimacion (entrado - consumido) se queda de reserva.
	local real = 7
	local a = A.nuevo{ entrado = 1, dentro = function() return real end }
	igual('manda la memoria', a.dentro(), 7)

	real = 3
	igual('y sigue al contador', a.dentro(), 3)

	a.consume(99)                          -- la estimacion diria 0
	igual('la estimacion no la pisa', a.dentro(), 3)

	real = -5
	igual('un valor absurdo se recorta', a.dentro(), 0)

	local b = A.nuevo{ entrado = 2, dentro = function() error('sin memoria') end }
	igual('si la lectura falla, vuelve a estimar', b.dentro(), 2)
end

print('\n10. el texto depende de cuando se cobro el credito')
do
	-- cobro al jugar: el monedero esta intacto, se le puede prometer
	local a = A.nuevo{}
	a.entra(2)
	local l = a.lineas(7)
	ok('sin se_pierden, promete el monedero',
		l[3] == 'SOLO VALEN AQUI. TU MONEDERO NO SE TOCA: 7')

	-- cobro al meter: el credito ya salio del monedero, se pierde de verdad
	local b = A.nuevo{ se_pierden = true }
	b.entra(2)
	local m = b.lineas(7)
	ok('con se_pierden, avisa de la perdida',
		m[3] == 'SI SALES AHORA LOS PIERDES. MONEDERO: 7')
	ok('y dice cuantos deja dentro',
		m[2] == 'DEJAS 2 CREDITOS DENTRO DE ESTA MAQUINA')

	-- modo manual: no hay monedero que ensenar
	local c = A.nuevo{ se_pierden = true }
	c.entra(1)
	ok('sin monedero, el aviso pelado',
		c.lineas(nil)[3] == 'SI SALES AHORA LOS PIERDES')
	ok('y en singular', c.lineas(nil)[2] == 'DEJAS 1 CREDITO DENTRO DE ESTA MAQUINA')

	ok('el mismo numero de lineas en los dos casos', #l == #m)
end

print(string.format('\n=== aviso: %d ok, %d fallos ===', pasadas, fallos))
os.exit(fallos == 0 and 0 or 1)
