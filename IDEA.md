# Baúl 🧳

> Todo lo que copias, guardado, ordenado y a un atajo de distancia.

Baúl es un gestor de portapapeles para macOS, inspirado en Paste. Guarda el historial de lo que copio y me deja tener **tableros con categorías** para lo que quiero conservar siempre.

---

## 1. Abrir el panel

- **⌘ ⇧ V** abre el panel desde cualquier app, igual que Paste hoy.
- Al volver a presionarlo, o con **Esc**, el panel se cierra.
- El panel aparece **horizontal en la parte inferior de la pantalla**, encima de todas las ventanas, incluso de las apps en pantalla completa.
- Abrir el panel **no le quita el foco** a la app en la que estoy trabajando, para poder pegar ahí directamente.
- Aparece en la pantalla donde está el cursor.

## 2. Las tarjetas

Cada elemento copiado se muestra como una tarjeta con:

- **Tipo:** Texto, Imagen, Link, etc.
- **Cuándo se copió**, en tiempo relativo: "hace 5 min", "ayer", "hace 3 días".
- **Ícono de la app de origen**, de dónde lo copié (Terminal, Chrome, VS Code…).
- **Vista previa** del contenido:
  - Texto: las primeras líneas.
  - Imagen: miniatura.
  - Link: la dirección, y si es posible el título de la página.
- **Detalle abajo:** cantidad de caracteres en el texto, tamaño en la imagen.
- **Número de posición** (1, 2, 3…) para el pegado rápido.

## 3. Historial

- Guarda automáticamente **texto e imágenes**.
- El historial conserva lo copiado en los **últimos 5 días**. Lo más antiguo se borra solo.
- Lo más reciente aparece primero, a la izquierda.
- Si copio algo que ya estaba en el historial, **no se duplica**: sube al principio.
- Opción de **borrar todo el historial** a mano.

## 4. Tableros (lo más importante)

- Puedo crear **tableros con nombre y color**, por ejemplo: `env`, `rxh`, `code`, `claude`.
- Los tableros aparecen como **pestañas** en la parte superior del panel, junto a "Portapapeles" (el historial).
- **Lo que guardo en un tablero nunca se borra**, aunque pasen los 5 días.
- Formas de guardar en un tablero:
  - Arrastrar una tarjeta del historial a la pestaña del tablero.
  - Clic derecho → "Guardar en…" → elegir el tablero.
- Puedo **renombrar**, **cambiar el color**, **reordenar** y **eliminar** tableros. Al eliminar uno, Baúl pide confirmación.
- Puedo **editar** el texto de un elemento guardado y **ponerle un título** para encontrarlo fácil (por ejemplo, "Token de staging").
- **⌘ ← / ⌘ →** dentro del panel cambia entre pestañas, igual que en Paste.

## 5. Buscar

- Al abrir el panel puedo **empezar a escribir directamente** para buscar.
- Busca en el texto, en los títulos y en el nombre de la app de origen.
- Busca en la pestaña actual, con la opción de buscar en todo.
- Filtros rápidos por tipo: solo texto, solo imágenes, solo links.

## 6. Pegar

- **Enter** o **doble clic**: pega el elemento **directamente en la app** donde estaba trabajando y cierra el panel.
- **⇧ Enter**: pega **como texto plano**, sin formato. Así no pierdo el "pegar sin formato" que ⌘⇧V tiene en muchas apps.
- **⌘ 1 … ⌘ 9**: pega al instante el elemento en esa posición.
- **⌘ C** sobre una tarjeta: solo la copia, sin pegar.
- Las **flechas ← →** recorren las tarjetas.

## 7. Privacidad

- **No guarda contraseñas** copiadas desde gestores de contraseñas (Contraseñas de Apple, 1Password, Bitwarden, etc.).
- **Lista de apps excluidas**: lo que copio desde esas apps no se guarda, por ejemplo la app del banco.
- **Pausar Baúl** temporalmente desde la barra de menú (por ejemplo, por 15 min o hasta que lo reactive).
- Todo se guarda **solo en mi Mac**: nada de nube ni de cuentas.
- Opción para borrar un elemento puntual del historial (clic derecho → Eliminar, o tecla Suprimir).

## 8. Barra de menú y configuración

- Ícono en la barra de menú con: abrir el panel, pausar, configuración y salir.
- **Configuración:**
  - Atajo para abrir el panel (por defecto ⌘⇧V).
  - Apps excluidas.
  - Iniciar Baúl al encender la Mac.
  - Borrar historial.
  - Ver cuánto espacio ocupa el historial.

## 9. Primer uso

1. Abrir Baúl: aparece el ícono en la barra de menú.
2. Dar el permiso de **Accesibilidad**, necesario para pegar directo en otras apps.
3. Si macOS lo pide, permitir que Baúl **lea el portapapeles** ("Permitir siempre").
4. Una pantalla corta explica: ⌘⇧V para abrir, Enter para pegar, cómo crear tableros.

---

## Antes de construir todo: prueba de concepto

Para no repetir lo que pasó con Telón, lo primero es comprobar en **macOS 27** las partes delicadas:

1. Que Baúl pueda **leer el portapapeles** de forma continua (y qué permiso pide macOS).
2. Que el **panel aparezca encima de todo** sin quitarle el foco a la app activa.
3. Que **pegar directo** en la app activa funcione bien (Terminal, Chrome, VS Code, Slack).
4. Que **⌘⇧V** se pueda tomar como atajo global.

Si estas cuatro funcionan, el resto del proyecto es seguro. Si alguna falla, se replantea antes de invertir más tiempo.

---

## Fuera de alcance

- Sincronización con iPhone o iCloud.
- Sugerencias "inteligentes" de qué pegar.

## Ideas para el futuro

- **Importar mis tableros desde Paste** (env, rxh, code, claude) para no perderlos al dejar Paste.
- **Pila de pegado** (como el ⌘⇧C de Paste): copiar varias cosas seguidas y pegarlas en orden, una tras otra.
- Guardar también **archivos** y **colores**.
- Reconocer texto dentro de las imágenes (OCR) para poder buscarlas.
- Conectarlo con **Destello**: que las capturas con flechas queden en un tablero.
