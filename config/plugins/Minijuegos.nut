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

class Minijuegos
{
	m_config = null;
	m_pressed = false;

	constructor()
	{
		m_config = fe.get_config();
		fe.add_ticks_callback( this, "on_tick" );
	}

	function activo( token )
	{
		local s = m_config[ token ];
		return ( s == null || s == "" ) ? false : fe.get_input_state( s );
	}

	function on_tick( ttime )
	{
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
				fe.plugin_command( exe, m_config[ "args" ] );  // bloquea hasta que el frontend sale
		}
	}
}

if ( !ScreenSaverActive )
	fe.plugin[ "Minijuegos" ] <- Minijuegos();
