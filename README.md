# advancedreadermenu.koplugin

Un plugin para [KOReader](https://github.com/koreader/koreader) que rediseña el menú de resaltado (highlight), añade nuevos estilos de subrayado geométricos, "colores" para pantallas blanco y negro, y reorganiza varios menús contextuales (seleccionar, resaltar, subrayar, Assistant, WordReference) para dejarlos más compactos y basados en íconos.

Basado en [zzz-readermenuredesign.koplugin](https://github.com/kristianpennacchia/zzz-readermenuredesign.koplugin) de kristianpennacchia.

Hecho con vibecoding usando Google Antigravity.

## Funciones

### Menú de resaltado rediseñado
Sobrescribe `ReaderHighlight:onShowHighlightMenu` para reconstruir el diálogo de resaltado que aparece al seleccionar texto o al tocar un highlight existente:
- Reemplaza los botones de texto por íconos (`select`, `highlight`, `style`, `copy`, `add_note`, `pinnedelements_pin_text`, `wordreference`, `translate`, `ai_assistant`, `wikipedia`, `dictionary`, `search`).
- Ordena los botones "conocidos" en una primera fila fija y agrupa cualquier botón inyectado por otros plugins (no reconocido) en filas secundarias de máximo 2 columnas.
- El botón de resaltar (highlight) abre directamente el selector de "color" en vez de guardar con el "color" por defecto.
- El botón de estilo abre un selector visual de estilos de subrayado (ver abajo) en vez del menú de texto plano de KOReader.

### Nuevos estilos de resaltado
Ante la dificultad de distinguir colores en pantallas blanco y negro, se incluyen nuevos estilos o "colores": 3 tonos fácilmente diferenciables de gris (Oscuro, medio y claro), diseño de matriz punteada, con rayas horizontales, verticales o diagonales, con cuadrículas o rombos. La distancia de las líneas puede ser editada desde el archivo highlight_colors.lua a gusto del lector.

### Selector visual de estilos (`highlight_styles.lua`)
Diálogo tipo grid con botones cuadrados que muestran una vista previa en miniatura de cada estilo de resaltado disponible (lighten, invert, strikeout, underscore y los estilos "fancy" añadidos por el plugin). Se ajusta automáticamente al ancho de pantalla, calculando cuántos botones caben por fila y envolviendo a múltiples filas si es necesario. El botón seleccionado queda resaltado con un borde.

### Subrayados geométricos adicionales (`fancyunderlines_logic.lua`)
Inyecta nuevos estilos de resaltado en la tabla global de KOReader y parchea `ReaderView:drawHighlightRect` para dibujarlos:
- **Double underline** — doble línea inferior.
- **Dashed** — línea punteada larga.
- **Dotted** — línea punteada corta.
- **Zig-zag** — línea en zigzag.
- **Wave** — línea ondulada (seno).

Soporta tanto buffers de color 8-bit (con patrones B/N para e-ink) como RGB32, y respeta las marcas de nota (`note_mark`) del highlight original.

### Menús de diccionario y WordReference
`onDictButtonsReady` reordena y reduce a íconos los botones del popup de definiciones (vocabulario, navegación prev/next, highlight, wikipedia, wordreference, diccionario, traducir, buscar, cerrar), agrupándolos en filas lógicas. `onWordReferenceDefinitionButtonsReady` hace lo mismo para el popup de WordReference.

### Instalador de íconos
Al cargar, el plugin copia automáticamente los íconos incluidos en `resources/icons/mdlight` hacia la carpeta de íconos de KOReader (sin sobrescribir íconos ya personalizados por el usuario), para que los botones anteriores puedan mostrarse correctamente.

## Configuración

Desde el menú principal de KOReader: **Herramientas → Advanced Reader Menu**

- **Show Unknown Buttons In Reader Highlight Menu** — si está activo, los botones de highlight que el plugin no reconoce (agregados por otros plugins) se muestran en filas adicionales debajo de la fila principal. Si está desactivado, se ocultan.
- **Show Nav Buttons In Dict Quick Lookup** — muestra u oculta los botones de navegación anterior/siguiente en el popup rápido de diccionario.

## Flujo de trabajo típico

1. Seleccioná texto o mantén presionado sobre él → se abre el menú de resaltado con íconos.
2. Toca el ícono de resaltar para elegir color directamente, o el ícono de subrayado para abrir el selector visual de estilos (incluye los estilos geométricos nuevos).
3. Para editar un highlight ya existente, toca sobre él en la página y repite el mismo flujo — el plugin detecta que hay un `index` y edita la anotación en lugar de crear una nueva.
4. Los menús de diccionario y WordReference quedan reorganizados automáticamente sin acción adicional.

## Instalación

Puedes instalar el plugin de dos formas: buscándolo directamente en KOReader con [appstore.koplugin](https://github.com/omer-faruq/appstore.koplugin), o transfiriéndolo manualmente por Wi-Fi con [filebrowserplus.koplugin](https://github.com/patelneeraj/filebrowserplus.koplugin), o por USB.

### Opción A — Appstore (búsqueda dentro de KOReader)

1. Abre KOReader → **Tools → App Store**.
2. Elige la pestaña **Plugins**. Usá el diálogo de filtro para acotar por nombre.
3. Busca `AdvancedReaderMenu` o `advancedreadermenu`.
4. Toca la entrada para abrir el menú rápido de acciones. Elegí **Install** para descargar el ZIP del repositorio.
5. Reinicia KOReader.

### Opción B — FilebrowserPlus (transferencia por Wi-Fi)

1. Abre el menú superior de KOReader.
2. Asegúrate de que el dispositivo esté conectado a Wi-Fi.
3. Anda a **Gearbox Menu → Network → FilebrowserPlus**.
4. Cuando el servidor arranque, vas a ver una IP y un puerto. Entra a esa dirección (ej. `http://192.168.x.x:8080`) desde tu teléfono o computadora conectados a la misma red Wi-Fi.
5. Opcionalmente puedes cambiar la contraseña o crear nuevos usuarios desde la interfaz web de Filebrowser.
6. Navega hasta la carpeta donde descargaste el plugin en el otro dispositivo.
7. Copia la carpeta `advancedreadermenu.koplugin/` a: `/mnt/us/koreader/plugins/`

### Opción C — USB

1. Conecta el Kindle a la computadora por USB.
2. Copia la carpeta `advancedreadermenu.koplugin/` a: `koreader/plugins/` dentro del almacenamiento del dispositivo.
3. Desconecta el USB de forma segura y reiniciá KOReader.

## Advertencia
- Fue probado exclusivamente en dispositivo Kindle Paperwhite 10 jailbreakeado.


## Créditos
Basado en [zzz-readermenuredesign.koplugin](https://github.com/kristianpennacchia/zzz-readermenuredesign.koplugin) de [kristianpennacchia](https://github.com/kristianpennacchia).
