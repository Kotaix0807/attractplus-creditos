-- Pruebas del cuadro de advertencia, sin MAME de por medio.
local A = dofile('../aviso.lua')

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

print('\n1b. un START que el juego IGNORA no puede gastar un credito')
do
	-- Con la partida ya en marcha la placa ignora el START (medido), pero
	-- creditos.lua no puede saberlo y resta igual. Sin tope, esa deuda se
	-- comia las monedas siguientes y el aviso se callaba.
	local a = A.nuevo{ entrado = 0 }
	a.entra(1)
	a.consume(1)                           -- la partida empieza: se gasta
	for _ = 1, 5 do a.consume(1) end       -- y aporrea START durante la partida
	igual('no se gasta de mas', a.consumido, 1)

	a.entra(2)                             -- mete dos monedas mas
	igual('las monedas nuevas siguen dentro', a.dentro(), 2)
	igual('y el aviso salta', pulsar(a, 'salir'), 'bloquear')
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
	-- Hay que dejar pasar la guarda del antirrebote: un flanco a los tres
	-- frames no es una segunda pulsacion, es el rebote de la primera (7c).
	for _ = 1, 20 do a.frame(false, false) end
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
	-- Solo se puede quitar cuando el numero es de la RAM: ahi sabemos que ya
	-- no queda nada. Estimando no se sabe, ver el escenario 7b.
	local real = 1
	local a = A.nuevo{ entrado = 0, dentro = function() return real end }
	a.entra(1)
	a.frame(true, false); a.frame(false, false)
	igual('cuadro arriba', a.visible(), true)
	real = 0                               -- el juego se lleva el credito
	a.frame(false, false)
	igual('ya no queda nada que perder', a.dentro(), 0)
	igual('cuadro fuera', a.visible(), false)
end

print('\n7b. sin direccion conocida, el aviso NO se le puede escapar')
do
	-- Decision de Eloy (2026-09-12): estimando, el error barato es molestar.
	-- La estimacion no distingue un START que empieza partida de otro que el
	-- juego tira, asi que se avisa siempre que el jugador haya metido monedas.
	local a = A.nuevo{ entrado = 0 }
	a.entra(1)
	a.consume(1)                           -- start: el juego se lo lleva...
	a.consume(5)                           -- ...y cinco pulsaciones que ignora
	igual('la estimacion dice cero', a.dentro(), 0)
	igual('pero no es segura', a.seguro(), false)
	igual('y aun asi avisa', pulsar(a, 'salir'), 'bloquear')
	igual('sin afirmar un numero', a.lineas(nil)[2],
		'PUEDEN QUEDAR CREDITOS DENTRO DE ESTA MAQUINA')

	-- El que solo entro a mirar sigue sin ser molestado
	local b = A.nuevo{ entrado = 1 }
	igual('sin meter monedas no molesta', pulsar(b, 'salir'), nil)

	-- Y con la direccion conocida se sigue afirmando, que es lo que vale
	local c = A.nuevo{ entrado = 0, dentro = function() return 0 end }
	c.entra(1)
	igual('con lectura exacta y cero, no molesta', pulsar(c, 'salir'), nil)
end

print('\n7c. el rebote de la tecla de salir NO confirma la salida')
do
	-- Un microinterruptor da varios flancos en unos milisegundos. Sin guarda,
	-- la misma pulsacion pintaba el cuadro y lo confirmaba tres frames
	-- despues: el jugador no llegaba a ver nada. Medido en la cabina.
	local a = A.nuevo{ entrado = 0, guarda = 15 }
	a.entra(2)
	igual('la primera pulsacion frena', a.frame(true, false), 'bloquear')
	a.frame(false, false)                  -- el contacto se abre
	igual('el rebote NO saca al jugador', a.frame(true, false), 'bloquear')
	igual('y el cuadro sigue puesto', a.visible(), true)

	-- pasada la guarda, la segunda pulsacion de verdad si sale
	a.frame(false, false)
	for _ = 1, 20 do a.frame(false, false) end
	igual('luego si se puede confirmar', a.frame(true, false), 'salir')
end

print('\n8. el texto dice la verdad')
do
	local a = A.nuevo{ entrado = 0 }
	a.entra(1)
	a.frame(true, false)
	local l = a.lineas(7)
	igual('singular bien escrito', l[2], 'PUEDE QUEDAR 1 CREDITO DENTRO DE ESTA MAQUINA')
	ok('tranquiliza sobre el monedero', l[3]:find('NO SE TOCA: 7') ~= nil, l[3])

	local b = A.nuevo{ entrado = 0 }
	b.entra(4)
	b.frame(true, false)
	igual('plural bien escrito', b.lineas(2)[2], 'PUEDEN QUEDAR 4 CREDITOS DENTRO DE ESTA MAQUINA')
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
	ok('y dice cuantos pueden quedar dentro',
		m[2] == 'PUEDEN QUEDAR 2 CREDITOS DENTRO DE ESTA MAQUINA')

	-- Con el contador leido de la RAM el cuadro SI afirma, que es la ventaja
	-- de tener la direccion: el numero es el del juego.
	local d = A.nuevo{ se_pierden = true, dentro = function() return 2 end }
	d.entra(2)
	ok('con la RAM se afirma', d.lineas(7)[2] == 'DEJAS 2 CREDITOS DENTRO DE ESTA MAQUINA')

	-- modo manual: no hay monedero que ensenar
	local c = A.nuevo{ se_pierden = true }
	c.entra(1)
	ok('sin monedero, el aviso pelado',
		c.lineas(nil)[3] == 'SI SALES AHORA LOS PIERDES')
	ok('y en singular', c.lineas(nil)[2] == 'PUEDE QUEDAR 1 CREDITO DENTRO DE ESTA MAQUINA')

	ok('el mismo numero de lineas en los dos casos', #l == #m)
end

print(string.format('\n=== aviso: %d ok, %d fallos ===', pasadas, fallos))
os.exit(fallos == 0 and 0 or 1)
