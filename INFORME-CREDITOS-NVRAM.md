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
| `tron` | arranca con **9 créditos** | pendiente, ver abajo |
| `berzerk` | arranca con **6 créditos** | pendiente |
| `joust` | arranca con **1 crédito** | pendiente |

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

## Lo que queda, y por qué no vale `nvram=0`

La salida obvia sería `nvram=0`, pero **está medida y no sirve para las Williams**:

> Arrancando `joust` con la NVRAM borrada, la pantalla se queda en
> **`FACTORY SETTINGS RESTORED`** a los 18 y a los 45 segundos. Cambiaríamos
> «arranca con créditos» por «arranca con un aviso y no entra al juego».

| juego | por qué sigue pendiente |
|---|---|
| `joust` | se encontró un byte que sube con las monedas (`a0f2`) pero **no es el que pinta**: escribirle 0 deja la pantalla en `CREDITS 4`. Hay otra copia |
| `berzerk` | su dirección de `creditos.dat` (`8a4`) es **falsa**: se queda en 0 teniendo 6 créditos en pantalla. Y el barrido anclado no encontró ninguna que suba |
| `tron` | tampoco se encontró. **Pero aquí `nvram=0` SÍ arranca limpio**, con `CREDITS 0` y su atracción normal — a cambio de perder sus puntuaciones, porque no está en `hiscore.dat` |

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
