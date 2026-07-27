---
name: advisor-tool
description: Use when building with the Claude API and the task fits "plan big, execute small" - a cheap/fast executor model (Haiku/Sonnet) consults a stronger advisor model (Opus/Fable) mid-generation for strategic guidance. Covers the server-side advisor tool (advisor_20260301, beta), valid model pairings, multi-turn rules, cost controls and steering prompts. NOT a Claude Code command - it is a Messages API feature.
---

# Advisor Tool — patrón "plan big, execute small"

Server tool **beta** de la Claude API: un **executor** barato/rápido (el `model` top-level del request) consulta a un **advisor** más inteligente (el `model` dentro de la tool) a mitad de generación. El advisor lee el transcript completo, devuelve un plan o corrección de rumbo, y el executor continúa. Todo ocurre dentro de un solo `/v1/messages` — sin round-trips extra del cliente.

**Cuándo usarlo:** workloads agénticos de horizonte largo (coding agents, computer use, research multi-paso) donde la mayoría de turnos son mecánicos pero el plan importa. Ya usas Sonnet → añade Opus como advisor (mejor calidad a costo similar o menor). Ya usas Haiku → advisor Opus da un salto de inteligencia sin pagar executor grande.
**Cuándo NO:** Q&A de un turno (nada que planear), o cuando cada turno realmente necesita el modelo grande.

## Quick start

Beta header obligatorio: `advisor-tool-2026-03-01`. Endpoint beta (`client.beta.messages.*`).

```python
response = client.beta.messages.create(
    model="claude-sonnet-4-6",              # executor
    max_tokens=4096,
    betas=["advisor-tool-2026-03-01"],
    tools=[{
        "type": "advisor_20260301",
        "name": "advisor",                   # obligatorio, literal
        "model": "claude-opus-4-8",          # advisor
        "max_tokens": 2048,                  # recomendado: ~7x menos output sin perder calidad
        # "max_uses": 3,                     # cap por request
        # "caching": {"type": "ephemeral", "ttl": "5m"},  # solo si esperas 3+ llamadas/conversación
    }],
    messages=[{"role": "user", "content": "..."}],
)
```

TypeScript: mismo shape con `client.beta.messages.create({ betas: ["advisor-tool-2026-03-01"], tools: [{ type: "advisor_20260301", name: "advisor", model: "claude-opus-4-8" }], ... })`.

## Pareos válidos (executor → advisor)

El advisor debe ser ≥ capaz que el executor (mínimo Sonnet 4.6). Par inválido → `400 invalid_request_error`.

| Executor | Advisors válidos |
|---|---|
| `claude-haiku-4-5`, `claude-sonnet-4-6` | Fable 5, Mythos 5, Opus 4.8/4.7/4.6, Sonnet 4.6 |
| `claude-sonnet-5`, `claude-opus-4-7`, `claude-opus-4-8` | Fable 5, Mythos 5, Opus 4.8/4.7 |
| `claude-opus-4-6` | Fable 5, Mythos 5, Opus 4.8/4.7/4.6 |
| `claude-fable-5` / `claude-mythos-5` | solo él mismo |

Disponibilidad: Claude API y Claude Platform on AWS (beta). NO en Bedrock, Vertex ni Foundry.

## Reglas críticas

1. **Multi-turn: reenvía `response.content` COMPLETO** (incluidos los bloques `advisor_tool_result`) en turnos siguientes. Quitar la advisor tool de `tools` mientras el historial contiene `advisor_tool_result` → 400. Para dejar de usarla a mitad de conversación: quita la tool **y** limpia esos bloques del historial.
2. **`server_tool_use.input` siempre es `{}`** — el servidor construye la vista del advisor desde el transcript; nada de lo que el executor ponga en input llega al advisor. El advisor corre sin tools; solo su texto de consejo vuelve al executor.
3. **`pause_turn`**: si el turno termina con un `server_tool_use` de advisor sin resultado, reenvía el mensaje assistant sin cambios (misma tool + beta header) y el API completa la llamada pendiente. Si además hay `tool_use` de tus tools, responde los `tool_result` normal y la llamada advisor corre al inicio del siguiente request.
4. **Variantes de resultado**: `advisor_result` (texto legible) para la mayoría; **Fable 5 / Mythos 5 devuelven `advisor_redacted_result`** (`encrypted_content` opaco — reenvíalo verbatim, el servidor lo descifra en el siguiente turno).
5. **Errores no rompen el request**: `advisor_tool_result_error` con `error_code` (`max_uses_exceeded`, `too_many_requests`, `overloaded`, `prompt_too_long`, `execution_time_exceeded`, `unavailable`) — el executor continúa sin consejo.
6. **Forzar consulta**: `tool_choice: {"type": "tool", "name": "advisor"}` — incompatible con extended thinking (400).

## Costos

- El advisor se factura a SUS tarifas como sub-inferencia; ver `usage.iterations[]` (`type: "advisor_message"`). El `usage` top-level solo refleja al executor.
- El `max_tokens` top-level NO acota al advisor — usa `max_tokens` en la tool (mín 1024; **2048 recomendado**: ~7x menos output, ~0% truncado). Truncado → `stop_reason: "max_tokens"` en el result.
- Recorte por prompt (soft): añade al user message `(Advisor: please keep your guidance under 80 words — I need a focused starting point, not a comprehensive plan.)`.
- `caching` en la tool: break-even a ~3 llamadas advisor por conversación; déjalo apagado en tareas cortas y no lo alternes a mitad de conversación.
- Sonnet executor a `effort: medium` + Opus advisor ≈ Sonnet a effort default, más barato.

## Steering (cuándo llama el executor al advisor)

- La tool trae descripción built-in; en research no suele necesitar más prompting. En **coding**, los executors sub-llaman: usa el system prompt sugerido de la doc (llamar advisor ANTES de trabajo sustantivo, al creer terminada la tarea, al atascarse, al cambiar de enfoque; orientación read-only no cuenta como trabajo sustantivo).
- **Haiku**: nudge de texto en turno 2 si no ha llamado (+7pts pass rate). **Sonnet**: el nudge no ayuda. **Opus**: NO apliques nudge (baja el rendimiento); solo añade el checkpoint "hard rule" si observas sub-llamado real.

## Relación con el cookbook "Plan Big, Execute Small" (CMA)

El mismo principio aplicado con Managed Agents: un agente planner con modelo grande genera el plan y agentes executor con modelo chico ejecutan pasos acotados (sesiones separadas o `multiagent` coordinator). El advisor tool es la versión "dentro de un solo request" del patrón; CMA es la versión orquestada multi-agente. Cookbook: https://github.com/anthropics/claude-cookbooks/blob/main/managed_agents/CMA_plan_big_execute_small.ipynb

## Fuente

Doc oficial (fetch para detalles frescos): https://platform.claude.com/docs/en/agents-and-tools/tool-use/advisor-tool.md
