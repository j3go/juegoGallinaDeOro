# Golden Chicken

Juego 3D en Godot 4.7 (GDScript) basado en `diseno_granja_huevos_dorados_v0_1.pdf`. Seis jugadores (vos y cinco rivales) compiten por huevos de oro en **Noche en la Granja**. La gallina anda suelta por el mapa y **le dispara al que lleve más huevos**. Gana quien conserve más huevos al terminar los 3 minutos.

## Reglas (diseño v0.1)
- **La gallina** elige al líder al empezar cada ataque (con empate, incluido el 0 a 0, alterna en un orden fijo). Lo sigue con un **láser** que solo avisa, lo **fija** un instante (destello y pitido) y dispara un huevo por el culo, doblada con las patas arriba, con retroceso y gas. El huevo vuela recto y golpea al **primer** personaje que encuentre, aunque no sea el objetivo. Si choca o termina su recorrido, cae como huevo recogible.
- **Entre ataques** la gallina recorre todo el mapa: camina, corre como loca (zigzag, cambios bruscos de velocidad, polvo y gritos) o se queda picoteando, a veces **vuela** de punta a punta del mapa (y puede soltar un huevo bomba a mitad de vuelo), y cada tanto **se teletransporta** a otro punto con un rayo de luz. Se configura en el grupo *Gallina* de `default_config.tres` (`roam_*`, `teleport_interval_*`).
- **Huevos especiales:** algunos ataques disparan un **huevo explosivo** (láser naranja, "¡HUEVO BOMBA!"): al chocar explota y derriba a todos en `explosion_radius` (2,6 m), haciéndoles soltar huevos. Otros disparan un **huevo loco** (láser violeta, "¡HUEVO LOCO!"): más lento, cambia de rumbo al azar y no sigue la línea del láser. Probabilidades en `explosive_egg_chance` y `erratic_egg_chance`; el vuelo en `fly_*`.
- **Impacto de huevo:** derriba y hace soltar los huevos, que se reparten por el suelo. El derribado se levanta solo y queda un rato protegido (parpadea): no actúa y los impactos no le quitan más.
- **Recoger (E):** hay que apretar al lado del huevo; pasar por encima no lo recoge. No se puede recoger mientras agarrás o te agarran, ni siquiera con inmortalidad.
- **Empujar (F o clic izquierdo):** empujón frontal corto con enfriamiento. No hace soltar huevos. Sirve para meter a un rival en el láser.
- **Agarrar (G o clic derecho):** el agarre dura 3 s y el siguiente se puede iniciar 13 s después de empezar el anterior. Los agarres forman **cadenas**: quien agarra tira con fuerza 1 hacia donde se mueve y el agarrado solo resiste con fuerza 0,3 (`grabbed_pull_weight`), así que podés arrastrarlo aunque tire para el otro lado. Al agarrar, los dos quedan trabados forcejeando y, si gana quien agarra, levanta al otro. **Cuando el agarre termina por tiempo**, el agarrado sale despedido y queda mareado en el piso `grab_throw_stun` segundos (1,1 s; no se mueve ni actúa, pero no pierde huevos; la inmortalidad lo evita). Las fuerzas iguales y opuestas se anulan y las de igual sentido se suman (hasta una velocidad máxima).
- **Objetos (Q para usar):** cada 30 s aparece una oleada en el mapa. El **kunai** se lanza hacia donde mira la cámara y hace soltar huevos. La **inmortalidad** dura 5 s y evita derribos y pérdidas (igual te pueden empujar y agarrar). Se lleva un objeto por vez.

## Cómo jugar
`godot --path .` o F5 en el editor. WASD mover, Shift correr, Espacio saltar, mouse cámara, Esc liberar el mouse.

## Ajustes
- `assets/config/default_config.tres` (script `scripts/resources/game_config.gd`): duración, cadencia y velocidad de la gallina, pérdida por impacto, empujón, agarre (3 s / 10 s), fuerza de las cadenas, oleadas de objetos, kunai e inmortalidad.
- `assets/config/npc_*.tres`: disfraz (`costume`), color y personalidad de cada rival (velocidad, radio de detección, oído, reacción, errores).

## Estructura
- `scenes/`: `main.tscn`, `world/night_farm.tscn` (usa `scripts/level.gd` + `scripts/visual/night_props.gd` y tiene marcadores `Spawns/`), `characters/` (player, npc, chicken), `items/golden_egg.tscn`, `ui/` (menú, HUD, resultados).
- `scripts/`: lógica (`game_manager`, `egg_manager`, `player_controller`, `npc_ai`, `chicken_ai`, `golden_egg`, `hud`…).
- Para agregar otro mapa: creá una escena como `night_farm.tscn` y sumala a `LEVELS` en `scripts/game_manager.gd` (con más de un mapa, el menú muestra el selector).
- `scripts/visual/`: modelos procedurales (`@tool`, se ven en el editor), escenario y efectos. Los personajes (`human_model.gd`) siguen `personajes.png`: Gallina (vos), Cono (Tomás), Pez (Lila) y Conejo (Rosa).
- El navmesh se genera al iniciar a partir de los colliders del escenario.

## Pruebas automáticas
`godot --headless --path . -- --autotest --duration=30 --timescale=4` juega una partida sin intervención y muestra el estado de la IA y las puntuaciones en consola. Otras opciones: `--mechanics-test` (comprueba las reglas del diseño), `--collision-audit` (revisa colisiones y aberturas), `--walk-test` (hace caminar al jugador por el mapa), `--cam=x,y,z,tx,ty,tz`, `--walk`, `--screenshot=archivo.png --shot-delay=8`, `--overview`, `--chicken-cam`, `--show-menu` (ver `scripts/debug/dev_tools.gd`).
