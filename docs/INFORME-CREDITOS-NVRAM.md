# Créditos que sobreviven en la NVRAM — informe

Medido en la cabina el 2026-09-12. **Todo lo que dice «arranca con N» se vio en
pantalla**, arrancando cada juego con su NVRAM real y capturando tres instantes
(18, 30 y 45 s), porque el rótulo de créditos suele ir dentro de un texto que
rota.

## Resumen

De **104 juegos instalados**, 62 tienen NVRAM escrita. De ésos, **cinco arrancan
con créditos** y **uno arrancaba en el menú de servicio**:

| juego | qué pasaba | estado |
|---|---|---|
| `robotron` | arranca con **2 créditos** | **ARREGLADO** — dirección `9851` |
| `defender` | arranca con **2 créditos** | **ARREGLADO** — dirección `a037` |
| `mk` | arrancaba en el **TEST MENU** | **ARREGLADO** — DIP Service Mode |
| `tron` | arranca con **9 créditos** | **ARREGLADO** — dirección `c501` |
| `joust` | arranca con **1 crédito** | **ARREGLADO** — dirección `a0f2` |
| `berzerk` | arranca con **6 créditos** | **ARREGLADO** — con `nvram=0` |

## Lo arreglado, y cómo

**`robotron` y `defender`.** No hizo falta `nvram=0`: se localizó su contador de
créditos y ahora el barrido de `creditos.lua` los limpia al arrancar, dejando
intactas las puntuaciones. Las dos direcciones están **verificadas ejecutando**:

- `defender @:maincpu,program,a037` — marcaba 2 (los créditos que se veían) y
  sube 2→3→4→5 con cada moneda. Estaba en `creditos.dat` importada de la
  colección de cheats y marcada `(cheat)`; ascendida.
- `robotron @:maincpu,program,9851` — no estaba. Escribirle 0 deja la pantalla
  en `CREDITS: 0`, que es la prueba que decide.

**`mk` no era un problema de créditos.** Su `.cfg` tenía el DIP `Service Mode`
encendido (`:IN1 mask=16 value=0`, donde `Off` es 16), así que arrancaba en el
menú de test y no era jugable. Puesto a Off; MAME quitó la línea del `.cfg` él
solo al coincidir con fábrica. Verificado: ya sale su tabla de récords y entra a
la demo. **Es el mismo fallo que el Rack Test de Ms. Pac-Man**, y se enciende
igual de fácil con un F1 despistado.

## Los tres que faltaban (resueltos el 2026-09-12)

**`joust` → `a0f2`** y **`tron` → `c501`**, las dos verificadas en pantalla. La
técnica que las sacó fue la **búsqueda diferencial**: foto de toda la RAM, una
moneda, quedarse con los bytes que suben 1, otra moneda, intersectar. No supone
ningún valor, que es donde había fallado antes — busqué `berzerk` anclado en 6
créditos cuando mis propias pruebas ya lo habían dejado en 12.

Dos trampas que costaron una pasada cada una:

- **El marcador NO se repinta al escribir en la RAM.** Escribir 0 en la
  dirección buena dejaba la pantalla igual, y parecía que la dirección era
  falsa. Estas placas redibujan el número sólo cuando cambia. La prueba que sí
  vale es **escribir 0 y meter UNA moneda**: si la dirección era la buena, la
  pantalla pasa a 1.
- **Tron no admitía monedas porque estaba en su tope de 9.** No era el ancho del
  pulso (probado con 30 frames). Se resolvió buscando a la baja, con START, que
  sí gasta un crédito. Y ahí mordió otra trampa ya documentada: **un solo
  START** — con la partida en marcha el segundo no gasta nada.

**`berzerk` se arregla con `nvram=0`, y es el único de los cinco.** Su contador
no se pudo localizar: `8a3` sube con cada moneda pero no es el almacén
(escribirle 0 y reiniciar deja los créditos puestos). Aquí `nvram=0` sí vale, y
está medido en las dos direcciones:

- arranca **limpio, con 0 créditos**, sin el `FACTORY SETTINGS RESTORED` que sí
  bloquea a Joust;
- y está en `hiscore.dat`, así que **sus puntuaciones se guardan aparte** en su
  `.hi` y no se pierden.

Como `nvram=0` evita **guardar** y no **cargar**, hubo que borrarle la NVRAM
vieja una vez.

> **Por qué NO se usó `nvram=0` en los otros cuatro:** arrancando `joust` con la
> NVRAM borrada, la pantalla se queda en **`FACTORY SETTINGS RESTORED`** a los
> 18 y a los 45 segundos. Cambiaríamos «arranca con créditos» por «no entra al
> juego».

## Lo que NO hay que configurar a mano

Comprobado uno a uno, **estos juegos no arrancan con créditos** aunque tengan
NVRAM escrita. No hace falta tocar su modo servicio:

`19xxu` `arkanoid` `atetris` `avsp` `btoads` `centiped` `digdug` `doubledr`
`elevator` `fatfury1` `gaunt2` `gaunt22p` `gauntlet` `gauntlet2p` `goldnaxe`
`kof97` `kof98` `kof99` `kof2000` `mario` `megaman2` `mk2` `mk3` `mslug`
`mslug2` `mslug3` `mvsc` `mwalk` `ncv2` `outrun` `polepos` `punchout` `qbert`
`rampage` `rbtapper` `samsho` `samsho2` `samsho3` `samsho4` `samsho5`
`simpsons2p` `ssf2t` `ssriders` `starwars` `strhoop` `tapper` `tekken`
`tekken2`

**Mortal Kombat II y 3 están entre ellos**: meter monedas no cambia ni un byte
de su NVRAM, y arrancan sin créditos. El que daba problemas era sólo el primero,
y por el DIP de servicio, no por la NVRAM.

## Dos avisos sobre el método

**Mis dos primeras pruebas eran inválidas y las tiré.** Metían monedas simuladas
y comparaban la NVRAM; daban un resultado limpio y equivocado. Lo destapó que
`mwalk` salía como «no guarda créditos» cuando está documentado que arranca con
`CREDITS 6`: **las monedas no llegaban a entrar**, ni a los 20 s ni a los 45.

Y la causa de que fallaran en las Williams es interesante: el barrido **les
borraba la NVRAM antes de probar**, y sin NVRAM válida esas placas se quedan en
`FACTORY SETTINGS RESTORED` sin aceptar monedas. Con su NVRAM real, las monedas
entran perfectamente — así se verificó `defender`.

> **Regla:** para saber si un juego arranca con créditos, arráncalo **con la
> NVRAM que tiene** y mira la pantalla. Simular monedas mide otra cosa.
