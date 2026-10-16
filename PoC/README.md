# Baúl PoC

App desechable para validar las partes delicadas en macOS 27. Resultados en [`docs/HALLAZGOS.md`](../docs/HALLAZGOS.md).

## Compilar y abrir

```sh
cd PoC
xcodegen generate
xcodebuild -project BaulPoC.xcodeproj -scheme BaulPoC -derivedDataPath build -allowProvisioningUpdates build
open build/Build/Products/Debug/BaulPoC.app
```

Aparece un 🧳 en la barra de menú. El log está en `~/Library/Logs/BaulPoC.log`:

```sh
tail -f ~/Library/Logs/BaulPoC.log
```

## Atajo

- Por defecto está en **⌃⌥⌘V** para no chocar con Paste: `defaults write dev.tonis.baul.poc altHotKey -bool YES`.
- Para probar el **⌘⇧V real**: cierra Paste, ejecuta `defaults delete dev.tonis.baul.poc altHotKey` y reabre el PoC.

## Prueba manual pendiente

1. 🧳 → **Pedir permiso de Accesibilidad** → activar *BaulPoC* en Ajustes del Sistema.
2. Copia 2 o 3 textos.
3. En cada app (Terminal, Chrome, VS Code, Slack), pon el cursor en un campo de texto, abre el panel, usa ← → y pulsa **Enter**: el texto debe pegarse ahí.
4. Pon una app en **pantalla completa** y abre el panel: debe verse encima.
5. Si tienes un segundo monitor: el panel debe aparecer donde está el cursor.
6. Recompila (`xcodebuild …`) y confirma que el permiso de Accesibilidad **sigue activo**.

Anota cualquier falla en `docs/HALLAZGOS.md`.
