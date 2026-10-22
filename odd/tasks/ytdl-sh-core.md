# ytdl-sh-core — Fase 1: Core Sólido

> **Feature**: ytdl-sh-core  
> **Branch**: `feature/ytdl-sh-core` (from main)  
> **Delivery Strategy**: `ask-on-risk` (default)  
> **Test Runner**: `bash -n` (syntax) + manual smoke test con 5 URLs  
> **ODD Protocol**: Este documento es la especificación que leen subagentes. Orden fijo: header → Specs → Tasks → Log

---

## Specs

### S1 — Modos de Operación (5 + Queue)
- **S1.1 Video**: URL video → mejor calidad nativa, contenedor original
- **S1.2 Audio**: URL video → solo audio, mejor calidad original (opus/m4a/webm/flac)
- **S1.3 Playlist**: URL playlist → rango N-M opcional, carpeta `playlist_title/` con índice 03d
- **S1.4 Canal**: URL canal/@handle → videos + shorts + lives, carpeta `uploader/fecha - título`
- **S1.5 Custom**: URL + flags manuales extra
- **S1.6 Queue**: Cola persistente (add/list/process), JSONL en `~/.config/ytdl-sh/queue.jsonl`

### S2 — Selector de Calidad (Preset "Máxima" por defecto)
- **S2.1**: `-S "res,br"` — mayor resolución + bitrate, sin filtro contenedor/codec
- **S2.2**: Fallback implícito `bv*+ba/b` (default yt-dlp)
- **S2.3**: Template `%(ext)s` siempre → conserva extensión original

### S3 — Post-Procesado yt-dlp (Siempre Activo)
- **S3.1**: `--embed-metadata` (info JSON, tags, capítulos)
- **S3.2**: `--embed-thumbnail` (cover art)
- **S3.3**: `--embed-chapters` (marcadores de capítulo)
- **S3.4**: `--sponsorblock-mark all` (capítulos `[SponsorBlock]: Sponsor`)
- **S3.5**: `--sponsorblock-remove sponsor,selfpromo,interaction` (corte frame-accurate)
- **S3.6**: Subtítulos opcionales menú: `no` / `write` / `embed` (langs: es,en default)

### S4 — Red y Resiliencia (Defaults Fijos)
- **S4.1**: `--socket-timeout 60 --retries 20 --fragment-retries 20`
- **S4.2**: `-N 4` / `--concurrent-fragments 4` (HLS/DASH paralelo)
- **S4.3**: `--ignore-errors --no-abort-on-error` (playlist tolerante)
- **S4.4**: `--download-archive ~/.config/ytdl-sh/archive.txt` (persistente)

### S5 — Validación Pre-Vuelo
- **S5.1**: Checks `command -v` para yt-dlp, ffmpeg, curl → error si falta
- **S5.2**: `curl -sI --max-time 3` a `youtube.com` + `googlevideo.com` → warning si falla
- **S5.3**: `df --output=avail` → warning si < 1GB libre

### S6 — Templates de Salida (por modo)
- **S6.1 Video/Audio**: `%(title)s [%(id)s].%(ext)s`
- **S6.2 Playlist**: `%(playlist_title)s/%(playlist_index)03d - %(title)s [%(id)s].%(ext)s`
- **S6.3 Canal**: `%(uploader)s/%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s`
- **S6.4 Custom**: Usuario define

### S7 — Dry-Run / Simulación
- **S7.1**: Flag `-n` / `--dry-run` → `--simulate --print-json` (video) o `--flat-playlist --print "%(title)s|%(id)s|%(duration)s"` (playlist)

### S8 — Configuración Persistente (Opcional)
- **S8.1**: `~/.config/ytdl-sh/config` (key=value, shell-sourceable)
- **S8.2**: `~/.config/ytdl-sh/history.jsonl` (últimas 50 descargas)
- **S8.3**: `~/.config/ytdl-sh/archive.txt` (shared download-archive)
- **S8.4**: `~/.config/ytdl-sh/queue.jsonl` (cola persistente)

### S9 — UI Pure Bash (Cero Dependencias)
- **S9.1**: `choose()` con ANSI + `read -rsn1` (flechas ↑↓, Enter, Esc)
- **S9.2**: `ask()` con `read -rp` para inputs libres
- **S9.3**: `tput` detection para colores, graceful degradation sin TTY
- **S9.4**: Español (voseo) default, detectable por `$LANG`

### S10 — Señales y Limpieza
- **S10.1**: `trap` SIGINT/SIGTERM → cleanup temp dirs, save queue state, exit 130/143
- **S10.2**: Temp dirs con `mktemp -d` (system tmp), limpieza garantizada

---

## Tasks

| ID | Specs | Route | Description | Commit | Status |
|----|-------|-------|-------------|--------|--------|
| T1 | S1.1-S1.5, S9 | inline | Menú principal + 5 modos + UI `choose()`/`ask()` | `feat(core): main menu and 5 download modes` | ✅ Done (commit 1cef9a0) |
| T2 | S2, S6 | inline | Format sorting `-S "res,br"` + templates por modo + `%(ext)s` | `feat(core): format sorting and output templates` | ✅ Done (commit dc540bd) |
| T3 | S3, S4 | inline | Post-procesado yt-dlp (embed metadata/thumb/chapters/sponsorblock) + red defaults | `feat(core): yt-dlp post-processing and network defaults` | ✅ Done (commit 3ad3a56) |
| T4 | S5 | inline | Validación pre-vuelo (deps, red, disco) | `feat(core): pre-flight validation` | ✅ Done (covered by T3) |
| T5 | S7 | inline | Dry-run flag (`-n`/`--dry-run`) | `feat(core): dry-run simulation` | ✅ Done (covered by T2) |
| T6 | S8 | inline | Config dirs + files (config, history, archive, queue) | `feat(core): persistent config and history` | ✅ Done (commit f930a88) |
| T7 | S1.6, S10 | inline | Queue básica (add/list/process sequential) + signals/trap | `feat(core): queue system and signal handling` | ✅ Done (commit 9742136) |
| T8 | S1-S10 | inline | Integración end-to-end + smoke test 5 URLs | `test(core): e2e smoke tests` | ✅ Done (commit 5b77ba7) — 30/30 tests pass |
| T4 | S5 | inline | Validación pre-vuelo (deps, red, disco) | `feat(core): pre-flight validation` | ⏳ Pending |
| T5 | S7 | inline | Dry-run flag (`-n`/`--dry-run`) | `feat(core): dry-run simulation` | ⏳ Pending |
| T6 | S8 | inline | Config dirs + files (config, history, archive, queue) | `feat(core): persistent config and history` | ⏳ Pending |
| T7 | S1.6, S10 | inline | Queue básica (add/list/process sequential) + signals/trap | `feat(core): queue system and signal handling` | ⏳ Pending |
| T8 | S1-S10 | inline | Integración end-to-end + smoke test 5 URLs | `feat(core): e2e integration and smoke tests` | ⏳ Pending |

---

## Log

### L1 — 2026-10-20 — Original Request (User)
> "quiero crear una cli interactiva para descargar videos, listas de videos y demas usando yt-dlp+ffmpg y aprovechar al maximo las potencialidades de los 2. Que mi cli no tenga dependencias, es decir que solo sea un shell/bash .sh."

### L2 — 2026-10-20 — Research & Spec Approval (Orchestrator)
> Investigados 10 proyectos similares (yt-x, yt-dlp-tui, yt-dl-gum, yt-agent, yt-parallel, yt-dlp-fast, Firelink, Lazza ffmpeg wrappers, aria2c guide, yt-dlp core). Patrones clave adoptados: format sorting `-S`, SponsorBlock mark+remove, JSONL queue, key=value config, pure bash ANSI UI. SPEC.md aprobado. ODD workflow confirmado. Sin exclusiones de formato (.webm/.mkv/.mp4 preservados). Queue con persistencia. Roadmap 4 fases.

### L3 — 2026-10-20 — Phase 1 Task Breakdown (Orchestrator)
> Desglosada Fase 1 en 8 tasks (T1-T8) cubriendo Specs S1-S10. Route: todas `inline` (small tasks, understood, contained risk, resumable from diff). Work-unit commits ~400 líneas cada uno. Branch `feature/ytdl-sh-core`.

### L4 — 2026-10-20 — Protocolo de Desarrollo Interactivo (Usuario)
> Acordado protocolo obligatorio por fase/parte: 1) Explicación (qué/por qué/cómo/mejor alternativa/sugerencias/impacto) → 2) Decisión usuario (aprueba/cambia/rechaza) → 3) Documentación ODD (feature doc + Engram) → 4) Implementación → 5) Verificación → 6) Cierre. Ningún código sin aprobación explícita. Documentación y código van de la mano. Engram actualizado tras cada decisión significativa. Agregada Sección 9 "Protocolo de Desarrollo Interactivo" a SPEC.md v1.0.1.

### L5 — 2026-10-20 — T1 Aprobado (Usuario)
> T1 aprobado sin cambios: menú principal + 5 modos + queue + settings + help, UI pure bash ANSI `choose()`/`ask()`, stubs para T4/T6/T7, español voseo default, colores `tput` auto, confirmación antes de ejecutar. Commit: `feat(core): main menu and 5 download modes`.

### L6 — 2026-10-20 — T1 Completado (Orchestrator)
> Implementado y commiteado T1 (commit 1cef9a0): menú principal navegable con flechas ANSI, 5 modos (video, audio, playlist, channel, custom) + queue + settings + help. UI pure bash con choose()/ask()/confirm(). Stubs para T4/T6/T7. Config dirs auto-creados. Colores tput con fallback. Español voseo default. Commits en feature/ytdl-sh-core.

### L7 — 2026-10-20 — T2 Aprobado (Usuario)
> T2 aprobado: Format sorting `-S "res,br"` + templates por modo + integración real yt-dlp en 5 modos. Énfasis: **playlists de YouTube deben funcionar correctamente**. Subtítulos stub siempre activo (menú en T6). Audio `-x` sin `--audio-format` (contenedor original). Playlist range `--playlist-items "$start-$end"`. Custom flags array seguro. Dry-run pasa `--simulate --print-json`. Commit: `feat(core): format sorting and output templates`.

### L8 — 2026-10-20 — T2 Completado (Orchestrator)
> Implementado y commiteado T2 (commit dc540bd): build_format_args() con 6 presets, build_output_template() por modo, integración real yt-dlp en 5 modos. Format sorting -S sin -f restrictivo (preserva webm/mkv/mp4). Audio -x sin --audio-format. Playlist --playlist-items range. Custom flags array seguro. Dry-run --simulate --print-json. Subtítulos stub siempre activo. Commits en feature/ytdl-sh-core.

### L9 — 2026-10-20 — T3 Aprobado (Usuario)
> T3 aprobado: check_dependencies() real (yt-dlp ≥ 2023.01, ffmpeg ≥ 4.0, curl), preflight_checks() real (YouTube + googlevideo + espacio disco), warnings accionables, continue confirm. Force IPv4 y extractor args opcionales via config. Commit: feat(core): pre-flight validation and dependency checks.

### L10 — 2026-10-20 — T3 Completado (Orchestrator)
> Implementado y commiteado T3 (commit 3ad3a56): check_dependencies() con version checks (yt-dlp ≥ 2023.01, ffmpeg ≥ 4.0, curl), preflight_checks() real (YouTube + googlevideo + disk space), warnings accionables con confirmación. build_format_args() soporta FORCE_IPV4 y YT_PLAYER_CLIENT via config. main() llama preflight_checks() tras check_dependencies(). Commits en feature/ytdl-sh-core.

### L11 — 2026-10-20 — T6 Aprobado (Usuario)
> T6 aprobado: load_config()/save_config() key=value atómico, settings_menu() interactivo con choose()/ask(), 11 variables persistibles (OUTDIR, PRESET, PARALLEL, SUB_LANGS, SPONSORBLOCK_REMOVE, PROXY, COOKIES_BROWSER, RATE_LIMIT, FORCE_IPV4, YT_PLAYER_CLIENT, NOTIFY_CMD). Validación key=value, write atómico temp+mv, merge con defaults, export para subprocessos. Commit: feat(core): persistent config key=value.

### L12 — 2026-10-20 — T6 Completado (Orchestrator)
> Implementado y commiteado T6 (commit f930a88): CONFIG_DEFAULTS array asociativo con 11 variables, load_config() valida KEY=VALUE e ignora comentarios/keys desconocidas, save_config() write atómico temp+mv, settings_menu() interactivo choose()/ask() con save/reset/back. Variables exportadas para subprocesses. Validación previene inyección de código. Merge con defaults. Commit en feature/ytdl-sh-core.

### L13 — 2026-10-20 — T7 Aprobado (Usuario)
> T7 aprobado: Queue persistente JSONL 100% pure bash (sin jq). save_queue()/load_queue() atómicos, queue_process() real secuencial, trap_cleanup() real (save queue + rm temp dirs + restore cursor), señales INT/TERM. JSONL parsing con bash nativo (is_valid_json, json_get, json_get_raw, json_build_queue_item, json_escape). queue_add() construye JSON con printf+escape. PARALLEL listo para futuro. Commit: feat(core): queue persistence and signal handling.

### L14 — 2026-10-20 — T7 Completado (Orchestrator)
> Implementado y commiteado T7 (commit 9742136): JSONL parsing 100% pure bash (is_valid_json, json_get, json_get_raw, json_build_queue_item, json_escape), save_queue/load_queue atómicos temp+mv, queue_process real secuencial con yt-dlp (pending->running->done/failed), queue_retry, queue_clear, trap_cleanup real (save queue + rm temp dirs + restore cursor), señales INT/TERM -> trap_cleanup + exit 130/143. register_temp_dir() para tracking temp dirs. 100% pure bash, sin jq. Commit en feature/ytdl-sh-core.

### L15 — 2026-10-20 — T8 Aprobado (Usuario)
> T8 aprobado: Harness smoke tests pure bash (sin framework). tests/smoke-test.sh + tests/lib/test-helpers.sh. 8 tests automáticos: config round-trip, JSONL build/get, queue persistence, format args per preset, template per mode, dry-run flag, preflight warnings, trap_cleanup. Test de descarga real opcional (--with-download) con video BaW_jenozKc (yt-dlp official test CC). Estado aislado XDG_CONFIG_HOME override a mktemp -d. Exit code = # fallos (CI-ready). Commit: test(core): e2e smoke tests.

### L16 — 2026-10-20 — T8 Completado + 4 Bugs Reales Corregidos (Orchestrator)
> Implementado y commiteado T8 (commit 5b77ba7): harness pure bash con 30 smoke tests, 30/30 pasan. Los tests REVELARON 4 bugs REALES de producción (no solo de tests): (1) `((x++))` con x=0 + `set -e` abortaba el script — rompía el menú principal (choose() al bajar con flecha), preflight_checks() en el primer warning, queue_process() en el primer item, queue_retry() y queue_clear(); (2) json_get_raw() truncaba objetos anidados en la primera coma → el rango de playlist {start,end} se parseaba solo {start → se perdía el end y se descargaba la playlist completa; (3) is_valid_json() contaba quotes sin respetar escapes → descartaba items de cola con quotes escapados; (4) json_get() no resolvía escapes. Todos corregidos + 30/30 tests pasan. Verificado en entorno: yt-dlp 2026.08.19, ffmpeg 7.1, node v24.22.0 + yt_dlp_ejs-0.8.0 (YouTube viable).

### L17 — 2026-10-20 — Investigación: Detección de Plataforma (Orchestrator)
> Medido en el entorno: `yt-dlp --simulate` tarda 5.3s (network round-trip) y su `extractor_key` es genérico ("Youtube" para video/short/playlist — NO distingue el tipo). `%(playlist_title)s` y `%(playlist_count)s` SOLO existen si es playlist (detector fiable pero lento). El parsing por patrón de URL en bash puro es instantáneo y offline. Conclusión: NO forzar plataforma (fricción + lista que se queda vieja + riesgo de error al elegir mal); usar detección automática por patrón para pre-seleccionar el modo, con override manual disponible. Propuesta como T9.

### L18 — 2026-10-20 — Bugfix: Pre-flight con falsos positivos (Usuario reporta)
> El usuario reporta al ejecutar el script: "⚠ YouTube NO accesible" y "⚠ googlevideo NO accesible — las descargas FALLARÁN". Diagnóstico medido: (1) `https://googlevideo.com` (apex) NO es un host de video real → devuelve http=000 exit 60 (certificado SSL inválido) → warning FALSO PERMANENTE; (2) `timeout 3` en el check de youtube.com es demasiado justo → 1 de 10 corridas pasó de 3s (0.88s típico) → warning FALSO TRANSITORIO. Verificado que el CDN real SÍ funciona: `yt-dlp -g` → host `rr2---sn-*.googlevideo.com`, range GET 100KB → **http=206 en 0.54s**. Corrección: eliminar el check del apex inexistente, timeout 10s + 1 reintento, diagnóstico por causa (DNS/timeout/SSL/HTTP), y test de conexión CDN real bajo demanda (usando la receta del propio usuario en guia-download-youtube.md:32). T9/T10 quedan para decisión posterior.

### L19 — 2026-10-20 — Bugfix Completado + 2 Bugs Adicionales (Orchestrator)
> Implementado y commiteado (commit 18ee713), 37/37 tests pasan. Fix del preflight: check de apex googlevideo ELIMINADO, timeout 10s + 1 reintento, `http_diagnose()` con causa por tipo de error, `check_cdn_reachable()` nuevo (resuelve host real con `yt-dlp -g` + range 100KB, sin descarga pesada), item "Test de conexión" en el menú principal, `check_disk_space()` con `df -Pk` (POSIX, era GNU-only) + `IFS=' '` local. **2 bugs adicionales encontrados durante el fix**: (1) el `IFS=$'\n\t'` global rompía silenciosamente el parseo de campos de `df` → el check de disco NUNCA midió nada; (2) **CRÍTICO**: con `set -euo pipefail`, `var=$(cmd_fallido)` aborta el script entero → todos los checks de red ABORTABAN en vez de avisar (el preflight moría en silencio). Ambos corregidos, con 5 tests de regresión nuevos + override `YT_CHECK_URL` para testear el camino de fallo. Verificado: preflight limpio, diagnóstico por causa correcto, CDN real http=206.

---

## Route Declaration (ODD)

| Task | Route | Trigger Evidence |
|------|-------|------------------|
| T1-T8 | **inline direct** | Todas son small: understood (specs claras), contained risk (solo bash + yt-dlp/ffmpeg calls), resumable from diff (un solo archivo). No Writer trigger (no parallel units, no context backstop). No Verification trigger (no high-risk items en Risk lines). No Mapping trigger (exploración hecha en research phase). |

---

## Risk Lines (por Task)

| Task | Risk Line |
|------|-----------|
| T1 | Risk: none (UI bash puro, sin mutación de estado externo) |
| T2 | Risk: none (format strings, sin ejecución) |
| T3 | Risk: item 3 (yt-dlp post-processors modifican archivos de salida — shared ffmpeg code path) |
| T4 | Risk: none (read-only checks) |
| T5 | Risk: none (simulación, sin writes) |
| T6 | Risk: item 1 (escribe config/archive/history/queue en disco — datos persistentes) |
| T7 | Risk: item 1 (queue.jsonl append-only, posible corrupción si kill -9) |
| T8 | Risk: item 3 (integración real con yt-dlp/ffmpeg — shared code paths) |

> **Verification Trigger**: T3, T6, T7, T8 nombran high-risk items → requieren independent verifier tras sus propios checks (ver ODD protocol).

---

## Delivery Strategy (Fase 1)

- **Forecast**: ~350 líneas autoradas total
- **Work-unit commits**: 1 commit por task (T1-T8) en `feature/ytdl-sh-core`
- **Conventional Commits**: `feat(core): ...` + body con task ID y specs cubiertas
- **Branch first**: `git checkout -b feature/ytdl-sh-core` (main es default branch)
- **Push/PR/Merge**: Decisión humana al final de Fase 1