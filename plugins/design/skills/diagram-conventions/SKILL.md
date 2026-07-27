---
name: diagram-conventions
description: Use when creating or editing ANY diagram (Mermaid or Excalidraw) - when to use sequence vs flow diagrams, Excalidraw typography per use case, and the black-background rule with contrast guidance.
---

# Diagrams — Mermaid & Excalidraw

## Cuándo usar cada tipo

| Tipo de diagrama | Cuándo |
|---|---|
| **Sequence diagram** | Flujos detallados o técnicos. Ejemplo: caso de uso "desde que entra un mensaje para generar un video hasta que termina el wizard"; un job paso a paso de inicio a fin; interacción entre N servicios con timing claro. |
| **Flow diagram** (flowchart / graph) | Explicaciones abstractas o globales. Ejemplo: arquitectura de servicios que se comunican; diagrama de decisión de alto nivel; visión general de un sistema. |

Regla mental: si el diagrama tiene un eje de tiempo implícito (paso 1 → 2 → 3 → 4 con actores específicos), es secuencia. Si es estático (componentes interconectados), es flowchart.

## Excalidraw — convención de tipografía

En todo `.excalidraw` que crees o edites:

| Caso de uso | Fuente |
|---|---|
| Títulos y subtítulos | **Virgil** (default Excalidraw) |
| Inputs / contenido descriptivo | **Nunito** |
| Explicaciones / anotaciones | **Comic Shanns** |
| Code / SQL / paths / identifiers | **Cascadia** |

## Excalidraw — fondo

**Background siempre negro** (`viewBackgroundColor: "#000000"`). Los colores de las cajas y stroke deben tener contraste suficiente sobre fondo oscuro:
- Stroke: tonos claros (white, sky-300, emerald-300, amber-300, etc.)
- Backgrounds de cajas: tonos saturados oscuros con fillStyle solid (no transparente sobre el negro)
- Texto de label: blanco o tono claro acorde al stroke de la caja

Editar visualmente desde la extensión de VS Code (`pomdtr.excalidraw-editor`) o https://excalidraw.com — los `fontFamily` numéricos varían por versión, mejor aplicar la fuente con UI que adivinar IDs en JSON crudo.
