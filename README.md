# yt-dlp-sh

**CLI interactiva para descargar videos, playlists y más, usando `yt-dlp` + `ffmpeg`.**
Un solo archivo `.sh`, cero dependencias extra.

```
╔══════════════════════════════════════════════════════════════════════╗
║                        ytdl-sh v1.0.0-core                        ║
║         Interactive yt-dlp + ffmpeg downloader                     ║
╚══════════════════════════════════════════════════════════════════════╝

  ▸ auto     — Detectar automáticamente (pega la URL y elijo el modo)
    video    — Video único (mejor calidad nativa)
    audio    — Solo audio (mejor calidad original)
    playlist — Playlist completa o rango N-M
    channel  — Canal completo (videos + shorts + lives)
    custom   — URL + flags manuales de yt-dlp
    queue    — Cola de descargas (añadir/listar/procesar)
    settings — Ajustes y configuración
    conn     — Test de conexión (YouTube + CDN de video)
    validate — Validar una URL (¿se puede descargar?)
    help     — Ayuda y atajos
    exit     — Salir
```

---

## Características

- **Cero dependencias extra** — un solo archivo `.sh`. Solo necesitás `bash`, `yt-dlp` y `ffmpeg`.
- **Detección automática** — pegás la URL y la CLI detecta el tipo de contenido (video, playlist, short, live, canal) sin hacer ni un request.
- **Sin exclusiones de formato** — usa *format sorting* (`-S`) en vez de selectores rígidos: descarga la mejor calidad disponible y conserva el contenedor original (`.webm`, `.mkv`, `.mp4`, `.m4a`, `.opus`…).
- **SponsorBlock** — marca los segmentos y además los recorta de verdad.
- **Metadatos completos** — tags, portada y capítulos embebidos en el archivo.
- **Subtítulos** — descarga y embebe en el video.
- **Cola persistente** — colas de descargas que sobreviven a cerrar la terminal.
- **Diagnóstico real** — verifica que YouTube y el CDN de video responden *antes* de que empieces a descargar.
- **Validación de URL** — te muestra el título real, la duración y cuántos videos tiene antes de gastar ancho de banda.

---

## Requisitos

| Herramienta | Versión mínima | Para qué |
|-------------|-----------------|----------|
| `bash` | 4.4+ | El script (macOS: `brew install bash`) |
| `yt-dlp` | 2023.01+ | Descarga. Se recomienda `2025+` para YouTube |
| `ffmpeg` | 4.0+ | Merge de video+audio, embebido de metadatos, SponsorBlock |
| `curl` | cualquiera | Validación de red |

> **Nota sobre YouTube**: `yt-dlp` reciente necesita un runtime JavaScript para resolver los challenges de YouTube. `deno` es el recomendado, pero `node` también funciona. Sin él, algunas descargas de YouTube fallan.

### Instalación de dependencias

```bash
# Debian / Ubuntu
sudo apt install yt-dlp ffmpeg curl

# Fedora
sudo dnf install yt-dlp ffmpeg curl

# macOS
brew install yt-dlp ffmpeg curl

# deno (runtime JS recomendado para YouTube)
curl -fsSL https://deno.land/install.sh | sh
```

---

## Instalación

```bash
git clone https://github.com/carlosFTP999/yt-dlp-sh.git
cd yt-dlp-sh
chmod +x ytdl-sh
./ytdl-sh
```

Para instalarlo en el `PATH`:

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/ytdl-sh" ~/.local/bin/ytdl-sh
```

---

## Uso

```bash
ytdl-sh                    # abre el menú interactivo
ytdl-sh --dry-run          # simula: no descarga, muestra el plan
ytdl-sh --help             # ayuda
ytdl-sh --version          # versión
```

### Atajos de teclado

| Tecla | Acción |
|-------|--------|
| `↑` / `↓` | Navegar el menú |
| `Enter` | Seleccionar |
| `Esc` | Cancelar y volver (funciona en **todas** las pantallas) |
| `Backspace` | Borrar el último carácter en un campo de texto |
| `Ctrl+C` | Salir del programa |

---

## Modos de descarga

| Modo | Qué hace | Plantilla de salida |
|------|----------|---------------------|
| **Detectar auto** | Pega la URL, detecta el tipo y elige el modo | según el tipo detectado |
| **Video** | Un video, mejor calidad nativa | `%(title)s [%(id)s].%(ext)s` |
| **Audio** | Solo audio, **sin reconversión** (conserva opus/m4a/webm/flac) | `%(title)s [%(id)s].%(ext)s` |
| **Playlist** | Lista completa o rango `N-M` | `<playlist_title>/%(playlist_index)03d - %(title)s [%(id)s].%(ext)s` |
| **Canal** | Videos + shorts + lives del canal | `<uploader>/%(upload_date>%Y-%m-%d)s - %(title)s [%(id)s].%(ext)s` |
| **Custom** | URL + flags manuales de `yt-dlp` | la que definas |

### Detección de URL

Al pegar una URL, la CLI la clasifica **sin conexión** (parseo puro de patrones, instantáneo):

| URL | Tipo detectado |
|-----|----------------|
| `youtube.com/playlist?list=PL…` | playlist |
| `youtube.com/watch?v=X&list=PL…` | video dentro de una playlist → **te pregunta** cuál querés |
| `youtube.com/watch?v=X` | video |
| `youtu.be/X` | video |
| `youtube.com/shorts/X` | short |
| `youtube.com/live/X` | live |
| `youtube.com/@handle` | canal |
| `youtube.com/channel/UC…` | canal |
| `youtube.com/c/NAME` · `/user/NAME` | canal |
| `youtube.com/playlist?list=UU…` | uploads del canal |

Además reconoce y etiqueta `tiktok`, `twitter`/`x`, `instagram`, `facebook`, `vimeo`, `twitch`, `reddit`, `soundcloud`, `bandcamp`, `bilibili`, `dailymotion` y más. **La plataforma nunca se impone**: `yt-dlp` ya resuelve el extractor correcto para 1800+ sitios.

---

## Presets de calidad

Se eligen con `-S` (*format sorting*), el selector moderno de `yt-dlp`:

| Preset | `-S` | Resultado |
|--------|------|-----------|
| **Máxima** (default) | `res,br` | Mejor resolución y bitrate disponibles, contenedor original |
| **Equilibrado** | `res:1080,br` | Tope de 1080p |
| **Compatibilidad** | `ext:mp4:m4a,codec:h264:aac,res,br` | Fuerza MP4/H.264/AAC |
| **Mínimo** | `+size,+br` | El archivo más pequeño |
| **AV1/Opus** | `codec:av1:opus,res,br` | Solo codecs modernos |
| **Personalizado** | libre | Tu propia expresión de sorting |

> No se usa `-f` con selectores rígidos: eso excluye formatos (`.webm`, `.mkv`, VP9, AV1…). Con `-S` + el merge nativo `bv*+ba/b` de `yt-dlp` obtenés la mejor calidad real sin perder nada.

---

## Post-procesado

Siempre activo:

| Flag | Efecto |
|------|--------|
| `--embed-metadata` | Tags, título, capítulos, info JSON |
| `--embed-thumbnail` | Portada dentro del archivo |
| `--embed-chapters` | Marcadores de capítulo |
| `--sponsorblock-mark all` | Capítulos `[SponsorBlock]: Sponsor`, `Intro`, etc. |
| `--sponsorblock-remove sponsor,selfpromo,interaction` | **Recorta** esos segmentos de verdad |
| `--write-subs --embed-subs` | Subtítulos descargados y embebidos |

---

## Diagnóstico

Dos herramientas para cuando algo falla:

### Test de conexión

Menú → **"Test de conexión"**. Verifica que YouTube responde y que el CDN de video es alcanzable, pidiendo solo 100 KB de un video de prueba. **No descarga nada pesado.**

### Validar una URL

Menú → **"Validar una URL"**. Consulta la metadata real y te muestra:

```
  Título:   Solución de ecuaciones | Primer grado y Racionales (Curso COMPLETO)
  Duración: 00:10:01
  Cantidad: 40 videos
  Extractor: Youtube
```

Útil para confirmar que pegaste la URL correcta **antes** de descargar varios GB, y para detectar URLs inválidas, privadas o no disponibles.

---

## Configuración

Se guarda en `~/.config/ytdl-sh/config` (formato `key=value`, editable a mano).

| Variable | Default | Descripción |
|----------|---------|-------------|
| `OUTDIR` | `$HOME/Descargas` | Directorio base de salida |
| `PRESET` | `maxima` | Preset de calidad |
| `PARALLEL` | `1` | Descargas simultáneas en la cola |
| `SUB_LANGS` | `es,en` | Idiomas de subtítulos (coma-separado) |
| `SPONSORBLOCK_REMOVE` | `sponsor,selfpromo,interaction` | Categorías a recortar |
| `PROXY` | *(vacío)* | Proxy HTTP/SOCKS, ej. `socks5://127.0.0.1:9050` |
| `COOKIES_BROWSER` | *(vacío)* | `chrome`, `firefox`, `edge`, `brave`, `opera`, `vivaldi` |
| `RATE_LIMIT` | *(vacío)* | Límite de velocidad, ej. `1M` |
| `FORCE_IPV4` | `false` | Forzar IPv4 |
| `YT_PLAYER_CLIENT` | *(vacío)* | Client de YouTube, ej. `android` |
| `PREFLIGHT_DEEP` | `auto` | `auto` (cache 6 h) · `always` · `never` |
| `VALIDATE_URL` | `false` | Validar la URL automáticamente al pegarla |
| `NOTIFY_CMD` | *(vacío)* | Comando de notificación al terminar |

También podés editar todo desde el menú → **Ajustes**.

### Archivos de estado

| Archivo | Contenido |
|---------|-----------|
| `~/.config/ytdl-sh/config` | Configuración |
| `~/.config/ytdl-sh/queue.jsonl` | Cola de descargas (JSON Lines) |
| `~/.config/ytdl-sh/history.jsonl` | Historial de descargas |
| `~/.config/ytdl-sh/archive.txt` | IDs ya descargados (no re-descarga) |
| `~/.config/ytdl-sh/.cdn_cache` | Cache del chequeo del CDN (6 h) |

---

## Cola de descargas

Menú → **"Cola"**:

- **Añadir** — mete una URL con su modo y preset
- **Listar** — muestra pendientes, completados y fallados
- **Procesar** — descarga secuencialmente, guardando el estado tras cada item (si se interrumpe, retoma)
- **Reintentar** — vuelve a poner en cola los fallados
- **Limpiar** — borra solo los pendientes, conserva el historial

---

## Problemas frecuentes

### «YouTube NO accesible» pero todo funciona

El chequeo es conservador. Mirá el mensaje completo: distingue DNS, timeout, error SSL o HTTP. Con un proxy corporativo es común que `youtube.com` responda pero el **CDN de video** no. En ese caso probá VPN o configurá `PROXY`.

### Las descargas fallan con `403 Forbidden`

YouTube limita por IP las descargas masivas. Esperá unos minutos o cambiá de salida (VPN).

### `HTTP Error 503` o `Tunnel connection failed`

El proxy no alcanza el CDN de video. Verificá con el **Test de conexión** y activá VPN.

### El video sale con extensión distinta a la esperada

Es intencional: se conserva el contenedor original del servidor. Si necesitás MP4 usá el preset **Compatibilidad**.

### `yt-dlp: command not found` en `ffprobe`

`ffmpeg` debe estar instalado (incluye `ffprobe`). En algunos sistemas hay que linkearlo aparte.

### YouTube pide verificación

`yt-dlp` se actualiza seguido: `yt-dlp -U`. Si seguís con problemas, probá `YT_PLAYER_CLIENT=android` en la config.

---

## Desarrollo

### Tests

```bash
tests/smoke-test.sh                # 77 tests, ~30 s
tests/smoke-test.sh --verbose      # muestra el detalle de los fallos
tests/smoke-test.sh --with-download  # + un test de descarga real (requiere red)
```

Salida: código de salida = cantidad de tests fallados (`0` = todo OK, listo para CI).

### Estructura

```
yt-dlp-sh/
├── ytdl-sh                 # el CLI (un solo archivo)
├── tests/
│   ├── smoke-test.sh       # suite de tests
│   └── lib/
│       └── test-helpers.sh # assertions
├── SPEC.md                 # especificación funcional
├── odd/tasks/              # documentos de desarrollo (ODD)
└── README.md
```

### Documentación

- [`SPEC.md`](SPEC.md) — especificación funcional completa (requisitos, criterios de aceptación, roadmap)
- [`odd/tasks/ytdl-sh-core.md`](odd/tasks/ytdl-sh-core.md) — bitácora de desarrollo

---

## Proyectos relacionados

Esta herramienta se inspiró en el trabajo de la comunidad. Proyectos similares consultados durante el diseño:

| Proyecto | Qué aportó |
|----------|------------|
| [yt-x](https://github.com/Benexl/yt-x) | Wrapper POSIX de `yt-dlp` con launcher, queue y config por archivo |
| [yt-dlp-tui](https://github.com/z4none/yt-dlp-tui) | TUI con inspección de formatos, selección de items de playlist, historial y resume |
| [yt-dl-gum](https://github.com/blackbunt/yt-dl-gum) | Wrapper TUI simple con detección de dependencias |
| [yt-agent](https://github.com/jvogan/yt-agent) | Herramienta de terminal para buscar, descargar, catalogar y recortar |
| [yt-parallel](https://github.com/phiroict/yt-parallel) | Descargas paralelas de `yt-dlp` desde una lista de URLs |
| [yt-dlp-fast](https://github.com/Shukurov777/yt-dlp-fast) | Integración de `aria2c` y modos de rendimiento |
| [Firelink](https://github.com/alireza388/Firelink-downloader) | Gestor de descargas con queues persistentes y scheduling |
| [yt-dlp](https://github.com/yt-dlp/yt-dlp) | El motor: extractores, format sorting, SponsorBlock, post-procesadores |
| [aria2c guide](https://aria2.org/guides/yt-dlp) | Uso de `aria2c` como transportador para descargas segmentadas |

---

## Licencia

MIT — ver [`LICENSE`](LICENSE).

`yt-dlp` está bajo Unlicense y `ffmpeg` bajo LGPL/GPL según la build. Esta herramienta es un wrapper: no incluye código de ninguno de los dos.
