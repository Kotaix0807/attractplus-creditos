// Layout SOLO para probar el plugin de creditos sin teclado.
//
// Bajo Xvfb no hay nadie que pulse botones, asi que el layout dispara las
// senales que haria una persona. Reproduce el caso que de verdad importa:
// meter varias monedas, jugar UNA partida, volver, y jugar OTRA con lo que
// queda en el monedero. Si al volver de la primera el contador esta a cero,
// se han perdido creditos.
//
// El fondo es un rectangulo opaco a pantalla completa creado por el LAYOUT,
// que corre despues del plugin: si el marcador se ve encima, el zorder del
// plugin funciona.

local flw = fe.layout.width
local flh = fe.layout.height

local fondo = fe.add_rectangle( 0, 0, flw, flh )
fondo.red = 20
fondo.green = 30
fondo.blue = 70

local titulo = fe.add_text( "PRUEBA DE CREDITOS", 0, flh / 4, flw, 60 )
titulo.set_rgb( 255, 255, 255 )

local juego = fe.add_text( "[Title]", 0, flh / 2, flw, 50 )
juego.set_rgb( 180, 200, 255 )

// Guion inicial: tres monedas, captura y lanzar
local guion = [
	[ 1200, "custom1" ],
	[ 1500, "custom1" ],
	[ 1800, "custom1" ],
	[ 2400, "screenshot" ],
	[ 3000, "select" ],
]

// Guion de cada vuelta del juego, en ms desde que se vuelve
local vuelta1 = [ [ 300, "screenshot" ], [ 1200, "select" ] ]
local vuelta2 = [ [ 300, "screenshot" ], [ 1500, "exit_to_desktop" ] ]

local paso = 0
local partidas = 0
local marca = -1
local vpaso = 0
local soplo = -1
local elegido = false

// La lista sale ordenada y pacman esta por el medio; se busca por nombre y se
// salta ahi con fe.list.index, que es asignable (Layouts.md, fe.CurrentList).
function elegir( nombre )
{
	for ( local i = 0; i < fe.list.size; i++ )
	{
		if ( fe.get_game_info( Info.Name, i - fe.list.index ) == nombre )
		{
			fe.list.index = i
			fe.log( "PRUEBA: elegido " + nombre + " en el indice " + i + "\n" )
			return
		}
	}
	fe.log( "PRUEBA: no encuentro " + nombre + "\n" )
}

function soplar( t )
{
	local c = fe.plugin[ "Creditos" ]
	local m = c.m_texto
	fe.log( "ESTADO t=" + t + " partidas=" + partidas + " creditos=" + c.m_creditos
		+ " texto=" + ( m == null ? "NULO" : "[" + m.msg + "] alpha=" + m.alpha ) + "\n" )
}

fe.add_ticks_callback( "tick" )
fe.add_transition_callback( "trans" )

function tick( t )
{
	if ( !elegido && ( t > 600 ) )
	{
		elegido = true
		elegir( "pacman" )
	}

	while ( ( paso < guion.len() ) && ( t >= guion[ paso ][ 0 ] ) )
	{
		fe.log( "PRUEBA: senal " + guion[ paso ][ 1 ] + " en t=" + t + "\n" )
		fe.signal( guion[ paso ][ 1 ] )
		paso++
	}

	if ( marca == 0 )
	{
		marca = t          // primer tick tras volver: aqui si vale el reloj
		vpaso = 0
	}

	if ( marca > 0 )
	{
		local dt = t - marca

		if ( ( dt / 150 ) != soplo )
		{
			soplo = dt / 150
			soplar( t )
		}

		local g = ( partidas == 1 ) ? vuelta1 : vuelta2
		while ( ( vpaso < g.len() ) && ( dt >= g[ vpaso ][ 0 ] ) )
		{
			fe.log( "PRUEBA: partida " + partidas + " vuelta+" + g[ vpaso ][ 0 ]
				+ " senal " + g[ vpaso ][ 1 ] + "\n" )
			fe.signal( g[ vpaso ][ 1 ] )
			vpaso++
		}
	}
}

function trans( ttype, var, ttime )
{
	if ( ttype == Transition.FromGame )
	{
		partidas++
		marca = 0          // aviso; la marca de tiempo la pone el tick
		soplo = -1
		fe.log( "PRUEBA: he vuelto de la partida " + partidas + "\n" )
	}
	return false
}
