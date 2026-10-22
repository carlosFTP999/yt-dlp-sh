# SPEC.md — ytdl-sh: Interactive yt-dlp + ffmpeg Downloader

> **Proyecto**: CLI interactiva pura en bash (un solo archivo, cero dependencias externas)  
> **Objetivo**: Aprovechar al máximo yt-dlp + ffmpeg para descargar de **todas las plataformas** con **cola (queue)**, **presets de calidad**, **SponsorBlock**, **metadatos completos** y **post-procesado opcional ffmpeg** (Fase 3)  
> **Workflow**: **Organic Driven Development (ODD)** — protocolo obligatorio en cada request  
> **Estado**: **APROBADO** — Listo para implementación Fase 1

---

## 1. Contexto y Análisis de Proyectos Similares (Investigación)

### 1.1 Proyectos Referenciados

| Proyecto | Repositorio | Tipo | Lenguaje | Características Clave Adoptadas/Referenciadas |
|----------|-------------|------|----------|-----------------------------------------------|
| **yt-x** | https://github.com/Benexl/yt-x | TUI/Launcher | POSIX sh + fzf/rofi | Browse 1800+ sitios, queue playlists, auto-mix .m3u8, preview thumbnails, config file `~/.config/yt-x/config`, mpv integration, POSIX-compliant (bash/zsh/dash) |
| **yt-dlp-tui** | https://github.com/z4none/yt-dlp-tui | TUI | Python + Textual | Format inspection, playlist item selection, queue, persistent JSON history, resume (`--continue`), independent yt-dlp/ffmpeg binary management |
| **yt-dl-gum** | https://github.com/blackbunt/yt-dl-gum | TUI | Bash + gum | Simple wrapper, auto-dependency detection (requiere gum binary) |
| **yt-agent** | https://github.com/jvogan/yt-agent | CLI/AI | Python | Search, download, catalog, clips, transcripts, fzf multi-select (scope YouTube-only) |
| **yt-parallel** | https://github.com/phiroict/yt-parallel | Batch | Rust + bash | Parallel yt-dlp jobs from URL list, date-folders, SAN/NAS move, `wait` para jobs background |
| **yt-dlp-fast** | https://github.com/Shukurov777/yt-dlp-fast | Wrapper | Bash + patches | aria2c (`-x 16 -s 16`), modes (turbo/fast/safe/audio/video/benchmark), patches yt-dlp internals |
| **Firelink** | https://github.com/alireza388/Firelink-downloader | GUI Desktop | Rust/Tauri/React | aria2 + yt-dlp + ffmpeg + Deno + SQLite, persistent queues, scheduling, browser capture |
| **yt-dlp (core)** | https://github.com/yt-dlp/yt-dlp | Engine | Python | 1800+ sitios, format sorting (`-S`), SponsorBlock, embed metadata/thumbnail/chapters, `--downloader aria2c`, `-N` concurrent fragments |
| **aria2c guide** | https://aria2.org/guides/yt-dlp | Doc | — | `--downloader aria2c --downloader-args "aria2c:-x 16 -s 16 -k 1M"`, 16 conexiones paralelas por archivo |
| **Lazza ffmpeg wrappers** | https://github.com/Lazza/ffmpeg-wrapper-scripts | Wrappers | Bash | Fixes ffmpeg `-map 0:a:0` crash cuando archivo no tiene audio track (relevante para robustez) |

### 1.2 Patrones Clave del Ecosistema (Extraídos de la Investigación)

| Patrón | Comando yt-dlp | Fuente/Proyecto |
|--------|----------------|-----------------|
| **Format Sorting moderno** | `-S "res,br,codec,ext,proto"` | yt-dlp core (2023+), yt-dlp-tui |
| **Merge nativo** | `bv*+ba/b` (default) | yt-dlp core |
| **SponsorBlock mark + remove** | `--sponsorblock-mark all --sponsorblock-remove sponsor,selfpromo,interaction` | yt-dlp core, yt-dlp-tui |
| **Archive/Resume** | `--download-archive FILE` | yt-dlp core, yt-dlp-tui, yt-x |
| **HLS/DASH paralelo** | `-N 8` / `--concurrent-fragments 8` | yt-dlp core, yt-dlp-fast |
| **HTTP paralelo (aria2c)** | `--downloader aria2c --downloader-args "aria2c:-x 16 -s 16 -k 1M"` | aria2.org guide, yt-dlp-fast, Firelink |
| **Streaming stdout** | `-o - URL \| mpv -` | yt-dlp manpages, mpv issues, yt-streamer.sh |
| **Match-filter interactivo** | `--match-filter -` | yt-dlp manpages |
| **Post-procesado ffmpeg** | `--exec`, `--postprocessor-args` | yt-dlp core, yt-dlp-fast |
| **Queue persistente JSONL** | `queue.jsonl` (append-only) | yt-dlp-tui (JSON history), yt-parallel (file list) |
| **Config key=value** | `~/.config/app/config` | yt-x, yt-dlp-tui (settings page) |

---

## 2. Requisitos Funcionales (Specs)

### S1 — Modos de Operación
| ID | Modo | Descripción | Entrada | Salida |
|----|------|-------------|---------|--------|
| S1.1 | **Video** | Video único, mejor calidad nativa | URL video | Archivo contenedor original |
| S1.2 | **Audio** | Solo audio, mejor calidad original | URL video | Audio contenedor original (opus/m4a/webm/flac) |
| S1.3 | **Playlist** | Lista completa o rango (N-M, saltos) | URL playlist | Carpeta `playlist_title/` con índice |
| S1.4 | **Canal** | Canal completo (videos + shorts + lives) | URL canal/@handle | Carpeta `uploader/fecha - título` |
| S1.5 | **Custom** | URL cruda + flags manuales | URL + flags extra | Según flags |
| S1.6 | **Queue** | Cola de múltiples URLs (añadir, listar, procesar) | Lista URLs | Procesamiento secuencial/paralelo |

### S2 — Selector de Calidad (Format Sorting)
| ID | Preset | `-S` value | Comportamiento |
|----|--------|------------|----------------|
| S2.1 | **Máxima** | `res,br` | Mayor resolución + bitrate (sin filtro contenedor/codec) |
| S2.2 | **Equilibrado** | `res:1080,br` | Cap 1080p + mejor bitrate |
| S2.3 | **Compatibilidad** | `ext:mp4:m4a,codec:h264:aac,res,br` | Fuerza mp4/h264/aac |
| S2.4 | **Tamaño mínimo** | `+size,+br` | Menor archivo + bitrate |
| S2.5 | **Solo AV1/Opus** | `codec:av1:opus,res,br` | Codecs modernos only |
| S2.6 | **Personalizado** | Input libre | Usuario escribe su `-S` |

> **Nota**: Todos usan fallback implícito `bv*+ba/b` (default yt-dlp). No hay `-f` restrictivo.

### S3 — Post-Procesado yt-dlp (Siempre Activo)
| Feature | Flag | Descripción |
|---------|------|-------------|
| Metadatos completos | `--embed-metadata` | Info JSON, tags, capítulos |
| Thumbnail portada | `--embed-thumbnail` | Cover art en archivo |
| Capítulos nativos | `--embed-chapters` | Marcadores de capítulo |
| SponsorBlock mark | `--sponsorblock-mark all` | Capítulos tipo `[SponsorBlock]: Sponsor` |
| SponsorBlock remove | `--sponsorblock-remove sponsor,selfpromo,interaction` | **Corte frame-accurate** |
| Subtítulos (opcional) | `--write-subs --embed-subs --sub-lang es,en` | Write + embed (configurable) |
| Merge contenedor | `--merge-output-format` | Solo si usuario elige (Fase 2) |
| Remux only | `--remux-video mkv/mp4/webm` | Cambio contenedor sin re-encode (Fase 2) |

### S4 — Red y Resiliencia
| Feature | Flag/Config | Valor Default |
|---------|-------------|---------------|
| Timeout socket | `--socket-timeout` | 60s |
| Reintentos | `--retries --fragment-retries` | 20 |
| Fragmentos concurrentes HLS/DASH | `-N` / `--concurrent-fragments` | 4 |
| Rate limit | `--throttled-rate` | Opcional (usuario) |
| Proxy | `--proxy` | Opcional (HTTP/SOCKS) |
| Cookies | `--cookies-from-browser chrome/firefox/edge` | Opcional |
| Geo-bypass | `--geo-verification-proxy` | Opcional |
| IPv4/IPv6 force | `--force-ipv4` | Opcional |

### S5 — Queue System (Cola)
| ID | Función | Detalle |
|----|---------|---------|
| S5.1 | **Añadir a cola** | URL + modo + preset + opciones → persiste en `queue.jsonl` |
| S5.2 | **Listar cola** | Muestra pendientes, en progreso, completados, fallados |
| S5.3 | **Procesar cola** | Secuencial (default) o paralelo (`-j N`) |
| S5.4 | **Persistencia** | `~/.config/ytdl-sh/queue.jsonl` (JSON Lines) |
| S5.5 | **Resume** | Al reiniciar, continúa items pendientes |
| S5.6 | **Control** | Pausar, reanudar, cancelar, reordenar, reintentar fallados |
| S5.7 | **Paralelismo** | `--parallel N` (jobs simultáneos), usa `wait -n` bash |

### S6 — Templates de Salida (por modo)
| Modo | Template (`-o`) |
|------|-----------------|
| Video | `%(title)s [%(id)s].%(ext)s` |
| Audio | `%(title)s [%(id)s].%(ext)s` |
| Playlist | `%(playlist_title)s/%(playlist_index)03d - %(title)s [%(id)s].%(ext)s` |
| Canal | `%(uploader)s/%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s` |
| Custom | Usuario define |

> **Siempre** `%(ext)s` → conserva extensión original (webm, mkv, mp4, m4a, opus, flac...)

### S7 — Validación Pre-Vuelo
| Check | Herramienta | Acción si falla |
|-------|-------------|-----------------|
| `yt-dlp` en PATH | `command -v` | Error + instrucciones install |
| `ffmpeg` en PATH | `command -v` | Error + instrucciones install |
| `curl` en PATH | `command -v` | Error (para validación red) |
| YouTube accesible | `curl -sI https://www.youtube.com` (3s) | Warning |
| googlevideo accesible | `curl -sI https://googlevideo.com` (3s) | Warning (VPN/proxy needed) |
| Espacio disco | `df --output=avail` | Warning si < 1GB |

### S8 — Configuración Persistente (Opcional)
| Archivo | Formato | Contenido |
|---------|---------|-----------|
| `~/.config/ytdl-sh/config` | `key=value` | Defaults: outdir, preset, parallel, proxy, cookies, subtitles lang, sponsorblock categories |
| `~/.config/ytdl-sh/history.jsonl` | JSON Lines | Últimas 50 descargas: url, modo, preset, archivo, timestamp, status |
| `~/.config/ytdl-sh/archive.txt` | Texto (1 ID/linea) | `--download-archive` compartido |
| `~/.config/ytdl-sh/queue.jsonl` | JSON Lines | Cola persistente |

### S9 — Dry-Run / Simulación
| Flag | Comportamiento |
|------|----------------|
| `--dry-run` / `-n` | Ejecuta yt-dlp con `--simulate --print-json` o `--flat-playlist --print "%(title)s|%(id)s|%(duration)s"` — **no descarga**, muestra plan |

### S10 — Notificaciones (Multiplataforma)
| Plataforma | Comando |
|------------|---------|
| Linux (libnotify) | `notify-send "ytdl-sh" "Descarga completada: $title"` |
| macOS | `osascript -e 'display notification "..." with title "ytdl-sh"'` |
| Termux | `termux-notification --title "ytdl-sh" --content "..."` |
| Webhook genérico | `curl -X POST "$WEBHOOK_URL" -d '{"text":"..."}'` (opcional) |

---

## 3. Requisitos No Funcionales

| ID | Requisito | Métrica |
|----|-----------|---------|
| NFR1 | **Un solo archivo** | `ytdl-sh` (bash, ~400-500 líneas) |
| NFR2 | **Cero dependencias externas** | Solo: bash 4+, yt-dlp, ffmpeg, curl (POSIX) |
| NFR3 | **Portabilidad** | Linux, macOS, WSL, Termux, Alpine, *BSD |
| NFR4 | **Startup < 200ms** | Sin cargar configs pesadas, sin binarios extra |
| NFR5 | **Memoria < 10MB** | Bash puro, sin subprocessos persistentes |
| NFR6 | **Idioma UI** | Español (voseo) default, detectable por `$LANG` |
| NFR7 | **Colors/TTY** | `tput` detection, degradación graceful sin TTY |
| NFR8 | **Señales** | `trap` SIGINT/SIGTERM → cleanup temp, save queue state |
| NFR9 | **Logs** | `--newline --progress` en TTY; opcional `--write-jsonl` a archivo |
| NFR10 | **Licencia** | MIT / Unlicense (compatible yt-dlp + ffmpeg GPL/LGPL) |

---

## 4. Arquitectura de Menús (Navigation Flow)

```
┌─────────────────────────────────────────────────────────────┐
│                      YTDL-SH v1.0                           │
│         Interactive yt-dlp + ffmpeg Downloader              │
└─────────────────────────────────────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
        ┌──────────┐   ┌──────────┐   ┌──────────┐
        │  COLAS   │   │  AJUSTES │   │  AYUDA   │
        └──────────┘   └──────────┘   └──────────┘
              │
              ▼
┌─────────────────────────────────────────────────────────────┐
│                    MODO DE DESCARGA                         │
├─────────┬─────────┬──────────┬─────────┬─────────┬─────────┤
│  Video  │  Audio  │ Playlist │ Canal   │ Custom  │  Queue  │
└────┬────┴────┬────┴────┬────┴────┬────┴────┬────┴────┬────┘
     │         │         │         │         │         │
     ▼         ▼         ▼         ▼         ▼         ▼
┌─────────────────────────────────────────────────────────────┐
│                     PRESET DE CALIDAD                       │
├────────────┬────────────┬────────────┬────────────┬────────┤
│  Máxima    │ Equilibrado│ Compatib.  │  Mínimo    │Custom  │
└────────────┴────────────┴────────────┴────────────┴────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                    OPCIONES AVANZADAS (opcional)            │
├──────────┬──────────┬──────────┬──────────┬────────────────┤
│ Cookies  │  Proxy   │ Match-   │ Subtít.  │  Rate Limit    │
│          │          │ filter   │          │                │
└──────────┴──────────┴──────────┴──────────┴────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                      CONFIRMACIÓN                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ Modo: Playlist  │ Preset: Máxima  │ Salida: ~/Desc  │   │
│  │ URL: https://...│ Items: 1-50     │ Subs: es,en     │   │
│  │ SponsorBlock: ✓ │ Archive: ✓      │ Parallel: 1     │   │
│  └─────────────────────────────────────────────────────┘   │
│  [Ejecutar]  [Dry-run]  [Editar]  [Cancelar]               │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                      EJECUCIÓN                              │
│  ████████████████████░░░░░░░░ 65%  2.3MB/s  ETA 0:45       │
│  [video 12/50]  "Título del video"  →  webm (VP9+Opus)    │
│  ────────────────────────────────────────────────────────  │
│  Log: [yt-dlp] [ffmpeg] [SponsorBlock] [embed]             │
└─────────────────────────────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                  POST-DESCARGA (Fase 3)                     │
├────────────┬────────────┬────────────┬────────────┬────────┤
│ Loudnorm   │ HDR→SDR    │ Trim       │ Burn-subs  │ Preview│
└────────────┴────────────┴────────────┴────────────┴────────┘
     │
     ▼
┌─────────────────────────────────────────────────────────────┐
│                      RESUMEN                                │
│  ✅ 48/50 completados  |  ⚠ 2 fallados  |  📁 ~/Desc/playlist│
│  [Abrir carpeta]  [Reintentar fallados]  [Volver al menú]   │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Contratos de Datos

### 5.1 Queue Entry (`queue.jsonl`)
```json
{
  "id": "q_20260115_143022_abc123",
  "url": "https://youtube.com/playlist?list=PL...",
  "mode": "playlist",
  "preset": "maxima",
  "options": {
    "start": 1,
    "end": 50,
    "subtitles": ["es", "en"],
    "sponsorblock_remove": ["sponsor", "selfpromo", "interaction"]
  },
  "status": "pending|running|done|failed",
  "created": "2026-01-15T14:30:22Z",
  "started": "2026-01-15T14:30:25Z",
  "finished": "2026-01-15T14:45:10Z",
  "output_dir": "/home/user/Descargas/playlist_title",
  "files": [{"path": "...", "size": 123456789, "ext": "webm"}],
  "error": null,
  "retry_count": 0
}
```

### 5.2 Config File (`~/.config/ytdl-sh/config`)
```bash
# ytdl-sh config — key=value (comentarios con #)
OUTDIR=/home/user/Descargas
PRESET=maxima
PARALLEL=1
SUB_LANGS=es,en
SPONSORBLOCK_REMOVE=sponsor,selfpromo,interaction
PROXY=
COOKIES_BROWSER=
RATE_LIMIT=
NOTIFY_CMD=notify-send
```

### 5.3 History Entry (`history.jsonl`)
```json
{
  "timestamp": "2026-01-15T14:45:10Z",
  "url": "https://youtube.com/watch?v=...",
  "mode": "video",
  "preset": "maxima",
  "file": "/home/user/Descargas/Video Title [abc123].webm",
  "size": 123456789,
  "duration": 1234,
  "status": "success",
  "format_id": "315+251",
  "container": "webm",
  "vcodec": "vp9",
  "acodec": "opus"
}
```

---

## 6. Criterios de Aceptación por Fase

### FASE 1 — Core Sólido (Target: 1 archivo, ~350 líneas)
| Criterio | Verificación |
|----------|--------------|
| AC1.1 | Script ejecuta sin errores en bash 4.4+ (Linux, macOS, WSL, Termux) |
| AC1.2 | Menú principal navega con flechas (ANSI), Enter selecciona, Esc cancela |
| AC1.3 | 5 modos funcionan: video, audio, playlist, channel, custom |
| AC1.4 | Preset "Máxima" (`-S "res,br"`) descarga mejor calidad nativa (webm/mkv/mp4) |
| AC1.5 | Archive persiste entre corridas (no re-descarga) |
| AC1.6 | SponsorBlock mark+remove activo por defecto |
| AC1.7 | Metadatos + thumbnail + capítulos embebidos |
| AC1.8 | Subtítulos opcionales (menú: no/escribir/embed) |
| AC1.9 | Validación red pre-vuelo (YouTube + googlevideo) con warnings |
| AC1.10 | Dry-run muestra plan sin descargar |
| AC1.11 | Stats post-descarga: archivos, extensiones, .part pendientes |
| AC1.12 | Config file opcional se crea al cambiar defaults |
| AC1.13 | History JSONL registra cada descarga |
| AC1.14 | Queue básica: add, list, process (secuencial), persist |

### FASE 2 — Presets & Calidad
| Criterio | Verificación |
|----------|--------------|
| AC2.1 | 6 presets funcionan (Máxima, Equilibrado, Compatibilidad, Mínimo, AV1/Opus, Custom) |
| AC2.2 | Audio mode: `-x` sin `--audio-format` → mantiene original (opus/m4a/webm/flac) |
| AC2.3 | Remux-only (`--remux-video mkv|mp4|webm`) cambia contenedor sin re-encode |
| AC2.4 | Match-filter builder interactivo (duración, vistas, fecha, uploader, tags) |
| AC2.5 | Cookies/Proxy/Geo helpers en menú avanzado |
| AC2.6 | Playlist range + saltos (`1-5,10,15-20`) |

### FASE 3 — Post-Procesado ffmpeg (Opcional, menú tras descarga)
| Criterio | Verificación |
|----------|--------------|
| AC3.1 | Menú post-proceso aparece tras descarga exitosa |
| AC3.2 | Loudnorm (EBU R128 I=-16 TP=-1.5 LRA=11) funciona |
| AC3.3 | HDR→SDR (tonemap=hable + zscale bt709) funciona |
| AC3.4 | Trim (inicio/fin o lista cortes) con `-ss -to -c copy` |
| AC3.5 | Burn-in subtítulos (`-vf subtitles=`) funciona |
| AC3.6 | Preview GIF/sprite grid generado |
| AC3.7 | Auto-detect HW accel (nvenc > qsv > vaapi > videotoolbox > cpu) |
| AC3.8 | Temp dir `mktemp -d` limpio al finalizar |

### FASE 4 — Polish & Persistencia
| Criterio | Verificación |
|----------|--------------|
| AC4.1 | Config file carga defaults al inicio |
| AC4.2 | History muestra últimas 10 con `fzf`/`choose` para re-descargar |
| AC4.3 | Notificaciones funcionan en Linux/macOS/Termux |
| AC4.4 | Log JSONL opcional (`--write-jsonl`) parseable |
| AC4.5 | README + install script + autocomplete (bash/zsh/fish) |
| AC4.6 | Tests de humo: 5 URLs distintas (YT, Twitch, Twitter, Vimeo, Generic) |

---

## 7. Decisiones Técnicas Clave

| Decisión | Elección | Justificación |
|----------|----------|---------------|
| **UI Framework** | Pure bash `choose()` con ANSI + `read -rsn1` | Cero deps, funciona en cualquier terminal, < 50 líneas |
| **Queue Storage** | JSON Lines (`queue.jsonl`) | Append-only, streaming parse, crash-safe, `jq` opcional |
| **Parallel Jobs** | `wait -n` (bash 4.3+) + job control | Nativo, sin GNU parallel, control de concurrencia |
| **Temp Dir** | `mktemp -d` (system tmp) | Limpio, sin basura en workspace, multi-instancia seguro |
| **Format Selection** | `-S "res,br"` + fallback implícito | Moderno, declarativo, sin exclusiones, future-proof |
| **Config Format** | `key=value` simple | Shell-sourceable, editable a mano, sin parser complejo |
| **Error Handling** | `set -euo pipefail` + `trap` + exit codes | Robusto, debuggeable, no silent failures |
| **Streaming stdout** | Opción en menú Custom: `-o - \| mpv -` | Instant playback, no disk write (usuario decide) |
| **aria2c Integration** | Flag `--use-aria2c` en menú avanzado | Opcional, 2-5x speed en CDNs que lo permiten |

---

## 8. Riesgos y Mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| yt-dlp rompe extractor (YouTube cambia) | Media | Alto | `--ignore-errors`, auto-update check (`yt-dlp -U`), fallback formats |
| ffmpeg no disponible / versión vieja | Baja | Alto | Check version al inicio, warning claro, `--merge-output-format` opcional |
| Proxy corporativo bloquea googlevideo | Alta (entorno usuario) | Alto | Validación pre-vuelo explícita, warning VPN, `--proxy` support |
| SponsorBlock API down | Baja | Medio | `--sponsorblock-remove` falla graceful, solo mark funciona |
| Nombres de archivo colisionan (Unicode, largo) | Media | Medio | `--restrict-filenames` opcional, `%(id)s` único en template |
| Queue corrupta (kill -9) | Baja | Medio | JSON Lines append-only, recovery al leer (skip líneas inválidas) |
| Espacio disco lleno | Media | Alto | Check `df` pre-vuelo, `--no-part` opcional, cleanup `.part` old |
| Bash version < 4.0 (macOS default) | Media | Medio | Shebang `#!/usr/bin/env bash`, check `BASH_VERSION`, instrucciones `brew install bash` |

---

## 9. Protocolo de Desarrollo Interactivo (OBLIGATORIO)

> **Acordado el 2026-10-20** — Este protocolo gobierna **cada fase y cada parte de cada fase**.

### Flujo por Iteración

| Paso | Acción | Responsable | Artefacto |
|------|--------|-------------|-----------|
| **1. Explicación** | Qué vamos a hacer, por qué, cómo se integra, si es la mejor alternativa, sugerencias e impacto | **Orchestrator** | Conversación |
| **2. Decisión** | Usuario: Aprueba / pide cambios / rechaza | **Usuario** | Confirmación explícita |
| **3. Documentación ODD** | Actualizar `odd/tasks/<feature>.md` (specs, tasks, log, risk lines) + Engram mirror | **Orchestrator** | Feature doc + Engram |
| **4. Implementación** | Escribir código siguiendo ODD (inline direct, commits por task, etc.) | **Orchestrator** | Código fuente |
| **5. Verificación** | Tests, checks, risk line validation | **Orchestrator** | Evidencia de checks |
| **6. Cierre** | Report outcome, failed/pending checks, next step | **Orchestrator** | Conversación + Log entry |

### Reglas de Oro

- **Ningún código se escribe sin aprobación explícita del paso 2**
- **Ningún paso se salta** — el orden es fijo
- **Cada task (T1-T8) pasa por este ciclo completo**
- **Documentación y código van de la mano** — no hay "documentar después"
- **Engram se actualiza tras cada decisión/descubrimiento significativo** (proactive save)

---

## 10. Roadmap de Implementación (ODD)

```
┌────────────────────────────────────────────────────────────────────┐
│                        YTDL-SH ROADMAP (ODD)                       │
├────────────┬────────────┬────────────┬────────────┬───────────────┤
│   FASE 1   │   FASE 2   │   FASE 3   │   FASE 4   │   CONTINUO    │
│  (Core)    │ (Presets)  │ (FFmpeg)   │ (Polish)   │               │
├────────────┼────────────┼────────────┼────────────┼───────────────┤
│ Semana 1-2 │ Semana 3   │ Semana 4   │ Semana 5   │ - yt-dlp -U   │
│            │            │            │            │ - Issue triage│
├────────────┼────────────┼────────────┼────────────┼───────────────┤
│ ✓ Menú     │ ✓ 6 presets│ ✓ Loudnorm │ ✓ Config   │ - New sites   │
│ ✓ 5 modos  │ ✓ Remux    │ ✓ Tonemap  │ ✓ History  │ - FFmpeg feat │
│ ✓ Archive  │ ✓ Match-f  │ ✓ Trim     │ ✓ Notify   │ - Shell compl │
│ ✓ SponsorB │ ✓ Cookies  │ ✓ Burn-subs│ ✓ JSONL    │ - Perf opts   │
│ ✓ Subs     │ ✓ Proxy    │ ✓ Preview  │ ✓ README   │               │
│ ✓ Val red  │ ✓ Range    │ ✓ HW accel │ ✓ Install  │               │
│ ✓ Dry-run  │ ✓ Audio    │ ✓ Temp     │ ✓ Tests    │               │
│ ✓ Queue    │   original │   cleanup  │            │               │
└────────────┴────────────┴────────────┴────────────┴───────────────┘
```

### Flujo ODD por Fase (Obligatorio) — Sección 10

**Cada fase sigue el protocolo ODD (según instrucciones del orchestrator):**

1. **Authorize** — Confirmar que la fase autoriza cambios (sí, implementación autorizada)
2. **Explore** — Leer código existente, verificar dependencias, probar comandos yt-dlp/ffmpeg reales
3. **Resolve uncertainty** — Preguntar solo decisiones de producto reales (ej: ¿default parallel=1 o 2?)
4. **Classify** — Tamaño por Task Size: small si understood + contained risk + resumable from diff
5. **Track** — Crear `odd/tasks/<feature-name>.md` + Engram mirror `odd/<feature-name>/tasks` **antes del primer write**
6. **Implement task by task** — Handoff by reference: `Spec: odd/tasks/<feature>.md, T2, S3-S4`
7. **Close** — Reportar outcome verificado, checks fallidos/pendientes, next step

**Reglas ODD aplicadas:**
- Small tasks → inline direct (read, edit, focused test, suite once)
- Large tasks → tracking + feature doc + work-unit commits (~400 líneas autoradas)
- Delegation solo por triggers: Mapping (explore >5 lookups), Writer (parallel units), Verification (named high-risk item)
- Test-first: RED → GREEN → REFACTOR para behavior changes
- Delivery: work-unit commits en feature branch, push/PR/merge = decisión humana

---

## 11. Apéndice: Referencias de Comandos Clave

### yt-dlp Flags de Referencia Rápida
```bash
# Core
yt-dlp -S "res,br" --ignore-errors --download-archive archive.txt \
  --embed-metadata --embed-thumbnail --embed-chapters \
  --sponsorblock-mark all --sponsorblock-remove sponsor,selfpromo,interaction \
  --write-subs --embed-subs --sub-lang es,en \
  -N 4 --socket-timeout 60 --retries 20 --fragment-retries 20 \
  --newline --progress \
  -o "%(title)s [%(id)s].%(ext)s" "URL"

# Audio original (sin reconversión)
yt-dlp -x -S "abr" ... "URL"

# Remux only (cambio contenedor)
yt-dlp --remux-video mkv ... "URL"

# aria2c para HTTP/FTP
yt-dlp --downloader aria2c --downloader-args "aria2c:-x 16 -s 16 -k 1M" ...

# Streaming a player
yt-dlp -o - "URL" | mpv -

# Simulación
yt-dlp --simulate --print-json "URL"
yt-dlp --flat-playlist --print "%(title)s|%(id)s|%(duration)s" "PLAYLIST_URL"
```

### ffmpeg Post-Proceso (Fase 3)
```bash
# Loudnorm EBU R128
ffmpeg -i in.mp4 -af loudnorm=I=-16:TP=-1.5:LRA=11 -c:v copy out.mp4

# HDR → SDR (tonemap hable)
ffmpeg -i in.mp4 -vf "zscale=t=linear,tonemap=hable,zscale=t=bt709,format=yuv420p" -c:a copy out.mp4

# Trim (copia stream)
ffmpeg -i in.mp4 -ss 00:01:30 -to 00:45:00 -c copy out.mp4

# Burn-in subtítulos
ffmpeg -i in.mp4 -vf "subtitles=sub.srt:force_style='FontSize=24'" -c:a copy out.mp4

# Preview sprite grid (10x10 cada 5%)
ffmpeg -i in.mp4 -vf "select='not(mod(n\,100))',scale=320:-1,tile=10x10" preview.jpg
```

---

## 12. Decisiones Pendientes (Pre-Implementación)

| Tema | Decisión Pendiente | Default Propuesto |
|------|-------------------|-------------------|
| **Nombre final** | `ytdl-sh` ✓ o otro? | `ytdl-sh` |
| **Directorio config** | `~/.config/ytdl-sh/` ✓ (XDG) | XDG_CONFIG_HOME/ytdl-sh |
| **Editor para custom flags** | `${EDITOR:-vi}` abre temp file? | Sí, temp file + read |
| **Auto-update check** | `yt-dlp -U` al inicio (sí/no/frecuencia)? | Weekly check, non-blocking |
| **Telemetría** | **Ninguna** (privacy by design) — confirmado | Hard no |
| **Shell completion** | Generar al instalar: `ytdl-sh --completion bash/zsh/fish` | Sí, Fase 4 |

---

## 13. Aprobación y Próximos Pasos

**✅ SPEC APROBADO** — Firmado por el usuario

### Próximos Pasos Inmediatos (Post-Aprobación)
1. **Crear `odd/tasks/ytdl-sh-core.md`** — Feature document para Fase 1 (ODD tracking)
2. **Implementar Fase 1** — Entregable: `ytdl-sh` archivo único ejecutable (~350 líneas)
3. **Testear con 5 plataformas** — YouTube, Twitch, Twitter/X, Vimeo, Generic extractor
4. **Iterar FASE 2** — Basado en feedback real de uso
5. **Documentar en README** + `install.sh` + shell completions

---

## 14. Metadatos del Documento

| Campo | Valor |
|-------|-------|
| **Versión** | 1.0.1 |
| **Fecha** | 2026-10-20 |
| **Autor** | Usuario + Gentle AI Orchestrator |
| **Workflow** | Organic Driven Development (ODD) |
| **Estado** | APROBADO — Ready for Phase 1 Implementation |
| **Ubicación** | `SPEC.md` (raíz del repositorio) |
| **Proyecto Engram** | `yt-dlp-shell` (topic: `odd/ytdl-sh-core/tasks`) |

---

*Este documento es la especificación única de verdad para ytdl-sh. Cualquier cambio de requisitos debe reflejarse aquí con versión incremental y log en `## Log`.*