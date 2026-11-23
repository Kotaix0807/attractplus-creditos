# Minijuegos del panel de luces (SDL2). Ver docs/minijuegos.md. En la cabina: make
CFLAGS = -O2 -Wall $(shell pkg-config --cflags sdl2 SDL2_ttf SDL2_mixer SDL2_image)
LIBS   = $(shell pkg-config --libs sdl2 SDL2_ttf SDL2_mixer SDL2_image) -lm

# El que corre en la cabina.
minijuegos: main.c
	$(CC) $(CFLAGS) -o minijuegos main.c $(LIBS)

# La reescritura de Eloy (propio.c), aparte para no pisar el binario de la cabina
# mientras no este terminada:  make propio
propio: propio.c
	$(CC) $(CFLAGS) -o propio propio.c $(LIBS)

clean:
	rm -f minijuegos propio
