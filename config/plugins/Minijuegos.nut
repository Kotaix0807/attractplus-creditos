///////////////////////////////////////////////////
//
// Attract-Mode Plus - Minijuegos (huevo de pascua)
//
// En el MENU, al pulsar START del Jugador 2 se lanza el frontend de minijuegos de
// luces (minijuegos/minijuegos, SDL). El frontend roba el foco, se juega en los
// botones del panel mirando los LEDs, y al salir (boton 0) vuelve aqui.
//
// Mapea P2 Start en Configure > Plugins > Minijuegos. Ver docs/minijuegos.md.
//
///////////////////////////////////////////////////

class UserConfig </ help="Minijuegos de luces: P2 Start en el menu lanza el frontend" /> {

	</ label="P2 Start", help="Jugador 2: Start (dispara los minijuegos)", is_input=true, order=1 />
	start="";

	</ label="Ejecutable", help="Binario del frontend de minijuegos", order=2 />
	exe="/home/eloy/Dev/arcade/attractplus/minijuegos/minijuegos";

	</ label="Argumentos", help="Normalmente vacio", order=3 />
	args="";
}

// Fundido a negro al lanzar CUALQUIER cosa, igual que el huevo de Adventure: un
// rectangulo negro a zorder maximo cuyo alpha sube 0->255 en FADE_MJ_MS. No hay
// fade-in: al volver se quita el velo de golpe (da igual, lo pidio asi Eloy).
const FADE_MJ_MS = 800;

class Minijuegos
{
	m_config = null;
	m_pressed = false;
	m_velo = null;        // rectangulo negro del fundido (se crea en StartLayout)
	m_lanzando = false;   // true mientras funde antes de lanzar el minijuego
	m_t0 = 0;

	constructor()
	{
		m_config = fe.get_config();
		fe.add_ticks_callback( this, "on_tick" );
		fe.add_transition_callback( this, "on_transition" );
	}

	function activo( token )
	{
		local s = m_config[ token ];
		return ( s == null || s == "" ) ? false : fe.get_input_state( s );
	}

	// Fundido de los juegos de MAME (pasan por Transition.ToGame): mientras devolvemos
	// tiempo que falta, AM+ sigue dibujando y NO lanza hasta que el velo esta en negro.
	function on_transition( ttype, var, ttime )
	{
		if ( ttype == Transition.StartLayout )
		{
			// El velo se crea AQUI para quedar por ENCIMA de los logos del layout
			// (mismo zorder maximo; gana el creado mas tarde, y StartLayout corre
			// despues del codigo del layout). alpha 0 = invisible mientras no se funde.
			if ( m_velo == null )
			{
				m_velo = fe.add_rectangle( 0, 0, 10000, 10000 );
				m_velo.set_rgb( 0, 0, 0 );
				m_velo.zorder = 2147483647;
			}
			m_velo.alpha = 0;
			m_lanzando = false;
			return 0;
		}
		if ( m_velo == null )
			return 0;
		if ( ttype == Transition.ToGame )
		{
			local a = ( ttime * 255 ) / FADE_MJ_MS;
			if ( a > 255 ) a = 255;
			m_velo.alpha = a;
			if ( ttime < FADE_MJ_MS )
				return FADE_MJ_MS - ttime;   // pide mas tiempo: sigue el fundido antes de lanzar
			return 0;                      // ya en negro: que MAME arranque
		}
		if ( ttype == Transition.FromGame )
		{
			m_velo.alpha = 0;              // sin fade-in: quitar el velo de golpe
			return 0;
		}
		return 0;
	}

	function on_tick( ttime )
	{
		// En pleno fundido para lanzar el minijuego: subir el velo y, ya en negro, lanzar.
		if ( m_lanzando )
		{
			if ( m_t0 < 0 ) m_t0 = ttime;
			local a = ( ( ttime - m_t0 ) * 255 ) / FADE_MJ_MS;
			if ( a > 255 ) a = 255;
			if ( m_velo != null ) m_velo.alpha = a;
			if ( a >= 255 )
			{
				m_lanzando = false;
				local exe = m_config[ "exe" ];
				if ( exe != null && exe != "" )
					fe.plugin_command( exe, m_config[ "args" ] );  // bloquea hasta que sale
				if ( m_velo != null ) m_velo.alpha = 0;            // sin fade-in al volver
			}
			return;
		}

		// No disparar con un menu del frontend abierto.
		if ( fe.overlay.is_up )
		{
			m_pressed = false;
			return;
		}

		// Lanzar al SOLTAR (evita repeticion mientras se mantiene pulsado).
		if ( activo( "start" ) )
		{
			m_pressed = true;
		}
		else if ( m_pressed )
		{
			m_pressed = false;
			local exe = m_config[ "exe" ];
			if ( exe != null && exe != "" )
			{
				m_lanzando = true;   // arranca el fundido; el lanzamiento va al terminar
				m_t0 = -1;
			}
		}
	}
}

if ( !ScreenSaverActive )
	fe.plugin[ "Minijuegos" ] <- Minijuegos();
