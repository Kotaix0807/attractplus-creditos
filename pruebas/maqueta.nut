// Maqueta de la API de Attract-Mode Plus, suficiente para ejercitar el plugin
// de creditos fuera del frontend. Cada pieza esta copiada del comportamiento
// real comprobado en src/ y Layouts.md, incluidos los detalles feos:
//   * min()/max() devuelven FLOAT (src/sq_math.cpp:74-80)
//   * los plugins corren ANTES del layout (src/fe_vm.cpp:1763)
//   * fe.get_config() entrega SIEMPRE cadenas

function min( a, b ) { return ( a < b ) ? a.tofloat() : b.tofloat(); }
function max( a, b ) { return ( a > b ) ? a.tofloat() : b.tofloat(); }

ScreenSaverActive <- false;

Transition <- {
	StartLayout = 0, EndLayout = 1, ToNewSelection = 2, FromOldSelection = 3,
	ToGame = 4, FromGame = 5, ToNewList = 6, EndNavigation = 7,
	ShowOverlay = 8, HideOverlay = 9, NewSelOverlay = 10, ChangedTag = 11
};
FromTo <- { NoValue = 0, Frontend = 1, ScreenSaver = 2 };
Align  <- { Left = 0, Centre = 1, Right = 2, Top = 3, Bottom = 4, TopLeft = 5 };
Style  <- { Regular = 0, Bold = 1, Italic = 2 };
Grid   <- { Pixel = 0, Percent = 1, Normalised = 2 };
PathTest <- { IsFileOrDirectory = 0, IsFile = 1, IsDirectory = 2 };

class TextoFalso
{
	msg = ""; x = 0; y = 0; width = 0; height = 0;
	zorder = 0; char_size = -1; align = 1; style = 0; outline = 0.0;
	red = 255; green = 255; blue = 255; alpha = 255;
	visible = true;

	constructor( m, px, py, pw, ph )
	{
		msg = m; x = px; y = py; width = pw; height = ph;
	}
}

MOCK <- {
	config = {},
	inputs = {},
	ticks = [],
	reloj = 0,
	senales = [],
	transiciones = [],
	textos = [],
	logs = [],
	comandos = [],

	function reset( cfg )
	{
		config = cfg;
		inputs = {};
		ticks = []; senales = []; transiciones = []; textos = []; logs = []; comandos = [];
		reloj = 0;
		fe.overlay.is_up = false;
	}

	// Un tick del frontend
	function tick( t )
	{
		foreach ( c in ticks ) c[1].call( c[0], t );
	}

	// Devuelve true si algun manejador se ha comido la senal
	function senal( s )
	{
		foreach ( c in senales )
			if ( c[1].call( c[0], s ) == true ) return true;
		return false;
	}

	function transicion( tipo, v, t )
	{
		foreach ( c in transiciones ) c[1].call( c[0], tipo, v, t );
	}

	// Pulsar y soltar el boton de moneda, que es cuando cuenta el credito.
	//
	// El reloj avanza de verdad entre monedas: el plugin tiene antirrebote y
	// dos pulsaciones en el mismo milisegundo son, por definicion, un rebote.
	// 'ms' es lo que se deja pasar antes de esta moneda; ponlo pequeno para
	// fingir precisamente un rebote.
	function moneda( id, ms = 200 )
	{
		reloj += ms;
		inputs[ id ] <- true;  tick( reloj );
		inputs[ id ] <- false; tick( reloj );
	}

	// Arranque completo del frontend: plugin primero, layout despues
	function arrancar_layout()
	{
		transicion( Transition.StartLayout, FromTo.Frontend, 0 );
	}
}

fs <- {
	function path_expand( p )
	{
		if ( p.len() >= 5 && p.slice( 0, 5 ) == "$HOME" )
			return getenv( "HOME" ) + p.slice( 5 );
		return p;
	}

	function path_test( p, flag ) { return true; }
	function get_file_mtime( p ) { return 0; }
}

fe <- {
	nv = {},
	plugin = {},
	overlay = { is_up = false },
	layout = { width = 640, height = 480 },
	list = { index = 0, size = 10 },
	script_dir = "",
	script_file = "Creditos.nut",

	function get_config() { return clone MOCK.config; }
	function log( s ) { MOCK.logs.append( s ); }

	function add_text( m, x, y, w, h )
	{
		local t = TextoFalso( m, x, y, w, h );
		MOCK.textos.append( t );
		return t;
	}

	function add_ticks_callback( env, fn )      { MOCK.ticks.append( [ env, env[fn] ] ); }
	function add_signal_handler( env, fn )      { MOCK.senales.append( [ env, env[fn] ] ); }
	function add_transition_callback( env, fn ) { MOCK.transiciones.append( [ env, env[fn] ] ); }
	function get_input_state( id )
	{
		if ( id in MOCK.inputs ) return MOCK.inputs[ id ];
		return false;
	}
	function signal( s ) {}

	// AM+ los lanza con fork()+execvp(), SIN pasar por un shell
	// (src/fe_util.cpp:1734). Se apuntan para poder mirarlos en las pruebas.
	function plugin_command( ejecutable, args = "", env = null, callback = null )
	{
		MOCK.comandos.append( { ejecutable = ejecutable, args = args } );
	}
	function plugin_command_bg( ejecutable, args = "" )
	{
		MOCK.comandos.append( { ejecutable = ejecutable, args = args, fondo = true } );
	}
	function load_module( n ) {}
}
