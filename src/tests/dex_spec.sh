# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2329  # falsos positivos del DSL
#
# Tests de dex.sh.

Describe 'best_match()'
	Include src/scripts/dex.sh

	# Nombres como los que genera compose: proyecto + servicio + índice.
	LIST='miproyecto_web-1
miproyecto_db-1
miproyecto_worker-1
otro_web-1'

	best()  { best_match "$1" <<<"$LIST" | cut -f1; }
	score() { best_match "$1" <<<"$LIST" | cut -f2; }

	# La clave del algoritmo: compose prefija con el proyecto, así que comparar
	# desde el principio no sirve. "web" tiene que encontrar "…_web-1".
	Describe 'encuentra la coincidencia DENTRO del nombre'
		Parameters
			web           miproyecto_web-1     "una palabra que va en medio"
			worker        miproyecto_worker-1  "sufijo largo"
			miproyecto_db miproyecto_db-1      "prefijo completo"
		End

		It "$3"
			When call best "$1"
			The output should equal "$2"
		End
	End

	Describe 'premia la coincidencia MÁS LARGA'
		Parameters
			miproyecto_worker 17
			web               3
		End

		It "'$1' puntúa $2"
			When call score "$1"
			The output should equal "$2"
		End
	End

	Describe 'ignora mayúsculas'
		Parameters
			WEB    miproyecto_web-1
			WoRkEr miproyecto_worker-1
		End

		It "'$1' encuentra $2"
			When call best "$1"
			The output should equal "$2"
		End
	End

	# Sugerir con 2 letras acierta por azar y manda al usuario al contenedor
	# equivocado. Por debajo de 3 caracteres, no adivina.
	Describe 'exige al menos 3 caracteres'
		Parameters
			we
			w
			""
		End

		It "'$1' no da sugerencia"
			When call best "$1"
			The output should be blank
		End
	End

	Describe 'no inventa cuando no hay nada parecido'
		It 'sin ninguna coincidencia, no sugiere'
			When call best zzzzz
			The output should be blank
		End

		It 'con la lista vacía tampoco'
			empty_list() { best_match web <<<'' | cut -f1; }
			When call empty_list
			The output should be blank
		End
	End

	# El caso de uso real: te comes una letra o escribes solo un trozo.
	Describe 'con un typo real, que es para lo que existe'
		Parameters
			miproyecto_wb-1 miproyecto_web-1 "falta una letra"
			proyecto_web    miproyecto_web-1 "falta el prefijo"
			web-1           miproyecto_web-1 "solo el sufijo"
		End

		It "$3"
			When call best "$1"
			The output should equal "$2"
		End
	End

	It 'con empate se queda con el primero'
		tie() { best_match web <<<$'aaa_web\nbbb_web' | cut -f1; }
		When call tie
		The output should equal "aaa_web"
	End
End

# Sobre el host de fixtures.sh. dex_main() llama a `exit`: con `When call`
# ShellSpec aborta el ejemplo, así que va con `When run` (que sí mide cobertura).
Describe 'dex.sh sobre un host de mentira'
	Include src/scripts/dex.sh

	setup() {
		TMP=$(mktemp -d)
		LOG="$TMP/docker.log"
		: >"$LOG"
		fixture_dex_docker "$LOG"
	}
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	calls() { [ -s "$LOG" ] && printf '%s' "$(<"$LOG")"; return 0; }
	plain()  { sed -E 's/\x1b\[[0-9;]*m//g'; }

	Describe 'print_available()'
		listing() { print_available 2>&1 | plain; }

		It 'agrupa los contenedores por stack'
			When call listing
			The output should include "▸ demo"
			The output should include "▸ otro"
		End

		It 'los que no pertenecen a ningún stack tienen su propio grupo'
			When call listing
			The output should include "no stack"
			The output should include "suelto-1"
		End

		It 'cuenta cuántos servicios hay en cada grupo'
			When call listing
			The output should include "(1 service)"
		End

		It 'muestra el servicio junto al nombre del contenedor'
			When call listing
			The output should include "demo_web-1"
			The output should include "web"
		End

		# Una lista vacía con cabecera parece un fallo. Si no hay nada levantado,
		# se dice, y se dice cómo levantarlo.
		It 'sin nada corriendo lo explica y sugiere qué hacer'
			nothing() { docker() { return 0; }; print_available 2>&1 | plain; }
			When call nothing
			The output should include "No containers are running"
			The output should include "docker compose up -d"
		End
	End

	Describe 'print_best()'
		It 'destaca el candidato con su servicio y su stack'
			best() { print_best demo_web-1 2>&1 | plain; }
			When call best
			The output should include "CLOSEST MATCH"
			The output should include "demo_web-1"
			The output should include "demo"
		End
	End

	Describe 'dex_main()'
		It 'sin nombre no adivina: dice el uso y sale con 2'
			When run dex_main
			The status should eq 2
			The stderr should include "Missing container name"
			The stderr should include "Usage: dex"
		End

		It 'y de paso te enseña lo que SÍ puedes elegir'
			When run dex_main
			The status should eq 2
			The stderr should include "demo_web-1"
			The stderr should include "AVAILABLE CONTAINERS"
		End

		# El motivo de existir del módulo: te comes una letra y no te manda a leer
		# `docker ps`, te dice cuál querías.
		It 'con un typo sugiere el más parecido y sale con 1'
			When run dex_main demo_wb-1
			The status should eq 1
			The stderr should include "CLOSEST MATCH"
			The stderr should include "demo_web-1"
		End

		It 'con un nombre sin parecido alguno no inventa una sugerencia'
			When run dex_main zzzzzzz
			The status should eq 1
			The stderr should not include "CLOSEST MATCH"
			The stderr should include "AVAILABLE CONTAINERS"
		End

		It 'si NO hay nada corriendo lo dice en vez de listar el vacío'
			empty_host() { docker() { return 0; }; dex_main loquesea; }
			When run empty_host
			The status should eq 1
			The stderr should include "NOTHING is running"
		End

		It 'con un nombre exacto ejecuta el comando DENTRO del contenedor'
			When run dex_main demo_web-1 ls -la /app
			The status should be success
			The result of function calls should include "exec -i demo_web-1 ls -la /app"
		End

		# Sin comando, shell interactiva: bash si la hay, y si no sh. Muchas
		# imágenes de producción (alpine, distroless) no traen bash.
		It 'sin comando abre una shell, con bash como preferencia'
			When run dex_main demo_web-1
			The result of function calls should include "exec -i demo_web-1 sh -c"
			The stderr should include "Opening a shell"
		End

		# -t forzado dentro de un pipe o de CI hace que docker aborte con "cannot
		# attach stdin to a TTY". Aquí no hay terminal, así que NO debe aparecer.
		It 'sin terminal NO pide pseudo-TTY'
			When run dex_main demo_web-1 ls
			The result of function calls should include "exec -i demo_web-1"
			The result of function calls should not include "exec -i -t"
		End
	End
End
