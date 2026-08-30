// juega.nut - banco de pruebas para trastear con Squirrel.
//
//   cd /home/eloy/groovyarcade-creditos/pruebas
//   ./sqhost juega.nut
//
// Esto NO es AM+: no hay fe.log ni fe.add_text. Sirve para el lenguaje puro:
// leer ficheros, partir cadenas, tablas, bucles. Cuando algo funcione aqui,
// lo llevas al plugin cambiando print() por fe.log().

// --- 1. imprimir ---
print("hola\n");                       // el \n es obligatorio, print no lo pone
print("un numero: " + 42 + "\n");
print(format("con formato: %d de %d\n", 3, 10));

// --- 2. leer un fichero entero como texto ---
function leer_texto( ruta )
{
    local f = file( ruta, "rb" );
    local n = f.len();
    local b = f.readblob( n );
    f.close();

    local texto = "";
    for ( local i = 0; i < n; i++ )
        texto += format( "%c", b[i] );

    return texto;
}

// --- 3. partirlo en lineas y en trozos ---
local ruta = "../arranque.dat";
local ajustes = {};

foreach ( linea in split( leer_texto( ruta ), "\n" ) )
{
    linea = strip( linea );

    // fuera comentarios y lineas vacias
    local almohadilla = linea.find( "#" );

    if ( almohadilla != null ) 
        linea = strip( linea.slice( 0, almohadilla ) );
    
    if ( linea.len() == 0 ) 
        continue;

    local trozos = split( linea, " \t" );
    local juego = trozos[0];
    local suyos = {};

    for ( local i = 1; i < trozos.len(); i++ )
    {
        local par = split( trozos[i], "=" );
        if ( par.len() == 2 )
            suyos[ par[0] ] <- par[1];
    }

    ajustes[ juego ] <- suyos;
}

// --- 4. mirar lo que salio ---
foreach ( juego, suyos in ajustes )
{
    print( juego + ":" );
    foreach ( clave, valor in suyos )
        print( "  " + clave + "=" + valor );
    print( "\n" );
}

print( "\npacman arranca en " + ajustes["pacman"]["arranque"] + " segundos\n" );
