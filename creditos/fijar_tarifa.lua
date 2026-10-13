-- fijar_tarifa.lua - fija el DIP de tarifa de un juego a "N monedas = 1 credito".
--
-- Es el hermano general de poner_1c1c.lua: aquel deja 1 moneda/1 credito; este
-- pone la tarifa que se le pida.  Lo usa el panel web para cambiar el precio por
-- jugada: como la cabina usa monedas de $100, "N monedas/credito" = $N*100 por
-- jugada ($100 -> 1 moneda, $200 -> 2 monedas...).
--
-- Se ejecuta UNA vez por juego; MAME guarda el DIP en su .cfg al salir.  Lanzalo
-- con fijar_tarifa.sh.  Reutiliza tarifa.lua (los HECHOS del DIP) y no toca
-- poner_1c1c.lua.
--
-- Entrada:  GA_FIJAR_MONEDAS = N  (monedas por 1 credito, entero >= 1)
--
-- Imprime una linea por juego, como poner_1c1c.lua:
--   TARIFA juego=pacman monedas=2 estado=cambiado antes=[1 Coin/1 Credit] ahora=[2 Coins/1 Credit]
--   TARIFA juego=xxx    monedas=3 estado=sin-opcion antes=[1 Coin/1 Credit]
--   TARIFA juego=yyy              estado=sin-dip
--
-- OJO para que el cambio PERSISTA en la cabina: creditos.lua con GA_TARIFA=1c1c
-- (su valor por defecto) vuelve a forzar 1 moneda/1 credito en cada arranque.
-- Para tarifas distintas de $100 la cabina tiene que lanzar creditos.lua con
-- GA_TARIFA=auto (no tocar el DIP, solo leerlo).  Ver docs/panel.md.

local mi_dir = (debug.getinfo(1, 'S').source or ''):match('^@(.*[/\\])') or ''
local T = dofile(mi_dir .. 'tarifa.lua')

local juego = emu.romname and emu.romname() or '?'
local objetivo = tonumber(os.getenv('GA_FIJAR_MONEDAS') or '')

local function decir(estado, antes, ahora)
	local linea = string.format('TARIFA juego=%s', juego)
	if objetivo then linea = linea .. string.format(' monedas=%d', objetivo) end
	linea = linea .. ' estado=' .. estado
	if antes then linea = linea .. string.format(' antes=[%s]', tostring(antes)) end
	if ahora then linea = linea .. string.format(' ahora=[%s]', tostring(ahora)) end
	print(linea)
end

if not objetivo or objetivo < 1 then
	decir('sin-objetivo')
	return
end

local dip = T.buscar_dip()
if not dip then
	decir('sin-dip')
	return
end

local antes = T.ajuste_actual(dip)

-- Busca el ajuste "objetivo monedas / 1 credito".  A igualdad, se prefiere el
-- sin premio y el valor mas bajo, como hace valor_1c1c para 1/1.
local mejor, mejor_texto, mejor_limpia = nil, nil, false
for valor, texto in pairs(dip.campo.settings) do
	local m, c, gratis = T.partir(texto)
	if not gratis and m == objetivo and c == 1 then
		local limpia = not T.con_premio(texto)
		if mejor == nil
				or (limpia and not mejor_limpia)
				or (limpia == mejor_limpia and valor < mejor) then
			mejor, mejor_texto, mejor_limpia = valor, texto, limpia
		end
	end
end

if not mejor then
	decir('sin-opcion', antes)
	return
end

if dip.campo.user_value == mejor then
	decir('ya-estaba', antes)
	return
end

dip.campo.user_value = mejor
decir('cambiado', antes, mejor_texto)
