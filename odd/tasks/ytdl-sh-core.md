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
| T2 | S2, S6 | inline | Format sorting `-S "res,br"` + templates por modo + `%(ext)s` | `feat(core): format sorting and output templates` | ✅ Approved — Implementing |
| T3 | S3, S4 | inline | Post-procesado yt-dlp (embed metadata/thumb/chapters/sponsorblock) + red defaults | `feat(core): yt-dlp post-processing and network defaults` | ⏳ Pending |
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