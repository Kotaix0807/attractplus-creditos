# Frontend de los minijuegos de luces. Ver docs/minijuegos.md.
CFLAGS = -O2 -Wall $(shell pkg-config --cflags sdl2 SDL2_ttf SDL2_mixer SDL2_image)
LIBS   = $(shell pkg-config --libs sdl2 SDL2_ttf SDL2_mixer SDL2_image) -lm

minijuegos: main.c
	$(CC) $(CFLAGS) -o minijuegos main.c $(LIBS)

clean:
	rm -f minijuegos
