-- Carga creditos.lua y, pasados unos frames, imprime como quedo el emulador.
--
-- Sirve para los juegos que reinician la placa durante el arranque (elevator):
-- MAME relanza el autoboot y, sin cuidado, la segunda ejecucion guarda como
-- "original" lo que dejo la primera. El sintoma es que el emulador se queda sin
-- freno y el boton de moneda con la secuencia vacia, o sea muerto.

local MI_DIR = (debug.getinfo(1, 'S').source or ''):match('^@(.*[/\\])') or ''
dofile(MI_DIR .. '../../creditos.lua')

EF = { n = 0, cuando = tonumber(os.getenv('GA_EF_FRAME') or '1500') }
EF.io = manager.machine.ioport

EF.sub = emu.add_machine_frame_notifier(function()
	EF.n = EF.n + 1
	if EF.n ~= EF.cuando then return end

	local v = manager.machine.video
	print(string.format('[final] throttled=%s rate=%s mute=%s',
		tostring(v.throttled), tostring(v.throttle_rate),
		tostring(manager.machine.sound.system_mute)))

	local tipo = EF.io:token_to_input_type('COIN1')
	for _, port in pairs(EF.io.ports) do
		for _, f in pairs(port.fields) do
			if f.type == tipo then
				print('[final] moneda: ' .. f:input_seq('standard').length .. ' codigos')
			end
		end
	end

	manager.machine:exit()
end)
