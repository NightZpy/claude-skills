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
| Mecánico (renames, moves, reformat, lookups) | `gpt-5.6-luna` effort `low` (alternativa: `spark` = `gpt-5.3-codex-spark`) | `model: 'haiku'` |
| Ejecución estándar (implementar paso acotado) | `gpt-5.6-terra` effort `medium`/`high` (alternativa: `gpt-5.4`) | `model: 'sonnet'` |
| Review/verificación de lo ejecutado | `gpt-5.6-terra` (regla global: review SIEMPRE Codex si está disponible; fallback `gpt-5.5`) | subagente fresco Opus/Sonnet solo como fallback |

Familia GPT-5.6 en Codex (verificado jul-2026 con auth ChatGPT): `gpt-5.6-terra` (balanceado) y `gpt-5.6-luna` (rápido/barato) **funcionan**; `gpt-5.6` a secas y `gpt-5.6-sol` (flagship) devuelven 400 con cuentas ChatGPT — Sol es solo para cuentas API. Ctx 272K.

Cómo despachar un executor Codex — dos vías:
- **Vía subagente** (simple): `Agent` con `subagent_type: 'codex:codex-rescue'` y el brief como prompt; el forwarder hace UNA llamada `task`. Pide `--write` para pasos que editan; añade `--model X --effort Y` en el brief si quieres fijarlos (sin flags usa el default de `~/.codex/config.toml`).
- **Vía runtime directo** (para paralelizar N pasos Codex): `codex-companion.mjs task --background --write [--model X] [--effort Y] "<brief>"` por paso → guarda cada job-id → sigue despachando Claude en paralelo → recoge con `status <job-id>` / `result <job-id>`. Si `status` = `failed`, lee el error: causa de cuota/modelo → redespacha ese paso con el fallback Claude; causa del brief → corrige el brief y reintenta UNA vez.

Reglas de mezcla:
- Codex ejecuta en el working tree real (no en contexto aislado): **nunca dos writers (Codex o Claude) sobre los mismos archivos a la vez** — pasos que escriben en zonas distintas sí pueden correr en paralelo; si comparten archivos, secuéncialos o usa worktrees.
- El brief a Codex debe ser tan autocontenido como el de un subagente Claude, y además decir explícitamente qué evidencia devolver (Codex no ve tu plan).
- El paso de review final sigue tu regla dura global: Codex primero; Claude solo si Codex no puede correr.

### Tercera flota: Frontier (modelos externos baratos)

Cuándo: pasos de **generación pura** (boilerplate, tests, refactor mecánico de texto, review de diff, análisis de contexto muy largo) donde el executor no necesita tools — el modelo devuelve texto/código y tú (o un subagente) lo aplicas/verificas.

Verifica disponibilidad una sola vez al inicio del EXECUTE: `node ~/.claude/plugins/cache/claude-code-delegate/cc-delegate/*/scripts/companion.mjs setup --json` → `ready: true`. Si el plugin no está instalado o no hay keys, esta flota no existe — sigue con Claude/Codex, no te detengas.

Tabla de ruteo:

| Tipo de paso | Modelo frontier | Equivalente |
|---|---|---|
| Boilerplate / bulk barato | `deepseek` | ~Haiku |
| Codegen / refactor / tests en volumen | `qwen` | ~Sonnet (gama baja) |
| Refactor agéntico complejo en texto | `glm` | ~Sonnet 5 |
| Auditoría contexto 1M / razonamiento profundo | `kimi` | ~Opus (caro — solo si Claude/Codex no alcanzan el contexto) |
| Segunda opinión / generalista frontier | `grok` | ~Opus/GPT-5.5 (Grok 4.5, 500K ctx) |

Despacho: `node .../companion.mjs task --background --model <alias> --file <ctx>... "<brief>"` → `jobId` → recoger con `status`/`result`. El brief debe ser autocontenido e indicar el formato de salida esperado (código completo o diff unificado). El output NO está aplicado: aplicarlo y verificarlo es un paso aparte (tuyo o de un subagente barato).

Regla: frontier NUNCA para pasos que requieren ejecutar comandos, explorar el repo o tomar decisiones — eso es Claude/Codex.

### Modo economía (límite de plan Claude cerca)

Cuándo se activa (cualquiera de estas señales):
1. El harness muestra warnings de límite de uso en la conversación (señal más fiable).
2. El usuario lo pide o comparte su `/usage` ("modo economía", "vamos al 80% y el reset es en 3 días").
3. Al inicio de un run largo, chequeo barato: `npx -y ccusage blocks --json` (bloque activo: burnRate/projection) — estima consumo desde transcripts locales; NO conoce el límite real del plan, úsalo como proxy junto con lo que diga el usuario. Claude no puede leer los números exactos de `/usage` por sí mismo.

Regla de sustitución mientras esté activo (el objetivo: que el plan Claude aguante hasta el reset):

| Rol normal | En modo economía |
|---|---|
| Fable/Opus orquesta | Sigue, pero como **supervisor mínimo**: planea una vez, revisa evidencia destilada, veredictos cortos. NUNCA lee material crudo ni ejecuta pasos. |
| Juicio profundo que Fable haría inline (análisis de diseño, diagnóstico sobre material dado, auditorías, resolver specs ambiguas) | Codex `gpt-5.6-terra` (lo más cercano a Fable disponible; Sol da 400 con auth ChatGPT) → sin Codex: `kimi` vía cc-delegate (AA 57 ≥ Opus 4.8, el sustituto más cercano; caro y lento — solo para pasos de juicio, no volumen) con TODO el material en `--file`. Fable solo emite el veredicto final sobre la respuesta. |
| Sonnet ejecución estándar | Codex `gpt-5.6-terra` (si hay cuota) → si el paso es generación pura, `glm`/`qwen` vía cc-delegate |
| Haiku mecánico | Codex `luna`; si es transformación de texto pura, `deepseek` vía cc-delegate |
| Review | Codex primero (regla global); sin Codex → `glm` + segunda opinión `grok` vía cc-delegate; review Claude SOLO para paths de seguridad críticos |
| Scouts/lecturas de investigación | Si es leer/resumir material textual: `kimi`/`glm` con `--file`. Subagente Claude solo cuando hacen falta tools del repo. |

- Los pasos que requieren tools (explorar repo, correr tests, editar en el árbol) no pueden ir a cc-delegate (texto puro): van a Codex; Sonnet queda como última opción.
- Desactivar al pasar el reset o cuando el usuario lo indique; anota en el reporte final qué corrió en modo economía.

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
