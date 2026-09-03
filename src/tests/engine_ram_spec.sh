# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329  # falsos positivos del DSL
#
# Aquí vivía el bug de mawk: al no poder abrir un fichero de /proc abortaba, se
# saltaba el END y devolvía VACÍO en vez de un proceso de menos.

Describe 'is_engine_proc()'
	Include src/scripts/engine-ram.sh

	# "containerd" NO contiene "docker": filtrar solo por *docker* lo dejaría
	# fuera. Y un proceso del usuario que se llame así entra — es el precio de
	# filtrar por nombre, y está asumido.
	Parameters
		dockerd          success "el demonio"
		containerd       success "no lleva 'docker' en el nombre"
		docker-proxy     success "el proxy de puertos"
		containerd-shim  success "truncado a 15 chars en /proc"
		mi-dockerd-falso success "falso positivo asumido"
		nginx            failure ""
		postgres         failure ""
		""               failure "cadena vacía"
	End

	It "$1 $3"
		When call is_engine_proc "$1"
		The status should be "$2"
	End
End

Describe 'mb()'
	Include src/scripts/engine-ram.sh

	setup() { PAGE=4096; }
	BeforeEach 'setup'

	Describe 'convierte páginas a MB con aritmética entera'
		Parameters
			256  1.0  "256 páginas de 4k = 1 MB"
			2560 10.0 ""
			0    0.0  ""
			128  0.5  "media página larga: una decimal"
			1    0.0  "una página redondea a 0.0, no revienta"
		End

		It "$1 -> $2 $3"
			When call mb "$1"
			The output should equal "$2"
		End
	End

	# printf "%.1f" respeta el locale: en es_ES daría "1,0" y chocaría con el punto
	# que usa jq. Sin un locale de coma generado el test pasaría EN VACÍO.
	comma_locale() { locale -a 2>/dev/null | grep -qiE '^(es_ES|de_DE|fr_FR)\.(utf-?8)$'; }
	no_comma_locale() { ! comma_locale; }
	pick_comma_locale() { locale -a 2>/dev/null | grep -iE '^(es_ES|de_DE|fr_FR)\.(utf-?8)$' | head -1; }

	It 'usa punto decimal sea cual sea el locale'
		Skip if "sin locale de coma decimal" no_comma_locale
		convert() { LC_ALL=$(pick_comma_locale) mb 2560; }
		When call convert
		The output should equal "10.0"
	End
End

Describe 'engine_ram()'
	Include src/scripts/engine-ram.sh

	# /proc/PID/statm: size resident shared text lib data dt -> el 2º es resident
	fake_proc() {
		mkdir -p "$PROC_ROOT/$1"
		printf '%s\n' "$2" >"$PROC_ROOT/$1/comm"
		printf '9999 %s 0 0 0 0 0\n' "$3" >"$PROC_ROOT/$1/statm"
	}

	setup() {
		TMP=$(mktemp -d)
		PROC_ROOT="$TMP/proc"
		mkdir -p "$PROC_ROOT"
		fake_proc 100 dockerd       2560   #  10 MB
		fake_proc 200 containerd    1280   #   5 MB
		fake_proc 300 nginx        25600   # 100 MB, NO debe contar
		fake_proc 400 docker-proxy   256   #   1 MB
	}
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	It 'suma solo los procesos del motor y deja fuera nginx'
		When call engine_ram 0
		The output should equal "16"
	End

	It '--list detalla los procesos del motor y solo esos'
		When call engine_ram 1
		The output should include "dockerd"
		The output should include "containerd"
		The output should include "docker-proxy"
		The output should not include "nginx"
		The output should include "16.0 MB"
	End

	# El bug original: awk abortaba al no poder abrir un fichero, se saltaba el
	# END y devolvía VACÍO en vez de un proceso de menos.
	It 'aguanta un /proc que cambia bajo los pies'
		half_dead() {
			mkdir -p "$PROC_ROOT/500"; printf 'dockerd\n' >"$PROC_ROOT/500/comm"  # sin statm
			mkdir -p "$PROC_ROOT/600"                                             # sin nada
			engine_ram 0
		}
		When call half_dead
		The output should equal "16"
	End

	It 'sin ningún proceso del motor devuelve 0, no cadena vacía'
		no_engine() { PROC_ROOT="$TMP/vacio"; mkdir -p "$PROC_ROOT"; engine_ram 0; }
		When call no_engine
		The output should equal "0"
	End
End
