local T = dofile('/home/eloy/groovyarcade-creditos/tarifa.lua')
local casos = {
	{'1 Coin/1 Credit',                1, 1, false},
	{'1 Coin/2 Credits',               1, 2, false},
	{'2 Coins/1 Credit',               2, 1, false},
	{'3 Coins/1 Credit',               3, 1, false},
	{'4 Coins/3 Credits',              4, 3, false},
	{'1 Coin/1 Credit, 5 Coins/6 Credits', 1, 1, false},
	{'A 1/1 B 1/1 C 1/1',              1, 1, false},
	{'A 2/1 B 1/3 C 2/1',              2, 1, false},
	{'A 1/1 B 1/6 C 1/1',              1, 1, false},
	{'1/1',                            1, 1, false},
	{'Free Play',                      0, 0, true},
	{'Off',                            nil, nil, nil},
	{'Upright',                        nil, nil, nil},
	{'256 (Cheat)',                    nil, nil, nil},
	{'None',                           nil, nil, nil},
	{'2 Coins to Start, 1 to Continue', nil, nil, nil},
	{'20000',                          nil, nil, nil},
	-- mwalk (Sega System 18): tarifas con premio por acumular monedas
	{'1 Coin/1 Credit, 2/3',           1, 1, false},
	{'2 Coins/1 Credit, 5/3, 6/4',     2, 1, false},
	{'Free Play (if Coin B too) or 1/1', 0, 0, true},
}
local fallos = 0
for _, c in ipairs(casos) do
	local m, cr, g = T.partir(c[1])
	local bien = (m == c[2]) and (cr == c[3]) and ((g or false) == (c[4] or false))
	if not bien then
		fallos = fallos + 1
		print(string.format('FALLO [%s] -> %s/%s gratis=%s (esperaba %s/%s gratis=%s)',
			c[1], tostring(m), tostring(cr), tostring(g),
			tostring(c[2]), tostring(c[3]), tostring(c[4])))
	else
		print(string.format('ok    [%s] -> %s/%s%s', c[1], tostring(m), tostring(cr),
			g and ' gratis' or ''))
	end
end
-- deteccion de premio
local premios = {
	{'1 Coin/1 Credit',        false},
	{'1 Coin/1 Credit, 2/3',   true},
	{'A 1/1 B 1/1 C 1/1',      false},
	{'2 Coins/1 Credit, 4/3',  true},
}
for _, c in ipairs(premios) do
	local r = T.con_premio(c[1])
	if r ~= c[2] then
		fallos = fallos + 1
		print(string.format('FALLO premio [%s] -> %s', c[1], tostring(r)))
	else
		print(string.format('ok    premio [%s] -> %s', c[1], tostring(r)))
	end
end

print(fallos == 0 and '=== analizador de tarifas: todo bien ===' or ('=== ' .. fallos .. ' fallos ==='))
os.exit(fallos == 0 and 0 or 1)
