# shellcheck shell=bash
# shellcheck disable=SC2154  # SHELLSPEC_PROJECT_ROOT lo exporta ShellSpec
# spec_helper.sh — lo que ShellSpec carga antes de cualquier specfile.

# LC_ALL no se toca: en locale C, ${#s} cuenta bytes y rompería pad().
export DCC_LANG=en
export DCC_CONFIG=/dev/null
export REPO_ROOT="$SHELLSPEC_PROJECT_ROOT"   # no es DCC_ROOT, que vale src/ tras un Include

# shellcheck source=src/tests/fixtures.sh
. "$SHELLSPEC_PROJECT_ROOT/src/tests/fixtures.sh"

# CERROJO: un spec que olvide su doble hablaría con el docker de la máquina.
docker() {
	printf 'spec_helper: docker SIN doblar: %s (dóblalo en un BeforeEach)\n' "$*" >&2
	return 127
}

spec_helper_precheck() { minimum_version "0.28.1"; }
spec_helper_loaded()   { :; }
spec_helper_configure() { :; }
