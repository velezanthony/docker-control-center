# shellcheck shell=bash
#
# El DSL dispara seis falsos positivos INHERENTES en shellcheck: las filas de
# `Parameters` son datos, `When call` invoca indirecto, y `setup()` escribe lo
# que otro bloque lee. SC2016: los `bash -c '...'` llevan $1 a propósito.
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2329,SC2016
#
# Tests de src/scripts/container-cpu.sh. Al reloj se le pone un doble EN UN
# FICHERO: `now_usec` se invoca dentro de $( ), o sea en una subshell, y una
# variable no sobreviviría.

# `Parameters` aplica a TODO el Describe que lo contiene, no al `It` siguiente:
# por eso cada tabla vive en su propio Describe anidado.
Describe 'pct()'
	Include src/scripts/container-cpu.sh

	Describe 'convierte deltas en % de UN core'
		Parameters
			1000000 1000000 100.0% "1 s de CPU en 1 s de reloj"
			2500000 1000000 250.0% "2,5 núcleos"
			0       1000000 0.0%   ""
			500000  1000000 50.0%  ""
			12345   1000000 1.2%   "redondea hacia abajo"
		End

		It "$1/$2 -> $3 $4"
			When call pct "$1" "$2"
			The output should equal "$3"
		End
	End

	# Un contenedor que se reinicia pone el contador a cero: el delta sale
	# negativo. Y sin tiempo transcurrido no se puede dividir.
	Describe 'no devuelve disparates'
		Parameters
			-9000000 1000000 "delta negativo se recorta a 0"
			1000000  0       "sin tiempo, en vez de dividir por cero"
		End

		It "$3"
			When call pct "$1" "$2"
			The output should equal "0.0%"
		End
	End

	# Sin un locale de coma decimal generado, este test pasaría EN VACÍO: bash
	# avisa por stderr y el formateo cae a C, que ya usa punto.
	comma_locale() { locale -a 2>/dev/null | grep -qiE '^(es_ES|de_DE|fr_FR)\.(utf-?8)$'; }
	no_comma_locale() { ! comma_locale; }
	pick_comma_locale() { locale -a 2>/dev/null | grep -iE '^(es_ES|de_DE|fr_FR)\.(utf-?8)$' | head -1; }

	It 'usa punto decimal, no el del locale'
		Skip if "sin locale de coma decimal" no_comma_locale
		convert() { LC_ALL=$(pick_comma_locale) pct 1500000 1000000; }
		When call convert
		The output should equal "150.0%"
	End
End

Describe 'cpu_usec()'
	Include src/scripts/container-cpu.sh

	setup()   { TMP=$(mktemp -d); CGROUP_ROOT="$TMP"; }
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	It 'lee el contador por la ruta de systemd'
		read_systemd() {
			mkdir -p "$CGROUP_ROOT/system.slice/docker-aaa.scope"
			printf 'usage_usec 12345\n' >"$CGROUP_ROOT/system.slice/docker-aaa.scope/cpu.stat"
			cpu_usec aaa
		}
		When call read_systemd
		The output should equal "12345"
	End

	It 'lee el contador por la ruta de cgroupfs, sin systemd'
		read_cgroupfs() {
			mkdir -p "$CGROUP_ROOT/docker/bbb"
			printf 'usage_usec 999\n' >"$CGROUP_ROOT/docker/bbb/cpu.stat"
			cpu_usec bbb
		}
		When call read_cgroupfs
		The output should equal "999"
	End

	It 'un id sin cgroup devuelve error'
		When call cpu_usec no-existe
		The status should be failure
		The output should be blank
	End
End

Describe 'container_cpu()'
	Include src/scripts/container-cpu.sh

	setup()   { TMP=$(mktemp -d); CGROUP_ROOT="$TMP"; }
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	write_cgroup() {
		mkdir -p "$CGROUP_ROOT/system.slice/docker-$1.scope"
		printf 'usage_usec %s\nuser_usec %s\n' "$2" "$2" \
			>"$CGROUP_ROOT/system.slice/docker-$1.scope/cpu.stat"
	}

	It 'mide entre dos muestras reales'
		measure() {
			printf '0' >"$TMP/clock"
			now_usec() {
				local n; n=$(<"$TMP/clock"); printf '%s' "$n"
				printf '%s' "$(( n + 1000000 ))" >"$TMP/clock"
			}
			docker() { printf 'quemado\tAAA\nocioso\tBBB\n'; }
			sleep()  { write_cgroup AAA 1000000; }   # entre muestras, AAA gasta 1 s
			write_cgroup AAA 0; write_cgroup BBB 0
			container_cpu
		}
		When call measure
		The line 1 of output should equal "$(printf 'quemado\t100.0%%')"
		The line 2 of output should equal "$(printf 'ocioso\t0.0%%')"
	End

	It 'sin contenedores vivos no dice nada'
		no_containers() { docker() { printf ''; }; container_cpu; }
		When call no_containers
		The output should be blank
	End

	It 'si docker no responde, devuelve error'
		docker_down() { docker() { return 1; }; container_cpu; }
		When call docker_down
		The status should be failure
		The output should be blank
	End

	# Camino de degradación (cgroup v1 o sin permisos): antes reventaba con
	# "first: variable sin asignar" por un `declare -A first` sin el =().
	It 'sin cgroups legibles: ni salida ni ruido en pantalla'
		degraded() { docker() { printf 'x\tSIN-CGROUP\n'; }; container_cpu 2>&1; }
		When call degraded
		The output should be blank
	End
End

# EPOCHREALTIME es de bash 5.0 y el proyecto declara bash 4+. En bash 4 la
# variable no existe y, con `set -u`, leerla aborta el script entero.
#
# Las dos ramas se piden en un bash NUEVO: sustituir now_usec aquí y
# preguntarle al doble no demostraría nada.
Describe 'now_usec()'
	with_epoch()    { bash -c '. "$1"; now_usec' _ "$REPO_ROOT/src/scripts/container-cpu.sh"; }
	without_epoch() { EPOCHREALTIME="" bash -c '. "$1"; now_usec' _ "$REPO_ROOT/src/scripts/container-cpu.sh"; }

	It 'con EPOCHREALTIME devuelve microsegundos'
		is_micros() { local n; n=$(with_epoch); [ "${#n}" -ge 16 ]; }
		When call is_micros
		The status should be success
	End

	# Las dos escalas tienen que ser la misma o los porcentajes saldrían
	# disparados en bash 4.
	It 'sin él (bash 4) devuelve la MISMA escala'
		same_scale() {
			local a b; a=$(with_epoch); b=$(without_epoch)
			[ "${#a}" -ge 16 ] && [ "${#a}" -eq "${#b}" ]
		}
		When call same_scale
		The status should be success
	End
End
