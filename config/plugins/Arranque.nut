///////////////////////////////////////////////////
//
// Ajustes de arranque por juego, editables desde la cabina.
//
// Escribe el mismo arranque.dat que lee creditos.lua (ajustes.lua): una linea
// por juego con pares clave=valor, y una linea 'defecto' para los demas.
//
//   defecto velocidad=0 arranque=5 max=30 sin=15
//   pacman arranque=5
//   mwalk nvram=0 arranque=10
//
// La clave importante del diseno: la linea del juego se SUSTITUYE EN SU SITIO y
// el resto del fichero se copia tal cual. Reescribirlo entero se llevaria por
// delante los comentarios, que es donde estan apuntadas las mediciones.
//
///////////////////////////////////////////////////

class UserConfig </ help="Ajusta la carga acelerada de cada juego (velocidad y segundos) desde la propia cabina" /> {
	</ label="Tecla del menu", help="Tecla o boton que abre los ajustes del juego seleccionado. Es la via directa: no hay que mapear nada en Controls", is_input=true, order=1 />
	boton="";

	</ label="Senal alternativa", help="Abre el menu tambien con esta accion del frontend. OJO: hay que mapearla antes en Controls > Custom, o no se emite nunca y parece que el plugin no funciona. 'ninguna' para no usarla", options="ninguna,custom1,custom2,custom3,custom4,custom5,custom6,custom7,custom8,custom9,custom10", order=2 />
	senal="ninguna";

	</ label="Fichero de ajustes", help="Debe ser el mismo arranque.dat que lee creditos.lua", order=3 />
	fichero="/home/eloy/groovyarcade-creditos/arranque.dat";
}


class Arranque
{
	// Las claves que se pueden editar: nombre en el fichero, etiqueta y ayuda.
	// Anadir una fila aqui es todo lo que hace falta para exponer un ajuste
	// nuevo. Es un static y no un const porque en Squirrel const solo admite
	// escalares (entero, float o cadena), no arreglos.
	static AJUSTES = [
		[ "velocidad", "Velocidad de carga (%)",
			"100 = normal, 200 = el doble, 1000 = diez veces. 0 = sin freno" ],
		[ "segundos",  "Segundos en negro",
			"Cuanto dura la carga tapada. Es exacto, no una estimacion" ],
		[ "negro",     "Tapar la pantalla",
			"0 = acelera igual pero NO tapa la pantalla. Util para ver el efecto de la velocidad mientras ajustas" ],
		[ "indicador", "Avisar en pantalla",
			"1 = muestra '>> CARGANDO AL 300%' mientras la emulacion va acelerada. Para ajustar" ],
		[ "nvram",     "Guardar NVRAM",
			"0 = este juego no guarda creditos ni puntuaciones entre sesiones" ],
		[ "auto",      "Alargar solo",
			"1 = se alarga hasta detectar que la placa esta lista. Solo en los juegos que estan en creditos.dat" ],
	];


	m_boton    = "";
	m_senal    = "ninguna";
	m_fichero  = "";
	m_pulsado  = false;

	constructor()
	{
		local c = fe.get_config();
		m_boton   = c[ "boton" ];
		m_senal   = ( c[ "senal" ] == "ninguna" ) ? "" : c[ "senal" ];
		m_fichero = fs.path_expand( c[ "fichero" ] );

		if ( m_boton.len() > 0 )
			fe.add_ticks_callback( this, "en_tick" );

		fe.add_signal_handler( this, "en_senal" );

		fe.log( "Arranque: listo (tecla=[" + m_boton + "] senal=[" + m_senal
			+ "] fichero=" + m_fichero + ")\n" );
	}

	// El menu se abre al SOLTAR la tecla, para que mantenerla pulsada no lo
	// reabra en bucle al cerrarlo.
	function en_tick( ttime )
	{
		if ( fe.overlay.is_up )
			return;

		local abajo = fe.get_input_state( m_boton );

		if ( abajo )
			m_pulsado = true;
		else if ( m_pulsado )
		{
			m_pulsado = false;
			menu();
		}
	}

	// ---- fichero ----

	function formatBlobToString(blobFile){

        local numbOfBytes = blobFile.len();
        local fileData = blobFile.readblob(numbOfBytes);
        local parsedData = "";
        
        blobFile.close();

        for(local i = 0; i < numbOfBytes; i++) 
            parsedData += format("%c", fileData[i]);
        return parsedData;
    }

	// Squirrel no tiene readline: se lee el fichero entero como blob y se
	// convierte byte a byte.
	//
	// Ojo: formatBlobToString espera el fichero ABIERTO, no la ruta. Pasarle la
	// ruta da "the index 'readblob' does not exist", porque una cadena no tiene
	// ese metodo.
	function leer_texto()
	{
		try {
			return formatBlobToString( file( m_fichero, "rb" ) );
		} catch ( e ) {
			fe.log( "Arranque: no puedo leer " + m_fichero + " (" + e + ")\n" );
			return null;
		}
	}

	// Al temporal y luego rename, que es atomico: si algo muere a media
	// escritura, el fichero de ajustes no se queda a medias.
	function escribir_texto( texto )
	{
		local tmp = m_fichero + ".tmp";

		try {
			local f = file( tmp, "wb" );
			local b = blob( texto.len() );
			for ( local i = 0; i < texto.len(); i++ )
				b.writen( texto[i], 'b' );
			f.writeblob( b );
			f.close();

			::rename( tmp, m_fichero );
			return true;
		} catch ( e ) {
			fe.log( "Arranque: no puedo escribir " + m_fichero + " (" + e + ")\n" );
			fe.log("Intentando eliminar cambios...\n");
			try { 
				::remove( tmp ); 
			} catch ( e2 ) 
			{
				fe.log("No se pudieron eliminar los cambios\n");
			}
			return false;
		}
	}

	// Quita el comentario de una linea y le recorta los espacios
	function limpiar( linea )
	{
		local c = linea.find( "#" );
		if ( c != null ) 
			linea = linea.slice( 0, c );
		return strip( linea );
	}

	// Los pares clave=valor de la linea de un juego.
	//
	// El nombre es siempre el PRIMER trozo, asi que no hay que comparar con
	// nada: del 1 en adelante son pares. Si el primer trozo tuviera un '=' la
	// linea estaria mal escrita (le falta el separador).
	function pares( linea )
	{
		local r = {};
		local trozos = split( limpiar( linea ), " \t" );

		for ( local i = 1; i < trozos.len(); i++ )
		{
			local p = split( trozos[i], "=" );
			if ( p.len() == 2 )
				r[ p[0] ] <- p[1];
		}

		return r;
	}

	function nombre_de( linea )
	{
		local l = limpiar( linea );
		if ( l.len() == 0 )
			return null;

		local trozos = split( l, " \t" );
		local n = trozos[0];

		if ( n.find( "=" ) != null )
		{
			fe.log( "Arranque: linea sin separador, la ignoro: " + l + "\n" );
			return null;
		}

		return n;
	}

	// Lee los ajustes de un juego (o de 'defecto')
	function ajustes_de( juego )
	{
		local texto = leer_texto();
		if ( texto == null ) return {};

		foreach ( linea in split( texto, "\n" ) )
		{
			if ( nombre_de( linea ) == juego )
				return pares( linea );
		}

		return {};
	}

	// Sustituye la linea del juego, o la anade al final si no existe.
	// Todo lo demas del fichero se copia tal cual, comentarios incluidos.
	function guardar_ajustes( juego, ajustes )
	{
		local texto = leer_texto();
		if ( texto == null ) return false;

		local linea_nueva = juego;
		foreach ( clave, valor in ajustes )
			linea_nueva += " " + clave + "=" + valor;

		local salida = "";
		local puesta = false;
		local lineas = split( texto, "\n" );

		foreach ( linea in lineas )
		{
			if ( nombre_de( linea ) == juego )
			{
				// Si no queda ningun ajuste, la linea desaparece
				if ( ajustes.len() > 0 )
					salida += linea_nueva + "\n";
				puesta = true;
			}
			else
				salida += linea + "\n";
		}

		if ( !puesta && ( ajustes.len() > 0 ) )
			salida += linea_nueva + "\n";

		return escribir_texto( salida );
	}

	// ---- menu ----

	function en_senal( sig )
	{
		if ( ( m_senal.len() == 0 ) || ( sig != m_senal ) )
			return false;

		// Dentro de un menu del frontend esa pulsacion significa otra cosa
		if ( fe.overlay.is_up )
			return false;

		menu();
		return true;   // consumida
	}

	function menu()
	{
		local juego = fe.game_info( Info.Name );
		if ( juego.len() == 0 )
			return;

		while ( true )
		{
			local a = ajustes_de( juego );
			local opciones = [];

			foreach ( fila in AJUSTES )
			{
				local v = ( fila[0] in a ) ? a[ fila[0] ] : "-";
				opciones.append( fila[1] + ": " + v );
			}

			opciones.append( "Quitar todos los ajustes de este juego" );
			opciones.append( "Salir" );

			local sel = fe.overlay.list_dialog(
				opciones,
				"Arranque de " + juego + " (" + fe.game_info( Info.Title ) + ")",
				0,
				opciones.len() - 1 );

			if ( ( sel < 0 ) || ( sel == opciones.len() - 1 ) )
				return;

			if ( sel == AJUSTES.len() )
			{
				guardar_ajustes( juego, {} );
				fe.overlay.splash_message( "Ajustes de " + juego + " quitados" );
				continue;
			}

			local clave = AJUSTES[ sel ][0];
			local antes = ( clave in a ) ? a[ clave ] : "";

			local nuevo = fe.overlay.edit_dialog(
				AJUSTES[ sel ][2] + "  (vacio = quitar)", antes );

			nuevo = strip( nuevo );

			if ( nuevo.len() == 0 )
			{
				if ( clave in a ) delete a[ clave ];
			}
			else
				a[ clave ] <- nuevo;

			if ( guardar_ajustes( juego, a ) )
				fe.log( "Arranque: " + juego + " -> " + clave + "=" + nuevo + "\n" );
		}
	}
}

fe.plugin[ "Arranque" ] <- Arranque();
