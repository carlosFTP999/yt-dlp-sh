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

# 23. Preflight: aborta si usuario rechaza
t_preflight_abort() {
  OUTDIR="$(mktemp -d)"
  # Confirm "n" -> die -> exit 1
  ( preflight_checks <<< "n" ) >/dev/null 2>&1
  local rc=$?
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