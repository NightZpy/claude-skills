// behavior-report-kit — standard report generator TEMPLATE.
//
// Provenance: spec'd in this kit's SKILL.md §6, field-tested in production on Russell
// (github.com/NightZpy/russell). No license header — this file is meant to be copied into
// your own repo and adapted freely; see the CONFIG block below and template/README.md.
//
// Builds ONE self-contained HTML review report (inline CSS/JS, data-URI media, no external
// requests) from a real Playwright JSON run + the features.json BDD contract. The product
// owner reviews every feature through this single artifact, typically on a phone.
//
// SKILL.md §5–§8 is the CONTRACT this file implements (badges, verdict format, media scoping,
// accept semantics) — redesign the HTML/CSS/JS freely, but keep the contract. Do not re-author
// this generator from the spec prose; copy this file and fill in CONFIG instead.
//
// Invocation (adjust the CONFIG paths below to match your repo layout first):
//   node build-review-report.mjs                 build the report
//   node build-review-report.mjs --config sample  smoke-run against template/sample-data/
//   node build-review-report.mjs --accept        promote ALL baselines (after a full review round)
//   node build-review-report.mjs --accept-only "<feature>" [--accept-only "<feature2>" ...]
//                                                 promote/baseline ONLY the named feature(s) —
//                                                 use when the owner reviewed a subset, so
//                                                 unreviewed stories are never silently baselined
//   node build-review-report.mjs --refresh "<feature>"   force-embed one feature
//   node build-review-report.mjs --compact-gifs  smallest GIF-fallback dials (used only
//                                                 when ffmpeg/libx264 is unavailable — the
//                                                 primary pipeline is H.264 MP4, see main())
//
// Owner-facing prose defaults to Spanish (field-tested); see STRINGS below to translate. Code
// and comments are English.

import { readFileSync, writeFileSync, existsSync, mkdirSync, mkdtempSync, rmSync, statSync } from 'node:fs';
import { join, resolve, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

// ===== CONFIG (adapt per project) =====
// Everything a new adopter needs to touch lives in this block. Fill it in for your repo, then
// leave the rest of the file alone — it implements the SKILL.md §6 contract, not your product's
// specifics. Re-run `node build-review-report.mjs --config sample` any time to sanity-check the
// generator itself still works, independent of your own fixtures.

/** Product name interpolated into the report's title/copy. Replace with your own product. */
const PRODUCT_NAME = 'Your Product';

// Paths. Defaults assume this file lives at test/behavior/build-review-report.mjs relative to
// the repo root — adjust REPO_ROOT (or hardcode absolute paths) if you place it elsewhere.
// `--config sample` points E2E_DIR/ARTIFACTS at this kit's template/sample-data/ instead, so the
// template can be smoke-run before you've wired up a real Playwright suite.
const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(__dirname, '..', '..');
const CONFIG_MODE = (() => {
	const idx = process.argv.indexOf('--config');
	return idx !== -1 ? process.argv[idx + 1] : 'default';
})();
const IS_SAMPLE_CONFIG = CONFIG_MODE === 'sample';

const E2E_DIR = IS_SAMPLE_CONFIG ? join(__dirname, 'sample-data') : join(REPO_ROOT, 'test', 'behavior');
const DATA_DIR = join(E2E_DIR, '.report-data'); // optional metrics.json / hygiene.json — see kit §6
const ARTIFACTS = IS_SAMPLE_CONFIG ? join(E2E_DIR, '.out') : join(REPO_ROOT, '.build', 'behavior-report');

// In sample mode results.json is a static checked-in fixture (there's no real Playwright run to
// produce it), so it's read straight out of E2E_DIR rather than the build ARTIFACTS dir.
const RESULTS_JSON = IS_SAMPLE_CONFIG ? join(E2E_DIR, 'results.json') : join(ARTIFACTS, 'results.json');
const FEATURES_JSON = join(E2E_DIR, 'features.json');
const REVIEW_STATE = join(E2E_DIR, 'review-state.json');
const METRICS_HISTORY = join(E2E_DIR, 'metrics-history.json');
const OUTPUT_HTML = join(ARTIFACTS, 'review-report.html');

// Media source notes: the size ladders below (VIDEO_LADDER / GIF_LADDER_*) assume 1280x800
// source recordings (Playwright's default viewport). Their `scale` values are upper bounds — if
// your recordings use a different resolution, pick your own rungs; the floor (never go blurrier)
// still applies (kit §6).

// STRINGS: every owner-facing string the report renders. The Spanish below is field-tested on
// Russell's non-technical Spanish-speaking users. To translate, swap the whole object — every
// render function below reads from STRINGS, so there is no hardcoded copy left to hunt down.
const STRINGS = {
	pageTitle: `Reporte de comportamiento — ${PRODUCT_NAME}`,
	subtitle: 'Cada funcionalidad, demostrada con la app real. Revísala aquí; no hace falta abrir nada.',
	triageLine: (noStory, featuresWithGaps) => `${noStory} comportamiento(s) aún sin prueba en ${featuresWithGaps} funcionalidad(es).`,
	countPass: n => `${n} pasaron`,
	countFail: n => `${n} fallaron`,
	countNew: n => `${n} nuevas`,
	countChanged: n => `${n} cambiaron`,
	timestampLabel: ts => `Generado: ${ts}`,
	filterAriaLabel: 'Filtrar historias',
	filterEmptyNote: 'Ninguna historia coincide con este filtro.',
	legendSummary: '¿Qué significan las etiquetas?',
	navIndex: 'Índice',
	orphanSuffix: 'sin especificar',
	askedLabel: 'Lo que pediste',
	featureGapBadge: n => `${n} sin implementar`,
	approvedHead: n => `Aprobadas · sin cambios (${n})`,
	burndownHead: 'Sin implementar',
	burndownProposedTag: 'propuesto',
	nostoryIntro: 'La funcionalidad puede existir; este reporte no puede dar fe. No hay una historia que demuestre este comportamiento acordado.',
	unspecifiedIntro: 'Hay una prueba para algo que no figura en el contrato acordado. Convendría agregarlo a features.json o retirarlo.',
	seedsHeader: 'Preparación fuera de cámara',
	doneHeader: 'Condiciones de terminado',
	failureSummary: 'Detalle del error',
	failureFallback: 'La prueba no pasó (sin texto de error disponible).',
	mediaApprovedNote: 'Media en versiones anteriores del artifact — esta historia ya fue aprobada y no cambió.',
	clipSpeedLabel: 'Velocidad',
	clipCaption: 'Grabación de la interacción real',
	noVideoNote: 'Sin video: no se pudo generar el MP4 a partir de la grabación. Las capturas de arriba muestran los momentos clave.',
	gifCaption: 'Grabación de la interacción real (cámara lenta) — video H.264 no disponible en este entorno',
	noGifReasonEncodeFailed: 'no se pudo generar el GIF a partir de la grabación',
	noGifReasonNoFfmpeg: 'ffmpeg no está disponible en este entorno',
	noGifNote: why => `Sin GIF: ${why}. Las capturas de arriba muestran los momentos clave.`,
	markUnmarked: 'Sin marcar',
	markStale: 'desactualizada',
	markNoteToggleLabel: 'Agregar nota',
	markNotePlaceholder: 'Nota breve…',
	guideSummary: 'Cómo usar este reporte',
	guideMap: [
		'<strong>Tarjeta con evidencia</strong> (PASÓ/PROPUESTO) → mira las capturas y el video, y marca ✓ o ✗ (+ nota si hace falta).',
		'<strong>FALLÓ</strong> → ya lo sabe el agente; agrega una nota solo si tienes contexto extra.',
		'<strong>SIN HISTORIA</strong> → NO falló: es algo prometido que aún no tiene prueba (backlog del agente). No debes hacer nada — márcala solo para ayudar a priorizar.',
		'<strong>CAMBIÓ</strong> → vuelve a mirarla: su contenido cambió desde la última vez que la revisaste.',
		'<strong>Los badges son hechos independientes</strong> (resultado · feliz/límite · novedad · aprobación) — no indican gravedad.'
	],
	guideSteps: [
		'Revisa lo que pide atención (usa los chips de filtro, arriba).',
		'Marca ✓ o ✗ en cada historia.',
		'Pulsa "Copiar veredicto".',
		'Pégalo en el CLI del agente — actúa con eso.'
	],
	metricsHeading: 'Panel de métricas',
	metricsNew: n => `Nuevo en este reporte: <strong>${n}</strong> historia(s) que requieren tu atención.`,
	metricCards: {
		behaviors: { label: 'Comportamientos E2E', sub: (happy, edge) => `feliz ${happy} · límite ${edge}` },
		unit: { label: 'Pruebas unitarias', sub: 'suite rápida' },
		system: { label: 'Pruebas de sistema', sub: 'sobre la app real' },
		coverage: { label: 'Cobertura', sub: () => `del alcance de ${PRODUCT_NAME}` },
		mutation: { label: 'Mutación', sub: 'mutantes eliminados' },
		duplication: { label: 'Duplicación', sub: clones => clones === null ? 'sin datos' : `${clones} clones` },
		spec: { label: 'Contrato de comportamiento', sub: (proposed, noStory, unspecified) => `propuestos ${proposed} · sin historia ${noStory} · sin especificar ${unspecified}` }
	},
	lightbox: { close: 'Cerrar', prev: 'Anterior', next: 'Siguiente', ariaLabel: 'Imagen ampliada' },
	verdict: {
		none: 'Sin marcas todavía',
		copy: 'Copiar veredicto',
		clear: 'Limpiar marcas',
		copied: 'Copiado ✓',
		confirmClear: '¿Borrar todas las marcas y notas de este reporte? No se puede deshacer.',
		modalTitle: 'Copia el veredicto manualmente',
		modalHint: 'No se pudo copiar al portapapeles automáticamente. Mantén pulsado el texto y elige Copiar, o usa el botón.',
		modalCopy: 'Copiar',
		modalCopied: '✓ Copiado',
		modalClose: 'Cerrar',
		stateUnmarked: 'Sin marcar',
		stateBien: '✓ Bien',
		stateFalla: '✗ Falla',
		countBien: 'bien',
		countFalla: 'falla',
		countNota: 'nota',
		reportHeader: 'VEREDICTO DEL REPORTE — ',
		bienHeader: 'BIEN (',
		fallaHeader: 'FALLA (',
		notasHeader: 'NOTAS (',
		sinMarcarLabel: 'SIN MARCAR: '
	},
	badges: {
		pass: ['PASÓ', 'La prueba se ejecutó sobre la app real y terminó bien.'],
		fail: ['FALLÓ', 'La prueba se ejecutó pero algo no salió como se esperaba; el error está expandido.'],
		happy: ['CAMINO FELIZ', 'El caso normal, tal como lo haría una persona sin problemas.'],
		edge: ['CASO LÍMITE', 'Un caso difícil o inusual, para comprobar que la app aguanta.'],
		new: ['NUEVO', 'Aparece por primera vez en un reporte; aún no lo habías revisado.'],
		changed: ['CAMBIÓ', 'Ya lo habías revisado antes, pero su contenido cambió desde entonces.'],
		proposed: ['PROPUESTO', 'Comportamiento propuesto en el contrato, a la espera de tu aprobación.'],
		nostory: ['SIN HISTORIA', 'Acordamos este comportamiento pero no hay prueba que lo demuestre: la funcionalidad puede existir, este reporte no puede dar fe.'],
		unspecified: ['SIN ESPECIFICAR', 'Hay una prueba para algo que no está en el contrato acordado.']
	},
	filters: {
		todo: 'Todo',
		attention: 'Atención',
		fail: 'Fallaron',
		changed: 'Cambiaron',
		new: 'Nuevas',
		proposed: 'Propuestas',
		nostory: 'Sin historia',
		approved: 'Aprobadas'
	}
};

// ---------------------------------------------------------------------------
// Story recording dials + size governance. Source recordings are 1280x800.
// Primary pipeline is H.264 MP4 (native speed, playback controls, fullscreen);
// the GIF pipeline stays in the code as a documented FALLBACK for environments
// without ffmpeg/libx264 — flip by checking hasH264Encoder() in main(). Each
// ladder is tried in order (quality dial reduced least-damaging-first) until
// the rendered report fits SIZE_TARGET_BYTES; neither ladder drops below its
// quality floor — a bigger report beats a blurrier recording.
// ---------------------------------------------------------------------------
const SIZE_TARGET_BYTES = 14 * 1024 * 1024;
const VIDEO_LADDER = [
	{ mode: 'video', scale: 1024, crf: 27 },
	{ mode: 'video', scale: 1024, crf: 28 },
	{ mode: 'video', scale: 1024, crf: 30 },
	{ mode: 'video', scale: 900, crf: 30 },
	{ mode: 'video', scale: 760, crf: 30 }
];
const GIF_LADDER_DEFAULT = [
	{ mode: 'gif', scale: 1024, fps: 8, colors: 128 },
	{ mode: 'gif', scale: 900, fps: 8, colors: 128 },
	{ mode: 'gif', scale: 760, fps: 8, colors: 128 },
	{ mode: 'gif', scale: 760, fps: 8, colors: 96 }
];
const GIF_LADDER_COMPACT = [
	{ mode: 'gif', scale: 760, fps: 8, colors: 96 }
];

// Per-story embedded-media byte log, reset each renderHtml() call — printed by main() after the
// winning ladder rung is chosen, so the console shows exactly what shipped.
let mediaLog = [];

// ---------------------------------------------------------------------------
// Small utilities.
// ---------------------------------------------------------------------------

/** Read a JSON file, returning `fallback` when it is missing or unparseable. */
function readJson(path, fallback) {
	if (!existsSync(path)) {
		return fallback;
	}
	try {
		return JSON.parse(readFileSync(path, 'utf8'));
	} catch {
		return fallback;
	}
}

/** Escape a string for safe inclusion in HTML text/attribute content. */
function esc(value) {
	return String(value ?? '')
		.replace(/&/g, '&amp;')
		.replace(/</g, '&lt;')
		.replace(/>/g, '&gt;')
		.replace(/"/g, '&quot;');
}

/** Short hex content hash (sha256, first 16 chars) of the given parts. */
function contentHash(parts) {
	const h = createHash('sha256');
	h.update(JSON.stringify(parts));
	return h.digest('hex').slice(0, 16);
}

/** Format a byte count as a compact human string. */
function humanSize(bytes) {
	if (bytes < 1024) {
		return `${bytes} B`;
	}
	if (bytes < 1024 * 1024) {
		return `${(bytes / 1024).toFixed(1)} KB`;
	}
	return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

/** Metric value or the em-dash placeholder when the field is missing/null. */
function metricOr(value) {
	return value === null || value === undefined ? '—' : String(value);
}

// ---------------------------------------------------------------------------
// CLI arguments.
// ---------------------------------------------------------------------------

/** Parse the recognised flags out of argv. */
function parseArgs(argv) {
	const args = { accept: false, compactGifs: false, refresh: null, acceptOnly: [] };
	for (let i = 0; i < argv.length; i++) {
		const a = argv[i];
		if (a === '--accept') {
			args.accept = true;
		} else if (a === '--compact-gifs') {
			args.compactGifs = true;
		} else if (a === '--refresh') {
			args.refresh = argv[++i] ?? null;
		} else if (a === '--accept-only') {
			args.acceptOnly.push(argv[++i] ?? '');
		}
	}
	return args;
}

// ---------------------------------------------------------------------------
// Playwright results → flat story list.
// ---------------------------------------------------------------------------

/**
 * `--config sample` only: rewrite every attachment's `path` from relative (as checked into
 * template/sample-data/results.json) to absolute, resolved against E2E_DIR. Mutates in place.
 */
function resolveSampleAttachmentPaths(suites) {
	for (const suite of suites ?? []) {
		for (const spec of suite.specs ?? []) {
			for (const test of spec.tests ?? []) {
				for (const result of test.results ?? []) {
					for (const att of result.attachments ?? []) {
						if (att.path && !att.path.startsWith('/')) {
							att.path = join(E2E_DIR, att.path);
						}
					}
				}
			}
		}
		if (suite.suites) {
			resolveSampleAttachmentPaths(suite.suites);
		}
	}
}

/**
 * Walk the nested Playwright suite tree collecting every spec, tracking which
 * features.json feature key each spec lives under. Specs can sit at any depth;
 * a spec belongs to the nearest ancestor suite whose title is a feature key.
 * Nested non-feature describes (e.g. "arranque con perfil ...") don't reset the feature.
 */
function collectSpecs(suites, featureKeys, currentFeature, out) {
	for (const suite of suites ?? []) {
		// A suite whose title matches a feature key becomes the feature for everything below it.
		const feature = featureKeys.has(suite.title) ? suite.title : currentFeature;
		for (const spec of suite.specs ?? []) {
			out.push({ spec, feature });
		}
		if (suite.suites) {
			collectSpecs(suite.suites, featureKeys, feature, out);
		}
	}
}

/**
 * Turn a Playwright spec into a normalized story record. Extraction paths (verified against
 * a real run in .build/behavior-report/results.json):
 *   - caption'd screenshot: result.attachments[] where name starts "snap:" (contentType image/png);
 *     caption is the text after the "snap:" prefix, in order.
 *   - GIF source: result.attachments[] where name === "video" (contentType video/webm).
 *   - off-camera seeds: test.annotations[] where type === "seed" → description (run-stable).
 *   - edge tag: spec.tags includes "edge" (Playwright's serializer strips the leading "@").
 *   - failure: result.status !== "passed" → error text from result.errors[].
 * Story title joins to a features.json behavior title by exact string match.
 */
function normalizeStory(entry) {
	const { spec, feature } = entry;
	const test = spec.tests?.[0];
	const result = test?.results?.[0];
	const attachments = result?.attachments ?? [];

	const captions = [];
	let videoPath = null;
	for (const att of attachments) {
		if (typeof att.name === 'string' && att.name.startsWith('snap:') && att.contentType === 'image/png') {
			captions.push({ caption: att.name.slice('snap:'.length), path: att.path });
		} else if (att.name === 'video' && att.path) {
			videoPath = att.path;
		}
	}

	const annotations = test?.annotations ?? result?.annotations ?? [];
	const seeds = annotations.filter(a => a?.type === 'seed').map(a => a.description).filter(Boolean);

	const passed = spec.ok === true && result?.status === 'passed';
	const isEdge = Array.isArray(spec.tags) && spec.tags.includes('edge');
	const errorText = (result?.errors ?? [])
		.map(e => (typeof e === 'string' ? e : (e?.message ?? e?.stack ?? '')))
		.filter(Boolean)
		.join('\n\n');

	return {
		feature,
		title: spec.title,
		passed,
		isEdge,
		captions,
		videoPath,
		seeds,
		errorText,
		durationMs: result?.duration ?? null
	};
}

// ---------------------------------------------------------------------------
// Story recording encoding: H.264 MP4 (primary — playback controls, native speed,
// fullscreen) via system ffmpeg, falling back to a palette-quantized GIF when ffmpeg or its
// libx264 encoder is unavailable.
// ---------------------------------------------------------------------------

let ffmpegAvailable = null;

/** Detect ffmpeg on PATH once. */
function hasFfmpeg() {
	if (ffmpegAvailable === null) {
		const probe = spawnSync('ffmpeg', ['-version'], { stdio: 'ignore' });
		ffmpegAvailable = probe.status === 0;
	}
	return ffmpegAvailable;
}

let h264Available = null;

/** Detect the libx264 encoder in ffmpeg's build once. */
function hasH264Encoder() {
	if (h264Available === null) {
		if (!hasFfmpeg()) {
			h264Available = false;
		} else {
			const probe = spawnSync('ffmpeg', ['-hide_banner', '-encoders']);
			h264Available = probe.status === 0 && /libx264/.test(String(probe.stdout));
		}
	}
	return h264Available;
}

/**
 * Encode a webm into an H.264 MP4 (native real-time speed — no baked slowdown; the in-report
 * speed buttons replace it) and return { dataUri, bytes }, or null on any failure.
 */
function encodeMp4(webmPath, dials) {
	if (!existsSync(webmPath) || !hasH264Encoder()) {
		return null;
	}
	const workDir = mkdtempSync(join(tmpdir(), 'behavior-report-mp4-'));
	try {
		const outMp4 = join(workDir, 'out.mp4');
		const result = spawnSync('ffmpeg', [
			'-y', '-i', webmPath,
			'-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', String(dials.crf),
			'-vf', `scale=${dials.scale}:-2`,
			'-an',
			outMp4
		], { stdio: 'ignore' });
		if (result.status !== 0 || !existsSync(outMp4)) {
			return null;
		}
		const buf = readFileSync(outMp4);
		return { dataUri: `data:video/mp4;base64,${buf.toString('base64')}`, bytes: buf.length };
	} catch {
		return null;
	} finally {
		rmSync(workDir, { recursive: true, force: true });
	}
}

/**
 * Encode a webm into a size-controlled GIF (palettegen/paletteuse for quality) and return
 * { dataUri, bytes }, or null on any failure. Fallback path only — dials per kit §6.
 */
function encodeGif(webmPath, dials) {
	if (!existsSync(webmPath) || !hasFfmpeg()) {
		return null;
	}
	const workDir = mkdtempSync(join(tmpdir(), 'behavior-report-gif-'));
	try {
		const palette = join(workDir, 'palette.png');
		const outGif = join(workDir, 'out.gif');
		const chain = `setpts=2.5*PTS,fps=${dials.fps},scale=${dials.scale}:-1:flags=lanczos`;

		const pass1 = spawnSync('ffmpeg', [
			'-y', '-i', webmPath,
			'-vf', `${chain},palettegen=max_colors=${dials.colors}`,
			palette
		], { stdio: 'ignore' });
		if (pass1.status !== 0 || !existsSync(palette)) {
			return null;
		}

		const pass2 = spawnSync('ffmpeg', [
			'-y', '-i', webmPath, '-i', palette,
			'-lavfi', `${chain} [x]; [x][1:v] paletteuse`,
			outGif
		], { stdio: 'ignore' });
		if (pass2.status !== 0 || !existsSync(outGif)) {
			return null;
		}

		const buf = readFileSync(outGif);
		return { dataUri: `data:image/gif;base64,${buf.toString('base64')}`, bytes: buf.length };
	} catch {
		return null;
	} finally {
		rmSync(workDir, { recursive: true, force: true });
	}
}

/** Read a PNG file into a data URI, or null if unreadable. */
function pngDataUri(path) {
	if (!path || !existsSync(path)) {
		return null;
	}
	try {
		return `data:image/png;base64,${readFileSync(path).toString('base64')}`;
	} catch {
		return null;
	}
}

// ---------------------------------------------------------------------------
// Badge model. Each story carries a set of badges the header counts and the legend explains.
// ---------------------------------------------------------------------------

// Badge chip → label + one-line meaning a non-engineer understands, sourced from STRINGS.badges
// (CONFIG block above) — order here is display order in the legend.
const BADGE_LEGEND = ['pass', 'fail', 'happy', 'edge', 'new', 'changed', 'proposed', 'nostory', 'unspecified']
	.map(type => [type, STRINGS.badges[type][0], STRINGS.badges[type][1]]);

/** True when a badge type demands attention (drives the nav dots and the "Atención" filter chip). */
function isAttentionBadge(type) {
	return type === 'fail' || type === 'new' || type === 'changed' || type === 'proposed' || type === 'nostory' || type === 'unspecified';
}

// ---------------------------------------------------------------------------
// Filter chips: header controls that show/hide items by category. Replaces the former
// "Solo lo nuevo" checkbox — a single chip couldn't express "just failures" or "just the
// gaps", so it's absorbed here as the "Atención" preset (new+changed+failing+proposed+
// nostory+unspecified, i.e. everything isAttentionBadge already flags).
// ---------------------------------------------------------------------------
const FILTER_CHIPS = [
	{ key: 'todo', label: STRINGS.filters.todo },
	{ key: 'attention', label: STRINGS.filters.attention },
	{ key: 'fail', label: STRINGS.filters.fail },
	{ key: 'changed', label: STRINGS.filters.changed },
	{ key: 'new', label: STRINGS.filters.new },
	{ key: 'proposed', label: STRINGS.filters.proposed },
	{ key: 'nostory', label: STRINGS.filters.nostory },
	{ key: 'approved', label: STRINGS.filters.approved }
];

/** Filter categories an item belongs to, derived purely from its already-computed badges/kind. */
function filterCatsFor(item) {
	const cats = [];
	if (item.badges.includes('fail')) { cats.push('fail'); }
	if (item.badges.includes('changed')) { cats.push('changed'); }
	if (item.badges.includes('new')) { cats.push('new'); }
	if (item.badges.includes('proposed')) { cats.push('proposed'); }
	if (item.badges.includes('nostory')) { cats.push('nostory'); }
	if (item.kind === 'story' && !item.badges.some(isAttentionBadge)) { cats.push('approved'); }
	if (item.badges.some(isAttentionBadge)) { cats.push('attention'); }
	return cats;
}

/** Render the space-separated data-filter attributes an item/nav-link needs for chip filtering. */
function filterAttrs(item) {
	return `data-filter-item data-filter="${esc(filterCatsFor(item).join(' '))}"`;
}

/** Tally live chip counts across every item in the model (features + orphans), "todo" = all. */
function countFilterChips(model) {
	const counts = {};
	for (const chip of FILTER_CHIPS) { counts[chip.key] = 0; }
	const all = [];
	for (const f of model.features) { all.push(...f.items); }
	for (const items of model.orphanByFeature.values()) { all.push(...items); }
	for (const item of all) {
		counts.todo++;
		for (const cat of filterCatsFor(item)) {
			counts[cat]++;
		}
	}
	return counts;
}

// ---------------------------------------------------------------------------
// Build the model: stories with badges + cross-checks + hashing + scoping.
// ---------------------------------------------------------------------------

/**
 * Assemble the full render model from all inputs. Returns { features, orphanStories, counts, hashesForAccept }.
 * A "feature" carries its askedFor text and an ordered list of items; an item is either a real
 * story, a NO STORY placeholder (agreed behavior with no matching story), or lives in orphanStories
 * (UNSPECIFIED story with no agreed behavior).
 */
function buildModel(results, features, reviewState, args) {
	const featureKeys = new Set(Object.keys(features));

	// Flatten specs → normalized stories.
	const specEntries = [];
	collectSpecs(results.suites, featureKeys, null, specEntries);
	const stories = specEntries.map(normalizeStory);

	// Index stories by feature+title for the cross-check.
	const storyByKey = new Map();
	for (const s of stories) {
		const key = `${s.feature} ${s.title}`;
		if (storyByKey.has(key)) {
			console.warn(`WARN: duplicate story key "${key}" — second result overwrites the first`);
		}
		storyByKey.set(key, s);
	}

	const acceptedScenarios = reviewState?.scenarios ?? {};
	const hashesForAccept = {};
	const counts = { pass: 0, fail: 0, new: 0, changed: 0, proposed: 0, noStory: 0, unspecified: 0, happy: 0, edge: 0, total: 0 };

	const featureModels = [];
	const matchedStoryKeys = new Set();

	for (const [featureName, featureDef] of Object.entries(features)) {
		const behaviors = featureDef.behaviors ?? {};
		const items = [];

		for (const [behaviorTitle, behaviorDef] of Object.entries(behaviors)) {
			const key = `${featureName} ${behaviorTitle}`;
			const story = storyByKey.get(key);
			const done = behaviorDef.done ?? [];
			const proposed = behaviorDef.status === 'proposed';

			if (!story) {
				// Agreed behavior with no story → NO STORY (red, open).
				counts.noStory++;
				counts.total++;
				items.push({
					kind: 'nostory',
					title: behaviorTitle,
					done,
					proposed,
					hash: '',
					badges: buildBadges({ noStory: true, proposed })
				});
				continue;
			}

			matchedStoryKeys.add(key);

			// Content hash = title + ordered captions + done conditions + seed texts.
			const hash = contentHash({
				title: story.title,
				captions: story.captions.map(c => c.caption),
				done,
				seeds: story.seeds
			});
			hashesForAccept[key] = hash;

			const accepted = acceptedScenarios[key];
			const isNew = accepted === undefined;
			const isChanged = accepted !== undefined && accepted !== hash;

			// Media scoping: embed for NEW/CHANGED/failing/PROPOSED, or when --refresh names this feature.
			const forceRefresh = args.refresh && args.refresh === featureName;
			const embed = isNew || isChanged || !story.passed || proposed || forceRefresh;

			// Tally.
			counts.total++;
			if (story.passed) { counts.pass++; } else { counts.fail++; }
			if (story.isEdge) { counts.edge++; } else { counts.happy++; }
			if (isNew) { counts.new++; }
			if (isChanged) { counts.changed++; }
			if (proposed) { counts.proposed++; }

			items.push({
				kind: 'story',
				title: story.title,
				done,
				story,
				proposed,
				embed,
				hash,
				badges: buildBadges({
					passed: story.passed,
					edge: story.isEdge,
					isNew,
					isChanged,
					proposed
				})
			});
		}

		featureModels.push({ name: featureName, askedFor: featureDef.askedFor ?? '', items });
	}

	// Stories that matched no agreed behavior → UNSPECIFIED (grouped under their feature, or a synthetic bucket).
	const orphanByFeature = new Map();
	for (const s of stories) {
		const key = `${s.feature} ${s.title}`;
		if (matchedStoryKeys.has(key)) {
			continue;
		}
		counts.unspecified++;
		counts.total++;
		if (s.passed) { counts.pass++; } else { counts.fail++; }
		if (s.isEdge) { counts.edge++; } else { counts.happy++; }
		// Content hash still computed so --accept can baseline it if later specified.
		const hash = contentHash({
			title: s.title,
			captions: s.captions.map(c => c.caption),
			done: [],
			seeds: s.seeds
		});
		hashesForAccept[key] = hash;
		const embed = true; // UNSPECIFIED always embeds (kit §6).
		const item = {
			kind: 'unspecified',
			title: s.title,
			done: [],
			story: s,
			proposed: false,
			embed,
			hash,
			badges: buildBadges({ passed: s.passed, edge: s.isEdge, unspecified: true })
		};
		const bucket = orphanByFeature.get(s.feature ?? '(sin funcionalidad)') ?? [];
		bucket.push(item);
		orphanByFeature.set(s.feature ?? '(sin funcionalidad)', bucket);
	}

	return { features: featureModels, orphanByFeature, counts, hashesForAccept };
}

/** Compose the ordered badge list for an item from its flags. */
function buildBadges(flags) {
	const badges = [];
	if (flags.passed === true) { badges.push('pass'); }
	if (flags.passed === false) { badges.push('fail'); }
	if (flags.edge === true) { badges.push('edge'); } else if (flags.edge === false) { badges.push('happy'); }
	if (flags.isNew) { badges.push('new'); }
	if (flags.isChanged) { badges.push('changed'); }
	if (flags.proposed) { badges.push('proposed'); }
	if (flags.noStory) { badges.push('nostory'); }
	if (flags.unspecified) { badges.push('unspecified'); }
	return badges;
}

// ---------------------------------------------------------------------------
// Metrics dashboard model.
// ---------------------------------------------------------------------------

/**
 * Build the metric cards from metrics.json (tolerating missing fields → "—"), the behavior counts,
 * and the history for sparklines.
 */
function buildMetrics(metrics, hygiene, counts, history) {
	const m = metrics ?? {};
	const h = hygiene ?? {};
	const dup = m.duplicationPct ?? h.duplicationPct ?? null;
	const dupClones = m.duplicationClones ?? h.clones ?? null;

	// Proven = passing, non-proposed stories that have an agreed behavior (pass count minus proposed/unspecified overlap
	// is hard to attribute exactly; we report what the report can vouch for: passing agreed stories).
	const provenTotal = counts.total;

	const C = STRINGS.metricCards;
	const cards = [
		{ key: 'behaviors', label: C.behaviors.label, value: `${counts.pass}/${provenTotal}`, sub: C.behaviors.sub(counts.happy, counts.edge), history: history.map(r => r.behaviorsPass) },
		{ key: 'unit', label: C.unit.label, value: metricOr(m.unitTests), sub: C.unit.sub, history: history.map(r => r.unitTests) },
		{ key: 'system', label: C.system.label, value: metricOr(m.systemTests), sub: C.system.sub, history: history.map(r => r.systemTests) },
		{ key: 'coverage', label: C.coverage.label, value: m.coveragePct === null || m.coveragePct === undefined ? '—' : `${m.coveragePct}%`, sub: C.coverage.sub(), history: history.map(r => r.coveragePct) },
		{ key: 'mutation', label: C.mutation.label, value: m.mutationScorePct === null || m.mutationScorePct === undefined ? '—' : `${m.mutationScorePct}%`, sub: C.mutation.sub, history: history.map(r => r.mutationScorePct) },
		{ key: 'duplication', label: C.duplication.label, value: dup === null || dup === undefined ? '—' : `${dup}%`, sub: C.duplication.sub(dupClones === null || dupClones === undefined ? null : dupClones), history: history.map(r => r.duplicationPct) },
		{ key: 'spec', label: C.spec.label, value: `${provenTotal - counts.noStory}/${provenTotal}`, sub: C.spec.sub(counts.proposed, counts.noStory, counts.unspecified), history: history.map(r => r.behaviorsTotal) }
	];

	const newThisReport = counts.new + counts.changed;
	return { cards, newThisReport };
}

/**
 * Render a tiny inline sparkline SVG from a numeric series (nulls skipped). Returns '' when
 * there is not enough data. Kept dependency-free and inlined.
 */
function sparkline(series) {
	const pts = (series ?? []).filter(v => typeof v === 'number' && !Number.isNaN(v));
	if (pts.length < 2) {
		return '';
	}
	const w = 72;
	const hgt = 20;
	const min = Math.min(...pts);
	const max = Math.max(...pts);
	const span = max - min || 1;
	const step = w / (pts.length - 1);
	const coords = pts.map((v, i) => {
		const x = (i * step).toFixed(1);
		const y = (hgt - ((v - min) / span) * (hgt - 2) - 1).toFixed(1);
		return `${x},${y}`;
	});
	return `<svg class="spark" viewBox="0 0 ${w} ${hgt}" width="${w}" height="${hgt}" aria-hidden="true"><polyline points="${coords.join(' ')}" fill="none" stroke="currentColor" stroke-width="1.5"/></svg>`;
}

// ---------------------------------------------------------------------------
// HTML rendering.
// ---------------------------------------------------------------------------

/** Render one badge chip. */
function renderBadge(type) {
	const entry = BADGE_LEGEND.find(b => b[0] === type);
	const label = entry ? entry[1] : type;
	return `<span class="badge badge-${type}">${esc(label)}</span>`;
}

/**
 * Render the media block (screenshots + story recording) for an embedded item, or the "media
 * omitted" note. The recording is H.264 MP4 with native controls/speed/fullscreen when
 * `dials.mode === 'video'`; otherwise it falls back to a GIF (ffmpeg/libx264 unavailable).
 * Screenshots always go through the lightbox; the video does not (it has its own fullscreen).
 */
function renderMedia(item, dials) {
	if (item.kind === 'nostory') {
		return '';
	}
	if (!item.embed) {
		return `<p class="media-note">${esc(STRINGS.mediaApprovedNote)}</p>`;
	}

	const story = item.story;
	const galleryId = slug(item.title);
	const figs = [];
	story.captions.forEach((cap, idx) => {
		const uri = pngDataUri(cap.path);
		if (!uri) {
			return;
		}
		figs.push(`<figure class="snap"><img class="lightbox-img" loading="lazy" src="${uri}" alt="${esc(cap.caption)}" data-story="${galleryId}" data-idx="${idx}"><figcaption>${esc(cap.caption)}</figcaption></figure>`);
	});

	let mediaBlock = '';
	if (story.videoPath) {
		if (dials.mode === 'video') {
			const enc = encodeMp4(story.videoPath, dials);
			if (enc) {
				mediaLog.push({ title: item.title, kind: 'video', bytes: enc.bytes });
				const poster = story.captions[0] ? pngDataUri(story.captions[0].path) : null;
				const posterAttr = poster ? ` poster="${poster}"` : '';
				const maxW = `min(100%, ${dials.scale}px)`;
				const videoId = `video-${galleryId}`;
				mediaBlock = `<figure class="clip">
					<div class="clip-speed" data-video="${videoId}">
						<span class="clip-speed-label">${esc(STRINGS.clipSpeedLabel)}</span>
						<button type="button" class="speed-btn" data-rate="0.5">0.5×</button>
						<button type="button" class="speed-btn is-active" data-rate="1">1×</button>
						<button type="button" class="speed-btn" data-rate="1.5">1.5×</button>
						<button type="button" class="speed-btn" data-rate="2">2×</button>
					</div>
					<video id="${videoId}" style="max-width:${maxW}" controls playsinline preload="metadata"${posterAttr} src="${enc.dataUri}"></video>
					<figcaption>${esc(STRINGS.clipCaption)}</figcaption>
				</figure>`;
			} else {
				mediaBlock = `<p class="media-note media-warn">${esc(STRINGS.noVideoNote)}</p>`;
			}
		} else {
			const gif = encodeGif(story.videoPath, dials);
			if (gif) {
				mediaLog.push({ title: item.title, kind: 'gif', bytes: gif.bytes });
				// Never display the GIF larger than its encoded width — avoids upscale blur.
				// PNGs above are native 1280px, so they need no such cap.
				const maxW = `min(100%, ${dials.scale}px)`;
				mediaBlock = `<figure class="gif"><img class="lightbox-img" loading="lazy" style="max-width:${maxW}" src="${gif.dataUri}" alt="${esc(STRINGS.clipCaption)}" data-story="${galleryId}-gif" data-idx="0" data-native-width="${dials.scale}"><figcaption>${esc(STRINGS.gifCaption)}</figcaption></figure>`;
			} else {
				const why = hasFfmpeg() ? STRINGS.noGifReasonEncodeFailed : STRINGS.noGifReasonNoFfmpeg;
				mediaBlock = `<p class="media-note media-warn">${esc(STRINGS.noGifNote(why))}</p>`;
			}
		}
	}

	const snapsHtml = figs.length ? `<div class="snaps">${figs.join('')}</div>` : '';
	return snapsHtml + mediaBlock;
}

/** Render the off-camera preparation list from seed annotations. */
function renderSeeds(seeds) {
	if (!seeds || seeds.length === 0) {
		return '';
	}
	const lis = seeds.map(s => `<li>${esc(s)}</li>`).join('');
	return `<div class="seeds"><h4>${esc(STRINGS.seedsHeader)}</h4><ul>${lis}</ul></div>`;
}

/**
 * Render the "done" completion-conditions checklist. The ✓ mark only appears when `proven` — a
 * real, passing story backs the list; NO STORY and failed stories get a neutral "○" instead, so
 * the checklist never reads as fulfilled when it isn't.
 */
function renderDone(done, proven) {
	if (!done || done.length === 0) {
		return '';
	}
	const lis = done.map(d => `<li>${esc(d)}</li>`).join('');
	const cls = proven ? 'checklist checklist-proven' : 'checklist checklist-unproven';
	return `<div class="done"><h4>${esc(STRINGS.doneHeader)}</h4><ul class="${cls}">${lis}</ul></div>`;
}

/** Render the failure block (auto-expanded error text) when a story failed. */
function renderFailure(item) {
	if (item.kind === 'nostory') {
		return '';
	}
	const story = item.story;
	if (story.passed) {
		return '';
	}
	const text = story.errorText || STRINGS.failureFallback;
	return `<details class="failure" open><summary>${esc(STRINGS.failureSummary)}</summary><pre>${esc(text)}</pre></details>`;
}

/**
 * Render the compact owner mark control (verdict toggle + on-demand note) for one story card or
 * NO STORY row. All state lives client-side in localStorage (`br-mark:<feature>\x00<title>`) —
 * this only emits the inert markup + data hooks; REPORT_JS hydrates it, cycles the toggle, and
 * feeds the sticky export bar. `hash` is empty for NO STORY rows (kit contract, no story to hash).
 */
function renderMark(featureName, item) {
	const attention = item.badges.some(isAttentionBadge) ? '1' : '0';
	return `<div class="mark" data-feature="${esc(featureName)}" data-title="${esc(item.title)}" data-hash="${esc(item.hash ?? '')}" data-attention="${attention}">
		<button type="button" class="mark-btn" data-state="unmarked"><span class="mark-btn-dot"></span><span class="mark-btn-text">${esc(STRINGS.markUnmarked)}</span></button>
		<span class="mark-stale" hidden>${esc(STRINGS.markStale)}</span>
		<button type="button" class="mark-note-toggle" aria-label="${esc(STRINGS.markNoteToggleLabel)}" title="${esc(STRINGS.markNoteToggleLabel)}">✎</button>
		<input type="text" class="mark-note-input" placeholder="${esc(STRINGS.markNotePlaceholder)}" maxlength="200" hidden>
	</div>`;
}

/** Slugify a string into a stable DOM id fragment. */
function slug(s) {
	return String(s).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 60);
}

/** Left-edge spine color class for an item card: fail > changed > new/proposed > gap > pass. */
function spineClass(item) {
	if (item.kind === 'nostory') {
		return 'st-gap';
	}
	if (item.badges.includes('fail')) {
		return 'st-fail';
	}
	if (item.badges.includes('changed')) {
		return 'st-changed';
	}
	if (item.badges.includes('new')) {
		return 'st-new';
	}
	if (item.badges.includes('proposed')) {
		return 'st-proposed';
	}
	if (item.kind === 'unspecified') {
		return 'st-gap';
	}
	return 'st-pass';
}

/** Attention priority for sorting attention-worthy stories (lower sorts first). */
function attentionRank(item) {
	if (item.badges.includes('fail')) {
		return 0;
	}
	if (item.badges.includes('changed')) {
		return 1;
	}
	if (item.badges.includes('new')) {
		return 2;
	}
	if (item.badges.includes('proposed')) {
		return 3;
	}
	return 4;
}

/**
 * Render a single story/nostory/unspecified card as a one-line `<details>` row — title +
 * badges + its mark control in the summary, full media/seeds/done detail behind the tap.
 * Every card uses this same collapsible shape (kit contract: unify, don't duplicate the
 * approved-row visual language); `opts.open` only controls its DEFAULT state — attention
 * items (failing/CHANGED/NEW/PROPOSED/UNSPECIFIED) start open, approved-unchanged start
 * collapsed. REPORT_JS may override this per-card on load based on the owner's stored mark
 * (kit contract §4: a previously bien/falla-marked card starts collapsed, unless it's
 * failing/CHANGED with a stale mark, which stays open for re-review) and auto-collapses a
 * card the moment the owner sets a mark on it (kit contract §3).
 */
function renderItem(item, dials, featureName, opts) {
	const open = !!(opts && opts.open);
	const attention = item.badges.some(isAttentionBadge);
	const id = `story-${slug(item.title)}`;
	const badges = item.badges.map(renderBadge).join('');
	const mark = renderMark(featureName, item);

	let intro = '';
	if (item.kind === 'nostory') {
		intro = `<p class="warn-lead">${esc(STRINGS.nostoryIntro)}</p>`;
	} else if (item.kind === 'unspecified') {
		intro = `<p class="warn-lead">${esc(STRINGS.unspecifiedIntro)}</p>`;
	}

	const proven = item.kind === 'story' && item.story.passed === true;
	const body = `${intro}
		${renderMedia(item, dials)}
		${renderSeeds(item.kind === 'nostory' ? [] : item.story.seeds)}
		${renderDone(item.done, proven)}
		${renderFailure(item)}`;

	return `<details class="item item-collapsed ${spineClass(item)} ${attention ? 'attention' : ''} ${item.kind}"${open ? ' open' : ''} id="${id}" data-attention="${attention ? '1' : '0'}" ${filterAttrs(item)}>
		<summary class="item-summary">
			<h3>${esc(item.title)}</h3>
			<div class="badges">${badges}</div>
			${mark}
		</summary>
		<div class="item-body">${body}</div>
	</details>`;
}

/**
 * Render the "sin implementar" burn-down list for one feature's NO STORY behaviors: a compact
 * row per behavior (title + optional "propuesto" tag), done-conditions tucked behind a tap —
 * never a full-size card. Keeps the honest red signal without drowning the real stories.
 */
function renderNostoryBurndown(items, featureName) {
	if (!items.length) {
		return '';
	}
	const rows = items.map(item => {
		const proposedTag = item.proposed ? `<span class="burndown-proposed">${esc(STRINGS.burndownProposedTag)}</span>` : '';
		const mark = renderMark(featureName, item);
		const doneHtml = renderDone(item.done, false);
		const attrs = filterAttrs(item);
		if (!doneHtml) {
			return `<li class="burndown-row burndown-row-plain" ${attrs}><span class="burndown-title">${esc(item.title)}</span>${proposedTag}${mark}</li>`;
		}
		return `<li class="burndown-row" ${attrs}><details><summary><span class="burndown-title">${esc(item.title)}</span>${proposedTag}${mark}</summary>${doneHtml}</details></li>`;
	}).join('');
	return `<div class="burndown">
		<h4 class="burndown-head">${esc(STRINGS.burndownHead)} <span class="burndown-count">${items.length}</span></h4>
		<ul class="burndown-list">${rows}</ul>
	</div>`;
}

/**
 * Render a feature section (header + askedFor + its items), attention-first: failing → changed
 * → new/proposed stories as full cards, then approved/unchanged stories collapsed to one-line
 * rows, then the NO STORY behaviors as a compact burn-down list — so the 66 gaps read as a map,
 * not a wall of red noise, and the real stories aren't buried under them.
 */
function renderFeature(feature, dials) {
	const id = `feature-${slug(feature.name)}`;

	const attentionItems = [];
	const approvedItems = [];
	const nostoryItems = [];
	for (const item of feature.items) {
		if (item.kind === 'nostory') {
			nostoryItems.push(item);
		} else if (item.badges.some(isAttentionBadge)) {
			attentionItems.push(item);
		} else {
			approvedItems.push(item);
		}
	}
	attentionItems.sort((a, b) => attentionRank(a) - attentionRank(b));

	const attentionHtml = attentionItems.map(i => renderItem(i, dials, feature.name, { open: true })).join('');
	const approvedHtml = approvedItems.length
		? `<div class="approved-group"><h4 class="approved-head">${esc(STRINGS.approvedHead(approvedItems.length))}</h4>${approvedItems.map(i => renderItem(i, dials, feature.name, { open: false })).join('')}</div>`
		: '';
	const gapBadge = nostoryItems.length ? `<span class="feature-gap-badge">${esc(STRINGS.featureGapBadge(nostoryItems.length))}</span>` : '';

	return `<section class="feature" id="${id}">
		<div class="feature-head">
			<h2>${esc(feature.name)}${gapBadge}</h2>
			<blockquote class="asked"><span class="asked-label">${esc(STRINGS.askedLabel)}</span>${esc(feature.askedFor)}</blockquote>
		</div>
		${attentionHtml}
		${approvedHtml}
		${renderNostoryBurndown(nostoryItems, feature.name)}
	</section>`;
}

/** Render the nav sidebar listing features/stories with attention dots. */
function renderNav(model) {
	const groups = [];
	for (const feature of model.features) {
		const links = feature.items.map(item => {
			const attention = item.badges.some(isAttentionBadge);
			const id = `story-${slug(item.title)}`;
			return `<li><a href="#${id}" ${filterAttrs(item)}>${attention ? '<span class="dot"></span>' : '<span class="dot dot-off"></span>'}${esc(item.title)}</a></li>`;
		}).join('');
		groups.push(`<li class="nav-feature"><a href="#feature-${slug(feature.name)}">${esc(feature.name)}</a><ul>${links}</ul></li>`);
	}
	for (const [featureName, items] of model.orphanByFeature) {
		const links = items.map(item => {
			const id = `story-${slug(item.title)}`;
			return `<li><a href="#${id}" ${filterAttrs(item)}><span class="dot"></span>${esc(item.title)}</a></li>`;
		}).join('');
		groups.push(`<li class="nav-feature"><span>${esc(featureName)} · ${esc(STRINGS.orphanSuffix)}</span><ul>${links}</ul></li>`);
	}
	return `<nav class="sidebar" id="nav-sidebar">
		<button type="button" class="nav-toggle" id="nav-toggle" aria-expanded="false" aria-controls="nav-list">${esc(STRINGS.navIndex)} <span class="nav-toggle-icon">▾</span></button>
		<div class="nav-list" id="nav-list">
			<h2>${esc(STRINGS.navIndex)}</h2>
			<ul>${groups.join('')}</ul>
		</div>
	</nav>`;
}

/**
 * Render the "Cómo usar este reporte" guide: a badges-legend-style `<details>`, open by default,
 * mapping what the owner sees to what to do about it, plus the 4-step review loop. Its open/closed
 * state persists across reloads via localStorage (REPORT_JS `br-guide-open`), same mechanic as the
 * mark controls' persistence, so a dismissed guide stays out of the way on the next visit.
 */
function renderGuide() {
	const mapLis = STRINGS.guideMap.map(li => `<li>${li}</li>`).join('');
	const stepLis = STRINGS.guideSteps.map(li => `<li>${esc(li)}</li>`).join('');
	return `<details class="guide" id="guide-details" open>
		<summary>${esc(STRINGS.guideSummary)}</summary>
		<div class="guide-body">
			<ul class="guide-map">${mapLis}</ul>
			<ol class="guide-steps">${stepLis}</ol>
		</div>
	</details>`;
}

/** Render the filter chip bar (single-select, "Todo" default) with live counts per chip. */
function renderFilterBar(counts) {
	const chips = FILTER_CHIPS.map(chip => {
		const active = chip.key === 'todo' ? ' is-active' : '';
		return `<button type="button" class="filter-chip${active}" data-filter-key="${chip.key}">${esc(chip.label)} <span class="filter-chip-count">${counts[chip.key] ?? 0}</span></button>`;
	}).join('');
	return `<div class="filter-bar" id="filter-bar" role="group" aria-label="${esc(STRINGS.filterAriaLabel)}">${chips}</div>`;
}

/** Render the collapsible badge legend. */
function renderLegend() {
	const rows = BADGE_LEGEND.map(([type, , meaning]) => `<div class="legend-row">${renderBadge(type)}<span class="legend-meaning">${esc(meaning)}</span></div>`).join('');
	return `<details class="legend"><summary>${esc(STRINGS.legendSummary)}</summary><div class="legend-body">${rows}</div></details>`;
}

/** Render the metrics dashboard. */
function renderMetrics(metricsModel) {
	const cards = metricsModel.cards.map(c => {
		const spark = sparkline(c.history);
		const top = spark ? `<div class="card-top">${spark}</div>` : '';
		return `<div class="card">
			${top}
			<div class="card-value">${esc(c.value)}</div>
			<div class="card-label">${esc(c.label)}</div>
			<div class="card-sub">${esc(c.sub)}</div>
		</div>`;
	}).join('');
	return `<section class="metrics" id="metrics">
		<h2>${esc(STRINGS.metricsHeading)}</h2>
		<p class="metrics-new">${STRINGS.metricsNew(metricsModel.newThisReport)}</p>
		<div class="cards">${cards}</div>
	</section>`;
}

/** Assemble the full HTML document. */
function renderHtml(model, metricsModel, generatedAt, dials) {
	mediaLog = [];
	const c = model.counts;
	const filterCounts = countFilterChips(model);
	const featureSections = model.features.map(f => renderFeature(f, dials)).join('');
	const orphanSections = [...model.orphanByFeature.entries()].map(([featureName, items]) => {
		const rendered = items.map(i => renderItem(i, dials, featureName, { open: true })).join('');
		return `<section class="feature orphan" id="feature-orphan-${slug(featureName)}">
			<div class="feature-head"><h2>${esc(featureName)} · ${esc(STRINGS.orphanSuffix)}</h2></div>
			${rendered}
		</section>`;
	}).join('');

	const featuresWithGaps = model.features.filter(f => f.items.some(i => i.kind === 'nostory')).length;
	const triageLine = c.noStory > 0
		? `<p class="triage-line">${esc(STRINGS.triageLine(c.noStory, featuresWithGaps))}</p>`
		: '';

	const css = REPORT_CSS;
	const js = renderReportJs(STRINGS);

	return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(STRINGS.pageTitle)}</title>
<style>${css}</style>
</head>
<body data-generated-at="${esc(generatedAt)}">
<header class="report-head">
	<div class="head-inner">
		<h1>${esc(STRINGS.pageTitle)}</h1>
		<p class="subtitle">${esc(STRINGS.subtitle)}</p>
		${triageLine}
		<div class="counts">
			<span class="count count-pass">${esc(STRINGS.countPass(c.pass))}</span>
			<span class="count count-fail">${esc(STRINGS.countFail(c.fail))}</span>
			<span class="count count-new">${esc(STRINGS.countNew(c.new))}</span>
			<span class="count count-changed">${esc(STRINGS.countChanged(c.changed))}</span>
		</div>
		${renderFilterBar(filterCounts)}
		<div class="controls">
			<span class="timestamp">${esc(STRINGS.timestampLabel(generatedAt))}</span>
		</div>
		${renderLegend()}
	</div>
</header>
<div class="layout">
	${renderNav(model)}
	<main class="content">
		<p class="filter-empty-note" id="filter-empty-note" hidden>${esc(STRINGS.filterEmptyNote)}</p>
		${renderGuide()}
		${renderMetrics(metricsModel)}
		${featureSections}
		${orphanSections}
	</main>
</div>
<div class="lightbox" id="lightbox" role="dialog" aria-modal="true" aria-label="${esc(STRINGS.lightbox.ariaLabel)}" aria-hidden="true">
	<button type="button" class="lightbox-close" id="lightbox-close" aria-label="${esc(STRINGS.lightbox.close)}">✕</button>
	<button type="button" class="lightbox-nav lightbox-prev" id="lightbox-prev" aria-label="${esc(STRINGS.lightbox.prev)}">‹</button>
	<img class="lightbox-stage" id="lightbox-img" src="" alt="">
	<button type="button" class="lightbox-nav lightbox-next" id="lightbox-next" aria-label="${esc(STRINGS.lightbox.next)}">›</button>
	<div class="lightbox-bar">
		<span class="lightbox-pos" id="lightbox-pos"></span>
		<p class="lightbox-caption" id="lightbox-caption"></p>
	</div>
</div>
<div class="verdict-bar" id="verdict-bar">
	<div class="verdict-bar-inner">
		<span class="verdict-counts" id="verdict-counts">${esc(STRINGS.verdict.none)}</span>
		<div class="verdict-actions">
			<button type="button" class="verdict-btn verdict-copy" id="verdict-copy">${esc(STRINGS.verdict.copy)}</button>
			<button type="button" class="verdict-btn verdict-clear" id="verdict-clear">${esc(STRINGS.verdict.clear)}</button>
		</div>
	</div>
</div>
<div class="verdict-modal" id="verdict-modal" role="dialog" aria-modal="true" aria-label="${esc(STRINGS.verdict.modalTitle)}" aria-hidden="true">
	<div class="verdict-modal-box">
		<h3>${esc(STRINGS.verdict.modalTitle)}</h3>
		<p class="verdict-modal-hint">${esc(STRINGS.verdict.modalHint)}</p>
		<textarea class="verdict-modal-text" id="verdict-modal-text" readonly rows="12"></textarea>
		<div class="verdict-modal-actions">
			<button type="button" class="verdict-modal-copy" id="verdict-modal-copy">${esc(STRINGS.verdict.modalCopy)}</button>
			<button type="button" class="verdict-modal-close" id="verdict-modal-close">${esc(STRINGS.verdict.modalClose)}</button>
		</div>
	</div>
</div>
<script>${js}</script>
</body>
</html>`;
}

// ---------------------------------------------------------------------------
// Generated per-category filter CSS: for each non-"todo" chip, hide any [data-filter-item]
// that doesn't carry that category, and collapse the containers (feature section, approved
// group, nostory burndown, nav feature group) once none of their items match anymore.
// ---------------------------------------------------------------------------
const FILTER_CONTAINERS = ['.feature', '.approved-group', '.burndown', '.nav-feature'];
const FILTER_CSS = FILTER_CHIPS.filter(chip => chip.key !== 'todo').map(chip => {
	const itemRule = `body[data-active-filter="${chip.key}"] [data-filter-item]:not([data-filter~="${chip.key}"]){display:none;}`;
	const containerRules = FILTER_CONTAINERS
		.map(sel => `body[data-active-filter="${chip.key}"] ${sel}:not(:has([data-filter-item][data-filter~="${chip.key}"])){display:none;}`)
		.join('\n');
	return `${itemRule}\n${containerRules}`;
}).join('\n');

// ---------------------------------------------------------------------------
// Inline CSS — dark, calm, phone-first, single column, no external fonts.
// ---------------------------------------------------------------------------
const REPORT_CSS = `
:root{
	--bg:#0e1117; --bg-soft:#161b22; --bg-card:#1a2029; --border:#2a313c; --border-2:#333b48;
	--fg:#e6edf3; --muted:#8b98a9; --muted-2:#5b6674; --accent:#a6a1ff; --accent-bg:#211f36;
	--pass:#3fb950; --fail:#f85149; --new:#58a6ff; --changed:#d29922;
	--proposed:#a371f7; --nostory:#f85149; --unspecified:#db6d28; --edge:#39c5cf; --happy:#3fb950;
	--radius:12px; --shadow:0 1px 2px rgba(0,0,0,.35);
	--mono:ui-monospace,"SF Mono",SFMono-Regular,Menlo,Consolas,monospace;
	--card-sticky-top:150px;
}
*{box-sizing:border-box;}
html{scroll-behavior:smooth;}
body{margin:0;background:var(--bg);color:var(--fg);
	font:16px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
	-webkit-font-smoothing:antialiased;overflow-wrap:break-word;word-break:break-word;}
html{overflow-x:hidden;}
img,video,svg,pre,textarea{max-width:100%;}
h1,h2,h3,h4{font-weight:650;line-height:1.25;margin:0 0 .4em;}
a{color:var(--accent);text-decoration:none;}
a:hover{text-decoration:underline;}
:focus-visible{outline:2px solid var(--accent);outline-offset:2px;border-radius:6px;}
.report-head{background:linear-gradient(180deg,#141b26,var(--bg));border-bottom:1px solid var(--border);padding:22px 18px 16px;position:sticky;top:0;z-index:20;backdrop-filter:blur(8px);}
.head-inner{max-width:1180px;margin:0 auto;min-width:0;}
.report-head h1{font-size:1.35rem;}
.subtitle{color:var(--muted);margin:.2em 0 .8em;font-size:.92rem;max-width:60ch;}
.triage-line{color:var(--unspecified);font-weight:600;font-size:.92rem;margin:0 0 .8em;}
.counts{display:flex;flex-wrap:wrap;gap:8px;margin-bottom:10px;}
.count{font-family:var(--mono);font-size:.76rem;font-weight:600;padding:4px 10px;border-radius:999px;background:var(--bg-card);border:1px solid var(--border);white-space:nowrap;}
.count-pass{color:var(--pass);} .count-fail{color:var(--fail);} .count-new{color:var(--new);} .count-changed{color:var(--changed);}
.controls{display:flex;align-items:center;gap:16px;flex-wrap:wrap;margin-bottom:6px;}
.timestamp{color:var(--muted-2);font-size:.74rem;font-family:var(--mono);}
.filter-bar{display:flex;flex-wrap:wrap;gap:8px;margin:2px 0 12px;}
.filter-chip{display:inline-flex;align-items:center;gap:7px;background:var(--bg-card);border:1px solid var(--border-2);border-left:3px solid var(--border-2);
	color:var(--muted);font-size:.82rem;font-weight:600;padding:8px 14px;border-radius:999px;cursor:pointer;min-height:40px;box-shadow:var(--shadow);}
.filter-chip-count{font-family:var(--mono);background:rgba(139,152,169,.16);color:inherit;border-radius:999px;padding:1px 8px;font-size:.74rem;font-weight:700;}
.filter-chip[data-filter-key="fail"]{border-left-color:var(--fail);}
.filter-chip[data-filter-key="changed"]{border-left-color:var(--changed);}
.filter-chip[data-filter-key="new"],.filter-chip[data-filter-key="attention"]{border-left-color:var(--accent);}
.filter-chip[data-filter-key="proposed"]{border-left-color:var(--proposed);border-left-style:dashed;}
.filter-chip[data-filter-key="nostory"]{border-left-color:var(--nostory);}
.filter-chip[data-filter-key="approved"]{border-left-color:var(--pass);}
.filter-chip.is-active{background:var(--accent-bg);border-color:var(--accent);color:var(--accent);}
.filter-chip.is-active .filter-chip-count{background:rgba(166,161,255,.22);}
.filter-empty-note{color:var(--muted);font-size:.9rem;font-style:italic;padding:20px 0;text-align:center;}
.guide,.legend{background:var(--bg-soft);border:1px solid var(--border);border-radius:var(--radius);box-shadow:var(--shadow);overflow:hidden;}
.legend{margin-top:6px;font-size:.85rem;}
.guide{margin:0 0 30px;}
.guide>summary,.legend>summary{cursor:pointer;padding:14px 18px;display:flex;justify-content:space-between;align-items:center;gap:10px;list-style:none;}
.guide>summary::-webkit-details-marker,.legend>summary::-webkit-details-marker{display:none;}
.guide>summary{font-size:1.02rem;font-weight:650;}
.legend>summary{color:var(--fg);font-weight:600;}
.guide>summary::after,.legend>summary::after{content:"⌄";color:var(--muted-2);font-size:1.15rem;transition:transform .2s;flex:0 0 auto;}
.guide[open]>summary::after,.legend[open]>summary::after{transform:rotate(180deg);}
.guide-body{padding:0 18px 18px;}
.legend-body{display:grid;gap:8px;padding:2px 18px 16px;}
.legend-row{display:flex;align-items:flex-start;gap:10px;}
.legend-meaning{color:var(--muted);font-size:.83rem;}
.guide-map,.guide-steps{margin:.4em 0;padding-left:22px;}
.guide-map li,.guide-steps li{font-size:.92rem;margin:.4em 0;color:var(--fg);}
.guide-map strong{color:var(--accent);}
.layout{max-width:1180px;margin:0 auto;display:flex;gap:26px;padding:22px 18px 104px;align-items:flex-start;min-width:0;}
.sidebar{flex:0 0 240px;position:sticky;top:var(--card-sticky-top);max-height:calc(100vh - 170px);overflow:auto;font-size:.85rem;min-width:0;}
.sidebar h2{font-size:.72rem;text-transform:uppercase;letter-spacing:.08em;color:var(--muted-2);font-family:var(--mono);}
.sidebar ul{list-style:none;padding:0;margin:0;}
.sidebar .nav-feature{margin-bottom:12px;min-width:0;}
.sidebar .nav-feature>a,.sidebar .nav-feature>span{font-weight:600;color:var(--fg);display:block;margin-bottom:4px;}
.sidebar .nav-feature ul{padding-left:2px;}
.sidebar li a{display:flex;align-items:center;gap:7px;padding:7px 0;color:var(--muted);min-height:32px;min-width:0;}
.dot{width:7px;height:7px;border-radius:50%;background:var(--accent);flex:0 0 auto;}
.dot-off{background:transparent;border:1px solid var(--border);}
.nav-toggle{display:none;width:100%;text-align:left;align-items:center;justify-content:space-between;gap:8px;
	background:var(--bg-card);border:1px solid var(--border-2);color:var(--fg);font-size:.92rem;font-weight:600;
	padding:12px 14px;border-radius:var(--radius);cursor:pointer;min-height:44px;box-shadow:var(--shadow);}
.nav-toggle-icon{color:var(--muted-2);}
.nav-list{display:block;}
.content{flex:1 1 auto;min-width:0;}
.metrics{margin-bottom:34px;min-width:0;}
.metrics h2,.feature-head h2,.orphan .feature-head h2{font-size:1.05rem;display:flex;align-items:center;gap:10px;flex-wrap:wrap;}
.metrics h2::before,.feature-head h2::before{content:"";width:6px;height:18px;background:var(--accent);border-radius:2px;flex:0 0 auto;display:inline-block;}
.metrics-new{color:var(--muted);font-size:.9rem;margin:.2em 0 1em;}
.cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:10px;min-width:0;}
.card{background:var(--bg-card);border:1px solid var(--border);border-radius:var(--radius);padding:12px 14px;box-shadow:var(--shadow);min-width:0;}
.card-top{display:flex;justify-content:flex-end;align-items:center;gap:8px;}
.card-label{font-size:.78rem;color:var(--fg);font-weight:600;margin:2px 0 1px;}
.spark{color:var(--accent);opacity:.85;}
.card-value{font-family:var(--mono);font-size:1.55rem;font-weight:700;letter-spacing:-.02em;line-height:1;}
.card-sub{font-family:var(--mono);font-size:.74rem;color:var(--muted-2);margin-top:3px;}
.feature{margin-bottom:40px;min-width:0;}
.feature-gap-badge{font-size:.68rem;font-weight:700;letter-spacing:.03em;padding:3px 9px;border-radius:999px;
	background:rgba(219,109,40,.18);color:#ffa657;white-space:nowrap;}
.asked{margin:.2em 0 1.2em;padding:12px 16px;background:var(--bg-soft);border-left:3px solid var(--accent);border-radius:0 var(--radius) var(--radius) 0;color:var(--fg);font-size:.95rem;overflow-wrap:break-word;}
.asked-label{display:block;font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;color:var(--accent);margin-bottom:4px;font-weight:700;font-family:var(--mono);}
.item{background:var(--bg-soft);border:1px solid var(--border);border-left-width:4px;border-radius:var(--radius);padding:18px;margin-bottom:18px;min-width:0;}
.item.st-pass{border-left-color:var(--pass);} .item.st-fail{border-left-color:var(--fail);}
.item.st-new{border-left-color:var(--accent);} .item.st-changed{border-left-color:var(--changed);}
.item.st-proposed{border-left-color:var(--proposed);} .item.st-gap{border-left-color:var(--nostory);}
.item.nostory,.item.unspecified{background:#1f1416;}
.item.unspecified{border-left-color:var(--unspecified);}
.approved-group{margin:18px 0 26px;min-width:0;}
.approved-head{font-size:.78rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin:0 0 8px;}
details.item-collapsed{padding:0;}
details.item-collapsed>.item-summary{list-style:none;display:flex;align-items:center;justify-content:space-between;
	gap:12px;flex-wrap:wrap;padding:14px 18px;cursor:pointer;min-height:44px;min-width:0;}
details.item-collapsed>.item-summary::-webkit-details-marker{display:none;}
details.item-collapsed>.item-summary h3{font-size:.95rem;margin:0;flex:1 1 220px;min-width:0;}
details.item-collapsed[open]>.item-summary{border-bottom:1px solid var(--border);
	position:sticky;top:var(--card-sticky-top);z-index:10;background:var(--bg-soft);border-radius:var(--radius) var(--radius) 0 0;}
.item.unspecified>.item-summary{background:#1f1416;}
details.item-collapsed>.item-body{padding:16px 18px 18px;min-width:0;}
.burndown{margin-top:22px;padding-top:16px;border-top:1px dashed var(--border);min-width:0;}
.burndown-head{font-size:.8rem;text-transform:uppercase;letter-spacing:.05em;color:var(--nostory);margin:0 0 10px;
	display:flex;align-items:center;gap:8px;}
.burndown-count{font-family:var(--mono);background:rgba(248,81,73,.16);color:#ff7b72;border-radius:999px;padding:1px 9px;font-size:.75rem;}
.burndown-list{list-style:none;margin:0;padding:0;display:flex;flex-direction:column;gap:6px;min-width:0;}
.burndown-row-plain{background:var(--bg-card);border:1px solid var(--border);border-left:3px solid var(--nostory);border-radius:8px;padding:10px 12px;
	display:flex;align-items:center;gap:8px;min-height:40px;min-width:0;}
.burndown-row details{background:var(--bg-card);border:1px solid var(--border);border-left:3px solid var(--nostory);border-radius:8px;}
.burndown-row summary{list-style:none;display:flex;align-items:center;gap:8px;padding:10px 12px;cursor:pointer;min-height:40px;min-width:0;}
.burndown-row summary::-webkit-details-marker{display:none;}
.burndown-row details>*:not(summary){padding:0 12px 12px;}
.burndown-row .done{margin-top:0;}
.burndown-title{color:var(--fg);font-size:.88rem;flex:1;min-width:0;}
.burndown-proposed{font-family:var(--mono);font-size:.68rem;color:var(--proposed);border:1px solid var(--proposed);border-style:dashed;border-radius:6px;padding:1px 6px;}
.badges{display:flex;flex-wrap:wrap;gap:6px;}
.badge{font-family:var(--mono);font-size:.66rem;font-weight:700;letter-spacing:.04em;text-transform:uppercase;padding:3px 8px;border-radius:6px;white-space:nowrap;border:1px solid transparent;}
.badge-pass{background:rgba(63,185,80,.14);color:var(--pass);border-color:rgba(63,185,80,.4);}
.badge-fail{background:rgba(248,81,73,.14);color:var(--fail);border-color:rgba(248,81,73,.4);}
.badge-happy{background:transparent;color:var(--muted);border-color:var(--border-2);}
.badge-edge{background:rgba(57,197,207,.14);color:var(--edge);border-color:rgba(57,197,207,.4);}
.badge-new{background:rgba(166,161,255,.14);color:var(--accent);border-color:rgba(166,161,255,.4);}
.badge-changed{background:rgba(210,153,34,.14);color:var(--changed);border-color:rgba(210,153,34,.4);}
.badge-proposed{background:transparent;color:var(--proposed);border-color:var(--proposed);border-style:dashed;}
.badge-nostory{background:rgba(248,81,73,.18);color:#ff7b72;border-color:rgba(248,81,73,.4);}
.badge-unspecified{background:rgba(219,109,40,.16);color:#ffa657;border-color:rgba(219,109,40,.4);}
.warn-lead{color:#ffa198;font-size:.9rem;margin:.4em 0 .2em;}
.snaps{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:12px;margin:14px 0;min-width:0;}
.snap{margin:0;background:var(--bg-card);border:1px solid var(--border);border-radius:10px;overflow:hidden;min-width:0;}
.snap img{width:100%;display:block;background:#000;}
.snap figcaption{padding:8px 10px;font-size:.8rem;color:var(--muted);}
.lightbox-img{cursor:zoom-in;}
.gif{margin:14px 0 6px;text-align:center;}
.gif img{width:100%;border-radius:10px;border:1px solid var(--border);background:#000;}
.gif figcaption{font-size:.8rem;color:var(--muted);margin-top:6px;}
.clip{margin:14px 0 6px;text-align:center;}
.clip-speed{display:flex;align-items:center;justify-content:center;gap:8px;margin-bottom:8px;flex-wrap:wrap;}
.clip-speed-label{font-size:.72rem;text-transform:uppercase;letter-spacing:.05em;color:var(--muted);margin-right:2px;}
.speed-btn{background:var(--bg-card);border:1px solid var(--border);color:var(--muted);font-size:.8rem;
	font-weight:600;padding:7px 13px;border-radius:999px;cursor:pointer;min-height:36px;}
.speed-btn.is-active{background:var(--accent-bg);border-color:var(--accent);color:var(--accent);}
.clip video{width:100%;border-radius:10px;border:1px solid var(--border);background:#000;display:block;margin:0 auto;}
.clip figcaption{font-size:.8rem;color:var(--muted);margin-top:6px;}
.media-note{color:var(--muted);font-size:.83rem;font-style:italic;margin:10px 0;}
.media-warn{color:#ffa657;font-style:normal;}
.seeds,.done{margin-top:14px;min-width:0;}
.seeds h4,.done h4{font-size:.72rem;text-transform:uppercase;letter-spacing:.06em;color:var(--muted-2);font-family:var(--mono);}
.seeds ul,.done ul{margin:.3em 0 0;padding-left:20px;}
.seeds li,.done li{font-size:.88rem;margin:.2em 0;color:var(--fg);overflow-wrap:break-word;}
.seeds li{font-family:var(--mono);font-size:.82rem;}
.checklist{list-style:none;padding-left:0;}
.checklist li{position:relative;padding-left:24px;}
.checklist-proven li::before{content:"✓";position:absolute;left:0;color:var(--pass);font-weight:700;}
.checklist-unproven li::before{content:"○";position:absolute;left:0;color:var(--muted);font-weight:700;}
.failure{margin-top:14px;background:#1f1416;border:1px solid var(--fail);border-radius:8px;padding:6px 12px;min-width:0;}
.failure summary{cursor:pointer;color:var(--fail);font-weight:600;font-size:.85rem;}
.failure pre{white-space:pre-wrap;overflow-wrap:break-word;word-break:break-word;font-size:.8rem;font-family:var(--mono);color:#ffb4ae;overflow-x:auto;max-width:100%;}
${FILTER_CSS}
.lightbox{display:none;position:fixed;inset:0;z-index:100;background:rgba(6,9,14,.94);
	backdrop-filter:blur(6px);flex-direction:column;align-items:center;justify-content:center;padding:16px;}
.lightbox.open{display:flex;}
.lightbox-stage{max-width:min(94vw,1100px);max-height:66vh;object-fit:contain;border-radius:8px;
	box-shadow:0 12px 40px rgba(0,0,0,.5);background:#000;}
.lightbox-bar{max-width:min(94vw,1100px);width:100%;padding:12px 6px 0;text-align:center;}
.lightbox-pos{display:block;font-size:.72rem;color:var(--muted);letter-spacing:.05em;margin-bottom:4px;
	font-variant-numeric:tabular-nums;}
.lightbox-caption{margin:0;color:var(--fg);font-size:.92rem;line-height:1.4;}
.lightbox-close{position:absolute;top:max(14px,env(safe-area-inset-top));right:14px;width:40px;height:40px;
	border-radius:50%;background:var(--bg-card);border:1px solid var(--border);color:var(--fg);
	font-size:1.1rem;cursor:pointer;}
.lightbox-nav{position:absolute;top:50%;transform:translateY(-50%);width:52px;height:52px;
	border-radius:50%;background:var(--bg-card);border:1px solid var(--border);color:var(--fg);
	font-size:1.7rem;line-height:1;cursor:pointer;display:flex;align-items:center;justify-content:center;}
.lightbox-nav:active{background:var(--bg-soft);}
.lightbox-prev{left:10px;}
.lightbox-next{right:10px;}
body.lightbox-locked{overflow:hidden;}
.mark{display:flex;align-items:center;gap:6px;flex-wrap:wrap;margin-top:10px;}
details.item-collapsed>.item-summary .mark,.burndown-row-plain .mark,.burndown-row summary .mark{margin-top:0;}
.mark-btn{display:inline-flex;align-items:center;gap:7px;background:var(--bg-card);border:1px solid var(--border-2);
	color:var(--muted);font-size:.82rem;font-weight:600;padding:8px 12px;border-radius:999px;cursor:pointer;min-height:40px;}
.mark-btn-dot{width:9px;height:9px;border-radius:50%;background:var(--muted);flex:0 0 auto;}
.mark-btn[data-state="bien"]{border-color:var(--pass);color:var(--pass);}
.mark-btn[data-state="bien"] .mark-btn-dot{background:var(--pass);}
.mark-btn[data-state="falla"]{border-color:var(--fail);color:var(--fail);}
.mark-btn[data-state="falla"] .mark-btn-dot{background:var(--fail);}
.mark-note-toggle{background:var(--bg-card);border:1px solid var(--border-2);color:var(--muted);
	font-size:.95rem;width:40px;height:40px;border-radius:50%;cursor:pointer;flex:0 0 auto;}
.mark-note-input{flex:1 1 160px;min-width:0;background:var(--bg-card);border:1px solid var(--border-2);
	color:var(--fg);font-size:.85rem;border-radius:8px;padding:9px 11px;min-height:40px;}
.mark-stale{font-size:.72rem;color:var(--changed);}
/* Owner verdict color — an edge + soft wash on the whole row/card, distinct from the PASS/FAIL
   result badges (which stay chips): this is the OWNER's ✓/✗, not the test's. "Sin marcar" stays
   the plain, unwashed look. */
.item-collapsed:has(.mark[data-mark-state="bien"]){box-shadow:inset 4px 0 0 var(--pass);background:linear-gradient(rgba(63,185,80,.07),rgba(63,185,80,.07)),var(--bg-soft);}
.item-collapsed:has(.mark[data-mark-state="falla"]){box-shadow:inset 4px 0 0 var(--fail);background:linear-gradient(rgba(248,81,73,.07),rgba(248,81,73,.07)),var(--bg-soft);}
/* The sticky summary paints its own opaque background above the card's, so an OPEN marked
   card (rare: a stale fail/changed mark) needs the same edge+wash repeated on the summary
   itself for visual continuity between the pinned header and the scrolling body below it. */
.item-collapsed:has(.mark[data-mark-state="bien"])>.item-summary{box-shadow:inset 4px 0 0 var(--pass);background:linear-gradient(rgba(63,185,80,.07),rgba(63,185,80,.07)),var(--bg-soft);}
.item-collapsed:has(.mark[data-mark-state="falla"])>.item-summary{box-shadow:inset 4px 0 0 var(--fail);background:linear-gradient(rgba(248,81,73,.07),rgba(248,81,73,.07)),var(--bg-soft);}
.burndown-row-plain:has(.mark[data-mark-state="bien"]){box-shadow:inset 4px 0 0 var(--pass);background:linear-gradient(rgba(63,185,80,.07),rgba(63,185,80,.07)),var(--bg-card);}
.burndown-row-plain:has(.mark[data-mark-state="falla"]){box-shadow:inset 4px 0 0 var(--fail);background:linear-gradient(rgba(248,81,73,.07),rgba(248,81,73,.07)),var(--bg-card);}
.burndown-row:has(.mark[data-mark-state="bien"])>details{box-shadow:inset 4px 0 0 var(--pass);background:linear-gradient(rgba(63,185,80,.07),rgba(63,185,80,.07)),var(--bg-card);}
.burndown-row:has(.mark[data-mark-state="falla"])>details{box-shadow:inset 4px 0 0 var(--fail);background:linear-gradient(rgba(248,81,73,.07),rgba(248,81,73,.07)),var(--bg-card);}
.verdict-bar{position:fixed;left:0;right:0;bottom:0;z-index:60;background:rgba(14,17,23,.92);
	backdrop-filter:blur(10px);border-top:1px solid var(--border);padding:10px 18px calc(10px + env(safe-area-inset-bottom));min-width:0;}
.verdict-bar-inner{max-width:1180px;margin:0 auto;display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;min-width:0;}
.verdict-counts{display:flex;flex-wrap:wrap;align-items:baseline;gap:4px 12px;font-size:.82rem;color:var(--muted);font-weight:600;min-width:0;}
.verdict-counts b{font-family:var(--mono);font-size:.95rem;}
.verdict-counts .vb-ok b{color:var(--pass);} .verdict-counts .vb-fail b{color:var(--fail);} .verdict-counts .vb-note b{color:var(--changed);}
.verdict-actions{display:flex;gap:10px;flex-wrap:wrap;}
.verdict-btn{border-radius:999px;padding:9px 16px;font-size:.85rem;font-weight:600;cursor:pointer;min-height:40px;border:1px solid var(--border-2);white-space:nowrap;}
.verdict-copy{background:var(--accent);border-color:var(--accent);color:#0e0d1a;}
.verdict-clear{background:var(--bg-card);color:var(--muted);}
.verdict-bar.collapsed{background:transparent;border-top:none;padding:0 0 calc(10px + env(safe-area-inset-bottom));
	display:flex;justify-content:center;}
.verdict-bar.collapsed .verdict-bar-inner{background:var(--bg-card);border:1px solid var(--border);border-radius:999px;
	padding:6px 16px;width:auto;}
.verdict-bar.collapsed .verdict-counts{font-size:.76rem;color:var(--muted);}
.verdict-bar.collapsed .verdict-actions{display:none;}
.verdict-modal{display:none;position:fixed;inset:0;z-index:110;background:rgba(6,9,14,.92);backdrop-filter:blur(6px);
	align-items:center;justify-content:center;padding:16px;}
.verdict-modal.open{display:flex;}
.verdict-modal-box{background:var(--bg-soft);border:1px solid var(--border);border-radius:var(--radius);
	padding:20px;max-width:min(94vw,560px);width:100%;}
.verdict-modal-box h3{font-size:1.05rem;}
.verdict-modal-hint{color:var(--muted);font-size:.85rem;margin:.3em 0 .9em;}
.verdict-modal-text{width:100%;min-height:220px;background:var(--bg-card);border:1px solid var(--border);
	color:var(--fg);font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.82rem;border-radius:8px;padding:10px;resize:vertical;}
.verdict-modal-actions{display:flex;gap:10px;margin-top:14px;}
.verdict-modal-copy{background:var(--accent);border:1px solid var(--accent);color:#0e0d1a;
	font-size:.85rem;font-weight:600;padding:9px 16px;border-radius:999px;cursor:pointer;min-height:40px;}
.verdict-modal-close{background:var(--bg-card);border:1px solid var(--border);color:var(--fg);
	font-size:.85rem;font-weight:600;padding:9px 16px;border-radius:999px;cursor:pointer;min-height:40px;}
@media (max-width:820px){
	body{--card-sticky-top:52px;}
	.layout{flex-direction:column;padding:16px 12px 96px;}
	.sidebar{position:static;flex-basis:auto;max-height:none;width:100%;order:1;margin:0 0 18px;border-top:none;padding-top:0;}
	.content{order:2;}
	.report-head{position:static;}
	.snaps{grid-template-columns:1fr;}
	.cards{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;}
	.nav-toggle{display:flex;position:sticky;top:0;z-index:30;}
	.nav-list{display:none;padding-top:12px;}
	.sidebar.nav-open .nav-list{display:block;}
	.lightbox-stage{max-height:56vh;}
	.lightbox-nav{width:46px;height:46px;font-size:1.5rem;}
	.verdict-bar-inner{justify-content:center;text-align:center;}
	.mark-note-input{flex-basis:100%;}
}
`;

// ---------------------------------------------------------------------------
// Inline JS — filter toggle, mobile nav jump-menu, screenshot lightbox carousel, per-video speed
// buttons, the owner mark controls + sticky verdict export bar, and the usage-guide dismissal.
// Vanilla, no framework, no external requests (strict artifact CSP). A function (not a plain
// const) so the handful of owner-facing strings it emits (verdict labels, button text) can be
// interpolated from STRINGS — the 'bien'/'falla'/'unmarked' tokens below are internal state
// keys matched by REPORT_CSS selectors ([data-state="bien"] etc.) and must NOT be translated.
function renderReportJs(S) {
	return `
(function(){
	var KEY='br-filter';
	var bar=document.getElementById('filter-bar');
	if(!bar){return;}
	var buttons=Array.prototype.slice.call(bar.querySelectorAll('.filter-chip'));
	var emptyNote=document.getElementById('filter-empty-note');

	function apply(key){
		document.body.setAttribute('data-active-filter',key);
		buttons.forEach(function(btn){
			btn.classList.toggle('is-active',btn.getAttribute('data-filter-key')===key);
		});
		if(!emptyNote){return;}
		if(key==='todo'){
			emptyNote.hidden=true;
			return;
		}
		var matchCount=document.querySelectorAll('[data-filter-item][data-filter~="'+key+'"]').length;
		emptyNote.hidden=matchCount>0;
	}

	var stored=null;
	try{stored=localStorage.getItem(KEY);}catch(e){}
	var validKeys=buttons.map(function(btn){return btn.getAttribute('data-filter-key');});
	var initial=(stored&&validKeys.indexOf(stored)!==-1)?stored:'todo';

	buttons.forEach(function(btn){
		btn.addEventListener('click',function(){
			var key=btn.getAttribute('data-filter-key');
			apply(key);
			try{localStorage.setItem(KEY,key);}catch(e){}
		});
	});

	apply(initial);
})();

(function(){
	var toggle=document.getElementById('nav-toggle');
	var sidebar=document.getElementById('nav-sidebar');
	if(!toggle||!sidebar){return;}
	toggle.addEventListener('click',function(){
		var open=sidebar.classList.toggle('nav-open');
		toggle.setAttribute('aria-expanded',open?'true':'false');
	});
})();

(function(){
	var lb=document.getElementById('lightbox');
	if(!lb){return;}
	var stage=document.getElementById('lightbox-img');
	var posEl=document.getElementById('lightbox-pos');
	var capEl=document.getElementById('lightbox-caption');
	var prevBtn=document.getElementById('lightbox-prev');
	var nextBtn=document.getElementById('lightbox-next');
	var closeBtn=document.getElementById('lightbox-close');
	var items=[];
	var index=0;

	function show(i){
		if(!items.length){return;}
		index=(i+items.length)%items.length;
		var it=items[index];
		stage.src=it.src;
		stage.alt=it.caption;
		stage.style.maxWidth=it.nativeWidth?('min(94vw, '+it.nativeWidth+'px)'):'';
		capEl.textContent=it.caption;
		posEl.textContent=(index+1)+' / '+items.length;
		var multi=items.length>1;
		prevBtn.style.display=multi?'':'none';
		nextBtn.style.display=multi?'':'none';
	}

	function openLightbox(storyId,startIdx){
		var group=Array.prototype.slice.call(document.querySelectorAll('.lightbox-img[data-story="'+storyId+'"]'));
		group.sort(function(a,b){return (parseInt(a.getAttribute('data-idx'),10)||0)-(parseInt(b.getAttribute('data-idx'),10)||0);});
		items=group.map(function(img){
			var fig=img.closest('figure');
			var figcap=fig?fig.querySelector('figcaption'):null;
			return {
				src:img.getAttribute('src'),
				caption:figcap?figcap.textContent:(img.getAttribute('alt')||''),
				nativeWidth:img.getAttribute('data-native-width')
			};
		});
		show(startIdx);
		lb.classList.add('open');
		lb.setAttribute('aria-hidden','false');
		document.body.classList.add('lightbox-locked');
	}

	function closeLightbox(){
		lb.classList.remove('open');
		lb.setAttribute('aria-hidden','true');
		document.body.classList.remove('lightbox-locked');
		stage.src='';
		items=[];
	}

	document.querySelectorAll('.lightbox-img').forEach(function(img){
		img.addEventListener('click',function(){
			var storyId=img.getAttribute('data-story');
			if(!storyId){return;}
			openLightbox(storyId,parseInt(img.getAttribute('data-idx'),10)||0);
		});
	});

	prevBtn.addEventListener('click',function(){show(index-1);});
	nextBtn.addEventListener('click',function(){show(index+1);});
	closeBtn.addEventListener('click',closeLightbox);
	lb.addEventListener('click',function(e){
		if(e.target===lb){closeLightbox();}
	});
	document.addEventListener('keydown',function(e){
		if(!lb.classList.contains('open')){return;}
		if(e.key==='Escape'){closeLightbox();}
		else if(e.key==='ArrowLeft'){show(index-1);}
		else if(e.key==='ArrowRight'){show(index+1);}
	});

	var touchX=null;
	lb.addEventListener('touchstart',function(e){
		touchX=e.changedTouches[0].clientX;
	},{passive:true});
	lb.addEventListener('touchend',function(e){
		if(touchX===null){return;}
		var dx=e.changedTouches[0].clientX-touchX;
		touchX=null;
		if(Math.abs(dx)<40){return;}
		show(dx<0?index+1:index-1);
	},{passive:true});
})();

(function(){
	document.querySelectorAll('.clip-speed').forEach(function(bar){
		var video=document.getElementById(bar.getAttribute('data-video'));
		if(!video){return;}
		var buttons=Array.prototype.slice.call(bar.querySelectorAll('.speed-btn'));
		buttons.forEach(function(btn){
			btn.addEventListener('click',function(){
				video.playbackRate=parseFloat(btn.getAttribute('data-rate'));
				buttons.forEach(function(b){b.classList.remove('is-active');});
				btn.classList.add('is-active');
			});
		});
	});
})();

(function(){
	var PREFIX='br-mark:';
	function keyFor(feature,title){return PREFIX+feature+'\\u0000'+title;}
	function loadMark(feature,title){
		try{
			var raw=localStorage.getItem(keyFor(feature,title));
			return raw?JSON.parse(raw):null;
		}catch(e){return null;}
	}
	function saveMark(feature,title,data){
		try{localStorage.setItem(keyFor(feature,title),JSON.stringify(data));}catch(e){}
	}
	function removeMark(feature,title){
		try{localStorage.removeItem(keyFor(feature,title));}catch(e){}
	}

	var NEXT_STATE={unmarked:'bien',bien:'falla',falla:'unmarked'};
	var STATE_LABEL={unmarked:'${S.verdict.stateUnmarked}',bien:'${S.verdict.stateBien}',falla:'${S.verdict.stateFalla}'};

	function applyState(markEl,state){
		var btn=markEl.querySelector('.mark-btn');
		btn.setAttribute('data-state',state);
		btn.querySelector('.mark-btn-text').textContent=STATE_LABEL[state];
		// Drives the owner-verdict edge/wash color on the enclosing card/row (CSS :has()) — a
		// fact independent of the PASS/FAIL result badges.
		markEl.setAttribute('data-mark-state',state);
	}

	// The card this mark belongs to — the collapsible story/nostory row (never the nested
	// done-conditions <details> some NO STORY rows also carry).
	function cardOf(markEl){
		return markEl.closest('details.item-collapsed, li.burndown-row');
	}

	// True when the card's own result badges say FALLÓ or CAMBIÓ — the only case where a stale
	// stored mark (kit contract §4) should force the card back open instead of collapsing it.
	function isFailOrChanged(markEl){
		var card=cardOf(markEl);
		return !!(card&&(card.querySelector('.badge-fail')||card.querySelector('.badge-changed')));
	}

	function hydrate(markEl){
		var feature=markEl.getAttribute('data-feature');
		var title=markEl.getAttribute('data-title');
		var hash=markEl.getAttribute('data-hash')||'';
		var stored=loadMark(feature,title);
		applyState(markEl,stored?stored.state:'unmarked');
		var noteInput=markEl.querySelector('.mark-note-input');
		if(stored&&stored.note){
			noteInput.value=stored.note;
			noteInput.hidden=false;
		}
		var stale=!!(stored&&hash&&stored.hash&&stored.hash!==hash);
		var staleEl=markEl.querySelector('.mark-stale');
		staleEl.hidden=!stale;

		// A card the owner already marked bien/falla in a previous session starts collapsed —
		// unless it's failing/CHANGED with a stale mark, which needs a fresh look.
		if(stored&&(stored.state==='bien'||stored.state==='falla')){
			var details=markEl.closest('details.item-collapsed');
			if(details){
				details.open=!!(stale&&isFailOrChanged(markEl));
			}
		}
	}

	function persist(markEl){
		var feature=markEl.getAttribute('data-feature');
		var title=markEl.getAttribute('data-title');
		var hash=markEl.getAttribute('data-hash')||'';
		var state=markEl.querySelector('.mark-btn').getAttribute('data-state');
		var note=markEl.querySelector('.mark-note-input').value.trim();
		if(state==='unmarked'&&!note){
			removeMark(feature,title);
		}else{
			saveMark(feature,title,{state:state,note:note,hash:hash});
		}
		updateBar();
	}

	var marks=Array.prototype.slice.call(document.querySelectorAll('.mark'));

	function computeSummary(){
		var counts={bien:0,falla:0,nota:0,sinMarcarAtencion:0};
		var items=[];
		marks.forEach(function(markEl){
			var feature=markEl.getAttribute('data-feature');
			var title=markEl.getAttribute('data-title');
			var attention=markEl.getAttribute('data-attention')==='1';
			var stored=loadMark(feature,title);
			var state=stored?stored.state:'unmarked';
			var note=stored&&stored.note?stored.note:'';
			if(state==='bien'){counts.bien++;}
			if(state==='falla'){counts.falla++;}
			if(note){counts.nota++;}
			if(attention&&state==='unmarked'){counts.sinMarcarAtencion++;}
			items.push({feature:feature,title:title,state:state,note:note});
		});
		return{counts:counts,items:items};
	}

	function buildVerdict(generatedAt,summary){
		var bien=summary.items.filter(function(i){return i.state==='bien';});
		var falla=summary.items.filter(function(i){return i.state==='falla';});
		var notas=summary.items.filter(function(i){return i.note;});
		var lines=[];
		lines.push('${S.verdict.reportHeader}'+generatedAt);
		lines.push('${S.verdict.bienHeader}'+bien.length+'):');
		bien.forEach(function(i){lines.push('- '+i.feature+' :: '+i.title);});
		lines.push('${S.verdict.fallaHeader}'+falla.length+'):');
		falla.forEach(function(i){lines.push('- '+i.feature+' :: '+i.title+(i.note?' — nota: '+i.note:''));});
		lines.push('${S.verdict.notasHeader}'+notas.length+'):');
		notas.forEach(function(i){lines.push('- '+i.feature+' :: '+i.title+' — '+i.note);});
		lines.push('${S.verdict.sinMarcarLabel}'+summary.counts.sinMarcarAtencion);
		return lines.join('\\n');
	}

	var bar=document.getElementById('verdict-bar');
	var countsEl=document.getElementById('verdict-counts');

	function updateBar(){
		var summary=computeSummary();
		var c=summary.counts;
		var parts=[];
		if(c.bien){parts.push('<span class="vb-ok"><b>'+c.bien+'</b> ${S.verdict.countBien}</span>');}
		if(c.falla){parts.push('<span class="vb-fail"><b>'+c.falla+'</b> ${S.verdict.countFalla}</span>');}
		if(c.nota){parts.push('<span class="vb-note"><b>'+c.nota+'</b> ${S.verdict.countNota}</span>');}
		countsEl.innerHTML=parts.length?parts.join(' · '):'${S.verdict.none}';
		bar.classList.toggle('collapsed',!(c.bien||c.falla||c.nota));
	}

	marks.forEach(function(markEl){
		hydrate(markEl);
		var btn=markEl.querySelector('.mark-btn');
		btn.addEventListener('click',function(){
			var newState=NEXT_STATE[btn.getAttribute('data-state')];
			applyState(markEl,newState);
			persist(markEl);
			// Marking is the "done reviewing this one" gesture — collapse it. Clearing back to
			// "sin marcar" never auto-reopens (reopening is one tap); already-collapsed rows just
			// stay collapsed (no motion).
			if(newState==='bien'||newState==='falla'){
				var details=markEl.closest('details.item-collapsed');
				if(details){details.open=false;}
			}
		});
		var noteToggle=markEl.querySelector('.mark-note-toggle');
		var noteInput=markEl.querySelector('.mark-note-input');
		noteToggle.addEventListener('click',function(){
			noteInput.hidden=!noteInput.hidden;
			if(!noteInput.hidden){noteInput.focus();}
		});
		noteInput.addEventListener('change',function(){persist(markEl);});
		noteInput.addEventListener('blur',function(){persist(markEl);});
	});

	// A click anywhere inside a mark control must never toggle an ancestor <details>/<summary>.
	document.addEventListener('click',function(e){
		if(e.target.closest&&e.target.closest('.mark')){e.preventDefault();}
	},true);

	var modal=document.getElementById('verdict-modal');
	var modalText=document.getElementById('verdict-modal-text');
	function showCopyModal(text){
		modalText.value=text;
		modal.classList.add('open');
		modal.setAttribute('aria-hidden','false');
		modalText.focus();
		modalText.select();
	}
	document.getElementById('verdict-modal-close').addEventListener('click',function(){
		modal.classList.remove('open');
		modal.setAttribute('aria-hidden','true');
	});
	var modalCopyBtn=document.getElementById('verdict-modal-copy');
	modalCopyBtn.addEventListener('click',function(){
		var text=modalText.value;
		var original=modalCopyBtn.textContent;
		function showCopied(){
			modalCopyBtn.textContent='${S.verdict.modalCopied}';
			setTimeout(function(){modalCopyBtn.textContent=original;},1800);
		}
		function fallbackExecCommand(){
			modalText.focus();
			modalText.select();
			try{
				if(document.execCommand('copy')){showCopied();}
			}catch(e){}
		}
		if(navigator.clipboard&&navigator.clipboard.writeText){
			navigator.clipboard.writeText(text).then(showCopied).catch(fallbackExecCommand);
		}else{
			fallbackExecCommand();
		}
	});
	modal.addEventListener('click',function(e){
		if(e.target===modal){
			modal.classList.remove('open');
			modal.setAttribute('aria-hidden','true');
		}
	});

	var copyBtn=document.getElementById('verdict-copy');
	copyBtn.addEventListener('click',function(){
		var generatedAt=document.body.getAttribute('data-generated-at')||'';
		var text=buildVerdict(generatedAt,computeSummary());
		if(navigator.clipboard&&navigator.clipboard.writeText){
			navigator.clipboard.writeText(text).then(function(){
				var original=copyBtn.textContent;
				copyBtn.textContent='${S.verdict.copied}';
				setTimeout(function(){copyBtn.textContent=original;},1800);
			}).catch(function(){showCopyModal(text);});
		}else{
			showCopyModal(text);
		}
	});

	document.getElementById('verdict-clear').addEventListener('click',function(){
		if(!window.confirm('${S.verdict.confirmClear}')){return;}
		marks.forEach(function(markEl){
			removeMark(markEl.getAttribute('data-feature'),markEl.getAttribute('data-title'));
			applyState(markEl,'unmarked');
			var noteInput=markEl.querySelector('.mark-note-input');
			noteInput.value='';
			noteInput.hidden=true;
			markEl.querySelector('.mark-stale').hidden=true;
		});
		updateBar();
	});

	updateBar();
})();

(function(){
	var KEY='br-guide-open';
	var details=document.getElementById('guide-details');
	if(!details){return;}
	try{
		var stored=localStorage.getItem(KEY);
		if(stored==='false'){details.open=false;}
		else if(stored==='true'){details.open=true;}
	}catch(e){}
	details.addEventListener('toggle',function(){
		try{localStorage.setItem(KEY,details.open?'true':'false');}catch(e){}
	});
})();
`;
}

// ---------------------------------------------------------------------------
// --accept: promote baselines, append a metrics-history row, flip proposed→approved.
// ---------------------------------------------------------------------------

/**
 * Rewrite features.json flipping every "proposed" behavior to "approved", preserving the exact
 * tab indentation, key order, and trailing newline of the source file (it is a hand-edited contract).
 * Uses a targeted line rewrite rather than JSON.stringify so formatting never drifts.
 */
function flipProposedToApproved(featuresPath) {
	let text = readFileSync(featuresPath, 'utf8');
	let flipped = 0;
	text = text.replace(/"status":\s*"proposed"/g, () => {
		flipped++;
		return '"status": "approved"';
	});
	writeFileSync(featuresPath, text);
	return flipped;
}

/** Escape a string for safe use inside a `new RegExp(...)` pattern. */
function escapeRegExp(s) {
	return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * Starting at `openIdx` (index of a `{`), return the index of its matching `}`, skipping over
 * braces that appear inside JSON string literals. Used to isolate one top-level feature's block
 * in features.json so a scoped flip never touches sibling features' text.
 */
function matchBraceRange(text, openIdx) {
	let depth = 0;
	let inString = false;
	let escape = false;
	for (let i = openIdx; i < text.length; i++) {
		const ch = text[i];
		if (inString) {
			if (escape) { escape = false; }
			else if (ch === '\\') { escape = true; }
			else if (ch === '"') { inString = false; }
			continue;
		}
		if (ch === '"') { inString = true; continue; }
		if (ch === '{') { depth++; }
		else if (ch === '}') { depth--; if (depth === 0) { return i; } }
	}
	throw new Error(`matchBraceRange: unbalanced braces from index ${openIdx}`);
}

/**
 * Rewrite features.json flipping "proposed" → "approved" ONLY within the named features' own
 * blocks (--accept-only), preserving formatting exactly like `flipProposedToApproved` — every
 * other feature's text, including any of its own "proposed" behaviors, is left untouched.
 */
function flipProposedToApprovedScoped(featuresPath, featureNames) {
	let text = readFileSync(featuresPath, 'utf8');
	let flipped = 0;
	for (const name of featureNames) {
		const keyMatch = new RegExp(`"${escapeRegExp(name)}"\\s*:\\s*\\{`).exec(text);
		if (!keyMatch) {
			continue;
		}
		const openIdx = keyMatch.index + keyMatch[0].length - 1;
		const closeIdx = matchBraceRange(text, openIdx);
		const block = text.slice(openIdx, closeIdx + 1).replace(/"status":\s*"proposed"/g, () => {
			flipped++;
			return '"status": "approved"';
		});
		text = text.slice(0, openIdx) + block + text.slice(closeIdx + 1);
	}
	writeFileSync(featuresPath, text);
	return flipped;
}

/** Build the metrics-history row appended on accept. Content-keyed for idempotency. */
function buildHistoryRow(metrics, counts, generatedAt) {
	const m = metrics ?? {};
	return {
		acceptedAt: generatedAt,
		runContentHash: contentHash({ m, counts }),
		behaviorsPass: counts.pass,
		behaviorsTotal: counts.total,
		behaviorsHappy: counts.happy,
		behaviorsEdge: counts.edge,
		unitTests: m.unitTests ?? null,
		systemTests: m.systemTests ?? null,
		coveragePct: m.coveragePct ?? null,
		mutationScorePct: m.mutationScorePct ?? null,
		duplicationPct: m.duplicationPct ?? null
	};
}

/** Perform the accept: write review-state, append history (idempotent), flip the contract. */
function doAccept(model, metrics, generatedAt) {
	// review-state.json: scenario hashes + the accepted feature list.
	const reviewState = {
		acceptedAt: generatedAt,
		features: model.features.map(f => f.name),
		scenarios: model.hashesForAccept
	};
	writeFileSync(REVIEW_STATE, JSON.stringify(reviewState, null, 2) + '\n');

	// metrics-history.json: append one row, unless the last row came from identical run content.
	const history = readJson(METRICS_HISTORY, []);
	const row = buildHistoryRow(metrics, model.counts, generatedAt);
	const last = history[history.length - 1];
	let appended = false;
	if (!last || last.runContentHash !== row.runContentHash) {
		history.push(row);
		appended = true;
	}
	writeFileSync(METRICS_HISTORY, JSON.stringify(history, null, 2) + '\n');

	// features.json: proposed → approved (preserve formatting).
	const flipped = flipProposedToApproved(FEATURES_JSON);

	console.log('--accept:');
	console.log(`  review-state.json: ${Object.keys(model.hashesForAccept).length} historia(s) baselined; features [${reviewState.features.join(', ')}]`);
	console.log(`  metrics-history.json: ${appended ? 'fila agregada' : 'sin cambios (misma corrida, idempotente)'} (${history.length} fila(s) en total)`);
	console.log(`  features.json: ${flipped} comportamiento(s) propuesto→aprobado`);
}

/**
 * Perform a scoped accept (--accept-only, repeatable): promote proposed→approved and baseline
 * story hashes ONLY for the named features — merged into the existing review-state.json/
 * features.json rather than the wholesale overwrite `doAccept` does. Exists because a partial
 * review round must never silently baseline (and later drop the media of) a feature's stories
 * the owner hasn't actually reviewed yet.
 */
function doAcceptOnly(model, metrics, generatedAt, featureNames) {
	const known = new Set(model.features.map(f => f.name));
	const unknown = featureNames.filter(n => !known.has(n));
	if (unknown.length) {
		console.error(`ERROR: --accept-only: funcionalidad(es) desconocida(s) en features.json: ${unknown.join(', ')}`);
		process.exit(1);
	}
	const wanted = new Set(featureNames);

	// This run's scenario hashes, restricted to the named features' declared stories plus any of
	// their UNSPECIFIED orphans — never the whole run's hashesForAccept.
	const scopedHashes = {};
	for (const feature of model.features) {
		if (!wanted.has(feature.name)) { continue; }
		for (const item of feature.items) {
			if (item.kind === 'story') {
				scopedHashes[`${feature.name} ${item.title}`] = item.hash;
			}
		}
	}
	for (const [featureName, items] of model.orphanByFeature) {
		if (!wanted.has(featureName)) { continue; }
		for (const item of items) {
			scopedHashes[`${featureName} ${item.title}`] = item.hash;
		}
	}

	// review-state.json: merge — every scenario/feature outside this scope is preserved as-is.
	const prevState = readJson(REVIEW_STATE, { acceptedAt: null, features: [], scenarios: {} });
	const scenarios = { ...(prevState.scenarios ?? {}), ...scopedHashes };
	const features = Array.from(new Set([...(prevState.features ?? []), ...featureNames]));
	const reviewState = { acceptedAt: generatedAt, features, scenarios };
	writeFileSync(REVIEW_STATE, JSON.stringify(reviewState, null, 2) + '\n');

	// metrics-history.json: same idempotent append rule as the wholesale --accept.
	const history = readJson(METRICS_HISTORY, []);
	const row = buildHistoryRow(metrics, model.counts, generatedAt);
	const last = history[history.length - 1];
	let appended = false;
	if (!last || last.runContentHash !== row.runContentHash) {
		history.push(row);
		appended = true;
	}
	writeFileSync(METRICS_HISTORY, JSON.stringify(history, null, 2) + '\n');

	// features.json: proposed → approved, scoped to the named features only.
	const flipped = flipProposedToApprovedScoped(FEATURES_JSON, featureNames);

	console.log('--accept-only:');
	console.log(`  funcionalidad(es): ${featureNames.join(', ')}`);
	console.log(`  review-state.json: ${Object.keys(scopedHashes).length} historia(s) baselined en esta corrida (scenarios totales: ${Object.keys(scenarios).length})`);
	console.log(`  metrics-history.json: ${appended ? 'fila agregada' : 'sin cambios (misma corrida, idempotente)'} (${history.length} fila(s) en total)`);
	console.log(`  features.json: ${flipped} comportamiento(s) propuesto→aprobado`);
}

// ---------------------------------------------------------------------------
// Main.
// ---------------------------------------------------------------------------

function main() {
	const args = parseArgs(process.argv.slice(2));
	// Video (H.264 MP4) is the primary recording pipeline — native speed, playback controls,
	// fullscreen. GIF is a documented fallback for environments without ffmpeg/libx264; risk:
	// the artifact CSP's tolerance of data: video can only be confirmed post-publish, so this
	// flag is the switch to flip if a published report ever renders it blocked.
	const useVideo = hasH264Encoder();
	const ladder = useVideo ? VIDEO_LADDER : (args.compactGifs ? GIF_LADDER_COMPACT : GIF_LADDER_DEFAULT);

	// Required inputs.
	if (!existsSync(RESULTS_JSON)) {
		console.error(`ERROR: no se encontró el resultado de Playwright en ${RESULTS_JSON}`);
		console.error('  Corre las historias primero (scripts/report/e2e-tests.sh).');
		process.exit(1);
	}
	const results = readJson(RESULTS_JSON, null);
	if (!results || !Array.isArray(results.suites)) {
		console.error(`ERROR: ${RESULTS_JSON} no tiene la forma esperada del reporter JSON de Playwright.`);
		process.exit(1);
	}
	// --config sample: the checked-in fixture stores attachment paths relative to sample-data/
	// (portable) — resolve them to absolute paths so pngDataUri()/encodeMp4() can read them.
	// No-op for a real run (RESULTS_JSON's own attachment paths are already absolute).
	if (IS_SAMPLE_CONFIG) {
		resolveSampleAttachmentPaths(results.suites);
	}
	const features = readJson(FEATURES_JSON, {});

	// Optional inputs (missing ⇒ "—" / hidden sections).
	const metrics = readJson(join(DATA_DIR, 'metrics.json'), null);
	const hygiene = readJson(join(DATA_DIR, 'hygiene.json'), null);
	const reviewState = readJson(REVIEW_STATE, null);
	const history = readJson(METRICS_HISTORY, []);

	// Build the model.
	const model = buildModel(results, features, reviewState, args);
	const metricsModel = buildMetrics(metrics, hygiene, model.counts, history);

	const generatedAt = new Date().toISOString();

	// Render, stepping down the GIF ladder (scale before colors) until the report
	// fits the size target or the quality floor is reached (kit §6 + size governance).
	let html, dialsUsed;
	for (const dials of ladder) {
		dialsUsed = dials;
		html = renderHtml(model, metricsModel, generatedAt, dials);
		if (Buffer.byteLength(html) <= SIZE_TARGET_BYTES) {
			break;
		}
	}

	mkdirSync(ARTIFACTS, { recursive: true });
	writeFileSync(OUTPUT_HTML, html);

	const size = statSync(OUTPUT_HTML).size;
	const c = model.counts;
	console.log('Reporte de comportamiento generado.');
	console.log(`  ${OUTPUT_HTML}`);
	console.log(`  Tamaño: ${humanSize(size)} (${size} bytes)`);
	console.log(`  Pipeline de grabación: ${dialsUsed.mode} — ${dialsUsed.mode === 'video' ? `scale=${dialsUsed.scale} crf=${dialsUsed.crf}` : `scale=${dialsUsed.scale} colores=${dialsUsed.colors} fps=${dialsUsed.fps}`}`);
	if (size > SIZE_TARGET_BYTES) {
		console.log(`  Aviso: por encima del objetivo de ${humanSize(SIZE_TARGET_BYTES)} incluso en el piso de calidad. La respuesta es acotar qué historias incrustan media, no degradar más la grabación.`);
	}
	if (mediaLog.length) {
		console.log('  Media incrustada por historia:');
		let mediaTotal = 0;
		for (const m of mediaLog) {
			mediaTotal += m.bytes;
			console.log(`    - [${m.kind}] ${m.title}: ${humanSize(m.bytes)}`);
		}
		console.log(`  Total media incrustada: ${humanSize(mediaTotal)}`);
	}
	console.log(`  Historias: ${c.total} · pasaron ${c.pass} · fallaron ${c.fail} · nuevas ${c.new} · cambiaron ${c.changed} · propuestas ${c.proposed} · sin historia ${c.noStory} · sin especificar ${c.unspecified}`);
	if (!hasFfmpeg()) {
		console.log('  Aviso: ffmpeg no disponible — la media se omitió con una nota honesta por historia.');
	} else if (!useVideo) {
		console.log('  Aviso: H.264 (libx264) no disponible — usando el pipeline de GIF de respaldo.');
	}

	// Accept runs AFTER building (so the report reflects pre-accept state on this same run's HTML).
	if (args.accept) {
		doAccept(model, metrics, generatedAt);
	} else if (args.acceptOnly.length) {
		doAcceptOnly(model, metrics, generatedAt, args.acceptOnly);
	}
}

main();
