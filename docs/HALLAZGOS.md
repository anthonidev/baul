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
- En el PoC el atajo se puede cambiar a ⌃⌥⌘V para convivir con Paste: `defaults write dev.tonis.baul.poc altHotKey -bool YES` (está activado ahora mismo).

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
