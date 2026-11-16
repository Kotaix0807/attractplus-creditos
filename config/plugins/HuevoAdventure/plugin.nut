///////////////////////////////////////////////////
//
// Attract-Mode Plus - HuevoAdventure (huevo de pascua)
//
// En el MENU, el codigo Konami con el SEGUNDO joystick desbloquea el port propio
// de Adventure de Eloy. Reglas (de Eloy):
//   - cada acierto suena correct.wav
//   - un fallo suena incorrect.wav, SOLO si ya llevaba >=1 acierto
//   - 2 s sin avanzar = incorrecto (se reinicia)
//   - al completar el codigo: suena la llave (MW_KeyAppear) y, cuando ESE sonido
//     termina, suena "Secret Exit" y se entra al juego (fundido a negro + lanzar).
//
// El codigo por defecto es el de Eloy: u u d d l r l r, boton2, boton1, start (P2).
// Mapea los 7 controles del Jugador 2 en Configure > Plugins > HuevoAdventure.
// Ver docs/huevo-adventure.md.
//
///////////////////////////////////////////////////

class UserConfig </ help="Huevo de pascua: codigo Konami del Jugador 2 -> port de Adventure" /> {

	</ label="Codigo", help="Secuencia secreta; tokens separados por comas: up,down,left,right,b1,b2,start", order=1 />
	code="up,up,down,down,left,right,left,right,b2,b1,start";

	// --- Controles del JUGADOR 2 (mapea pulsando cada control del 2o panel) -----
	</ label="P2 Arriba", help="Jugador 2: arriba", is_input=true, order=2 />
	up="";
	</ label="P2 Abajo", help="Jugador 2: abajo", is_input=true, order=3 />
	down="";
	</ label="P2 Izquierda", help="Jugador 2: izquierda", is_input=true, order=4 />
	left="";
	</ label="P2 Derecha", help="Jugador 2: derecha", is_input=true, order=5 />
	right="";
	</ label="P2 Boton 1", help="Jugador 2: boton 1", is_input=true, order=6 />
	b1="";
	</ label="P2 Boton 2", help="Jugador 2: boton 2", is_input=true, order=7 />
	b2="";
	</ label="P2 Start", help="Jugador 2: Start", is_input=true, order=8 />
	start="";

	// --- Sonidos (junto al plugin; se resuelven contra fe.script_dir) -----------
	</ label="Sonido acierto", help="Cada tecla correcta del combo", order=9 />
	snd_ok="correct.wav";
	</ label="Sonido error", help="Al fallar, SOLO si ya llevabas >=1 acierto", order=10 />
	snd_err="incorrect.wav";
	</ label="Sonido llave", help="Al completar el codigo (aparece la llave)", order=11 />
	snd_key="MW_KeyAppear.wav";
	</ label="Sonido apertura", help="Tras la llave; al terminar se entra al juego", order=12 />
	snd_unlock="49. Secret Exit!.mp3";

	</ label="Ejecutable del port", help="Binario del port de Adventure a lanzar", order=13 />
	port_exe="/home/arcade/Adventure_linux/adventure";
	</ label="Argumentos del port", help="Normalmente vacio", order=14 />
	port_args="";
}

const RESET_TIME = 2000;    // 2 s sin avanzar = incorrecto (regla de Eloy)
const FADE_MS = 800;        // fundido a negro al desbloquear
const SND_MAX = 6000;       // red de seguridad por si un sonido no reportara su fin

// --- Cerrojo compartido huevo / minijuegos / lanzar-juego -------------------
// Una accion en marcha bloquea a las otras: evita que al accionar una (y mientras
// funde la transicion) se dispare otra o se lance un juego con SELECT. Vive en la
// root table (AM+ comparte la VM entre plugins). Se "echa" cada tick mientras la
// accion sigue; dura 1 s tras el ultimo tick (cubre el fade de 800 ms). Un 'hasta'
// mas lejano que la ventana = ttime reinicio (recarga de layout) -> se da por abierto.
// El mismo bloque, identico, esta en Minijuegos.nut: lo crea el primero que cargue.
if ( !("ga_bloqueo_hasta" in getroottable()) )
{
	::ga_bloqueo_hasta <- 0;
	::ga_echar <- function( t ) { ::ga_bloqueo_hasta = t + 1000; };
	::ga_abierto <- function( t ) { local d = ::ga_bloqueo_hasta - t; return !( d > 0 && d <= 1000 ); };
	::ga_en_juego <- false;   // true mientras se lanza/corre un juego de MAME (ToGame..FromGame)
}

class HuevoAdventure
{
	m_config = null;
	m_commands = null;
	m_valid = [ "up", "down", "right", "left", "b1", "b2", "start" ];

	m_current = 0;          // aciertos acumulados (0..N)
	m_last_time = 0;
	m_pressed = false;

	m_dir = "";
	m_snd_ok = null;
	m_snd_err = null;
	m_snd_key = null;
	m_snd_unlock = null;

	m_fase = "escucha";     // "escucha" | "llave" | "salida" | "entrada"
	m_t0 = 0;               // inicio de la fase actual (fin/timeout de sonido y fundidos)
	m_velo = null;

	constructor()
	{
		m_config = fe.get_config();
		m_dir = fe.script_dir;

		m_commands = [];
		foreach ( c in split( m_config[ "code" ], "," ) )
		{
			local cc = strip( c );
			if ( m_valid.find( cc ) != null )
				m_commands.append( cc );
		}
		if ( m_commands.len() == 0 )
			return;

		m_snd_ok     = cargar_sonido( m_config[ "snd_ok" ] );
		m_snd_err    = cargar_sonido( m_config[ "snd_err" ] );
		m_snd_key    = cargar_sonido( m_config[ "snd_key" ] );
		m_snd_unlock = cargar_sonido( m_config[ "snd_unlock" ] );

		fe.add_ticks_callback( this, "on_tick" );
		fe.add_transition_callback( this, "on_transition" );
		fe.add_signal_handler( this, "on_signal" );
	}

	// Mientras la ceremonia esta en marcha (codigo completado -> llave -> apertura
	// -> port -> fundido de vuelta), se COME el SELECT para que no se lance un juego
	// ENCIMA del huevo: ese era el bug (en la transicion aun se podia elegir juego y
	// se accionaban las dos cosas a la vez). Fuera de la ceremonia (m_fase=="escucha")
	// no se toca nada, el frontend funciona normal.
	function on_signal( sig )
	{
		if ( m_fase != "escucha" && sig == "select" )
			return true;   // consumido: AM+ no lanza el juego
		return false;
	}

	function cargar_sonido( ruta )
	{
		if ( ruta == null || ruta == "" )
			return null;
		// ruta relativa -> junto al plugin (fe.script_dir); garantiza el separador
		if ( ruta[0] != '/' )
		{
			local d = m_dir;
			if ( d.len() > 0 && d[ d.len() - 1 ] != '/' )
				d = d + "/";
			ruta = d + ruta;
		}
		return fe.add_sound( ruta );
	}

	function suena( s )
	{
		if ( s == null ) return;
		s.playing = false;      // re-dispara desde el principio
		s.rewind = true;
		s.playing = true;
	}

	// true cuando el sonido ya termino (AM+ pone playing=false al acabar) o no existe
	function termino( s )
	{
		return ( s == null ) || ( !s.playing );
	}

	// Un fallo reinicia el combo; el sonido de error SOLO si ya habia aciertos.
	function fallar()
	{
		if ( m_current > 0 )
			suena( m_snd_err );
		m_current = 0;
		m_pressed = false;
	}

	// Solo el control MAPEADO (Jugador 2). El name-pin de attract.cfg
	// (fijar_joysticks.py) mantiene P2 estable en Joy1, asi que el combo es
	// exclusivo del P2; el P1 maneja el frontend y no debe dispararlo.
	function activo( token )
	{
		local s = m_config[ token ];
		return ( s == null || s == "" ) ? false : fe.get_input_state( s );
	}

	function on_tick( ttime )
	{
		if ( m_fase != "escucha" )
		{
			::ga_echar( ttime );      // mantener el cerrojo mientras dura la ceremonia
			avanzar_ceremonia( ttime );
			return;
		}

		// No molestar con un menu del frontend abierto.
		if ( fe.overlay.is_up )
			return;

		// Registrar al SOLTAR el control esperado (como KonamiCode).
		local down = activo( m_commands[ m_current ] );
		if ( down )
		{
			m_pressed = true;
		}
		else if ( m_pressed )
		{
			m_current++;
			m_last_time = ttime;
			m_pressed = false;
			suena( m_snd_ok );                 // cada acierto suena

			if ( m_current >= m_commands.len() )
			{
				// Solo si NO hay otra accion en marcha (minijuego/lanzar un juego).
				if ( ::ga_abierto( ttime ) && !::ga_en_juego )
					empezar_ceremonia( ttime );
				else
				{
					m_current = 0;      // descartar el combo: hay algo mas en transicion
					m_pressed = false;
				}
			}
		}
		else if ( m_current > 0 )
		{
			if ( ttime > m_last_time + RESET_TIME )
			{
				fallar();                      // timeout = incorrecto
			}
			else
			{
				foreach ( v in m_valid )
				{
					// una tecla distinta de la esperada rompe el combo
					if ( v != m_commands[ m_current ]
						&& activo( v ) )
					{
						fallar();
						break;
					}
				}
			}
		}
	}

	// --- Ceremonia: llave -> (fin) -> apertura -> (fin) -> lanzar -------------
	function empezar_ceremonia( ttime )
	{
		m_fase = "llave";
		m_t0 = ttime;
		m_current = 0;
		if ( m_velo != null )
			m_velo.alpha = 0;         // pantalla NORMAL mientras suena la llave
		suena( m_snd_key );        // 1) aparece la llave
	}

	function avanzar_ceremonia( ttime )
	{
		if ( m_fase == "llave" )
		{
			// Pantalla normal; solo suena la llave. Al terminar -> apertura + fade out.
			if ( ttime > m_t0 + 200 && ( termino( m_snd_key ) || ttime > m_t0 + SND_MAX ) )
			{
				suena( m_snd_unlock );        // 2) "Secret Exit"
				m_fase = "salida";
				m_t0 = ttime;
			}
		}
		else if ( m_fase == "salida" )
		{
			// FADE OUT a negro mientras suena 49. Secret Exit.
			local a = ( ( ttime - m_t0 ) * 255 ) / FADE_MS;
			if ( a > 255 ) a = 255;
			if ( m_velo != null )
				m_velo.alpha = a;

			// Ya en negro y 49 terminado -> lanzar el port (bloquea hasta que salga).
			if ( a >= 255 && ( termino( m_snd_unlock ) || ttime > m_t0 + SND_MAX ) )
			{
				lanzar_port();
				m_fase = "entrada";
				m_t0 = -1;             // se fija en el 1er tick tras volver (ttime fresco)
			}
		}
		else if ( m_fase == "entrada" )
		{
			// FADE IN al volver del juego; m_t0 se fija con el 1er ttime fresco.
			if ( m_t0 < 0 )
				m_t0 = ttime;
			local a = 255 - ( ( ttime - m_t0 ) * 255 ) / FADE_MS;
			if ( a < 0 ) a = 0;
			if ( m_velo != null )
				m_velo.alpha = a;
			if ( a <= 0 )
			{
				if ( m_velo != null )
					m_velo.alpha = 0;
				m_fase = "escucha";
			}
		}
	}

	function lanzar_port()
	{
		local exe = m_config[ "port_exe" ];
		if ( exe == null || exe == "" )
			return;
		// plugin_command lanza el binario y BLOQUEA el frontend hasta que el port
		// sale (ESC). El port se encarga por dentro de "nivel 1 ganado" y
		// "superjugador" (es codigo de Eloy). Ver docs/huevo-adventure.md.
		fe.plugin_command( exe, m_config[ "port_args" ] );
	}

	function on_transition( ttype, var, ttime )
	{
		if ( ttype == Transition.StartLayout )
		{
			// Al arrancar el frontend, matar cualquier port de Adventure colgado de una
			// sesion anterior: si AM+ murio mientras lo ejecutaba (bloqueado en
			// plugin_command), el binario queda huerfano y reaparece al relanzar AM+.
			// Aqui no puede haber uno legitimo (uno legitimo tiene AM+ bloqueado).
			local exe = m_config[ "port_exe" ];
			if ( exe != null && exe != "" )
				fe.plugin_command_bg( "/usr/bin/pkill", "-f " + exe );
			// El velo se crea AQUI (no en el constructor) para quedar POR ENCIMA de
			// los logos del layout (umag.png/dic.png), que usan el MISMO zorder
			// maximo (2147483647): con zorder igual gana el creado mas tarde, y
			// StartLayout corre DESPUES del codigo del layout que crea los logos.
			// Rectangulo (un texto vacio no pinta fondo); tamano grande fijo cubre
			// cualquier resolucion; alpha 0 = invisible, el fundido lo sube/baja.
			if ( m_velo == null )
			{
				m_velo = fe.add_rectangle( 0, 0, 10000, 10000 );
				m_velo.set_rgb( 0, 0, 0 );
				m_velo.zorder = 2147483647;
			}
			m_velo.alpha = 0;
			m_current = 0;
			m_fase = "escucha";
		}
		if ( ttype == Transition.FromGame )
		{
			// Un combo a medias NO sobrevive a una partida. Si el boton esperado quedo
			// pulsado al entrar al juego, al volver la rama de avance (else if m_pressed)
			// corre ANTES que la del RESET_TIME: completaba el combo con el reloj
			// saltado y lanzaba el port. Jugar en medio mata el combo entero.
			m_current = 0;
			m_pressed = false;
		}
	}
}

if ( !ScreenSaverActive )
	fe.plugin[ "HuevoAdventure" ] <- HuevoAdventure();
