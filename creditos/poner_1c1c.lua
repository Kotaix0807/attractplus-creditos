-- poner_1c1c.lua - deja el DIP de tarifa de un juego en 1 moneda = 1 credito.
--
-- Pasada de configuracion, se ejecuta UNA vez por juego. MAME guarda el DIP en
-- su .cfg al salir, asi que a partir de entonces el numero de creditos que
-- ensena el frontend es exactamente el que ve el juego, sin compensaciones.
--
-- No se usa desde el frontend: para eso esta creditos.lua. Lanzalo con
-- poner_1c1c.sh, que recorre la lista de juegos.
--
-- Imprime una linea por juego, facil de mirar en bloque:
--   1C1C juego=pacman estado=cambiado antes=[1 Coin/2 Credits]
--   1C1C juego=dkong  estado=ya-estaba antes=[1 Coin/1 Credit]
--   1C1C juego=xxx    estado=sin-dip
--   1C1C juego=yyy    estado=sin-opcion antes=[2 Coins/1 Credit]
--   1C1C juego=zzz    estado=respeto-gratis antes=[Free Play]
--
-- Las partidas gratis se respetan: si alguien puso un juego en Free Play a
-- proposito, no se le toca.

local mi_dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*[/\\])') or ''
local T = dofile(mi_dir .. 'tarifa.lua')

local juego = emu.romname and emu.romname() or '?'

local function decir(estado, antes, ahora)
	local linea = string.format('1C1C juego=%s estado=%s', juego, estado)
	if antes then linea = linea .. string.format(' antes=[%s]', tostring(antes)) end
	if ahora then linea = linea .. string.format(' ahora=[%s]', tostring(ahora)) end
	print(linea)
end

local dip = T.buscar_dip()
if not dip then
	decir('sin-dip')
	return
end

local antes = T.ajuste_actual(dip)
local _, _, gratis = T.partir(antes)

if gratis then
	decir('respeto-gratis', antes)
	return
end

local valor, texto = T.valor_1c1c(dip)
if not valor then
	decir('sin-opcion', antes)
	return
end

if dip.campo.user_value == valor then
	decir('ya-estaba', antes)
	return
end

dip.campo.user_value = valor
decir('cambiado', antes, texto)
