# Baúl 🧳

> Todo lo que copias, guardado, ordenado y a un atajo de distancia.

Gestor de portapapeles para macOS 27, hecho a medida para reemplazar Paste. Funciona solo en tu Mac: sin nube ni cuentas.

## Instalar

```sh
brew install xcodegen swiftlint   # una sola vez
make install                      # compila en Release y copia a /Applications
```

La primera vez, Baúl muestra una bienvenida. Da el permiso de **Accesibilidad** (es lo que permite pegar directo en la app donde estás) y, si Paste sigue abierto, ciérralo: los dos usan ⌘⇧V.

## Uso

| Tecla | Acción |
|---|---|
| ⌘⇧V | Abrir / cerrar el panel |
| ← → | Moverse entre tarjetas |
| Enter / doble clic | Pegar en la app donde estabas |
| ⇧Enter | Pegar como texto, sin formato |
| ⌘1 … ⌘9 | Pegar la tarjeta en esa posición |
| ⌘C | Copiar sin pegar |
| ⌘← ⌘→ | Cambiar de pestaña |
| ⌘⌫ o ⌦ | Borrar la tarjeta (en un tablero: quitarla) |
| Escribir | Buscar (⌘F vuelve al buscador) |
| Esc | Cerrar |

**Tableros:** usa el botón **+** para crear uno. Para guardar algo, arrastra la tarjeta a la pestaña del tablero o usa clic derecho → *Guardar en…*. Lo guardado no se borra nunca. El historial conserva los últimos 5 días.

## Desarrollo

Ver `CLAUDE.md` (arquitectura y convenciones), `PLAN.md` (fases) y `docs/HALLAZGOS.md` (lo aprendido en el camino).
