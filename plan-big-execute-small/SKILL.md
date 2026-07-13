---
name: plan-big-execute-small
description: Orchestration mode - run the current task with the "plan big, execute small" pattern inside this session. The session model (Fable/Opus) acts as planner+advisor and dispatches bounded execution steps to cheap subagents (Sonnet default, Haiku for mechanical work), reviewing each result against the plan before proceeding. Use when the user invokes /plan-big-execute-small, says "plan big execute small", "patron planner/executor", or asks to run a big task with cheap executors under big-model supervision. NOT for trivial tasks (one file, one step) - just do those directly.
---

# Plan Big, Execute Small — orquestación en sesión

Tú (el modelo de la sesión: Fable/Opus) eres el **planner y advisor**. Los subagentes baratos son los **executors**. La inteligencia cara se gasta en planear, revisar y corregir rumbo — nunca en teclear pasos mecánicos.

## Roles

| Rol | Quién | Hace |
|---|---|---|
| Planner | Tú (modelo de sesión) | Especifica la tarea completa, la descompone en pasos acotados y verificables |
| Executor | Subagente Claude (`sonnet`/`haiku`) o **Codex** (ver tabla abajo) | Ejecuta UN paso acotado y reporta evidencia |
| Advisor/Verifier | Tú | Revisa cada resultado contra el plan, corrige rumbo, sintetiza |

Consistente con la regla de tiering global: Sonnet es el workhorse; Haiku solo mecánico; lo genuinamente difícil (decisión de arquitectura, bug sutil, seguridad) NO se delega — lo haces tú inline o con subagente sin tag (hereda el modelo de sesión).

## Executors disponibles: Claude y Codex

Dos flotas de executors; elige por paso. **Verifica Codex una sola vez al inicio del EXECUTE** (no por paso): `node ~/.claude/plugins/cache/openai-codex/codex/<version>/scripts/codex-companion.mjs setup --json` → `ready: true` y `auth.loggedIn: true`. Si no está listo, o una tarea falla por cuota/límite/`model not supported`, **cae al equivalente Claude de la tabla y sigue** — anótalo en el reporte final, no te detengas ni reintentes en bucle.

| Tipo de paso | Codex (si disponible) | Claude (default/fallback) |
|---|---|---|
| Mecánico (renames, moves, reformat, lookups) | `spark` (= `gpt-5.3-codex-spark`) o `gpt-5.4-mini`, effort `low` | `model: 'haiku'` |
| Ejecución estándar (implementar paso acotado) | `gpt-5.4` effort `medium`/`high` | `model: 'sonnet'` |
| Review/verificación de lo ejecutado | `gpt-5.5` (regla global: review SIEMPRE Codex si está disponible; `gpt-5.6` da 400 con auth ChatGPT) | subagente fresco Opus/Sonnet solo como fallback |

Cómo despachar un executor Codex — dos vías:
- **Vía subagente** (simple): `Agent` con `subagent_type: 'codex:codex-rescue'` y el brief como prompt; el forwarder hace UNA llamada `task`. Pide `--write` para pasos que editan; añade `--model X --effort Y` en el brief si quieres fijarlos (sin flags usa el default de `~/.codex/config.toml`).
- **Vía runtime directo** (para paralelizar N pasos Codex): `codex-companion.mjs task --background --write [--model X] [--effort Y] "<brief>"` por paso → guarda cada job-id → sigue despachando Claude en paralelo → recoge con `status <job-id>` / `result <job-id>`. Si `status` = `failed`, lee el error: causa de cuota/modelo → redespacha ese paso con el fallback Claude; causa del brief → corrige el brief y reintenta UNA vez.

Reglas de mezcla:
- Codex ejecuta en el working tree real (no en contexto aislado): **nunca dos writers (Codex o Claude) sobre los mismos archivos a la vez** — pasos que escriben en zonas distintas sí pueden correr en paralelo; si comparten archivos, secuéncialos o usa worktrees.
- El brief a Codex debe ser tan autocontenido como el de un subagente Claude, y además decir explícitamente qué evidencia devolver (Codex no ve tu plan).
- El paso de review final sigue tu regla dura global: Codex primero; Claude solo si Codex no puede correr.

## Flujo

### 1. PLAN (tú, sin delegar)
- Lee lo mínimo necesario para especificar bien (o despacha 1-2 scouts Sonnet de solo-lectura si el mapa es grande).
- Escribe el plan: pasos **acotados** (un entregable por paso), cada uno con: objetivo, archivos/alcance, output esperado, y **cómo se verifica** (comando, test, criterio observable).
- Marca dependencias: pasos independientes se despachan en paralelo; dependientes, en secuencia.
- Preséntalo al usuario en 3-6 líneas antes de ejecutar (salvo que ya haya aprobado un plan).

### 2. EXECUTE (subagentes)
- Un Agent por paso, `model: 'sonnet'` (o `'haiku'` si es mecánico). Pasos independientes → despacha en paralelo en un solo mensaje.
- **El prompt del executor debe ser autocontenido**: los subagentes no ven tu contexto. Incluye rutas exactas, convenciones del repo relevantes, el output esperado y el criterio de verificación. Pídeles evidencia (output de comando, diff, test verde), no afirmaciones.
- Prohibido al executor: decisiones de diseño/arquitectura, tocar fuera de su alcance, "mejorar" código adyacente. Si un paso requiere una decisión, debe reportarla de vuelta, no tomarla.

### 3. ADVISE (tú, en cada resultado)
- Revisa el reporte contra el criterio del paso. ¿Evidencia real o afirmación?
- Falla o se desvía → UN reintento con feedback correctivo concreto (qué estuvo mal, qué esperabas).
- Segunda falla, o el paso resultó ser judgment-heavy → escálalo: hazlo tú inline o redespacha sin tag de modelo.
- Un resultado puede invalidar pasos posteriores del plan — ajusta el plan antes de seguir despachando, no después.

### 4. VERIFY & SYNTHESIZE (tú)
- Corre la verificación global (tests, build, el flujo de punta a punta — skill `verify` si aplica).
- Resumen final para el usuario: qué se hizo, evidencia, qué quedó fuera.

## Reglas duras

- Nunca despaches sin plan escrito: pasos sin criterio de verificación producen "listo ✅" falsos.
- Nunca aceptes un reporte sin evidencia verificable.
- Escalar es barato, re-trabajar es caro: a la segunda falla de un executor, sube el modelo o hazlo tú.
- Tareas triviales (un archivo, un paso) NO usan este patrón — hazlas directo; el overhead de orquestar supera el ahorro.

## Economía del patrón (del cookbook, medido)

- **El ahorro está en mantener el material crudo fuera de TU contexto.** Los tokens pesados (páginas web, logs, archivos grandes, sweeps de codebase) deben leerse en el contexto del subagente, que devuelve hallazgos destilados. Si el material crudo termina en el contexto del coordinador, pagaste orquestación para nada. En los runs del cookbook: ~2.5x más barato y ~3x más rápido, con 84-98% del input facturado a tarifa de worker.
- **Delegar tiene costo fijo por subagente** — la granularidad de los briefs tiene un óptimo. Partir el mismo trabajo en más briefs más estrechos SUBE el costo. Prefiere pocos pasos sustanciosos a muchos micro-pasos.
- **No delegues juicio sobre material crudo sutil**: un lector barato puede resumir y perder exactamente lo que importaba (análisis fino de documentos, decisiones sobre matices). Eso lo lees tú.
- **Verifica también la premisa, no solo los pasos**: si la descomposición del plan parte de tu memoria (una lista, un supuesto), gasta un paso barato en verificarla — el cookbook auditó 20 hechos perfectamente sobre una lista que traía un ítem equivocado de memoria.

## Origen

Adaptación al harness de Claude Code del cookbook CMA "Plan Big, Execute Small" (coordinador frontier sin tools + workers baratos con las tools, leyendo en threads paralelos y reportando destilado) y del advisor tool de la API. Cookbook: https://github.com/anthropics/claude-cookbooks/blob/main/managed_agents/CMA_plan_big_execute_small.ipynb
