-- Comprobaciones del cerrojo del boton de moneda, sin MAME.
local DIR = (debug.getinfo(1, 'S').source or ''):match('^@(.*[/\\])') or ''
local CER = dofile(DIR .. '../cerrojo.lua')

local ok, fallos = 0, 0

local function comprueba(que, cond)
	if cond then ok = ok + 1; print('  ok    ' .. que)
	else fallos = fallos + 1; print('  FALLO ' .. que) end
end

-- un cerrojo de mentira que apunta lo que le piden
local function nuevo(limite)
	local hechos = { bloqueos = 0, sueltas = 0 }
	local c = CER.nuevo{
		limite = limite,
		bloquear = function() hechos.bloqueos = hechos.bloqueos + 1 end,
		soltar   = function() hechos.sueltas = hechos.sueltas + 1 end,
	}
	return c, hechos
end

print('\n1. con monedero, la moneda pasa')
do
	local c, h = nuevo(3)
	c.frame()
	comprueba('no bloquea de entrada', h.bloqueos == 0)
	comprueba('quedan 3', c.disponible() == 3)
	comprueba('la moneda vale', c.moneda() == true)
	c.frame()
	comprueba('quedan 2', c.disponible() == 2)
	comprueba('sigue sin bloquear', h.bloqueos == 0)
end

print('\n2. al gastar el monedero se echa el cerrojo')
do
	local c, h = nuevo(2)
	c.frame()
	c.moneda(); c.frame()
	comprueba('con una todavia no', h.bloqueos == 0)
	c.moneda(); c.frame()
	comprueba('con la segunda si', h.bloqueos == 1)
	comprueba('y no quedan', c.disponible() == 0)
end

print('\n3. bloqueado, la moneda se rechaza')
do
	local c, h = nuevo(1)
	c.frame(); c.moneda(); c.frame()
	comprueba('bloqueado', h.bloqueos == 1)
	comprueba('la siguiente se rechaza', c.moneda() == false)
	comprueba('no cuenta como metida', c.metidas == 1)
	comprueba('se apunta el rechazo', c.rechazadas == 1)
	c.moneda(); c.moneda()
	comprueba('por muchas que pulse', c.metidas == 1)
	comprueba('tres rechazos', c.rechazadas == 3)
end

print('\n4. sin monedero se bloquea desde el primer frame')
do
	local c, h = nuevo(0)
	comprueba('todavia no se ha decidido', c.echado == nil)
	c.frame()
	comprueba('bloquea ya', h.bloqueos == 1)
	comprueba('la primera moneda ya se rechaza', c.moneda() == false)
end

print('\n5. solo se llama a bloquear cuando cambia la situacion')
do
	local c, h = nuevo(0)
	for i = 1, 100 do c.frame() end
	comprueba('un solo bloqueo en 100 frames', h.bloqueos == 1)
	comprueba('y ninguna suelta', h.sueltas == 0)
end

print('\n6. al salir se suelta el boton pase lo que pase')
do
	local c, h = nuevo(0)
	c.frame()
	c.soltar_todo()
	comprueba('soltado', h.sueltas == 1)
	c.soltar_todo()
	comprueba('y no se suelta dos veces', h.sueltas == 1)
end

print('\n7. limites raros no lo tumban')
do
	local c = CER.nuevo{ limite = -5 }
	c.frame()
	comprueba('un limite negativo es cero', c.disponible() == 0)
	comprueba('y rechaza', c.moneda() == false)

	local d = CER.nuevo{}
	d.frame()
	comprueba('sin opciones tampoco revienta', d.disponible() == 0)

	local e = CER.nuevo{ limite = 2.7 }
	comprueba('el limite se trunca a entero', e.limite == 2)
end

print('\n8. mientras la maquina arranca, el boton esta cerrado')
do
	local c, h = nuevo(5)
	c.listo = false

	c.frame()
	comprueba('bloquea aunque haya monedero', h.bloqueos == 1)
	comprueba('y dice por que', c.motivo() == 'arrancando')
	comprueba('la moneda se rechaza', c.moneda() == false)
	comprueba('sin gastar monedero', c.metidas == 0)
	comprueba('siguen los 5 disponibles', c.disponible() == 5)

	c.listo = true
	c.frame()
	comprueba('al terminar el arranque se suelta', h.sueltas == 1)
	comprueba('ya no hay motivo', c.motivo() == nil)
	comprueba('y ahora si entra', c.moneda() == true)
end

print('\n9. arrancar sin monedero deja el boton cerrado igual')
do
	local c, h = nuevo(0)
	c.listo = false
	c.frame()
	comprueba('cerrado por arranque', c.motivo() == 'arrancando')

	c.listo = true
	c.frame()
	comprueba('sigue cerrado, ahora por falta de creditos', c.motivo() == 'sin creditos')
	comprueba('no se ha soltado en ningun momento', h.sueltas == 0)
	comprueba('y un solo bloqueo', h.bloqueos == 1)
end

print(string.format('\n=== cerrojo: %d ok, %d fallos ===', ok, fallos))
os.exit(fallos == 0 and 0 or 1)
