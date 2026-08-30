// Interprete Squirrel minimo, solo para poder EJECUTAR el plugin contra una
// maqueta de la API de Attract-Mode Plus. Usa las mismas fuentes de Squirrel
// 3.0.7 que compila AM+ (extlibs/squirrel) y las mismas librerias estandar
// que registra src/fe_vm.cpp:631-635.
#include <squirrel.h>
#include <sqstdio.h>
#include <sqstdblob.h>
#include <sqstdmath.h>
#include <sqstdstring.h>
#include <sqstdsystem.h>
#include <sqstdaux.h>
#include <cstdio>
#include <cstdarg>

static void print_fn( HSQUIRRELVM, const SQChar *s, ... )
{
	va_list a; va_start( a, s ); vfprintf( stdout, s, a ); va_end( a );
}

static void error_fn( HSQUIRRELVM, const SQChar *s, ... )
{
	va_list a; va_start( a, s ); vfprintf( stderr, s, a ); va_end( a );
}

int main( int argc, char **argv )
{
	if ( argc < 2 ) { fprintf( stderr, "uso: sqhost fichero.nut\n" ); return 2; }

	HSQUIRRELVM v = sq_open( 2048 );
	sq_setprintfunc( v, print_fn, error_fn );
	sq_pushroottable( v );

	sqstd_register_bloblib( v );
	sqstd_register_iolib( v );
	sqstd_register_mathlib( v );
	sqstd_register_stringlib( v );
	sqstd_register_systemlib( v );
	sqstd_seterrorhandlers( v );

	int rc = 0;
	if ( SQ_FAILED( sqstd_dofile( v, argv[1], SQFalse, SQTrue ) ) )
	{
		fprintf( stderr, "\n*** el script fallo\n" );
		rc = 1;
	}

	sq_close( v );
	return rc;
}
