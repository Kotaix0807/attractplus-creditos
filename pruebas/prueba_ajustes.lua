-- Comprobaciones de los ajustes por juego, sin MAME.
local DIR = (debug.getinfo(1, 'S').source or ''):match('^@(.*[/\\])') or ''
local A = dofile(DIR .. '../ajustes.lua')

local ok, fallos = 0, 0
local function comprueba(que, cond, detalle)
	if cond then ok = ok + 1; print('  ok    ' .. que)
	else fallos = fallos + 1; print('  FALLO ' .. que .. '  -> ' .. tostring(detalle)) end
end
local function igual(que, a, b) comprueba(que, a == b, tostring(a) .. ' /= ' .. tostring(b)) end

local TMP = os.tmpname()
local function escribe(texto)
	local f = io.open(TMP, 'w'); f:write(texto); f:close()
end
local function sin_entorno() return nil end

print('\n1. lectura del fichero')
do
	escribe([[
# un comentario
defecto  velocidad=0 arranque=5 max=30

pacman   arranque=7          # comentario al final
simpsons velocidad=2 fijo=1
]])
	local t = A.leer(TMP)
	igual('el defecto', t.defecto.arranque, 5)
	igual('un juego', t.juegos.pacman.arranque, 7)
	igual('otro juego', t.juegos.simpsons.velocidad, 2)
	igual('y sus banderas', t.juegos.simpsons.fijo, 1)
	comprueba('los comentarios no ensucian', t.juegos['#'] == nil)
end

print('\n2. un fichero que no existe no revienta')
do
	local t, err = A.leer('/no/existe/arranque.dat')
	comprueba('devuelve tabla vacia', type(t) == 'table' and next(t.juegos) == nil)
	comprueba('y explica por que', type(err) == 'string')

	local a = A.para(t, 'pacman', sin_entorno)
	igual('se cae a los valores internos', a.frames('arranque', nil, 300), 300)
end

print('\n3. precedencia: entorno > juego > defecto > interno')
do
	escribe('defecto arranque=5\npacman arranque=7\n')
	local t = A.leer(TMP)

	local p = A.para(t, 'pacman', sin_entorno)
	local _, de_donde = p.frames('arranque', 'GA_ARRANQUE', 300)
	igual('el juego manda sobre el defecto', p.frames('arranque', nil, 300), 420)
	igual('y se sabe de donde salio', de_donde, 'juego')

	local q = A.para(t, 'otro', sin_entorno)
	igual('sin linea propia, el defecto', q.frames('arranque', nil, 300), 300)

	local r = A.para(t, 'pacman', function(v) return (v == 'GA_ARRANQUE') and '999' or nil end)
	igual('el entorno manda sobre todo', r.frames('arranque', 'GA_ARRANQUE', 300), 999)
	local _, dd = r.frames('arranque', 'GA_ARRANQUE', 300)
	igual('y tambien se sabe', dd, 'entorno')
end

print('\n4. los segundos del fichero se pasan a frames, el entorno no')
do
	escribe('defecto arranque=2.5\n')
	local t = A.leer(TMP)
	local a = A.para(t, 'loquesea', sin_entorno)
	igual('2,5 s son 150 frames', a.frames('arranque', nil, 0), 150)

	-- La variable de entorno va en frames, como estaba antes de existir el
	-- fichero: si se convirtiera, las pruebas viejas darian numeros absurdos.
	local b = A.para(t, 'loquesea', function() return '90' end)
	igual('el entorno se toma tal cual', b.frames('arranque', 'GA_ARRANQUE', 0), 90)
end

print('\n5. valores que no son tiempos')
do
	escribe('defecto velocidad=0\nsimpsons velocidad=4 turbo=0\n')
	local t = A.leer(TMP)

	igual('velocidad del defecto', A.para(t, 'x', sin_entorno).valor('velocidad', nil, 9), 0)
	igual('velocidad del juego', A.para(t, 'simpsons', sin_entorno).valor('velocidad', nil, 9), 4)
	igual('bandera del juego', A.para(t, 'simpsons', sin_entorno).valor('turbo', nil, 1), 0)
	igual('bandera ausente cae al interno', A.para(t, 'x', sin_entorno).valor('turbo', nil, 1), 1)
end

print('\n6. basura en el fichero no lo tumba')
do
	escribe('esto no tiene igual\notro = = =\nbien arranque=3\n')
	local t = A.leer(TMP)
	comprueba('la linea buena se lee', t.juegos.bien and t.juegos.bien.arranque == 3)
	comprueba('las malas no revientan', t.juegos.esto ~= nil)

	escribe('defecto arranque=hola\n')
	local u = A.leer(TMP)
	local a = A.para(u, 'x', sin_entorno)
	igual('un valor no numerico se ignora', a.frames('arranque', nil, 300), 300)
end

print('\n7. mayusculas y minusculas dan igual en el nombre del juego')
do
	escribe('PacMan arranque=6\n')
	local t = A.leer(TMP)
	igual('se encuentra en minusculas', A.para(t, 'pacman', sin_entorno).frames('arranque', nil, 0), 360)
end

print('\n8. una linea sin separador de verdad se avisa, no se traga')
do
	-- Paso: un editor dejo "pacman?arranque=5" con un caracter raro en vez de
	-- un espacio. Sin aviso, esa linea se apunta como un juego que no existe y
	-- sus ajustes no se aplican NUNCA, en silencio.
	escribe('defecto arranque=5\npacman?arranque=9\n')
	local t = A.leer(TMP)

	comprueba('se avisa de la linea', #t.avisos == 1, #t.avisos)
	comprueba('y no se apunta como juego', t.juegos['pacman?arranque=9'] == nil)

	local a = A.para(t, 'pacman', sin_entorno)
	igual('asi que pacman cae al defecto', a.frames('arranque', nil, 0), 300)
end

print('\n9. la bandera nvram')
do
	escribe('defecto nvram=1\nmwalk nvram=0 arranque=10\n')
	local t = A.leer(TMP)
	igual('el juego la apaga', A.para(t, 'mwalk', sin_entorno).valor('nvram', nil, 1), 0)
	igual('otro juego la mantiene', A.para(t, 'pacman', sin_entorno).valor('nvram', nil, 1), 1)
	igual('y sus segundos van aparte', A.para(t, 'mwalk', sin_entorno).frames('arranque', nil, 0), 600)
end

os.remove(TMP)
print(string.format('\n=== ajustes: %d ok, %d fallos ===', ok, fallos))
os.exit(fallos == 0 and 0 or 1)
