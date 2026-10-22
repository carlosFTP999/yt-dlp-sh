#!/usr/bin/env bash
# test-helpers.sh — Pure bash assertion helpers (cero deps)
# Usado por tests/smoke-test.sh. No requiere frameworks externos.
#
# Uso:
#   source tests/lib/test-helpers.sh
#   run_test "nombre" test_function
#   assert_eq "$expected" "$actual"

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_TEST=""

# Ejecuta una función de test y reporta PASS/FAIL
# Uso: run_test "nombre descriptivo" nombre_funcion
run_test() {
  local name="$1"
  local fn="$2"
  CURRENT_TEST="$name"
  TESTS_RUN=$((TESTS_RUN + 1))
  printf "  [....] %-45s " "$name"
  if "$fn" >/dev/null 2>&1; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "\r  [PASS] %-45s\n" "$name"
    return 0
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "\r  [FAIL] %-45s\n" "$name"
    return 1
  fi
}

# Assert: dos strings son iguales
# Uso: assert_eq "$esperado" "$real"
assert_eq() {
  local expected="$1"
  local actual="$2"
  if [[ "$actual" != "$expected" ]]; then
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    return 1
  fi
  return 0
}

# Assert: string contiene substring
# Uso: assert_contains "$haystack" "$needle"
assert_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "    expected to contain: '$needle'"
    echo "    got: '$haystack'"
    return 1
  fi
  return 0
}

# Assert: string NO contiene substring
# Uso: assert_not_contains "$haystack" "$needle"
assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "    expected NOT to contain: '$needle'"
    echo "    got: '$haystack'"
    return 1
  fi
  return 0
}

# Assert: comando retorna exit code específico
# Uso: assert_exit 0 command args...
assert_exit() {
  local expected="$1"
  shift
  "$@" >/dev/null 2>&1
  local actual=$?
  if [[ "$actual" != "$expected" ]]; then
    echo "    expected exit: $expected"
    echo "    actual exit:   $actual"
    return 1
  fi
  return 0
}

# Assert: variable no vacía
# Uso: assert_nonempty "$valor"
assert_nonempty() {
  local val="$1"
  if [[ -z "$val" ]]; then
    echo "    expected non-empty value, got empty"
    return 1
  fi
  return 0
}

# Assert: archivo existe
# Uso: assert_file_exists "$path"
assert_file_exists() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "    expected file to exist: $path"
    return 1
  fi
  return 0
}

# Assert: array tiene N elementos
# Uso: assert_array_size 3 "${ARRAY[@]}"
assert_array_size() {
  local expected="$1"
  shift
  local actual=$#
  if [[ "$actual" != "$expected" ]]; then
    echo "    expected array size: $expected"
    echo "    actual array size:   $actual"
    return 1
  fi
  return 0
}

# Imprime resumen final con colores (si TTY)
# Retorna 0 si todos pasaron, 1 si hay fallos
print_summary() {
  local width=48
  local failed_color=""
  local pass_color=""
  local reset=""
  if [[ -t 1 ]]; then
    pass_color="\033[32m"
    failed_color="\033[31m"
    reset="\033[0m"
  fi

  echo
  printf '%*s\n' "$width" "" | tr ' ' '═'
  printf '  Total:   %d\n' "$TESTS_RUN"
  printf '  %sPassed:  %d%s\n' "$pass_color" "$TESTS_PASSED" "$reset"
  if (( TESTS_FAILED > 0 )); then
    printf '  %sFailed:  %d%s\n' "$failed_color" "$TESTS_FAILED" "$reset"
  else
    printf '  Failed:  %d\n' "$TESTS_FAILED"
  fi
  printf '%*s\n' "$width" "" | tr ' ' '═'

  (( TESTS_FAILED == 0 ))
}