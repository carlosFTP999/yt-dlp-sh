#!/usr/bin/env bash
# smoke-test.sh — End-to-end smoke tests para ytdl-sh
# Pure bash, cero dependencias externas. Corre contra el script real.
#
# Uso:
#   tests/smoke-test.sh              # Tests automáticos (rápido)
#   tests/smoke-test.sh --verbose    # Muestra salida de assertions en fallos
#   tests/smoke-test.sh --with-download  # + test de descarga real (lento, red)
#
# Exit code = número de tests fallados (0 = todo OK, listo para CI)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Helpers y código bajo test
source "$SCRIPT_DIR/lib/test-helpers.sh"
source "$REPO_DIR/ytdl-sh"

# Estado aislado: no tocar ~/.config real
ISOLATED_HOME="$(mktemp -d)"
export XDG_CONFIG_HOME="$ISOLATED_HOME"
init_config_dirs

# Opciones
TEST_VERBOSE="${TEST_VERBOSE:-0}"
RUN_DOWNLOAD=0
for arg in "$@"; do
  case "$arg" in
    --verbose) TEST_VERBOSE=1 ;;
    --with-download) RUN_DOWNLOAD=1 ;;
    -h|--help)
      echo "Uso: tests/smoke-test.sh [--verbose] [--with-download]"
      exit 0
      ;;
  esac
done

# Wrapper que respeta verbose
run_t() {
  local name="$1" fn="$2"
  reset_state
  TESTS_RUN=$((TESTS_RUN + 1))
  CURRENT_TEST="$name"
  if [[ "$TEST_VERBOSE" == "1" ]]; then
    printf "  [RUN ] %s\n" "$name"
    if "$fn"; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "  [PASS] %s\n" "$name"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf "  [FAIL] %s\n" "$name"
    fi
  else
    printf "  [....] %-45s " "$name"
    if "$fn" >/dev/null 2>&1; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      printf "\r  [PASS] %-45s\n" "$name"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf "\r  [FAIL] %-45s\n" "$name"
    fi
  fi
}

# ══════════════════════════════════════════════════════════════════════
# TESTS
# ══════════════════════════════════════════════════════════════════════

# 1. Config round-trip
t_config_roundtrip() {
  OUTDIR="/tmp/ytdl_sh_test_out"
  PRESET="equilibrado"
  save_config
  OUTDIR="/default/wrong"
  PRESET="maxima"
  load_config
  assert_eq "$OUTDIR" "/tmp/ytdl_sh_test_out" || return 1
  assert_eq "$PRESET" "equilibrado" || return 1
}

# 2. Config: defaults para keys ausentes
t_config_defaults() {
  rm -f "$CONFIG_FILE"
  load_config
  # Las defaults declaradas en ytdl-sh deben aplicarse
  assert_eq "$PRESET" "maxima" || return 1
  assert_eq "$FORCE_IPV4" "false" || return 1
}

# 3. Config: ignora keys inválidas y comentarios
t_config_ignores_invalid() {
  cat > "$CONFIG_FILE" <<EOF
# comment
OUTDIR=/valid/path
INVALID_KEY=value
=bad
EOF
  load_config
  assert_eq "$OUTDIR" "/valid/path" || return 1
}

# 4. JSON: build + get roundtrip
t_json_build_get() {
  local item
  item=$(json_build_queue_item "q1" "https://x.com/v" "video" "maxima" "{}" "pending" "2026-10-20T10:00:00Z")
  assert_eq "$(json_get "$item" "id")" "q1" || return 1
  assert_eq "$(json_get "$item" "url")" "https://x.com/v" || return 1
  assert_eq "$(json_get "$item" "mode")" "video" || return 1
  assert_eq "$(json_get "$item" "preset")" "maxima" || return 1
  assert_eq "$(json_get "$item" "status")" "pending" || return 1
}

# 5. JSON: escape de caracteres especiales
t_json_escape() {
  local item
  item=$(json_build_queue_item "q1" 'url"con\comillas' "video" "maxima" "{}" "pending" "2026-10-20")
  assert_eq "$(json_get "$item" "url")" 'url"con\comillas' || return 1
  is_valid_json "$item" || return 1
}

# 6. JSON: validación de línea inválida
t_json_invalid() {
  is_valid_json 'not json' && return 1
  is_valid_json '{unbalanced' && return 1
  is_valid_json '{"ok":"yes"}' || return 1
}

# 7. Queue: add / save / load
t_queue_persistence() {
  QUEUE=()
  QUEUE+=("$(json_build_queue_item "q1" "https://x.com/1" "video" "maxima" "{}" "pending" "2026-10-20")")
  QUEUE+=("$(json_build_queue_item "q2" "https://x.com/2" "audio" "minimo" "{}" "pending" "2026-10-20")")
  save_queue
  QUEUE=()
  load_queue
  assert_array_size 2 "${QUEUE[@]}" || return 1
  assert_eq "$(json_get "${QUEUE[0]}" "id")" "q1" || return 1
  assert_eq "$(json_get "${QUEUE[1]}" "mode")" "audio" || return 1
}

# 8. Queue: opciones de playlist serializadas
t_queue_playlist_options() {
  QUEUE=()
  QUEUE+=("$(json_build_queue_item "q1" "https://x.com/pl" "playlist" "maxima" '{"start":"5","end":"20"}' "pending" "2026-10-20")")
  save_queue
  QUEUE=()
  load_queue
  assert_eq "$(json_get "${QUEUE[0]}" "options")" '{"start":"5","end":"20"}' || return 1
}

# 9. Queue: load con líneas corruptas (skip)
t_queue_corrupt_skip() {
  printf '%s\n' \
    '{"id":"q1","url":"https://x.com/1","mode":"video","preset":"maxima","options":{},"status":"pending","created":"2026-10-20"}' \
    'corrupt line {' \
    '{"id":"q2","url":"https://x.com/2","mode":"audio","preset":"maxima","options":{},"status":"pending","created":"2026-10-20"}' \
    > "$QUEUE_FILE"
  QUEUE=()
  load_queue
  assert_array_size 2 "${QUEUE[@]}" || return 1
}

# 10. Format args: preset maxima
t_format_maxima() {
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_contains "$joined" "-S res,br" || return 1
  assert_contains "$joined" "--embed-metadata" || return 1
  assert_contains "$joined" "--embed-thumbnail" || return 1
  assert_contains "$joined" "--embed-chapters" || return 1
  assert_contains "$joined" "--sponsorblock-mark all" || return 1
}

# 11. Format args: preset compatibilidad fuerza mp4/h264
t_format_compat() {
  build_format_args "compatibilidad"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_contains "$joined" "ext:mp4:m4a,codec:h264:aac" || return 1
}

# 12. Format args: NO hay -f restrictivo
t_format_no_restrictive_f() {
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  # No debe forzar contenedor/codec específico (preserva webm/mkv/mp4)
  assert_not_contains "$joined" "-f " || return 1
}

# 13. Format args: red defaults
t_format_network() {
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_contains "$joined" "--socket-timeout 60" || return 1
  assert_contains "$joined" "--retries 20" || return 1
  assert_contains "$joined" "-N 4" || return 1
  assert_contains "$joined" "--ignore-errors" || return 1
}

# 14. Format args: proxy/cookies condicionales
t_format_proxy_conditional() {
  PROXY=""
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_not_contains "$joined" "--proxy" || return 1

  PROXY="socks5://127.0.0.1:9050"
  build_format_args "maxima"
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_contains "$joined" "--proxy socks5://127.0.0.1:9050" || return 1
  PROXY=""
}

# 15. Format args: force-ipv4
t_format_force_ipv4() {
  FORCE_IPV4="true"
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_contains "$joined" "--force-ipv4" || return 1
  FORCE_IPV4="false"
}

# 16. Format args: YT player client
t_format_yt_client() {
  YT_PLAYER_CLIENT="android"
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_contains "$joined" "--extractor-args youtube:player_client=android" || return 1
  YT_PLAYER_CLIENT=""
}

# 17. Dry-run: añade --simulate --print-json
t_dryrun_flag() {
  DRY_RUN="true"
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_contains "$joined" "--simulate" || return 1
  assert_contains "$joined" "--print-json" || return 1
  DRY_RUN="false"
}

# 18. Dry-run: sin dry-run no incluye simulate
t_dryrun_off() {
  DRY_RUN="false"
  build_format_args "maxima"
  local joined
  joined=$(printf '%s ' "${YTDLP_ARGS[@]}")
  assert_not_contains "$joined" "--simulate" || return 1
}

# 19. Template: playlist con índice
t_template_playlist() {
  local tmpl
  tmpl=$(build_output_template "playlist" "/out")
  assert_contains "$tmpl" "%(playlist_index)03d" || return 1
  assert_contains "$tmpl" "%(ext)s" || return 1
  assert_contains "$tmpl" "%(playlist_title)s" || return 1
}

# 20. Template: canal con fecha
t_template_channel() {
  local tmpl
  tmpl=$(build_output_template "channel" "/out")
  assert_contains "$tmpl" "%(upload_date>%Y-%m-%d)s" || return 1
  assert_contains "$tmpl" "%(uploader)s" || return 1
}

# 21. Template: video preserva %(ext)s
t_template_video_ext() {
  local tmpl
  tmpl=$(build_output_template "video" "/out")
  assert_contains "$tmpl" "%(ext)s" || return 1
  assert_contains "$tmpl" "%(id)s" || return 1
}

# 22. Preflight: corre sin crash (warnings no matan)
t_preflight_runs() {
  OUTDIR="$(mktemp -d)"
  # Subshell con set -e activo: si un warning aborta el script, falla el test
  ( set -euo pipefail; preflight_checks <<< "y" >/dev/null 2>&1 )
}

# 22b. REGRESIÓN: preflight NO debe probar el apex googlevideo.com
# (host inexistente con certificado SSL inválido → falso positivo permanente)
t_preflight_no_apex_cdn() {
  OUTDIR="$(mktemp -d)"
  local out
  out=$(preflight_checks <<< "y" 2>&1)
  # El apex googlevideo.com no es un host válido: nunca debe probarse.
  # (los hosts reales rr*---sn-*.googlevideo.com sí son legítimos)
  assert_not_contains "$out" "https://googlevideo.com" || return 1
  assert_not_contains "$out" '"https://googlevideo.com"' || return 1
}

# 22c. REGRESIÓN: el preflight usa timeout generoso, no 3s
t_preflight_timeout_generous() {
  # El fix usa --max-time 10 + reintento. Verificamos que no queda el 3s.
  local body
  body=$(sed -n '/^check_youtube_reachable()/,/^}/p' "$REPO_DIR/ytdl-sh")
  assert_contains "$body" "max-time 10" || return 1
  assert_not_contains "$body" "max-time 3" || return 1
}

# 22d. Diagnóstico por causa de error HTTP
t_http_diagnose() {
  local reason
  reason=$(http_diagnose "https://www.youtube.com" 2>&1)
  assert_nonempty "$reason" || return 1
  assert_contains "$reason" "ok" || return 1
}

# 22i. REGRESIÓN: el reintento debe resetear el código de error
# Si el intento 1 falla (timeout) y el intento 2 tiene éxito (200),
# el check debe reconocer el éxito. Antes: "YouTube NO accesible — ok (http=200)"
t_check_retry_resets_rc() {
  local mockdir count_file out rc=0
  mockdir="$(mktemp -d)"
  count_file="$mockdir/count"

  cat > "$mockdir/curl" <<'MOCK'
#!/usr/bin/env bash
n=$(cat "$MOCK_COUNT_FILE" 2>/dev/null || echo 0)
echo $((n + 1)) > "$MOCK_COUNT_FILE"
if (( n == 0 )); then exit 28; fi
printf '200'
MOCK
  chmod +x "$mockdir/curl"

  out=$(PATH="$mockdir:$PATH" MOCK_COUNT_FILE="$count_file" \
        check_youtube_reachable 2>&1) || rc=$?
  rm -rf "$mockdir"

  assert_eq "$rc" "0" || return 1
  assert_not_contains "$out" "NO accesible" || return 1
  return 0
}

# ══════════════════════════════════════════════════════════════════════
# T9: DETECCIÓN DE URL — tabla de patrones
# ══════════════════════════════════════════════════════════════════════

# Helper: verifica que detect_url devuelve "tipo plataforma"
assert_detect() {
  local url="$1" exp_tipo="$2" exp_plat="$3"
  local tipo plataforma
  IFS=' ' read -r tipo plataforma < <(detect_url "$url")
  assert_eq "$tipo" "$exp_tipo" || return 1
  assert_eq "$plataforma" "$exp_plat" || return 1
  return 0
}

t_detect_youtube_patterns() {
  # playlist
  assert_detect "https://www.youtube.com/playlist?list=PLabc123" "playlist" "youtube" || return 1
  # watch simple
  assert_detect "https://www.youtube.com/watch?v=BaW_jenozKc" "video" "youtube" || return 1
  # watch dentro de playlist (ambiguo)
  assert_detect "https://www.youtube.com/watch?v=BaW_jenozKc&list=PLabc123" "video_in_playlist" "youtube" || return 1
  # youtu.be
  assert_detect "https://youtu.be/BaW_jenozKc" "video" "youtube" || return 1
  # shorts
  assert_detect "https://www.youtube.com/shorts/BaW_jenozKc" "shorts" "youtube" || return 1
  # live
  assert_detect "https://www.youtube.com/live/BaW_jenozKc" "live" "youtube" || return 1
  # embed
  assert_detect "https://www.youtube.com/embed/BaW_jenozKc" "video" "youtube" || return 1
  # handle
  assert_detect "https://www.youtube.com/@midudev" "channel" "youtube" || return 1
  # channel
  assert_detect "https://www.youtube.com/channel/UCabcdefghijklmnop" "channel" "youtube" || return 1
  # /c/
  assert_detect "https://www.youtube.com/c/midudev" "channel" "youtube" || return 1
  # /user/
  assert_detect "https://www.youtube.com/user/midudev" "channel" "youtube" || return 1
  # mobile
  assert_detect "https://m.youtube.com/watch?v=BaW_jenozKc" "video" "youtube" || return 1
}

t_detect_youtube_uploads() {
  # list=UU... → uploads del propio canal
  assert_detect "https://www.youtube.com/playlist?list=UUabc123" "uploads" "youtube" || return 1
  # list=PL... → playlist normal
  assert_detect "https://www.youtube.com/playlist?list=PLabc123" "playlist" "youtube" || return 1
}

t_detect_other_platforms() {
  assert_detect "https://www.tiktok.com/@user/video/123" "video" "tiktok" || return 1
  assert_detect "https://vimeo.com/123456" "video" "vimeo" || return 1
  assert_detect "https://twitter.com/user/status/123" "video" "twitter" || return 1
  assert_detect "https://x.com/user/status/123" "video" "twitter" || return 1
  assert_detect "https://www.instagram.com/p/ABC/" "video" "instagram" || return 1
  assert_detect "https://www.soundcloud.com/artist/track" "audio" "soundcloud" || return 1
  assert_detect "https://www.twitch.tv/videos" "channel" "twitch" || return 1
}

t_detect_unknown_platform() {
  # Plataforma desconocida → devuelve el dominio como label
  assert_detect "https://mi-sitio.example/video/1" "video" "mi-sitio.example" || return 1
}

t_detect_type_to_mode() {
  assert_eq "$(type_to_mode playlist)" "playlist" || return 1
  assert_eq "$(type_to_mode video_in_playlist)" "playlist" || return 1
  assert_eq "$(type_to_mode channel)" "channel" || return 1
  assert_eq "$(type_to_mode uploads)" "channel" || return 1
  assert_eq "$(type_to_mode shorts)" "video" || return 1
  assert_eq "$(type_to_mode live)" "video" || return 1
  assert_eq "$(type_to_mode video)" "video" || return 1
  assert_eq "$(type_to_mode audio)" "audio" || return 1
}

t_detect_extract_playlist_id() {
  assert_eq "$(extract_playlist_id "https://www.youtube.com/playlist?list=PLabc123")" "PLabc123" || return 1
  assert_eq "$(extract_playlist_id "https://www.youtube.com/watch?v=X&list=PLxyz789")" "PLxyz789" || return 1
  assert_eq "$(extract_playlist_id "https://www.youtube.com/watch?v=X")" "" || return 1
}

t_detect_no_network() {
  # La detección NO debe hacer red: url_host/url_path son parseo puro
  local body
  body=$(sed -n '/^detect_url()/,/^}/p' "$REPO_DIR/ytdl-sh")
  assert_not_contains "$body" "curl " || return 1
  assert_not_contains "$body" "yt-dlp" || return 1
}

t_detect_url_host() {
  assert_eq "$(url_host "https://www.youtube.com/watch?v=X")" "youtube.com" || return 1
  assert_eq "$(url_host "https://youtu.be/X")" "youtu.be" || return 1
  assert_eq "$(url_host "http://m.youtube.com/x")" "m.youtube.com" || return 1
  assert_eq "$(url_host "https://user:pw@site.com/x")" "site.com" || return 1
}

t_detect_url_path() {
  assert_eq "$(url_path "https://www.youtube.com/playlist?list=X")" "/playlist" || return 1
  assert_eq "$(url_path "https://www.youtube.com/watch?v=X")" "/watch" || return 1
  assert_eq "$(url_path "https://youtu.be/X")" "/X" || return 1
  assert_eq "$(url_path "https://youtube.com")" "" || return 1
}

# 22j. REGRESIÓN: el flujo de detección NO debe abortar el script
# Con set -e, `read` que llega a EOF sin newline devuelve 1 y aborta.
# Además, dentro de `if "$fn"` el set -e está desactivado, así que este
# test DEBE correr en un subshell con set -e explícito para ser fiel
# al contexto de producción.
t_detect_flow_not_fatal() {
  (
    set -euo pipefail
    local tipo plataforma
    IFS=' ' read -r tipo plataforma < <(detect_url "https://www.youtube.com/playlist?list=PLabc") || true
    [[ "$tipo" == "playlist" ]] || { echo "tipo=$tipo"; exit 1; }
    [[ "$plataforma" == "youtube" ]] || { echo "plataforma=$plataforma"; exit 1; }
    exit 0
  )
}

# ══════════════════════════════════════════════════════════════════════
# T10: CACHE DEL CDN + VALIDACIÓN DE URL
# ══════════════════════════════════════════════════════════════════════

t_cdn_cache_roundtrip() {
  rm -f "$CDN_CACHE_FILE"
  cdn_cache_write "rr1---sn-test.googlevideo.com" "ok"
  assert_file_exists "$CDN_CACHE_FILE" || return 1
  local host
  host=$(cdn_cache_valid) || return 1
  assert_eq "$host" "rr1---sn-test.googlevideo.com" || return 1
}

t_cdn_cache_ttl_expired() {
  rm -f "$CDN_CACHE_FILE"
  # Timestamp de hace 7 horas (> TTL de 6h)
  local old_ts=$(( $(date +%s) - 25200 ))
  printf '%s %s %s\n' "$old_ts" "rr1---sn-test.googlevideo.com" "ok" > "$CDN_CACHE_FILE"
  cdn_cache_valid && return 1
  return 0
}

t_cdn_cache_ttl_valid() {
  rm -f "$CDN_CACHE_FILE"
  local now_ts=$(date +%s)
  printf '%s %s %s\n' "$now_ts" "rr1---sn-test.googlevideo.com" "ok" > "$CDN_CACHE_FILE"
  local host
  host=$(cdn_cache_valid) || return 1
  assert_eq "$host" "rr1---sn-test.googlevideo.com" || return 1
}

t_cdn_cache_failure_not_cached() {
  # Un fallo NO debe quedar cacheado: el próximo arranque debe reintentar
  rm -f "$CDN_CACHE_FILE"
  local old_ts=$(( $(date +%s) - 300 ))
  printf '%s %s %s\n' "$old_ts" "rr1---sn-test.googlevideo.com" "fail" > "$CDN_CACHE_FILE"
  cdn_cache_valid && return 1
  return 0
}

t_cdn_cache_corrupt_ignored() {
  rm -f "$CDN_CACHE_FILE"
  printf 'basura no parseable\n' > "$CDN_CACHE_FILE"
  cdn_cache_valid && return 1
  # Escritura corrupta: al reescribir debe quedar bien
  cdn_cache_write "host-test" "ok"
  local host
  host=$(cdn_cache_valid) || return 1
  assert_eq "$host" "host-test" || return 1
}

t_cdn_cached_never_skips() {
  PREFLIGHT_DEEP="never"
  local out
  out=$(check_cdn_cached 2>&1)
  assert_contains "$out" "desactivado" || return 1
  PREFLIGHT_DEEP="auto"
}

t_cdn_cached_uses_cache_no_network() {
  # Con cache válido, el deep check NO debe hacer red
  rm -f "$CDN_CACHE_FILE"
  cdn_cache_write "rr9---sn-cached.googlevideo.com" "ok"
  PREFLIGHT_DEEP="auto"
  local out
  out=$(check_cdn_cached 2>&1)
  assert_contains "$out" "cacheado" || return 1
  assert_contains "$out" "rr9---sn-cached.googlevideo.com" || return 1
}

t_validate_field_parser() {
  local out="TITULO:Mi Video
DURACION:870
CANTIDAD:40
EXTRACTOR:Youtube"
  assert_eq "$(validate_field "$out" "TITULO")" "Mi Video" || return 1
  assert_eq "$(validate_field "$out" "DURACION")" "870" || return 1
  assert_eq "$(validate_field "$out" "CANTIDAD")" "40" || return 1
  assert_eq "$(validate_field "$out" "EXTRACTOR")" "Youtube" || return 1
  # Título con dos puntos → debe conservar el resto
  assert_eq "$(validate_field "TITULO:Video: Parte 2" "TITULO")" "Video: Parte 2" || return 1
}

t_validate_field_playlist_title() {
  local out="TITULO:Video | Parte 1
PLTITULO:Mi Playlist
DURACION:601
CANTIDAD:40
EXTRACTOR:Youtube"
  assert_eq "$(validate_field "$out" "PLTITULO")" "Mi Playlist" || return 1
  assert_eq "$(validate_field "$out" "CANTIDAD")" "40" || return 1
  # Título con "|" debe conservarse completo
  assert_eq "$(validate_field "$out" "TITULO")" "Video | Parte 1" || return 1
}

t_validate_field_missing() {
  assert_eq "$(validate_field "OTRA:1" "TITULO")" "" || return 1
}

t_format_duration_helper() {
  assert_eq "$(format_duration 870)" "00:14:30" || return 1
  assert_eq "$(format_duration 3600)" "01:00:00" || return 1
  assert_eq "$(format_duration 59)" "00:00:59" || return 1
  assert_eq "$(format_duration "NA")" "NA" || return 1
}

t_init_creates_outdir() {
  # init_config_dirs debe crear OUTDIR: si no existe, df no puede medir
  # el espacio y el check de disco queda inoperante
  local d
  d="$(mktemp -d)/subdir/deep"
  OUTDIR="$d"
  init_config_dirs
  [[ -d "$d" ]] || { echo "OUTDIR no creado: $d"; return 1; }
  return 0
}

t_preflight_deep_config_exists() {
  # PREFLIGHT_DEEP y VALIDATE_URL deben existir en CONFIG_DEFAULTS
  assert_eq "${CONFIG_DEFAULTS[PREFLIGHT_DEEP]}" "auto" || return 1
  assert_eq "${CONFIG_DEFAULTS[VALIDATE_URL]}" "false" || return 1
}

t_validate_flow_not_fatal() {
  # El flujo de validación no debe abortar el script (con set -e real)
  (
    set -euo pipefail
    local out rc=0
    out=$(validate_url "https://www.youtube.com/watch?v=BaW_jenozKc") || rc=$?
    # Puede fallar (video no disponible) o funcionar; en ambos casos
    # debe devolver algo y no abortar el script
    [[ -n "$out" ]] || { echo "salida vacía"; exit 1; }
    exit 0
  )
}

# 22k. REGRESIÓN CRÍTICA: el menú debe verse en la terminal
# choose() se invoca como `choice=$(choose ...)`. Si imprimiera el menú a
# stdout, el command substitution lo capturaría y el usuario NO VERÍA NADA
# del menú (solo el título). El menú debe ir a stderr; stdout solo lleva
# el valor seleccionado.
t_choose_menu_visible() {
  local errfile="$ISOLATED_HOME/choose_err"
  local out
  out=$(printf '\n' | choose "Menu de prueba" "opcion1" "descripcion uno" "opcion2" "descripcion dos" 2>"$errfile") || true

  # stdout debe contener SOLO el valor seleccionado
  assert_eq "$out" "opcion1" || return 1

  # stderr debe contener el menú completo
  local err
  err=$(cat "$errfile")
  assert_contains "$err" "descripcion uno" || return 1
  assert_contains "$err" "descripcion dos" || return 1
  assert_contains "$err" "Menu de prueba" || return 1
  return 0
}

# 22l. REGRESIÓN: el menú no debe contaminar stdout con el valor + menú
t_choose_stdout_is_only_value() {
  local out
  out=$(printf '\n' | choose "X" "a" "desc" 2>/dev/null) || true
  # Exactamente el valor, sin líneas extra
  assert_eq "$out" "a" || return 1
  [[ "$out" != *$'\n'* ]] || return 1
  return 0
}

# 22m. REGRESIÓN CRÍTICA: las flechas deben navegar el menú
# Leer la secuencia ESC[ en dos reads separados hace que el byte '[' se
# pierda y las flechas dejen de funcionar: el menú queda inservible.
t_choose_arrow_navigation() {
  local out
  out=$(printf '\033[B\033[B\033[B\n' | choose "Menu" \
        "uno" "d1" "dos" "d2" "tres" "d3" "cuatro" "d4" 2>/dev/null) || true
  # 3 flechas abajo desde "uno" → debe llegar a "cuatro"
  assert_eq "$out" "cuatro" || return 1
}

t_choose_arrow_up() {
  local out
  out=$(printf '\033[B\033[B\033[A\n' | choose "Menu" \
        "uno" "d1" "dos" "d2" "tres" "d3" 2>/dev/null) || true
  # abajo, abajo, arriba → "dos"
  assert_eq "$out" "dos" || return 1
}

t_choose_esc_cancels() {
  local rc=0
  printf '\033' | choose "Menu" "a" "d" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" "1" || return 1
}

t_choose_stops_at_boundaries() {
  # No debe pasar del primer ni del último elemento
  local out
  out=$(printf '\033[A\n' | choose "Menu" "uno" "d1" "dos" "d2" 2>/dev/null) || true
  assert_eq "$out" "uno" || return 1
  out=$(printf '\033[B\033[B\033[B\n' | choose "Menu" "uno" "d1" "dos" "d2" 2>/dev/null) || true
  assert_eq "$out" "dos" || return 1
}

# 22n. REGRESIÓN CRÍTICA: el valor devuelto por choose NO debe traer escapes
# tput civis/cnorm escriben a stdout. Como choose() se invoca como
# $(choose ...), esas secuencias contaminaban el valor seleccionado y el
# case nunca matcheaba: el menú respondía a las flechas pero Enter no
# hacía nada. Se usa un mock de tput que escribe a stdout, como el real.
t_choose_value_is_clean() {
  local mockdir
  mockdir="$(mktemp -d)"
  cat > "$mockdir/tput" <<'MOCK'
#!/usr/bin/env bash
printf '\033[?25l'
MOCK
  chmod +x "$mockdir/tput"

  local saved_tput="$HAS_TPUT"
  HAS_TPUT=1
  local out
  out=$(printf '\n' | PATH="$mockdir:$PATH" choose "Menu" "opcion" "desc" 2>/dev/null) || true
  HAS_TPUT="$saved_tput"
  rm -rf "$mockdir"

  if [[ "$out" == *$'\e'* ]]; then
    echo "el valor contiene secuencias de escape: $out"
    return 1
  fi
  assert_eq "$out" "opcion" || return 1
}

# 22g. REGRESIÓN CRÍTICA: un check de red fallido NO debe abortar el script
# Con set -euo pipefail, `var=$(cmd_fallido)` aborta el script entero.
# Este test reproduce el contexto real (set -e activo) y exige que el
# diagnóstico se muestre y que el script llegue al final.
t_network_failure_not_fatal() {
  (
    set -euo pipefail
    local reason
    reason=$(http_diagnose "https://host-inalcanzable.invalid" 2>&1) || true
    [[ -n "$reason" ]] || { echo "diagnóstico vacío"; exit 1; }
    # El preflight con host inalcanzable debe AVISAR, no morir en silencio
    local out
    out=$(YT_CHECK_URL="https://host-inalcanzable.invalid" check_youtube_reachable 2>&1) || true
    [[ "$out" == *"NO accesible"* ]] || { echo "sin warning: $out"; exit 1; }
    exit 0
  )
}

# 22h. REGRESIÓN: check_disk_space no debe abortar si df falla
t_disk_check_not_fatal() {
  (
    set -euo pipefail
    OUTDIR="/ruta/que/no/existe/probablemente"
    check_disk_space >/dev/null 2>&1 || true
    exit 0
  )
}

# 22f. REGRESIÓN: el check de disco debe MEDIR de verdad
# (el IFS global del script rompía el read de campos de df)
t_disk_space_measured() {
  OUTDIR="$(mktemp -d)"
  local out
  out=$(check_disk_space 2>&1)
  assert_not_contains "$out" "no se pudo medir" || return 1
  assert_contains "$out" "GB libres" || return 1
}

# 22e. Test de conexión CDN existe y no usa el apex inválido
t_cdn_check_function() {
  # La función debe resolver el host real vía yt-dlp -g
  local body
  body=$(sed -n '/^check_cdn_reachable()/,/^}/p' "$REPO_DIR/ytdl-sh")
  assert_contains "$body" "yt-dlp -g" || return 1
  # Range pequeño: valida la ruta sin descargar nada pesado
  assert_contains "$body" "0-100000" || return 1
  # Nunca debe probar el apex inexistente
  assert_not_contains "$body" 'https://googlevideo.com' || return 1
}

# 23. Preflight: aborta si usuario rechaza
t_preflight_abort() {
  OUTDIR="$(mktemp -d)"
  # Host inalcanzable -> warning real -> confirm "n" -> die -> exit != 0
  local rc=0
  ( YT_CHECK_URL="https://host-inalcanzable.invalid" preflight_checks <<< "n" ) >/dev/null 2>&1 || rc=$?
  (( rc != 0 )) || return 1
}

# 24. Dependencias: detecta yt-dlp/ffmpeg/curl
t_dependencies() {
  command -v yt-dlp >/dev/null || return 1
  command -v ffmpeg >/dev/null || return 1
  command -v curl >/dev/null || return 1
  check_dependencies >/dev/null 2>&1 || return 1
}

# 25. Signals: trap_cleanup persiste queue
t_trap_cleanup() {
  QUEUE=()
  QUEUE+=("$(json_build_queue_item "q1" "https://x.com/1" "video" "maxima" "{}" "pending" "2026-10-20")")
  trap_cleanup
  assert_file_exists "$QUEUE_FILE" || return 1
  assert_array_size 1 "${QUEUE[@]}" || return 1
}

# 26. Signals: trap_cleanup limpia temp dirs
t_trap_cleanup_tempdirs() {
  local d1 d2
  d1="$(mktemp -d)"
  d2="$(mktemp -d)"
  register_temp_dir "$d1"
  register_temp_dir "$d2"
  trap_cleanup
  [[ -d "$d1" ]] && return 1
  [[ -d "$d2" ]] && return 1
  return 0
}

# 27. Queue: retry marca failed como pending
t_queue_retry() {
  QUEUE=()
  QUEUE+=("$(json_build_queue_item "q1" "https://x.com/1" "video" "maxima" "{}" "failed" "2026-10-20")")
  queue_retry >/dev/null 2>&1
  assert_eq "$(json_get "${QUEUE[0]}" "status")" "pending" || return 1
}

# 28. Queue: clear solo borra pending
t_queue_clear_pending_only() {
  QUEUE=()
  QUEUE+=("$(json_build_queue_item "q1" "https://x.com/1" "video" "maxima" "{}" "pending" "2026-10-20")")
  QUEUE+=("$(json_build_queue_item "q2" "https://x.com/2" "audio" "maxima" "{}" "done" "2026-10-20")")
  queue_clear <<< "y" >/dev/null 2>&1
  assert_array_size 1 "${QUEUE[@]}" || return 1
  assert_eq "$(json_get "${QUEUE[0]}" "status")" "done" || return 1
}

# 29. Queue: process actualiza status
t_queue_process_status() {
  # Subshell con set -e activo: replica el contexto real de producción.
  # Si queue_process aborta (bug de set -e), el subshell retorna != 0.
  (
    set -euo pipefail
    QUEUE=()
    QUEUE+=("$(json_build_queue_item "q1" "https://invalid.invalid/x" "video" "maxima" "{}" "pending" "2026-10-20")")
    queue_process >/dev/null 2>&1
    status=$(json_get "${QUEUE[0]}" "status")
    [[ "$status" == "done" || "$status" == "failed" ]]
  )
}

# 30. Config: save es atómico (archivo existe y válido)
t_config_atomic_write() {
  save_config >/dev/null 2>&1
  assert_file_exists "$CONFIG_FILE" || return 1
  # Debe contener las 11 keys
  local keys
  keys=$(grep -cE '^(OUTDIR|PRESET|PARALLEL|SUB_LANGS|SPONSORBLOCK_REMOVE|PROXY|COOKIES_BROWSER|RATE_LIMIT|FORCE_IPV4|YT_PLAYER_CLIENT|NOTIFY_CMD)=' "$CONFIG_FILE")
  assert_eq "$keys" "11" || return 1
}

# 31. [Opcional] Descarga real con yt-dlp (video de prueba CC)
t_real_download() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  # Video oficial de prueba de yt-dlp (CC, dominio público, ~10s)
  local url="https://www.youtube.com/watch?v=BaW_jenozKc"
  build_format_args "maxima"
  yt-dlp "${YTDLP_ARGS[@]}" --no-embed-thumbnail --no-embed-chapters \
    -o "$tmpdir/%(title)s.%(ext)s" "$url" >/dev/null 2>&1
  local rc=$?
  rm -rf "$tmpdir"
  (( rc == 0 )) || return 1
}

# ══════════════════════════════════════════════════════════════════════
# EJECUCIÓN
# ══════════════════════════════════════════════════════════════════════

echo
printf '%s\n' "════════════════════════════════════════════════════════════"
printf '  ytdl-sh Smoke Tests%s\n' "$([[ "$RUN_DOWNLOAD" == "1" ]] && echo " (+ descarga real)")"
printf '%s\n' "════════════════════════════════════════════════════════════"
echo

# Reset de estado compartido entre tests
reset_state() {
  QUEUE=()
  TEMP_DIRS=()
  PROXY=""
  COOKIES_BROWSER=""
  RATE_LIMIT=""
  FORCE_IPV4="false"
  YT_PLAYER_CLIENT=""
  DRY_RUN="false"
  OUTDIR="$ISOLATED_HOME/out"
  PRESET="maxima"
  PARALLEL="1"
  SUB_LANGS="es,en"
  SPONSORBLOCK_REMOVE="sponsor,selfpromo,interaction"
  NOTIFY_CMD=""
  rm -f "$CONFIG_FILE" "$QUEUE_FILE" "$ARCHIVE_FILE" "$HISTORY_FILE"
}

run_test_group() {
  reset_state
  run_t "config: round-trip" t_config_roundtrip
  run_t "config: defaults para keys ausentes" t_config_defaults
  run_t "config: ignora keys inválidas/comentarios" t_config_ignores_invalid
  run_t "config: write atómico (11 keys)" t_config_atomic_write

  reset_state
  run_t "json: build + get roundtrip" t_json_build_get
  run_t "json: escape de caracteres" t_json_escape
  run_t "json: validación línea inválida" t_json_invalid

  reset_state
  run_t "queue: add/save/load" t_queue_persistence
  run_t "queue: opciones playlist" t_queue_playlist_options
  run_t "queue: skip líneas corruptas" t_queue_corrupt_skip
  run_t "queue: retry failed->pending" t_queue_retry
  run_t "queue: clear solo pending" t_queue_clear_pending_only
  run_t "queue: process actualiza status" t_queue_process_status

  reset_state
  run_t "format: preset maxima" t_format_maxima
  run_t "format: preset compatibilidad" t_format_compat
  run_t "format: sin -f restrictivo" t_format_no_restrictive_f
  run_t "format: red defaults" t_format_network
  run_t "format: proxy condicional" t_format_proxy_conditional
  run_t "format: force-ipv4" t_format_force_ipv4
  run_t "format: YT player client" t_format_yt_client

  reset_state
  run_t "dry-run: añade --simulate" t_dryrun_flag
  run_t "dry-run: off no incluye simulate" t_dryrun_off

  reset_state
  run_t "template: playlist índice" t_template_playlist
  run_t "template: canal fecha" t_template_channel
  run_t "template: video %(ext)s" t_template_video_ext

  reset_state
  run_t "preflight: corre sin crash" t_preflight_runs
  run_t "preflight: aborta si rechaza" t_preflight_abort
  run_t "preflight: NO prueba apex googlevideo" t_preflight_no_apex_cdn
  run_t "preflight: timeout generoso (10s)" t_preflight_timeout_generous
  run_t "preflight: diagnóstico por causa" t_http_diagnose
  run_t "conn: test CDN usa host real" t_cdn_check_function
  run_t "preflight: disco se mide de verdad" t_disk_space_measured
  run_t "detect: patrones YouTube" t_detect_youtube_patterns
  run_t "detect: uploads vs playlist" t_detect_youtube_uploads
  run_t "detect: otras plataformas" t_detect_other_platforms
  run_t "detect: plataforma desconocida" t_detect_unknown_platform
  run_t "detect: type_to_mode" t_detect_type_to_mode
  run_t "detect: extract_playlist_id" t_detect_extract_playlist_id
  run_t "detect: no hace red" t_detect_no_network
  run_t "detect: url_host" t_detect_url_host
  run_t "detect: url_path" t_detect_url_path
  run_t "detect: flujo NO aborta el script" t_detect_flow_not_fatal
  run_t "ui: el menú SE VE (stderr)" t_choose_menu_visible
  run_t "ui: stdout solo trae el valor" t_choose_stdout_is_only_value
  run_t "ui: flechas navegan el menú" t_choose_arrow_navigation
  run_t "ui: flecha arriba" t_choose_arrow_up
  run_t "ui: ESC cancela" t_choose_esc_cancels
  run_t "ui: límites del menú" t_choose_stops_at_boundaries
  run_t "ui: el valor NO trae escapes" t_choose_value_is_clean

  reset_state
  run_t "cache: round-trip" t_cdn_cache_roundtrip
  run_t "cache: TTL vencido" t_cdn_cache_ttl_expired
  run_t "cache: TTL válido" t_cdn_cache_ttl_valid
  run_t "cache: fallo NO se cachea" t_cdn_cache_failure_not_cached
  run_t "cache: corrupto se ignora" t_cdn_cache_corrupt_ignored
  run_t "cache: PREFLIGHT_DEEP=never" t_cdn_cached_never_skips
  run_t "cache: válido no hace red" t_cdn_cached_uses_cache_no_network
  run_t "validate: parser de campos" t_validate_field_parser
  run_t "validate: campo ausente" t_validate_field_missing
  run_t "validate: playlist_title" t_validate_field_playlist_title
  run_t "validate: format_duration" t_format_duration_helper
  run_t "validate: config existe" t_preflight_deep_config_exists
  run_t "init: crea el directorio de salida" t_init_creates_outdir
  run_t "validate: flujo NO aborta" t_validate_flow_not_fatal

  reset_state
  run_t "preflight: fallo de red NO es fatal" t_network_failure_not_fatal
  run_t "preflight: reintento resetea rc" t_check_retry_resets_rc
  run_t "preflight: df fallido NO es fatal" t_disk_check_not_fatal
  run_t "deps: yt-dlp/ffmpeg/curl" t_dependencies

  reset_state
  run_t "signals: trap_cleanup persiste queue" t_trap_cleanup
  run_t "signals: trap_cleanup limpia temp" t_trap_cleanup_tempdirs
}

run_test_group

if (( RUN_DOWNLOAD == 1 )); then
  echo
  echo "  --- Test de descarga real (lento, requiere red) ---"
  reset_state
  run_t "real: descarga video CC yt-dlp" t_real_download
fi

# Limpieza final
rm -rf "$ISOLATED_HOME"

echo
if print_summary; then
  echo "  ✅ Todos los tests pasaron"
  exit 0
else
  echo "  ❌ Hay tests fallados"
  exit "$TESTS_FAILED"
fi