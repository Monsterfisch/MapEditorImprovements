# Map Editor Improvements

**Autores**: Monsterfish, Heroesflorian
**Versión**: 1.0.65

Hace que el editor de mapas muestre más información sobre el mapa en el que trabajas y añade herramientas que le faltaban: fases de crecimiento de árboles, manzanos, más arbustos, árboles talados, grava y hierro, variantes de rocas, tamaños de manadas y mucho más. Cada función puede desactivarse en los ajustes.

## Contadores del mapa

En el editor de terreno:

- **Descripciones emergentes en los botones de categoría.** Apunta a un botón para ver cuántos elementos tiene el mapa frente al límite del juego:
  - **Animales:** animales y unidades frente al límite real (2499, o 9999 en Extreme), manadas y grupos —cada manada y cada grupo de tropas ocupa uno de su límite propio de 1249— y aves: cuervos (marcas en árboles, sin límite propio) y gaviotas (máximo 99).
  - **Vegetación:** árboles y arbustos. Todas las plantas comparten un límite de 1999.
  - **Rocas:** rocas.
- **Menú Animales:** los botones de ciervo, camello, conejo y león muestran cuántos hay de cada animal.
- **Menú Vegetación:** cada botón de árbol y arbusto muestra cuántos ejemplares hay en el mapa.

Un botón rojo **«i»** sobre el botón de la llave oculta o vuelve a mostrar todo esto. Los ajustes deciden si empieza visible u oculto. La línea descriptiva de los botones se desplaza un poco a la derecha para hacerle sitio.

## Árboles y arbustos

Los árboles del menú Vegetación se ordenan según el terreno en el que se propagan: primero los tres de terreno fértil (hierba de oasis, matorral denso y ligero) con un fino borde verde, y después el de terreno árido (tierra, tierra pedregosa, dunas) con un fino borde beige.

- **Fase de crecimiento según el tamaño del pincel.** Con un árbol elegido, el tamaño del pincel decide su tamaño:

  | Pincel | Árbol |
  |---|---|
  | 1 a 3 | árboles jóvenes, de menor a mayor |
  | 4 | adulto (lo que el editor colocaba siempre) |
  | 5 | adulto; los leñadores lo dejan en paz hasta que vuelve a ser un árbol normal |
  | 6 | árbol muerto |
  | 7 | árbol muerto que desaparece antes |

  Los arbustos salen siempre igual.
- **Botón de manzano** en el menú Vegetación (en la línea descriptiva aparece «Apple tree», en alemán «Apfelbaum»).
- **Más arbustos.** Al elegir el arbusto de cinco colores, una fila sobre el menú Vegetación ofrece los cinco.
- **Árboles talados.** Al elegir un árbol, una fila encima lo muestra en pie y luego talado con cada número posible de troncos (9 a 1 en árboles adultos, menos en pequeños, ninguno en muertos; los más pequeños caen con 1 tronco). Haz clic en uno para colocar árboles talados; haz clic de nuevo en él, en el árbol en pie o en el menú para volver a árboles en pie.
- **Mezclas aleatorias.** Las filas sobre el menú Vegetación añaden botones «?»:
  - **Árbol aleatorio** (primero en la fila de talados): mezcla aleatoria desde la fase menor hasta la del pincel (no en pincel 1 ni árboles muertos).
  - **Árbol talado aleatorio** (último en la fila de talados): número aleatorio de troncos de 1 al máximo del árbol.
  - **Arbusto aleatorio** (último en la fila de arbustos): mezcla aleatoria de los cinco colores.

  Vuelve a pulsar o elige otro botón para detener la mezcla.
- **Árboles junto a obstáculos.** Casilla al final de la fila superior para plantar árboles justo junto a edificios, rocas, muros y otros árboles (los arbustos ya podían). Apunta a ella para ver si está activa.
- **Filas ordenadas.** Arriba los árboles (con manzano y casilla); el arbusto que estaba allí baja con los demás arbustos ordenados.
- **Vista previa de árbol.** Muestra en la casilla bajo el ratón el árbol exacto que se plantará, en su fase o talado —también para el cuentagotas. No se muestra con zoom alejado ni en casillas no válidas; sigue visible con el menú oculto (Tab).
- **Sin apilamiento de arbustos.** Impide poner una planta sobre una casilla que ya tiene otra y permite al borrador limpiar todos los arbustos apilados de mapas antiguos.

La fila sobre el menú Vegetación flota sobre el mapa y hacer clic en ella no coloca nada en el mapa.

## Texturas de terreno

El menú Texturas añade **Grava** al final de la fila superior y **Hierro** al final de la inferior (el mismo hierro que en Alturas), repartiendo ambas filas uniformemente. Con el hierro en Texturas se puede ocultar el del menú Alturas (ajuste).

**Máscara.** Botón (cuadrado medio relleno) arriba a la izquierda del editor de terreno. Activa, las herramientas naturales (alturas, texturas, agua, vegetación, rocas y cuentagotas) solo modifican casillas con la misma textura que la primera clicada. Al soltar el ratón, el siguiente clic elige una nueva textura.

## Agua

Recupera dos adornos de río del editor del primer Stronghold:

- **Espuma:** agua blanca y rocío como bajo una cascada, en cada casilla de río bajo el pincel. También puede ir sobre mar, convirtiéndolo en río con espuma (ajuste).
- **Olas pequeñas:** en la casilla de río bajo el ratón.

Ambos solo van en río y se guardan en el mapa (véase `docs/river-decorations.md` en el repositorio).

## Rocas

- **Poste indicador en mapas de escaramuza.** Reciben el mismo menú Rocas que los escenarios.
- **Rotación aleatoria en la vista previa.** Gira una vez por segundo en lugar de cada fotograma, mostrando exactamente la roca que se colocará.
- **Fila de variantes.** Muestra las cuatro variantes del tamaño elegido orientadas como se colocarán. Haz clic para fijar una; vuelve a clicar o pulsa cualquier botón de Rocas para volver a alternarlas.
- **Rocas invisibles.** Casilla a la derecha del menú Rocas que coloca rocas invisibles al instante (truco de las «2k piedras») sin poner antes 4000 rocas; se guardan normalmente.
- **Borrar rocas invisibles.** El borrador las elimina igual que las rocas normales, sin truco del arbusto.
- **Roca pequeña adicional.** Quinta variante para las rocas más pequeñas, presente en el juego pero inédita en el editor; se guarda normalmente.
- **Eliminar rocas perdidas.** Botón abajo a la derecha que retira de la lista rocas rotas y cubiertas por arbustos sin casillas restantes que ocupaban plazas de las 4000; su descripción indica cuántas hay.

## Alturas

- **Altura máxima.** Vuelve la herramienta del primer Stronghold a la derecha de Altura mínima: fija la altura en 156 bajo el pincel.
- **Opciones de herramientas de altura.** Panel sobre el menú Alturas (de abajo arriba):
  - **Restablecer texturas de terreno** (desactivado al inicio): si restauran la textura básica (y tierra en mesetas). Desactivado, solo cambian altura.
  - **Romper casillas de roca** (desactivado al inicio): si subir, bajar, igualar, colina y montaña rompen rocas tocadas. Desactivado, quedan intactas.
  - **Ignorar agua** e **Ignorar tierra fértil** (desactivados al inicio): dejan intactas las casillas de agua/foso o de matorral/oasis.
  - Para subir, bajar e igualar: **Ajustar al rango** (activado al inicio), **Invertir** (solo igualar: vuelve rugoso el terreno y crea bultos aleatorios en plano; mantener Ctrl hace lo mismo, configurable), **rango de altura** (deslizador doble, 8–156 inicial, de 0 a 255) e **intensidad** (7 es la velocidad del juego en igualar).
  - **Cambio de altura de rocas** (Roca entera al inicio): *Solo casilla*, *Roca entera* o *Borrar roca* (como Altura mínima).
  El rango, Ajustar al rango, Invertir e ignorar se restablecen al salir del editor. Subir y bajar ya no dan la vuelta al llegar al mínimo o máximo.

## Modo castillo

En el menú de construcción del modo castillo:

- **Contadores de edificios** sobre el minimapa: total del mapa frente al límite, total de edificios de todos los jugadores y los del jugador actual.
- **Ruinas de torres.** Fila sobre el menú Torres con las ruinas de las cinco torres.
- **Entrada de túnel y tiendas de asedio.** En edificios militares: entrada de túnel con el gremio de zapadores y las seis tiendas de asedio con el gremio de ingenieros.
- **Estatua y santuarios.** Estatua 2×2, santuario 2×2 y santuario 1×1 sin usar, al final de sus variantes o sobre el menú de cosas buenas.
- **Variantes de edificios.** Jardín (2×2, 3×3, 4×4), estatua, santuario, pozo negro y choza muestran todas sus variantes fijas en una fila superior.
- **Varias fortalezas.** Colocar una nueva ya no borra la anterior (ni su hoguera); la más reciente es la activa y las demás permanecen.
- **Varios edificios de almacén y reclutamiento.** Cuarteles, campamentos, gremios y demás edificios únicos ya no se borran, y almacenes, graneros y arsenales extra pueden ir en cualquier sitio y quedar vacíos sin límite (antes 8 graneros/arsenales y 32 almacenes vacíos por jugador).
- **Mangoneles y balistas de torre en cualquier lugar.** En cualquier casilla libre sin unidad (suelo, muros, puertas, cualquier torre o fortaleza); en torres propias cuadradas y redondas funcionan igual que antes.
- **Fortaleza sin hoguera ni almacén.** **Solo fortaleza** y **Sin almacén** con vista previa y comprobación de espacio adaptadas.
- **Muros dañados.** Modo **Dañado** para escaleras, muro bajo, muro alto y almenas conservando su altura.
- **Catedral en ruinas.** Modo **En ruinas** (gráfico de la misión «Kerak»); en partida funciona normalmente y el cuentagotas conserva el aspecto. Necesita `gm/tile_churches.gm1` original.
- **Foso excavado, planificado y permanente.** Modos **Excavado**, **Planificado** y **Permanente** (imposible de rellenar o borrar en partida) sobre el menú de puertas.
- **Foso sobre pantano.** El pantano permanece debajo y reaparece si el foso se rellena.
- **Quitar foso conserva el terreno.** Solo altera casillas con foso, devolviendo la altura sin borrar la textura.
- **Nombres de edificios más a la izquierda.** Desplazados 100 píxeles a la izquierda para despejar los contadores.
- **Barrera.** Barrera 1×1 borrable abajo a la derecha del menú Ruinas.

## Manadas

Con ciervo, león, conejo o camello seleccionado, un panel sobre Animales muestra el tamaño de manada (fijo + aleatorio) y el comportamiento grupal. Su casilla ajusta el tamaño al pincel: 2 × tamaño del pincel − 1 animales (1 con pincel 1; 13 con pincel 7).

Botones rojos de papelera en Animales: **Borrar todos los cuervos** (los árboles quedan), **Borrar todas las gaviotas** y **Borrar todos los animales** (como Alt + E; las aves quedan).

Si quedan menos de 200 manadas y grupos disponibles, una línea superior avisa cuántos faltan.

## Borrador

También borra las gaviotas sobre las casillas borradas. Un panel encima elige qué borrar:

- **Todo** – todo, como antes.
- **Animales** – animales, cuervos (los árboles quedan) y gaviotas.
- **Unidades** – todas las demás unidades.
- **Edificios** – edificios, fortalezas, ruinas y muros.
- **Vegetación** – árboles y arbustos.
- **Rocas** – rocas, incluidas las invisibles.

## Ajustes del mapa

- **Mostrar mapas bloqueados:** casilla en Cargar del editor para listar también mapas bloqueados.
- **Botón Ajustes del mapa** en la pantalla de menú del mapa (junto a Guardar y Salir), a la derecha de Equilibrado / Desequilibrado o Invasión / Economía. Abre el menú Alt + ,.
- **Menú Ajustes del mapa ampliado:** título, Un jugador y Multijugador; en Un jugador Asedio, Invasión, Económico y Construcción libre; en Multijugador tamaños 160, 200, 300, 400, Personalizado y deslizador de 10 a 400 (aplica al soltar); Equilibrado y Rey de la colina; Bloquear mapa; Atrás (Esc y Alt + , también cierran). Todo seguía en el código del juego y solo faltaban los botones. Bloquear mapa activa el bloqueo «Misión», que mantiene el mapa en la lista de escaramuzas y lo oculta en Cargar salvo que esté marcada «Mostrar mapas bloqueados».

## Imágenes

Los botones de manzano y grava usan los archivos de la carpeta `images` del módulo: `apple.png`, `apple_hover.png`, `apple_selected.png` y `gravel.png`, `gravel_hover.png`, `gravel_selected.png` (normal, al pasar el ratón, seleccionado). Puedes reemplazarlos por los tuyos.

## Pinceles

Los pinceles del juego cuentan dos veces la casilla bajo el ratón y omiten la esquina superior izquierda. Con este ajuste cada pincel tiene su forma completa.

## Deshacer y rehacer

Dos flechas arriba a la izquierda (en los menús de terreno y castillo): deshacen y rehacen hasta 20 pasos. Cada clic y cada trazo mantenido cuentan como un paso; los clics sin cambios no generan paso. Hacer algo nuevo tras deshacer descarta los pasos de rehacer y cargar otro mapa reinicia el historial.

## Cuentagotas

Situado en la columna izquierda del editor de terreno, sobre el tamaño del pincel. Muestra la fila **Alturas**, **Texturas**, **Objetos**, **Todo** y lo que contiene.

- **Tomar:** haz clic en una casilla.
- **Aplicar:** haz clic o arrastra; Alturas deja intacta la textura y Texturas las alturas.
- **Objetos:** toma un edificio, muro, árbol o roca. Edificios y muros se colocan como con su botón y para su jugador original (se elige su escudo); árboles y rocas como con sus herramientas, con arrastre, vista previa y comprobaciones. Al salir vuelven el pincel, la rotación y el modo talado anteriores.
- **Todo** toma también un árbol o roca 1×1 y lo coloca en cada casilla libre bajo el pincel.
- No aplica alturas a mar, playa, pantano, foso, rocas, muros ni edificios; ni texturas a rocas, muros o edificios. Las rocas de acantilado se limpian y recrean en bordes empinados. Mantener **Alt** fuerza alturas y texturas en todas las casillas (las rocas permanecen; experimental).
- Elegir de nuevo el cuentagotas o un modo lo vacía. **P** lo selecciona y cambia de modo; mantener **Ctrl** toma una nueva casilla sin vaciar el modo y al soltar vuelve a aplicar. Las tres teclas son configurables o desactivables.
- Deshacer también revierte trazos del cuentagotas.

## Mantener el menú siempre actualizado

El juego solo redibuja el menú cuando el ratón está encima. Con este ajuste el menú se actualiza continuamente en el editor de mapas sin cambiar nada fuera de él.

## Cuadrícula de recursos

Dibuja sobre el mapa la cuadrícula que usa la IA al buscar emplazamientos para sus canteras,
minas de hierro, pozos de brea y leñadores: bloques de 5 × 5 casillas. Una veta de piedra dentro
de un solo bloque vale más para la IA que la misma veta repartida entre cuatro. También dibuja
las cuatro líneas donde el diseño del castillo de la IA gira según la posición de la fortaleza,
y en cada bloque las casillas que cubriría una mina de hierro de la IA.

- **Alt + G** la muestra u oculta en el editor de mapas. Se puede elegir otra combinación de
  Alt + tecla en los ajustes, o cambiar el atajo en Custom Hotkeys.
- Por defecto solo se muestra en la vista plana (barra espaciadora), donde las líneas quedan
  exactamente sobre el suelo, y se oculta en la vista de la tecla V.
- **Permitir la cuadrícula durante partidas** te permite comprobar las líneas en una partida de
  prueba.
- Se pueden cambiar los colores de la cuadrícula, los límites y la superficie de la mina.
- No se guarda nada en el mapa.

## Conviene saber

- Funciona con Stronghold Crusader y Stronghold Crusader Extreme. Los límites se leen del juego, así que Extreme muestra su límite superior de unidades.
- Árboles, arbustos y rocas se cuentan por las plazas que ocupan en las listas del juego; una pila de arbustos cuenta cada arbusto.
- No guarda nada extra en el mapa.
