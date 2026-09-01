///////////////////////////////////////////////////
//
// Attract-Mode Plus - plugin "Creditos"
//
// Emula la ranura de monedas de una recreativa:
//
//   * un boton fisico suma creditos y se ven en pantalla
//   * el contador sobrevive a cambios de layout y a reinicios (fe.nv)
//   * opcionalmente no se puede lanzar ningun juego sin credito
//   * el monedero es un fichero compartido con MAME: al lanzar se deja ahi
//     el saldo y los creditos que entran en la partida, y al volver se lee
//     el saldo que quedo
//
// Ese fichero es la clave para no perder creditos. Mientras se juega,
// creditos.lua descuenta de el cada moneda que el jugador mete de verdad, asi
// que al salir de la partida el saldo es el bueno. Formato (ver monedero.lua):
//
//     saldo 4
//     inserta 1
//
// El monedero lleva CREDITOS, no monedas. Cuantas monedas hacen falta para
// conseguirlos depende del DIP de tarifa de cada juego, y eso solo se sabe
// con el juego ya cargado: lo resuelve creditos.lua. Aqui no se toca, o se
// descontaria la tarifa dos veces.
//
// Sin acentos a proposito, igual que creditos.lua.
//
///////////////////////////////////////////////////

class UserConfig </ help="Contador de creditos estilo recreativa: un boton mete monedas y se insertan en el juego al lanzarlo" /> {

	</ label="Boton de moneda", help="Boton fisico que suma creditos (la ranura de monedas de la cabina)", is_input=true, order=1 />
	boton="";

	</ label="Senal alternativa", help="Suma creditos tambien con esta accion del frontend, mapeable en Controls. 'ninguna' para no usarla", options="ninguna,custom1,custom2,custom3,custom4,custom5,custom6,custom7,custom8,custom9,custom10", order=2 />
	senal="ninguna";

	</ label="Creditos por moneda", help="Cuantos creditos suma cada pulsacion del boton", order=3 />
	por_pulsacion="1";

	</ label="Maximo de creditos", help="Tope del contador, como en las placas reales", order=4 />
	maximo="99";

	</ label="Exigir credito para jugar", help="Si es 'Si', el boton de seleccionar no lanza nada sin creditos", options="Si,No", order=5 />
	exigir="Si";

	</ label="Creditos por partida", help="Cuantos creditos hacen falta para lanzar un juego. Con 'Que se inserta al lanzar' en 'Nada' NO se cobran: solo se exigen, y el jugador los mete dentro con el boton", order=6 />
	coste="1";

	</ label="Que se inserta al lanzar", help="'Nada' es el modo con contador fisico: el jugador entra con la maquina a cero y mete los creditos que quiera con el boton de moneda, viendolos salir de su monedero. 'Solo el coste' inserta un credito al lanzar. 'Todos' mete el monedero entero en el juego y lo que sobre al salir SE PIERDE", options="Nada,Solo el coste,Todos", order=7 />
	gasto="Nada";

	</ label="Antirrebote (ms)", help="Milisegundos que se ignoran tras contar una moneda. Es SOLO contra el rebote de contactos, no para limitar el ritmo: aqui entran monedas de verdad y todas tienen que contar. OJO si tu chauchera manda varios pulsos por moneda (una de 500 puede mandar 5): este valor debe ser MENOR que el hueco entre pulsos, o se comeria monedas. 40 mata el rebote (que dura menos de 20 ms) y deja pasar trenes de pulsos separados 100 ms. 0 lo desactiva", order=8 />
	antirrebote="40";

	</ label="Fichero del monedero", help="Fichero que se comparte con MAME para llevar la cuenta. Debe coincidir con GA_ARCHIVO de creditos.lua", order=10 />
	buzon="$HOME/.attract/creditos.txt";

	</ label="Mostrar marcador", options="Si,No", order=10 />
	mostrar="Si";

	</ label="Posicion del marcador", options="Abajo izquierda,Abajo derecha,Arriba izquierda,Arriba derecha", order=11 />
	posicion="Abajo izquierda";

	</ label="Tamano del texto", help="Altura de las letras en pixeles", order=12 />
	tamano="24";

	</ label="Etiqueta", help="Texto que precede al numero de creditos", order=13 />
	etiqueta="CREDITOS";

	</ label="Texto sin creditos", help="Se muestra parpadeando cuando el contador esta a cero", order=14 />
	vacio="INSERTA MONEDA";

}


// Los ajustes llegan siempre como cadena y el usuario puede teclear
// cualquier cosa: nunca dejar que un ajuste malo tumbe el frontend.
function creditos_entero( valor, defecto )
{
	try {
		local n = valor.tointeger();
		return n;
	} catch ( e ) {
		return defecto;
	}
}

// Ojo: el min()/max() que AM+ anade al root table devuelve FLOAT
// (src/sq_math.cpp), asi que aqui se comparan enteros a mano. Si no, el
// contador acaba mostrando "CREDITOS 3.00000" y el buzon lleva decimales.
function creditos_ajuste( valor, defecto, minimo )
{
	local n = creditos_entero( valor, defecto );
	return ( n < minimo ) ? minimo : n;
}

class Creditos
{
	// --- ajustes ya normalizados ---
	m_boton      = "";
	m_senal      = "";
	m_paso       = 1;
	m_maximo     = 99;
	m_exigir     = true;
	m_coste      = 1;
	m_todos      = false;
	m_nada       = true;    // el jugador mete los creditos el mismo, con el boton
	m_buzon      = "";
	m_tamano     = 24;
	m_etiqueta   = "CREDITOS";
	m_vacio      = "INSERTA MONEDA";
	m_posicion   = "";
	m_mostrar    = true;

	// --- estado ---
	m_creditos   = 0;
	m_pulsado    = false;   // deteccion de flanco del boton de moneda
	m_antirrebote = 150;
	m_ultima     = -1000000;   // cuando se conto la ultima moneda (ms de tick)
	m_rebotes    = 0;
	m_ahora      = 0;      // ultimo ttime visto, para la senal
	m_texto      = null;
	m_parpadeo   = true;
	m_reloj      = 0;
	m_resinc     = false;   // el proximo tick reinicia el ciclo de parpadeo

	static ZORDER = 2147483647;   // maximo entero con signo: siempre encima
	static NV_CLAVE = "Creditos";
	static PARPADEO_MS = 450;
	static MARGEN = 16;

	constructor()
	{
		local c = fe.get_config();

		m_boton    = c[ "boton" ];
		m_senal    = ( c[ "senal" ] == "ninguna" ) ? "" : c[ "senal" ];
		m_paso     = creditos_ajuste( c[ "por_pulsacion" ], 1, 1 );
		m_maximo   = creditos_ajuste( c[ "maximo" ], 99, 1 );
		m_exigir   = ( c[ "exigir" ] == "Si" );
		m_coste    = creditos_ajuste( c[ "coste" ], 1, 1 );
		m_antirrebote = creditos_ajuste( c[ "antirrebote" ], 150, 0 );
		m_todos    = ( c[ "gasto" ] == "Todos" );
		m_nada     = ( c[ "gasto" ] == "Nada" );
		m_buzon    = fs.path_expand( c[ "buzon" ] );
		m_tamano   = creditos_ajuste( c[ "tamano" ], 24, 4 );
		m_etiqueta = c[ "etiqueta" ];
		m_vacio    = c[ "vacio" ];
		m_posicion = c[ "posicion" ];
		m_mostrar  = ( c[ "mostrar" ] == "Si" );

		// El contador vive en fe.nv, que AM+ carga al arrancar y guarda al
		// salir, al cambiar de layout y tras cada pulsacion. Los plugins se
		// releen con cada layout, asi que aqui es donde se recupera.
		if ( fe.nv.rawin( NV_CLAVE ) )
			m_creditos = fe.nv[ NV_CLAVE ];

		// El tick hace dos cosas: leer el boton de moneda y parpadear el aviso.
		// Se registra siempre, aunque no haya boton, o sin boton no parpadearia.
		fe.add_ticks_callback( this, "en_tick" );
		fe.add_signal_handler( this, "en_senal" );
		fe.add_transition_callback( this, "en_transicion" );

		// Al arrancar se deja el saldo por escrito, para que el contador
		// fisico marque lo correcto desde el primer momento.
		escribir_monedero( m_creditos, 0 );
	}

	// ---- contador ----

	function guardar()
	{
		if ( fe.nv.rawin( NV_CLAVE ) )
			fe.nv[ NV_CLAVE ] = m_creditos;
		else
			fe.nv[ NV_CLAVE ] <- m_creditos;

		// El monedero se escribe en CADA cambio, no solo al lanzar el juego:
		// es lo que lee el contador fisico de la cabina (daemon.py), que tiene
		// que enterarse de la moneda en el momento en que entra. De paso, el
		// fichero se recrea solo si alguien lo borra.
		//
		// Va con inserta=0 a proposito: la orden de meter creditos en la
		// partida solo la escribe ToGame, justo antes del lanzamiento.
		escribir_monedero( m_creditos, 0 );
	}

	// Una moneda, venga del boton o de la senal.
	//
	// El antirrebote esta aqui y no en sumar() a proposito: los contactos de
	// una chauchera REBOTAN al cerrarse (abren y cierran varias veces en unos
	// milisegundos). El tick del frontend corre una vez por fotograma
	// (main.cpp: feVM.tick()), asi que puede muestrear ese rebote como varias
	// pulsaciones completas y una moneda acaba dando tres creditos.
	//
	// ttime es el reloj del tick en ms. Al volver de una partida da un salto
	// hacia delante (inofensivo) y al recargar el layout vuelve atras, que si
	// se detecta se da por bueno el siguiente credito.
	function moneda( ttime )
	{
		if ( m_antirrebote > 0 )
		{
			if ( ttime < m_ultima )
				m_ultima = ttime - m_antirrebote - 1;

			local desde = ttime - m_ultima;

			if ( desde < m_antirrebote )
			{
				m_rebotes++;
				fe.log( "Creditos: rebote descartado, solo " + desde
					+ " ms desde la anterior (van " + m_rebotes + ")\n" );
				return;
			}
		}

		m_ultima = ttime;
		sumar( m_paso );
	}

	function sumar( n )
	{
		local t = m_creditos + n;
		m_creditos = ( t > m_maximo ) ? m_maximo : t;
		guardar();
		pintar();
	}

	function hay_para_jugar()
	{
		return ( !m_exigir || ( m_creditos >= m_coste ) );
	}

	// Creditos que se pasan al juego al lanzarlo.
	//
	// Con m_nada (el ajuste por defecto, "Nada") el plugin no inserta ni cobra
	// nada: es una hucha y punto. El jugador entra con la maquina a cero y mete
	// los creditos que quiera con el boton de moneda; cada uno sale de su
	// monedero y el contador fisico lo ensena al momento. Lo que se queda
	// dentro de la maquina al salir SI se pierde, y de eso avisa el cuadro de
	// creditos.lua.
	//
	// Con m_todos ("Todos") entra el monedero completo, y ahi esta la trampa:
	// los creditos que el juego no gaste se quedan dentro de la partida y al
	// salir de MAME se pierden, porque no hay forma general de saber cuantos
	// quedaban.
	function creditos_a_gastar()
	{
		if ( m_nada )
			return 0;

		if ( m_todos )
			return m_creditos;

		return ( m_creditos < m_coste ) ? m_creditos : m_coste;
	}

	// ---- buzon para creditos.lua ----

	// Se escribe SIEMPRE, tambien un 0, para que nunca quede una orden vieja
	// que se colaria en el siguiente juego.
	//
	// Al temporal y luego rename() porque el renombrado es atomico: si algo
	// muere a media escritura, el monedero no se queda a medias. MAME hace lo
	// mismo desde su lado (monedero.lua).
	function escribir_monedero( saldo, inserta )
	{
		local texto = "saldo " + saldo + "\ninserta " + inserta + "\n";
		local tmp = m_buzon + ".tmp";

		try {
			local f = file( tmp, "wb" );
			local b = blob( texto.len() );

			for ( local i = 0; i < texto.len(); i++ )
				b.writen( texto[i], 'b' );

			f.writeblob( b );

			// close() explicito, no vale confiar en el recolector: MAME
			// arranca inmediatamente despues de esto.
			f.close();

			::rename( tmp, m_buzon );
			return true;
		} catch ( e ) {
			fe.log( "Creditos: no se pudo escribir el monedero " + m_buzon + " (" + e + ")\n" );
			try { ::remove( tmp ); } catch ( e2 ) {}
			return false;
		}
	}

	// Devuelve el saldo que dejo la partida, o null si no se puede leer.
	// Devolver null es importante: significa "no toques el contador", no
	// "cero". Si MAME se cayo a medias, perder los creditos seria lo peor.
	function leer_saldo()
	{
		try {
			local f = file( m_buzon, "rb" );
			local n = f.len();
			local b = f.readblob( n );
			f.close();

			local texto = "";
			for ( local i = 0; i < n; i++ )
				texto += format( "%c", b[i] );

			foreach ( linea in split( texto, "\n" ) )
			{
				local partes = split( strip( linea ), " \t" );
				if ( ( partes.len() == 2 ) && ( partes[0] == "saldo" ) )
					return partes[1].tointeger();
			}
		} catch ( e ) {
			fe.log( "Creditos: no se pudo leer el monedero " + m_buzon + " (" + e + ")\n" );
		}

		return null;
	}


	// ---- marcador ----

	function crear_texto()
	{
		if ( !m_mostrar || ( m_texto != null ) )
			return;

		local ancho = fe.layout.width;
		local alto  = fe.layout.height;
		local h     = m_tamano * 2;
		local w     = ancho - ( MARGEN * 2 );
		local y     = ( m_posicion.find( "Arriba" ) != null ) ? MARGEN : alto - MARGEN - h;

		m_texto = fe.add_text( "", MARGEN, y, w, h );
		m_texto.zorder    = ZORDER;
		m_texto.char_size = m_tamano;
		m_texto.align     = ( m_posicion.find( "derecha" ) != null ) ? Align.Right : Align.Left;
		m_texto.style     = Style.Bold;
		m_texto.outline   = 1.0;

		pintar();
	}

	// Deja el aviso encendido y reinicia el ciclo de parpadeo en el proximo
	// tick. Se hace asi, y no fijando el reloj aqui, porque quien llama no
	// tiene por que saber la hora: al volver de un juego el reloj del frontend
	// ha avanzado todo lo que duro la partida, y fijarlo con un valor viejo
	// apagaria el aviso en el primer tick.
	function destellar()
	{
		m_parpadeo = true;
		m_resinc = true;
		pintar();
	}

	function pintar()
	{
		if ( m_texto == null )
			return;

		if ( m_creditos > 0 )
		{
			m_texto.msg   = m_etiqueta + " " + m_creditos;
			m_texto.alpha = 255;
			m_texto.red   = 255;
			m_texto.green = 255;
			m_texto.blue  = 255;
		}
		else
		{
			m_texto.msg   = m_vacio;
			m_texto.alpha = m_parpadeo ? 255 : 0;
			m_texto.red   = 255;
			m_texto.green = 220;
			m_texto.blue  = 0;
		}
	}

	// ---- callbacks ----

	function en_tick( ttime )
	{
		m_ahora = ttime;

		if ( m_resinc )
		{
			m_resinc = false;
			m_reloj = ttime;
		}

		// El reloj del tick cuenta desde que arranco el layout. Si por lo que
		// sea va hacia atras, se resincroniza: si no, el parpadeo se quedaria
		// congelado hasta que el tiempo alcanzase el valor viejo.
		if ( ttime < m_reloj )
			m_reloj = ttime;

		// Parpadeo del "inserta moneda"
		if (( m_creditos == 0 ) && ( ttime > m_reloj + PARPADEO_MS ))
		{
			m_reloj = ttime;
			m_parpadeo = !m_parpadeo;
			pintar();
		}

		if ( m_boton.len() == 0 )
			return;

		// El credito se cuenta al soltar, igual que KonamiCode, para que
		// mantener el boton pulsado no dispare una lluvia de monedas.
		local abajo = fe.get_input_state( m_boton );

		if ( abajo )
			m_pulsado = true;
		else if ( m_pulsado )
		{
			m_pulsado = false;
			moneda( ttime );
		}
	}

	function en_senal( sig )
	{
		if (( m_senal.len() > 0 ) && ( sig == m_senal ))
		{
			// Por el mismo antirrebote que el boton: la senal tambien puede
			// venir de un contacto que rebota.
			moneda( m_ahora );
			return true;   // consumida, que no haga nada mas el frontend
		}

		// Sin creditos no se juega. Solo se bloquea el "select" de la lista:
		// dentro de un menu del frontend hace falta para confirmar.
		if (( sig == "select" ) && !fe.overlay.is_up && !hay_para_jugar() )
		{
			// Destello del aviso para que se vea que falta credito. Se apoya en
			// la hora del ultimo tick: con m_reloj = 0 el siguiente tick lo
			// apagaria inmediatamente.
			destellar();
			return true;
		}

		return false;
	}

	function en_transicion( ttype, var, ttime )
	{
		if ( ttype == Transition.StartLayout )
		{
			// Los objetos del plugin se crean antes que los del layout, asi
			// que aqui, ya cargado el layout, es donde el marcador se crea
			// para poder quedar por encima (mas el zorder maximo).
			m_texto = null;
			crear_texto();
		}
		else if ( ttype == Transition.FromGame )
		{
			// De vuelta de la partida: el saldo que manda es el del fichero,
			// porque creditos.lua ha ido descontando las monedas que el
			// jugador metio durante el juego.
			local saldo = leer_saldo();

			if ( saldo == null )
			{
				fe.log( "Creditos: no leo el monedero al volver, dejo el contador como estaba\n" );
			}
			else
			{
				if ( saldo > m_maximo ) saldo = m_maximo;
				if ( saldo < 0 ) saldo = 0;

				if ( saldo != m_creditos )
					fe.log( "Creditos: el monedero vuelve con " + saldo
						+ " (el frontend tenia " + m_creditos + ")\n" );

				m_creditos = saldo;
				guardar();
			}

			// El jugador esta mirando la pantalla: que el aviso aparezca
			// encendido en vez de en mitad del ciclo apagado.
			destellar();
		}
		else if ( ttype == Transition.ToGame )
		{
			// Ultima parada antes de lanzar el emulador: pre_run() dispara
			// ToGame y justo despues hace el fork/execvp.
			local gasto = creditos_a_gastar();

			m_creditos = m_creditos - gasto;
			guardar();

			// Al fichero van las dos cifras: lo que queda en el monedero y lo
			// que MAME debe meter en la partida.
			escribir_monedero( m_creditos, gasto );

			destellar();
		}

		return false;
	}
}

if ( !ScreenSaverActive )
	fe.plugin[ "Creditos" ] <- Creditos();
