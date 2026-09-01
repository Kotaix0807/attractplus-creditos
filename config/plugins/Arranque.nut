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
	</ label="Senal para abrir el menu", help="Accion del frontend que abre los ajustes del juego seleccionado. Se mapea en Controls > Custom", options="custom1,custom2,custom3,custom4,custom5,custom6,custom7,custom8,custom9,custom10", order=1 />
	senal="custom2";

	</ label="Fichero de ajustes", help="Debe ser el mismo arranque.dat que lee creditos.lua", order=2 />
	fichero="/home/eloy/groovyarcade-creditos/arranque.dat";
}


class Arranque
{
	// Las claves que se pueden editar: nombre en el fichero, etiqueta y ayuda.
	// Anadir una fila aqui es todo lo que hace falta para exponer un ajuste
	// nuevo. Es un static y no un const porque en Squirrel const solo admite
	// escalares (entero, float o cadena), no arreglos.
	static AJUSTES = [
		[ "velocidad", "Velocidad de carga", "0 = sin freno, 1 = normal, 2 = el doble..." ],
		[ "arranque",  "Segundos de carga",  "Segundos que dura la carga tapada (pantalla en negro)" ],
		[ "fijo",      "Tiempo fijo",        "1 = usa los segundos tal cual, sin deteccion automatica" ],
		[ "nvram",     "Guardar NVRAM",      "0 = el juego no guarda creditos ni puntuaciones entre sesiones" ],
		[ "turbo",     "Acelerar",           "0 = no acelerar ni silenciar este juego" ],
	];

	m_senal    = "custom2";
	m_fichero  = "";

	constructor()
	{
		local c = fe.get_config();
		m_senal   = c[ "senal" ];
		m_fichero = fs.path_expand( c[ "fichero" ] );

		fe.add_signal_handler( this, "en_senal" );
	}

	// ---- fichero ----

	// Squirrel no tiene readline: se lee el fichero entero como blob y se
	// convierte byte a byte.
	function formatBlobToString(blobFile){

        local numbOfBytes = blobFile.len();
        local fileData = blobFile.readblob(numbOfBytes);
        local parsedData = "";
        
        blobFile.close();

        for(local i = 0; i < numbOfBytes; i++) 
            parsedData += format("%c", fileData[i]);
        return parsedData;
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
			try { ::remove( tmp ); } catch ( e2 ) {}
			return false;
		}
	}

	// Quita el comentario de una linea y le recorta los espacios
	function limpiar( linea )
	{
		local c = linea.find( "#" );
		if ( c != null ) linea = linea.slice( 0, c );
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
			if ( p.len() == 2 ) r[ p[0] ] <- p[1];
		}

		return r;
	}

	function nombre_de( linea )
	{
		local l = limpiar( linea );
		if ( l.len() == 0 ) return null;

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
		if ( sig != m_senal )
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
		if ( juego.len() == 0 ) return;

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
