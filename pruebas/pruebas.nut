// Pruebas del plugin de creditos contra la maqueta de AM+.
dofile( "maqueta.nut", true );

PLUGIN <- "/home/eloy/attractplus/config/plugins/Creditos.nut";
BUZON  <- "buzon_de_pruebas.txt";   // relativo: se ejecuta desde este directorio

fallos <- 0;
pasadas <- 0;

function ok( titulo, condicion, detalle = "" )
{
	if ( condicion ) { pasadas++; print( "  ok   " + titulo + "\n" ); }
	else { fallos++; print( "  FALLO " + titulo + "  -> " + detalle + "\n" ); }
}

function igual( titulo, obtenido, esperado )
{
	ok( titulo, obtenido == esperado, "esperaba <" + esperado + "> y llego <" + obtenido + ">" );
}

// Los ajustes por defecto, copiados de la clase UserConfig del plugin.
// Al final se comprueba que no se hayan desincronizado, valor a valor.
function config_defecto()
{
	return {
		boton = "Joy0 Button5",
		senal = "ninguna",
		por_pulsacion = "1",
		maximo = "99",
		exigir = "Si",
		coste = "1",
		antirrebote = "40",
		gasto = "Nada",
		buzon = BUZON,
		mostrar = "Si",
		posicion = "Abajo izquierda",
		tamano = "24",
		etiqueta = "CREDITOS",
		vacio = "INSERTA MONEDA"
	};
}

// La variante que inserta creditos al lanzar. Casi todas las pruebas de abajo
// son de esa mecanica, que sigue existiendo como opcion aunque ya no sea la de
// por defecto.
function config_insertando()
{
	local c = config_defecto();
	c.gasto = "Solo el coste";
	return c;
}

function borrar_buzon()
{
	try { remove( BUZON ); } catch ( e ) {}
}

// Simula lo que creditos.lua deja en el fichero al terminar la partida
function escribir_buzon_crudo( texto )
{
	local f = file( BUZON, "wb" );
	local b = blob( texto.len() );
	for ( local i = 0; i < texto.len(); i++ ) b.writen( texto[i], 'b' );
	f.writeblob( b );
	f.close();
}

function leer_buzon()
{
	try {
		local f = file( BUZON, "rb" );
		local n = f.len();
		local b = f.readblob( n );
		f.close();
		local s = "";
		for ( local i = 0; i < n; i++ ) s += format( "%c", b[i] );
		return s;
	} catch ( e ) {
		return null;
	}
}

// Carga el plugin como lo haria AM+: se ejecuta el script y despues el layout
function cargar( cfg, limpiar_nv = true )
{
	if ( limpiar_nv ) fe.nv = {};
	MOCK.reset( cfg );
	dofile( PLUGIN, true );
	MOCK.arrancar_layout();
	return fe.plugin[ "Creditos" ];
}

function marcador() { return MOCK.textos[ MOCK.textos.len() - 1 ]; }

///////////////////////////////////////////////////
print( "\n1. contar monedas y mostrarlas\n" );
{
	local p = cargar( config_insertando() );
	igual( "arranca a cero", p.m_creditos, 0 );
	igual( "avisa de que falta moneda", marcador().msg, "INSERTA MONEDA" );

	MOCK.moneda( "Joy0 Button5" );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.moneda( "Joy0 Button5" );

	igual( "tres pulsaciones, tres creditos", p.m_creditos, 3 );
	igual( "el marcador es texto entero, no float", marcador().msg, "CREDITOS 3" );
	igual( "el marcador va encima de todo", marcador().zorder, 2147483647 );
	ok( "tipo entero en el contador", typeof p.m_creditos == "integer", typeof p.m_creditos );
}

print( "\n2. mantener pulsado no es una lluvia de monedas\n" );
{
	local p = cargar( config_insertando() );
	MOCK.inputs[ "Joy0 Button5" ] <- true;
	MOCK.tick( 0 ); MOCK.tick( 16 ); MOCK.tick( 32 ); MOCK.tick( 48 );
	igual( "pulsado sin soltar: nada", p.m_creditos, 0 );
	MOCK.inputs[ "Joy0 Button5" ] <- false;
	MOCK.tick( 64 );
	igual( "al soltar: un credito", p.m_creditos, 1 );
}

print( "\n3. lanzar juego: el monedero no se vacia\n" );
{
	borrar_buzon();
	local p = cargar( config_insertando() );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.moneda( "Joy0 Button5" );

	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );

	// Lo importante: al juego va UN credito, no los tres. Los creditos que el
	// juego no gasta se quedan dentro de la partida y se pierden al salir, asi
	// que el frontend se queda con el resto.
	igual( "al juego un credito, dos al monedero", leer_buzon(), "saldo 2\ninserta 1\n" );
	igual( "los otros dos siguen en el frontend", p.m_creditos, 2 );
	igual( "el marcador lo refleja", marcador().msg, "CREDITOS 2" );
	igual( "y se puede lanzar otra partida", MOCK.senal( "select" ), false );
}

print( "\n3b. modo 'Todos', que si vacia el monedero\n" );
{
	borrar_buzon();
	local c = config_insertando();
	c.gasto = "Todos";
	local p = cargar( c );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "entra el monedero entero y no queda saldo", leer_buzon(), "saldo 0\ninserta 3\n" );
	igual( "y el frontend se queda a cero", p.m_creditos, 0 );
	igual( "el marcador vuelve a pedir moneda", marcador().msg, "INSERTA MONEDA" );
}

// La tarifa del juego NO se toca aqui a proposito: el buzon lleva creditos y
// solo creditos. Quien sabe cuantas monedas hacen falta es creditos.lua, que
// lee el DIP del juego ya cargado. Si el plugin tambien compensara, se
// descontaria dos veces. Esa parte se prueba en prueba_tarifa.lua y midiendo
// con MAME de verdad.

print( "\n4. el buzon nunca guarda un valor viejo\n" );
{
	borrar_buzon();
	local p = cargar( config_insertando() );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "primer lanzamiento", leer_buzon(), "saldo 0\ninserta 1\n" );
	igual( "el monedero queda vacio", p.m_creditos, 0 );

	// Segundo lanzamiento sin meter monedas: si el buzon no se reescribiera,
	// el juego se llevaria un credito de regalo.
	local c = config_insertando();
	c.exigir = "No";
	local q = cargar( c, false );
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "segundo lanzamiento sin creditos ordena 0", leer_buzon(), "saldo 0\ninserta 0\n" );
}

print( "\n5. sin credito no se juega\n" );
{
	local p = cargar( config_insertando() );
    igual( "select bloqueado a cero", MOCK.senal( "select" ), true );

	MOCK.moneda( "Joy0 Button5" );
	igual( "con credito, select pasa", MOCK.senal( "select" ), false );

	// El select tambien confirma dentro de los menus del frontend: ahi
	// bloquearlo dejaria la cabina inutilizable.
	local q = cargar( config_insertando() );
	fe.overlay.is_up = true;
	igual( "en un menu no se bloquea", MOCK.senal( "select" ), false );
	fe.overlay.is_up = false;

	// Y con la exigencia desactivada se juega gratis
	local c = config_insertando();
	c.exigir = "No";
	local r = cargar( c );
	igual( "exigir=No deja jugar gratis", MOCK.senal( "select" ), false );
}

print( "\n6. partidas que cuestan mas de un credito\n" );
{
	borrar_buzon();
	local c = config_insertando();
	c.coste = "2";
	local p = cargar( c );
	for ( local i = 0; i < 5; i++ ) MOCK.moneda( "Joy0 Button5" );
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "el juego recibe el coste", leer_buzon(), "saldo 3\ninserta 2\n" );
	igual( "el resto se queda en el frontend", p.m_creditos, 3 );
	igual( "y sigue habiendo para otra", MOCK.senal( "select" ), false );
}

print( "\n7. topes y ajustes raros\n" );
{
	local c = config_insertando();
	c.maximo = "2";
	local p = cargar( c );
	for ( local i = 0; i < 5; i++ ) MOCK.moneda( "Joy0 Button5" );
	igual( "el contador no pasa del maximo", p.m_creditos, 2 );

	local d = config_insertando();
	d.por_pulsacion = "tres";   // el usuario teclea cualquier cosa
	d.maximo = "";
	d.tamano = "-5";
	local q = cargar( d );
	MOCK.moneda( "Joy0 Button5" );
	igual( "ajuste no numerico cae al defecto", q.m_creditos, 1 );
	ok( "tamano negativo se corrige", q.m_tamano >= 4, q.m_tamano + "" );
	borrar_buzon();
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "y el monedero sale bien", leer_buzon(), "saldo 0\ninserta 1\n" );
}

print( "\n8. al volver del juego manda el monedero\n" );
{
	// Este es el caso que se perdia creditos: el jugador mete 5, juega una
	// partida metiendo una moneda mas por el camino, y al salir el frontend
	// tiene que ensenar lo que de verdad queda.
	local p = cargar( config_insertando() );
	for ( local i = 0; i < 5; i++ ) MOCK.moneda( "Joy0 Button5" );
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "al lanzar quedan cuatro", p.m_creditos, 4 );

	// creditos.lua ha descontado una moneda mas metida durante la partida
	escribir_buzon_crudo( "saldo 3\ninserta 0\n" );
	MOCK.transicion( Transition.FromGame, FromTo.NoValue, 0 );

	igual( "el frontend adopta el saldo del monedero", p.m_creditos, 3 );
	igual( "y lo pinta", marcador().msg, "CREDITOS 3" );
	igual( "y lo guarda para el proximo arranque", fe.nv[ "Creditos" ], 3 );
}

print( "\n8b. si el monedero no se puede leer, no se toca el contador\n" );
{
	local p = cargar( config_insertando() );
	for ( local i = 0; i < 3; i++ ) MOCK.moneda( "Joy0 Button5" );
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "quedan dos al lanzar", p.m_creditos, 2 );

	// MAME se cayo y dejo el fichero a medias, o alguien lo borro
	borrar_buzon();
	MOCK.transicion( Transition.FromGame, FromTo.NoValue, 0 );
	igual( "sin fichero, el contador aguanta", p.m_creditos, 2 );

	escribir_buzon_crudo( "esto no es un monedero\n" );
	MOCK.transicion( Transition.FromGame, FromTo.NoValue, 0 );
	igual( "con basura, tambien aguanta", p.m_creditos, 2 );

	escribir_buzon_crudo( "saldo dos\n" );
	MOCK.transicion( Transition.FromGame, FromTo.NoValue, 0 );
	igual( "saldo no numerico, aguanta", p.m_creditos, 2 );
}

print( "\n8c. un saldo absurdo no revienta el contador\n" );
{
	local c = config_insertando();
	c.maximo = "10";
	local p = cargar( c );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	escribir_buzon_crudo( "saldo 9999\ninserta 0\n" );
	MOCK.transicion( Transition.FromGame, FromTo.NoValue, 0 );
	igual( "se recorta al maximo", p.m_creditos, 10 );
}

print( "\n9. los creditos sobreviven al cambio de layout\n" );
{
	local p = cargar( config_insertando() );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.moneda( "Joy0 Button5" );
	igual( "guardados en fe.nv", fe.nv[ "Creditos" ], 2 );

	// Cambiar de layout vuelve a ejecutar el plugin desde cero
	local q = cargar( config_insertando(), false );
	igual( "el nuevo plugin los recupera", q.m_creditos, 2 );
	igual( "y los pinta", marcador().msg, "CREDITOS 2" );
}

print( "\n10. parpadeo del aviso\n" );
{
	local p = cargar( config_insertando() );
	local a1 = marcador().alpha;
	MOCK.tick( 500 );
	local a2 = marcador().alpha;
	MOCK.tick( 1000 );
	local a3 = marcador().alpha;
	ok( "el aviso parpadea", ( a1 != a2 ) && ( a2 != a3 ), a1 + "/" + a2 + "/" + a3 );

	MOCK.moneda( "Joy0 Button5" );
	MOCK.tick( 1500 ); MOCK.tick( 2000 );
	igual( "con creditos no parpadea", marcador().alpha, 255 );
}

print( "\n11. el aviso parpadea aunque no haya boton configurado\n" );
{
	local c = config_insertando();
	c.boton = "";               // solo senal, sin boton fisico
	c.senal = "custom1";
	local p = cargar( c );
	local a1 = marcador().alpha;
	MOCK.tick( 500 );
	local a2 = marcador().alpha;
	ok( "parpadea sin boton", a1 != a2, a1 + "/" + a2 );
}

print( "\n12. el aviso se enciende al quedarse sin creditos\n" );
{
	local p = cargar( config_insertando() );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.tick( 1000 );                       // el reloj del parpadeo avanza
	borrar_buzon();
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "al gastar, el aviso sale encendido", marcador().alpha, 255 );
	MOCK.tick( 1100 );
	igual( "y sigue encendido su medio segundo", marcador().alpha, 255 );
	MOCK.tick( 1600 );
	igual( "luego ya se apaga", marcador().alpha, 0 );

	// El select bloqueado tambien enciende el aviso, y no se apaga al frame
	// siguiente: el destello se cuenta desde la hora del ultimo tick.
	MOCK.senal( "select" );
	igual( "select bloqueado enciende el aviso", marcador().alpha, 255 );
	MOCK.tick( 1700 );
	igual( "el destello no se apaga de inmediato", marcador().alpha, 255 );
	MOCK.tick( 2300 );
	igual( "y se apaga cuando toca", marcador().alpha, 0 );
}

print( "\n13. al volver del juego el aviso se ve enseguida\n" );
{
	local p = cargar( config_insertando() );
	MOCK.moneda( "Joy0 Button5" );
	MOCK.tick( 3000 );
	borrar_buzon();
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );

	// Mientras se juega el reloj del frontend sigue corriendo: al volver da un
	// salto enorme, y aun asi el aviso tiene que aparecer encendido.
	MOCK.transicion( Transition.FromGame, FromTo.NoValue, 0 );
	MOCK.tick( 15000 );
	igual( "encendido tras la partida", marcador().alpha, 255 );
	MOCK.tick( 15200 );
	igual( "sigue encendido", marcador().alpha, 255 );
	MOCK.tick( 15600 );
	igual( "y luego parpadea normal", marcador().alpha, 0 );
}

print( "\n14. un reloj que va hacia atras no congela el parpadeo\n" );
{
	local p = cargar( config_insertando() );
	MOCK.tick( 5000 );
	MOCK.tick( 5500 );
	local antes = marcador().alpha;
	MOCK.tick( 10 );                         // layout recargado: reloj a cero
	MOCK.tick( 500 );
	ok( "vuelve a parpadear", marcador().alpha != antes,
		"antes " + antes + " ahora " + marcador().alpha );
}

print( "\n15. senal alternativa como ranura\n" );
{
	local c = config_insertando();
	c.senal = "custom1";
	local p = cargar( c );
	igual( "custom1 mete moneda y se consume", MOCK.senal( "custom1" ), true );
	igual( "y suma credito", p.m_creditos, 1 );
	igual( "otras senales pasan de largo", MOCK.senal( "next_game" ), false );
}

print( "\n16. sin marcador ni boton no revienta\n" );
{
	local c = config_insertando();
	c.mostrar = "No";
	c.boton = "";
	c.senal = "custom2";
	local p = cargar( c );
	igual( "no crea texto", MOCK.textos.len(), 0 );
	MOCK.tick( 0 ); MOCK.tick( 500 );   // sin boton el tick sigue corriendo
	MOCK.senal( "custom2" );
	igual( "sigue contando", p.m_creditos, 1 );
	borrar_buzon();
	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "y escribe el monedero", leer_buzon(), "saldo 0\ninserta 1\n" );
}

print( "\n17. la config de la prueba coincide con UserConfig\n" );
{
	local esperada = config_defecto();
	local faltan = "";
	local distintos = "";

	foreach ( clave, valor in UserConfig )
	{
		if ( typeof valor != "string" ) continue;

		if ( !( clave in esperada ) )
			faltan += clave + " ";
		// buzon y boton los fija la prueba: uno a un temporal y el otro a un
		// boton de mentira, porque UserConfig los trae vacios o al HOME real.
		else if ( ( clave != "buzon" ) && ( clave != "boton" )
				&& ( esperada[ clave ] != valor ) )
			distintos += clave + "(" + valor + "!=" + esperada[ clave ] + ") ";
	}

	igual( "no hay ajustes sin probar", faltan, "" );
	igual( "y los valores por defecto coinciden", distintos, "" );
}

print( "\n18. modo 'Nada': el plugin es una hucha y no inserta\n" );
{
	borrar_buzon();
	local p = cargar( config_defecto() );   // gasto = "Nada", el de por defecto

	for ( local i = 0; i < 5; i++ ) MOCK.moneda( "Joy0 Button5" );
	igual( "cinco creditos en el monedero", p.m_creditos, 5 );
	igual( "y ya estan por escrito antes de lanzar", leer_buzon(), "saldo 5\ninserta 0\n" );

	MOCK.transicion( Transition.ToGame, FromTo.NoValue, 0 );
	igual( "al lanzar no se inserta ni se cobra nada", leer_buzon(), "saldo 5\ninserta 0\n" );
	igual( "el contador no baja", p.m_creditos, 5 );

	// creditos.lua cobra las monedas que el jugador mete dentro de la partida
	escribir_buzon_crudo( "saldo 2\ninserta 0\n" );
	MOCK.transicion( Transition.FromGame, FromTo.NoValue, 0 );
	igual( "al volver adopta lo que gasto dentro", p.m_creditos, 2 );
}

print( "\n19. modo 'Nada': sigue exigiendo credito para elegir juego\n" );
{
	borrar_buzon();
	local q = cargar( config_defecto() );
	igual( "sin creditos no se puede elegir", MOCK.senal( "select" ), true );
	MOCK.moneda( "Joy0 Button5" );
	igual( "con uno si", MOCK.senal( "select" ), false );
	igual( "y no se lo ha gastado", q.m_creditos, 1 );
}

print( "\n20. el monedero se escribe en cada moneda, no solo al lanzar\n" );
{
	borrar_buzon();
	local p = cargar( config_defecto() );
	igual( "al arrancar ya hay fichero", leer_buzon(), "saldo 0\ninserta 0\n" );

	MOCK.moneda( "Joy0 Button5" );
	igual( "primera moneda por escrito", leer_buzon(), "saldo 1\ninserta 0\n" );
	MOCK.moneda( "Joy0 Button5" );
	igual( "segunda tambien", leer_buzon(), "saldo 2\ninserta 0\n" );

	borrar_buzon();
	MOCK.moneda( "Joy0 Button5" );
	igual( "borrado, se recrea solo", leer_buzon(), "saldo 3\ninserta 0\n" );
}

print( "\n21. antirrebote: una moneda que rebota no cuenta tres veces\n" );
{
	borrar_buzon();
	local c = config_defecto();
	c.antirrebote = "150";      // fijo para poder probar los limites
	local p = cargar( c );

	// Un contacto que rebota: tres cierres en 12 ms. Es UNA moneda.
	MOCK.moneda( "Joy0 Button5", 200 );
	MOCK.moneda( "Joy0 Button5", 4 );
	MOCK.moneda( "Joy0 Button5", 8 );
	igual( "el rebote no suma", p.m_creditos, 1 );
	igual( "y queda anotado", p.m_rebotes, 2 );

	// pasado el antirrebote, la siguiente moneda si cuenta
	MOCK.moneda( "Joy0 Button5", 200 );
	igual( "la moneda de verdad si", p.m_creditos, 2 );

	// justo en el limite
	MOCK.moneda( "Joy0 Button5", 149 );
	igual( "149 ms todavia es rebote", p.m_creditos, 2 );
	MOCK.moneda( "Joy0 Button5", 1 );
	igual( "150 ms ya cuenta", p.m_creditos, 3 );
}

print( "\n22. el antirrebote se puede apagar y ajustar\n" );
{
	borrar_buzon();
	local c = config_defecto();
	c.antirrebote = "0";
	local p = cargar( c );

	MOCK.moneda( "Joy0 Button5", 200 );
	MOCK.moneda( "Joy0 Button5", 1 );
	MOCK.moneda( "Joy0 Button5", 1 );
	igual( "con 0 cuentan todas", p.m_creditos, 3 );

	borrar_buzon();
	local d = config_defecto();
	d.antirrebote = "500";
	local q = cargar( d );

	MOCK.moneda( "Joy0 Button5", 600 );
	MOCK.moneda( "Joy0 Button5", 300 );
	igual( "con 500 hace falta mas hueco", q.m_creditos, 1 );
	MOCK.moneda( "Joy0 Button5", 600 );
	igual( "y con el hueco cuenta", q.m_creditos, 2 );
}

print( "\n23b. con el defecto (40 ms) pasa un tren de pulsos de chauchera\n" );
{
	// Una chauchera de varias monedas manda un pulso por unidad, separados
	// unos 100 ms. Con el antirrebote por defecto tienen que contar todos.
	borrar_buzon();
	local p = cargar( config_defecto() );

	MOCK.moneda( "Joy0 Button5", 500 );
	MOCK.moneda( "Joy0 Button5", 100 );
	MOCK.moneda( "Joy0 Button5", 100 );
	MOCK.moneda( "Joy0 Button5", 100 );
	MOCK.moneda( "Joy0 Button5", 100 );
	igual( "una moneda de 5 unidades da 5 creditos", p.m_creditos, 5 );

	// pero el rebote de contactos, que dura mucho menos, sigue fuera
	MOCK.moneda( "Joy0 Button5", 8 );
	igual( "y el rebote sigue descartado", p.m_creditos, 5 );
}

print( "\n23. el reloj del tick puede ir hacia atras sin comerse una moneda\n" );
{
	borrar_buzon();
	local p = cargar( config_defecto() );
	MOCK.moneda( "Joy0 Button5", 5000 );
	igual( "primera moneda", p.m_creditos, 1 );

	// al recargar el layout, ttime vuelve a empezar
	MOCK.reloj = 0;
	MOCK.moneda( "Joy0 Button5", 10 );
	igual( "la siguiente no se pierde", p.m_creditos, 2 );
}

print( "\n=== " + pasadas + " ok, " + fallos + " fallos ===\n" );
if ( fallos > 0 ) throw "hay fallos";
