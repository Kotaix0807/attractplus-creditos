// Pruebas del editor de ajustes por juego (Arranque.nut), con la maqueta.
dofile( "maqueta.nut", true );

PLUGIN <- "/home/eloy/attractplus/config/plugins/Arranque.nut";
DAT <- "arranque_de_pruebas.dat";

fallos <- 0; pasadas <- 0;
function ok( t, c, d = "" ) {
	if ( c ) { pasadas++; print( "  ok   " + t + "\n" ); }
	else { fallos++; print( "  FALLO " + t + "  (" + d + ")\n" ); }
}
function igual( t, a, b ) { ok( t, a == b, "esperaba <" + b + "> y llego <" + a + ">" ); }

function escribe( texto ) {
	local f = file( DAT, "wb" );
	local b = blob( texto.len() );
	for ( local i = 0; i < texto.len(); i++ ) b.writen( texto[i], 'b' );
	f.writeblob( b ); f.close();
}
function lee() {
	local f = file( DAT, "rb" ); local n = f.len(); local b = f.readblob( n ); f.close();
	local t = ""; for ( local i = 0; i < n; i++ ) t += format( "%c", b[i] ); return t;
}

function cargar() {
	MOCK.reset( { senal = "custom2", fichero = DAT } );
	dofile( PLUGIN, true );
	return fe.plugin[ "Arranque" ];
}

local ORIGINAL = "# cabecera con una nota importante\n"
	+ "#   velocidad  0 = sin freno\n"
	+ "\n"
	+ "defecto velocidad=0 arranque=5\n"
	+ "\n"
	+ "# Medido: la placa termina en el frame 250\n"
	+ "pacman arranque=5\n"
	+ "mwalk nvram=0 arranque=10\n";

print( "\n1. lee los ajustes de un juego\n" );
{
	escribe( ORIGINAL );
	local p = cargar();
	local a = p.ajustes_de( "pacman" );
	igual( "un ajuste", a[ "arranque" ], "5" );
	igual( "y otro juego con dos", p.ajustes_de( "mwalk" )[ "nvram" ], "0" );
	igual( "el defecto tambien", p.ajustes_de( "defecto" )[ "velocidad" ], "0" );
	igual( "un juego sin linea da tabla vacia", p.ajustes_de( "dkong" ).len(), 0 );
}

print( "\n2. editar NO se lleva por delante los comentarios\n" );
{
	escribe( ORIGINAL );
	local p = cargar();
	p.guardar_ajustes( "pacman", { arranque = "9", velocidad = "2" } );

	local t = lee();
	ok( "la cabecera sigue", t.find( "cabecera con una nota importante" ) != null );
	ok( "el comentario del juego sigue", t.find( "Medido: la placa termina" ) != null );
	ok( "la linea de defecto sigue", t.find( "defecto velocidad=0 arranque=5" ) != null );
	ok( "y la de mwalk", t.find( "mwalk nvram=0 arranque=10" ) != null );
	ok( "pacman tiene lo nuevo", t.find( "arranque=9" ) != null );
	ok( "y ya no lo viejo", t.find( "pacman arranque=5" ) == null );
}

print( "\n3. un juego que no estaba se anade al final\n" );
{
	escribe( ORIGINAL );
	local p = cargar();
	p.guardar_ajustes( "dkong", { velocidad = "4" } );
	igual( "se lee de vuelta", p.ajustes_de( "dkong" )[ "velocidad" ], "4" );
	ok( "y no se toco pacman", p.ajustes_de( "pacman" )[ "arranque" ] == "5" );
}

print( "\n4. sin ajustes, la linea del juego desaparece\n" );
{
	escribe( ORIGINAL );
	local p = cargar();
	p.guardar_ajustes( "pacman", {} );
	igual( "pacman ya no tiene ajustes", p.ajustes_de( "pacman" ).len(), 0 );
	ok( "pero mwalk si", p.ajustes_de( "mwalk" ).len() == 2 );
	ok( "y los comentarios siguen", lee().find( "Medido: la placa termina" ) != null );
}

print( "\n5. una linea sin separador se ignora y se avisa\n" );
{
	escribe( "defecto velocidad=0\npacman?arranque=9\n" );
	local p = cargar();
	igual( "no se lee como pacman", p.ajustes_de( "pacman" ).len(), 0 );
	local avisado = false;
	foreach ( l in MOCK.logs ) if ( l.find( "sin separador" ) != null ) avisado = true;
	ok( "y queda avisado en el log", avisado );
}

print( "\n6. el menu edita el juego seleccionado\n" );
{
	escribe( ORIGINAL );
	local p = cargar();
	MOCK.juego = "dkong"; MOCK.titulo = "Donkey Kong";

	MOCK.elecciones = [ 0, 6 ];        // "Velocidad de carga", luego "Salir"
	MOCK.escrituras = [ "3" ];
	MOCK.senal( "custom2" );

	igual( "se guardo", p.ajustes_de( "dkong" )[ "velocidad" ], "3" );
	ok( "el titulo del menu nombra el juego",
		MOCK.menus[0].titulo.find( "dkong" ) != null, MOCK.menus[0].titulo );
	ok( "y ensena el valor actual antes de editar",
		MOCK.menus[0].opciones[0].find( "-" ) != null, MOCK.menus[0].opciones[0] );
}

print( "\n7. no se abre encima de un menu del frontend\n" );
{
	escribe( ORIGINAL );
	local p = cargar();
	fe.overlay.is_up = true;
	MOCK.senal( "custom2" );
	igual( "no se abrio ningun menu", MOCK.menus.len(), 0 );
	fe.overlay.is_up = false;
}

print( "\n=== arranque: " + pasadas + " ok, " + fallos + " fallos ===\n" );
try { remove( DAT ); } catch ( e ) {}
if ( fallos > 0 ) throw "hay fallos";
