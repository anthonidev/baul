# Baúl: plan de desarrollo

Referencia funcional: [`IDEA.md`](IDEA.md). Este documento define **cómo** se construye.

## Decisiones

| Tema | Decisión | Por qué |
|---|---|---|
| Plataforma | macOS 27+, Swift 6 (concurrencia estricta), SwiftUI + AppKit donde haga falta | Uso personal, sin compatibilidad hacia atrás |
| Distribución | Sin App Sandbox, firmado con *Personal Team* (cuenta Apple gratuita) | Permite simular ⌘V y leer el portapapeles sin trabas; firma estable = el permiso de Accesibilidad no se pierde al recompilar |
| Datos | Solo local, cada Mac con su propio historial. Sin sincronización | Fuera de alcance |
| Persistencia | SQLite con [GRDB](https://github.com/groue/GRDB.swift) + FTS5 | Búsqueda de texto completo, migraciones explícitas, borrados en lote eficientes |
| Imágenes | Archivos en `~/Library/Application Support/Baul/blobs/<sha256>` + miniatura | La base de datos se mantiene liviana; el hash sirve para no duplicar |
| Atajo global | [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Atajo global + selector de atajo para Configuración, ya resuelto |
| Ajustes simples | `@AppStorage` / `UserDefaults` | No justifica una dependencia |
| Iniciar al encender | `SMAppService.mainApp` | API nativa |
| Títulos de links | `LPMetadataProvider` (LinkPresentation) | API nativa |
| Pruebas | Swift Testing | Estándar actual |
| Estilo | `swift-format` + SwiftLint | Consistencia |

**Dependencias externas:** solo GRDB y KeyboardShortcuts.

## Arquitectura

```
Baul.xcodeproj
└─ BaulApp (target)        → arma las piezas: crea servicios, conecta dependencias
Packages/BaulKit (paquete Swift local)
├─ BaulCore                → modelos de dominio, protocolos, reglas puras
├─ BaulPersistence         → GRDB: migraciones, repositorios, FTS, almacén de blobs
├─ BaulSystem              → portapapeles, pegado, atajo, permisos, panel (AppKit)
└─ BaulUI                  → vistas SwiftUI y modelos de vista @Observable
```

- Dependencias en una sola dirección: `BaulUI → BaulCore ← BaulPersistence / BaulSystem`. `BaulCore` no importa AppKit ni GRDB.
- Todo lo que toca el sistema va detrás de un protocolo (`PasteboardReading`, `PastePerforming`, `ClipRepository`, `Clock`…) para poder probarlo con versiones falsas.
- UI en `@MainActor`; acceso a base de datos a través de un `actor`; modelos de dominio `struct` + `Sendable`.

### Modelo de datos

```
Clip         id, kind (text|image|link), text?, blobHash?, contentHash (único),
             sourceBundleID?, sourceAppName?, byteSize, charCount?,
             imageWidth?, imageHeight?, linkTitle?, createdAt, lastCopiedAt
Board        id, name, colorHex, sortOrder
BoardEntry   id, boardID, clipID, customTitle?, customText?, sortOrder, addedAt
ExcludedApp  bundleID, name
clip_fts     FTS5 sobre text, linkTitle, sourceAppName, customTitle, customText
```

- **No duplicar:** si `contentHash` ya existe → se actualiza `lastCopiedAt` y sube al principio.
- **Limpieza:** se borran los `Clip` con `lastCopiedAt` de más de 5 días **sin ningún `BoardEntry`**. Después se borran los blobs huérfanos.
- **Editar en tablero:** se escribe en `customText` / `customTitle` de la entrada; el `Clip` original no se toca.

---

## Fase 0: Prueba de concepto

**Objetivo:** confirmar en macOS 27 las cuatro partes delicadas antes de invertir más tiempo.

Una app desechable en `PoC/` (no se reutiliza su código):

1. Leer el portapapeles de forma continua (`changeCount` cada ~0,5 s) y anotar qué permiso pide macOS.
2. `NSPanel` no activante, encima de todo, incluso de apps en pantalla completa, que reciba teclado sin quitar el foco.
3. Pegar directo con `CGEvent` (⌘V) en Terminal, Chrome, VS Code y Slack.
4. Registrar ⌘⇧V como atajo global y comprobar que gana sobre el atajo de cada app.
5. Firmar con Personal Team, recompilar y verificar que el permiso de Accesibilidad se mantiene.

**Listo cuando:** los 5 puntos funcionan. Si alguno falla, se replantea antes de seguir.

## Fase 1: Base del proyecto

**Objetivo:** esqueleto limpio sobre el que crece todo lo demás.

- Repositorio git, `.gitignore`, `CLAUDE.md` con convenciones.
- Proyecto Xcode + paquete `BaulKit` con los 4 módulos vacíos y sus dependencias.
- App solo de barra de menú (`LSUIElement`), `MenuBarExtra` con "Salir".
- GRDB integrado: base en Application Support, primera migración con el esquema completo.
- `swift-format`, SwiftLint y un target de pruebas que corre.

**Listo cuando:** compila, arranca como ícono en la barra de menú, crea la base de datos y las pruebas pasan.

## Fase 2: Captura del historial

**Objetivo:** Baúl guarda todo lo que copias, sin interfaz todavía.

- `PasteboardMonitor`: detecta cambios, lee texto e imágenes, registra la app de origen.
- Clasificación texto / link / imagen (en `BaulCore`, con pruebas).
- `ClipRepository`: insertar, no duplicar, ordenar por `lastCopiedAt`.
- `BlobStore`: guardar imagen por hash + miniatura.
- Limpieza de 5 días al arrancar y cada hora.
- Respetar desde ya las marcas de contraseñas (`org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType`).

**Listo cuando:** copias cosas en distintas apps y aparecen bien en la base de datos, sin duplicados y sin contraseñas. Pruebas de dominio y repositorio en verde.

## Fase 3: Panel e historial visible (MVP usable)

**Objetivo:** reemplazar el uso diario básico de Paste.

- `PanelController`: panel inferior, horizontal, en la pantalla del cursor, encima de todo, sin quitar foco.
- ⌘⇧V abre y cierra; Esc cierra.
- Tarjetas: tipo, tiempo relativo, ícono de la app, vista previa (líneas de texto, miniatura, dirección del link), detalle (caracteres / tamaño), número de posición.
- Flechas ← → para recorrer; Enter y doble clic para pegar directo y cerrar.
- `PasteService`: escribir en el portapapeles + ⌘V simulado. Asegurar que pegar desde Baúl no vuelva a guardarse como copia nueva.
- Barra de menú: abrir panel, salir.

**Listo cuando:** lo usas un día entero en lugar de Paste para el historial.

## Fase 4: Tableros

**Objetivo:** lo más importante de la idea: guardar cosas para siempre.

- Crear tablero con nombre y color; renombrar, cambiar color, reordenar, eliminar con confirmación.
- Pestañas en la parte superior: "Portapapeles" + tableros; ⌘← / ⌘→ para cambiar.
- Guardar: arrastrar tarjeta a una pestaña; clic derecho → "Guardar en…".
- Editar texto y ponerle título a un elemento guardado.
- Lo guardado no se borra con la limpieza (con prueba que lo garantice).

**Listo cuando:** tienes tus tableros (`env`, `rxh`, `code`, `claude`) armados y en uso.

## Fase 5: Búsqueda y pegado avanzado

- Escribir directo al abrir el panel para buscar (FTS5).
- Busca en texto, títulos y app de origen; en la pestaña actual con opción "buscar en todo".
- Filtros rápidos: texto, imágenes, links.
- ⇧Enter pega como texto plano; ⌘1…⌘9 pega por posición; ⌘C solo copia.
- Clic derecho → Eliminar y tecla Suprimir.
- Título de la página en los links (`LPMetadataProvider`, en segundo plano).

**Listo cuando:** encuentras cualquier cosa en segundos sin tocar el mouse.

## Fase 6: Privacidad, configuración y primer uso

- Lista de apps excluidas (con Contraseñas de Apple incluida por defecto).
- Pausar desde la barra de menú: 15 min, 1 h o hasta reactivar.
- Ventana de Configuración: atajo (KeyboardShortcuts), apps excluidas, iniciar al encender, borrar historial, espacio ocupado.
- Primer uso: pedir Accesibilidad, explicar permiso del portapapeles, pantalla corta con ⌘⇧V / Enter / tableros.

**Listo cuando:** una instalación limpia en la otra Mac queda funcionando siguiendo solo la pantalla de bienvenida.

## Fase 7: Pulido

- Animaciones de apertura/cierre del panel y de las tarjetas.
- Rendimiento con miles de elementos: listas perezosas, miniaturas en caché, consultas paginadas.
- Accesibilidad (VoiceOver, etiquetas).
- Ícono de la app y de la barra de menú.

**Listo cuando:** se siente tan fluida como Paste. Ahí se cancela la suscripción.

---

## Ideas para después (fuera de este plan)

- Pila de pegado (copiar varias cosas y pegarlas en orden).
- Guardar archivos y colores.
- OCR en imágenes para buscarlas.
- Integración con Destello.
