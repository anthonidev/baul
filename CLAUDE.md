# Baúl

Gestor de portapapeles personal para macOS 27 (reemplazo de Paste). Qué hace: `IDEA.md`. Cómo se construye: `PLAN.md`. Hallazgos y decisiones: `docs/HALLAZGOS.md`.

## Comandos

- `make run`: genera el proyecto, compila y abre la app.
- `make test`: pruebas (Swift Testing) del paquete `Packages/BaulKit`.
- `make lint`: SwiftLint; debe quedar sin advertencias.
- `make install`: build Release en `/Applications/Baul.app`.
- `Baul.xcodeproj` se genera con XcodeGen desde `project.yml`: no se edita a mano ni se versiona.

## Arquitectura

- `App/`: target de la app. Solo composición (`AppModel`), pegado (`ClipboardController`) y escenas.
- `Packages/BaulKit`:
  - `BaulCore`: dominio puro (modelos, reglas, protocolos `LibraryStore`/`ImageStore`). Sin AppKit ni GRDB.
  - `BaulPersistence`: SQLite con GRDB (migraciones en `AppDatabase`, FTS5 con trigramas) e imágenes en disco.
  - `BaulSystem`: portapapeles, pegado con `CGEvent`, permisos, atajo global, inicio de sesión.
  - `BaulUI`: SwiftUI + el `NSPanel` flotante. Modelos `@Observable` probados con SQLite en memoria.
- Dependencias: `UI → System → Core ← Persistence`. Core no depende de nadie.

## Convenciones

- Swift 6, concurrencia estricta. `BaulUI`/`BaulSystem`/app: main actor por defecto. `BaulCore`/`BaulPersistence`: `nonisolated`; trabajo pesado con `@concurrent`.
- Modelos de dominio: `struct`/`enum` `Sendable`. Las filas de GRDB (`*Record`) no salen de `BaulPersistence`.
- Textos de la interfaz y comentarios en español. Nombres de código en inglés.
- Pruebas nuevas con Swift Testing (`@Test`, `#expect`), con nombres en lenguaje natural entre backticks.
- `Logger` (subsystem `dev.tonis.baul`), nunca `print`.
- Rutas de archivo: `url.path(percentEncoded: false)`. `path()` codifica los espacios ("Application Support").

## Trampas conocidas (ver docs/HALLAZGOS.md)

- `NSPanel.isFloatingPanel = true` reinicia el `level`: asignarlo antes.
- El campo de búsqueda se come flechas/Enter/Esc: el teclado del panel se maneja con un monitor local en `PanelController`.
- Si Paste está abierto, ⌘⇧V abre los dos paneles.
- Firmar siempre con el certificado Apple Development (equipo RS79YL6DLM) para que no se pierda el permiso de Accesibilidad.
