# Hallazgos

Bitácora de lo que se descubrió en cada fase. Lo más reciente se agrega al final de cada sección.

Entorno de las pruebas: macOS 27.0.1, Xcode 27.0, Swift 6.4, MacBook Pro (pantalla Retina integrada).

---

## Fase 0: Prueba de concepto (16-oct-2026)

Código: [`PoC/`](../PoC). Instrucciones para la prueba manual: [`PoC/README.md`](../PoC/README.md).

### Resumen

| # | Riesgo | Resultado | Cómo se verificó |
|---|---|---|---|
| 1 | Leer el portapapeles continuamente | ✅ Funciona sin diálogos | Automático (pbcopy + imagen PNG) |
| 2 | Panel encima de todo sin quitar el foco | ✅ Funciona | Automático (lista de ventanas + capturas) |
| 3 | Pegar directo con ⌘V simulado | ⏳ Falta la prueba manual | Requiere que tú des el permiso de Accesibilidad |
| 4 | ⌘⇧V como atajo global | ✅ Funciona, ⚠️ choca con Paste | Automático (evento simulado) |
| 5 | La firma mantiene los permisos al recompilar | ✅ Firma estable | `codesign -d -r-` |

Conclusión provisional: **no hay ningún bloqueo**. El único punto que queda abierto (pegar directo) es la técnica que usan todos los gestores de portapapeles, incluido Paste, así que el riesgo es bajo. Seguí con las fases siguientes en paralelo.

### 1. Portapapeles

- `NSPasteboard.general.changeCount` revisado cada 0,5 s detecta cada copia. Leer el texto toma ~0,3 ms.
- **Privacidad del portapapeles (macOS 15.4+):** el SDK expone `NSPasteboard.accessBehavior` con 4 estados: `default`, `ask`, `alwaysAllow`, `alwaysDeny`. Según el header:
  - Una app que nunca disparó la alerta está en `default`; la primera lectura programática muestra la alerta y pasa a `ask`.
  - Desde ese momento aparece en *Ajustes del Sistema → Privacidad*, donde se puede elegir "Permitir siempre".
  - Las lecturas "originadas por el usuario y relacionadas con pegar" nunca muestran alerta.
- **En esta Mac, el PoC reportó `alwaysAllow` desde el primer arranque y no apareció ninguna alerta.** No sé si es por ser una app firmada en desarrollo o porque macOS 27 cambió el valor por defecto. Por si acaso, la app real:
  - lee `accessBehavior` al arrancar y la pantalla de bienvenida explica cómo activar "Permitir siempre" si está en `ask`/`alwaysDeny`;
  - nunca lee el contenido si `changeCount` no cambió (leer `changeCount` no dispara la alerta).
- Imágenes: un PNG copiado llega con tipos `public.png` + `public.tiff`; `NSImage(pasteboard:)` lo lee bien.
- **App de origen:** `NSWorkspace.frontmostApplication` en el momento de detectar la copia. Ojo: si copias desde la terminal con `pbcopy`, se registra la app que está al frente, no la terminal. Es una aproximación aceptable (es lo que hacen todos).

### 2. Panel

Configuración que funciona (`NSPanel`):

```swift
styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]
isFloatingPanel = true          // ⚠️ ANTES de fijar el nivel
level = .popUpMenu              // capa 101, encima de casi todo
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
hidesOnDeactivate = false
override var canBecomeKey: Bool { true }   // para recibir teclado
```

- ✅ La app activa **no cambia** al mostrar el panel (se verificó con TextEdit y Warp al frente: el menú superior sigue siendo el de esa app).
- ✅ Aparece en la pantalla del cursor (`NSEvent.mouseLocation` → `NSScreen`).
- 🐞 **Trampa:** `isFloatingPanel = true` reinicia el nivel a `.floating` (capa 3). Si se asigna después de `level`, el panel queda debajo de otras ventanas flotantes. Hay que asignarlo primero.
- 🐞 **Trampa de teclado:** cuando el campo de búsqueda tiene el foco, su editor se come las flechas, Enter y Esc **antes** que `.onKeyPress` de SwiftUI. Solución: un `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` que intercepta la navegación y deja pasar el resto de las letras a la búsqueda. Es justo lo que pide la idea: escribir para buscar, flechas para moverse.
- 🐞 **Trampa de foco:** el `.onAppear` de SwiftUI corre solo la primera vez. Al reabrir el panel hay que volver a enfocar el campo (`makeFirstResponder`) en cada apertura.
- Falta probar a mano: encima de una app en **pantalla completa** y con **varios monitores**.

### 3. Pegar directo

- Implementación: escribir en el portapapeles → ocultar panel → esperar ~60 ms → `CGEvent` ⌘V a `.cghidEventTap`.
- Requiere **Accesibilidad**. `AXIsProcessTrusted()` devolvió `false` porque nadie lo ha concedido aún, y no lo concedí por ti.
- Hay que guardar el `changeCount` que genera nuestra propia escritura para no volver a guardarlo como copia nueva. Ya está así en el PoC.

### 4. Atajo global

- `RegisterEventHotKey` (Carbon) devuelve `noErr` **aunque Paste ya tenga ⌘⇧V registrado**: macOS no da exclusividad. Con los dos corriendo, **ambas apps reciben el atajo**: se abren los dos paneles y Paste puede quedarse con el teclado.
- ➡️ **Para usar Baúl hay que desactivar el atajo en Paste o cerrar Paste.** Esto se menciona también en la pantalla de primer uso.
- No necesita ningún permiso.
- En el PoC el atajo se puede cambiar a ⌃⌥⌘V para convivir con Paste: `defaults write dev.tonis.baul.poc altHotKey -bool YES`.
- **Actualización:** Paste ya se desinstaló, así que Baúl usa ⌘⇧V sin conflicto.

### 5. Firma

- Hay un certificado válido: `Apple Development: tonirodriguez110@gmail.com`, equipo **RS79YL6DLM** (Personal Team).
- El requisito designado de la firma queda así:
  `identifier "dev.tonis.baul…" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: …" …`
  No depende del hash del binario, así que **el permiso de Accesibilidad se mantiene entre compilaciones**. Se pierde solo si cambia el certificado (se renueva una vez al año) o el bundle ID.
- Sin App Sandbox y con Hardened Runtime. No hace falta ningún *entitlement* especial para `CGEvent` ni Carbon.

### Herramientas instaladas

- `xcodegen` 2.46 y `swiftlint` 0.65 vía Homebrew.
- `swift-format` ya viene con Xcode (`xcrun swift-format`).
- El `.xcodeproj` se genera con XcodeGen a partir de `project.yml` y no se versiona.

---

## Fases 1 a 7: la app (16-oct-2026)

### Estado por fase

| Fase | Estado | Verificado |
|---|---|---|
| 1. Base del proyecto | ✅ | XcodeGen + paquete `BaulKit` (4 módulos), SwiftLint sin advertencias, `make` para todo |
| 2. Captura del historial | ✅ | Texto, RTF/HTML, links (con título), imágenes + miniatura; sin duplicados; limpieza de 5 días; contraseñas ocultas no se guardan |
| 3. Panel | ✅ (falta pegar directo, prueba manual) | Panel inferior, tarjetas, ← →, Esc, clic fuera, ⌘C. **Enter/⇧Enter/⌘1…9 necesitan el permiso de Accesibilidad** |
| 4. Tableros | ✅ (falta arrastrar, prueba manual) | Crear, renombrar/color, mover, eliminar con confirmación, *Guardar en…*, editar título/texto, ⌘← ⌘→ |
| 5. Búsqueda | ✅ | Escribir para buscar, fragmentos sin tildes, "En todo", filtros por tipo |
| 6. Privacidad y configuración | ✅ | Apps excluidas, pausa (15 min / 1 h / indefinida), atajo, inicio al encender, espacio ocupado, borrar historial, bienvenida |
| 7. Pulido | ✅ parcial | Ícono, rendimiento medido, accesibilidad básica (etiquetas en tarjetas). Animaciones: las del sistema |

Pruebas automáticas: **66** (Swift Testing): núcleo 21, persistencia 33, modelo del panel 12.

### Decisiones de diseño

- **Un elemento, varias vistas.** El historial (`clip`) y lo guardado (`boardEntry`) son tablas distintas. Una entrada apunta a un elemento y puede sobrescribir título y texto sin tocar el original. La base de datos impide borrar un elemento que está en un tablero (`ON DELETE RESTRICT`).
- **"Borrar del historial" no borra lo guardado.** Si un elemento está en un tablero, se marca `inHistory = 0` y sigue vivo en el tablero. Si lo vuelves a copiar, reaparece en el historial. Cuando se quita del último tablero y ya no está en el historial, se borra junto con su imagen.
- **Búsqueda con FTS5 + trigramas** (`tokenize='trigram remove_diacritics 1'`): "stag" encuentra "Staging" y "cancion" encuentra "canción". Las palabras de menos de 3 letras usan `LIKE`, porque el índice de trigramas no las cubre.
- **Formato al pegar.** Se guardan RTF y HTML junto al texto. Enter pega con formato y ⇧Enter solo el texto. Si editas el texto en un tablero, se descarta el formato original.
- **Pegar desde Baúl sube el elemento al principio**, como si se hubiera copiado de nuevo. El cambio que Baúl hace en el portapapeles se ignora para no duplicarlo.
- **Títulos de links:** nunca para `localhost`, `.local`, IPs privadas ni nombres sin dominio. Un GET a `localhost:3000/api/...` podría tener efectos en un servidor de desarrollo.
- **Debug y Release usan carpetas distintas** (`~/Library/Application Support/Baul-Debug` y `.../Baul`). En Debug, la base se recrea si cambia una migración. Así, desarrollar nunca toca los datos de la app instalada.
- **Copiar archivos en Finder se ignora** por ahora; si no, guardaría solo el nombre del archivo. Está en "Ideas para después".

### Bugs encontrados al probar la app real

1. **`URL.path()` codifica los espacios** (`Application%20Support`) y SQLite no pudo abrir la base. Se usa `path(percentEncoded: false)` en todo el proyecto y hay una prueba con una carpeta que contiene espacios.
2. **Un ⌫ de más borraba una tarjeta.** Al enfocar el buscador con ⌘F, macOS selecciona todo el texto: el primer ⌫ vaciaba la búsqueda y el segundo borraba la tarjeta seleccionada. Ahora borrar una tarjeta pide **⌘⌫** (o ⌦), y ⌫ solo edita la búsqueda.
3. **El ícono de la barra de menú puede quedar oculto detrás del notch** si la barra está llena. macOS lo coloca fuera de la pantalla (lo confirmé con la API de Accesibilidad: posición `(-1, 970)`). Por eso todo lo esencial (pausar, configuración, bienvenida, salir) también está en el menú **⋯** del panel. Con Paste desinstalado, el ícono ya se ve.
4. **`LibraryItem` choca con un tipo de SwiftUI** del mismo nombre: se renombró a `ClipItem`.
5. **Las escenas `Settings` de SwiftUI no se abren de forma fiable** desde una app sin ventana principal. Configuración y Bienvenida son ventanas AppKit con contenido SwiftUI (`HostedWindowController`).

### Rendimiento

Con 5.000 elementos en el historial (prueba `PerformanceTests`):

| Consulta | Tiempo |
|---|---|
| Listar los 300 más recientes | ~1,8 ms |
| Buscar "token-42 staging" | ~1,4 ms |
| Buscar "42" (corta, usa LIKE) | ~1,8 ms |

Un cuadro de pantalla dura ~16 ms, así que hay mucho margen. El panel muestra hasta 300 tarjetas en un `LazyHStack`.

### Cómo se probó

Además de las pruebas automáticas, la app se ejecutó y se manejó con eventos de teclado y mouse simulados (`CGEvent`), con capturas de pantalla para verificar. El arrastre simulado no es fiable (macOS abría el menú contextual), así que queda como prueba manual.

### Pruebas manuales pendientes

1. Dar el permiso de **Accesibilidad** (bienvenida → *Dar permiso…*) y probar **Enter, ⇧Enter, ⌘1…⌘9 y doble clic** en Terminal, Chrome, VS Code y Slack.
2. **Arrastrar** una tarjeta a la pestaña de un tablero.
3. Abrir el panel sobre una app en **pantalla completa** y con **dos monitores**.
4. Activar **Iniciar al encender la Mac** y reiniciar. Debe hacerse con la app de `/Applications` (`make install`).
5. Copiar una contraseña desde tu gestor real y confirmar que no aparece.
