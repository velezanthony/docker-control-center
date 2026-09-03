# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329  # falsos positivos del DSL
#
# Datos inyectados por PSDATA / VOLMAP / CPU, cero docker.
# REGLA: $SEP (\x1f) no puede viajar en los argumentos de `When` — aborta la
# suite con código 102 aunque los tests pasen. Siempre en una función auxiliar.

Describe 'fmt_status()'
	Include src/scripts/dashboard.sh

	status_of() { fmt_status <<<"$1" | cut -f1; }
	health_of() { fmt_status <<<"$1" | cut -f2; }

	# Las tres con artículo van ANTES que la abreviatura genérica: si no,
	# " minutes?" se come el " minute" de "About a minute" y queda "About am".
	Describe 'abrevia las duraciones de Go'
		Parameters
			"Up About a minute"            "up ~1m"
			"Up About an hour"             "up ~1h"
			"Up Less than a second"        "up <1s"
			"Up 15 hours"                  "up 15h"
			"Up 1 hour"                    "up 1h"
			"Up 7 days"                    "up 7d"
			"Up 2 years"                   "up 2y"
			"Exited (0) 3 weeks ago"       "exit 0 3w"
			"Exited (137) 2 months ago"    "exit 137 2mo"
			"Created"                      "created"
			"Restarting (1) 5 seconds ago" "restarting 1 5s"
		End

		It "'$1' -> '$2'"
			When call status_of "$1"
			The output should equal "$2"
		End
	End

	Describe 'extrae la marca de salud en el segundo campo'
		Parameters
			"Up 2 hours (healthy)"          "+"
			"Up 2 hours (unhealthy)"        "!"
			"Up 2 hours (health: starting)" "~"
			"Up 2 hours"                    ""
		End

		It "'$1' -> '$2'"
			When call health_of "$1"
			The output should equal "$2"
		End
	End

	It 'la salud no ensucia el estado'
		When call status_of "Up 2 hours (healthy)"
		The output should equal "up 2h"
	End
End

Describe 'fmt_ports()'
	Include src/scripts/dashboard.sh

	Parameters
		"0.0.0.0:8085->8080/tcp, [::]:8085->8080/tcp" "8085→8080"     "IPv4 e IPv6 del mismo puerto, una vez"
		"0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp"    "80→80 443→443" ""
		"6379/tcp"                                    ""              "expuesto pero NO publicado"
		""                                            ""              ""
	End

	It "'$1' -> '$2' $3"
		When call fmt_ports "$1"
		The output should equal "$2"
	End
End

Describe 'exit_code()'
	Include src/scripts/dashboard.sh

	Parameters
		"Exited (137) 2 hours ago" "137"
		"Exited (0) 1 day ago"     "0"
		"Up 3 hours"               ""     # un contenedor vivo no tiene código
	End

	It "'$1' -> '$2'"
		When call exit_code "$1"
		The output should equal "$2"
	End
End

# La tabla que decide qué pinta cada `dcc ps` / `dcc status` / `dcc images`.
# Fuente ÚNICA: la consulta el despachador, así que un cambio aquí se propaga a
# todas las vistas sin que nadie lo anuncie.
Describe 'dcc_view_sections()'
	Include src/scripts/dashboard.sh

	Describe 'cada vista pide sus secciones'
		Parameters
			dash    "summary,alerts,stacks,volumes,images,disk" "el panel entero"
			status  "summary,disk"                             "resumen ejecutivo"
			ps      "stacks"                                   ""
			psa     "stacks"                                   "alias de ps, MISMA vista"
			images  "images"                                   ""
			volumes "volumes"                                  ""
		End

		It "$1 -> $2 $3"
			When call dcc_view_sections "$1"
			The output should equal "$2"
		End
	End

	# Devolver != 0 es lo que permite al despachador seguir probando (¿operación?
	# ¿módulo?) sin mantener una segunda lista de nombres en paralelo.
	It 'lo que NO es una vista falla, para que quien pregunta siga buscando'
		When call dcc_view_sections stack-start
		The status should be failure
		The output should be blank
	End
End

Describe 'want()'
	Include src/scripts/dashboard.sh

	setup() { ONLY="summary,disk"; }
	BeforeEach 'setup'

	Parameters
		summary success ""
		disk    success ""
		stacks  failure ""
		sum     failure "no casa por subcadena"
	End

	It "'$1' -> $2 $3"
		When call want "$1"
		The status should be "$2"
	End
End

# En el fichero único TODOS los módulos se cargan en CADA invocación, así que un
# `tput` a nivel de módulo lo pagaba hasta `dcc version`, que no pinta una regla
# en su vida. Se calcula la primera vez que hace falta y se queda cacheado.
Describe 'la anchura del terminal es perezosa'
	Include src/scripts/dashboard.sh

	setup()   { WTMP=$(mktemp -d); }
	cleanup() { rm -rf "$WTMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	It 'no se calcula al cargar el módulo'
		width_at_load() { printf '%s' "$W"; }
		When call width_at_load
		The output should be blank
	End

	# El registro va a FICHERO: `W=$(tput cols)` corre en subshell y un contador en
	# variable volvería siempre a cero — el test pasaría aunque no cacheara nada.
	It 'las siguientes ya no preguntan al terminal'
		asks_once() {
			: >"$WTMP/tput.log"
			tput() { printf 'x' >>"$WTMP/tput.log"; printf '80'; }
			rule >/dev/null; rule >/dev/null; rule >/dev/null
			printf '%s' "$(<"$WTMP/tput.log")"
		}
		When call asks_once
		The output should equal "x"
	End

	Describe 'y sigue acotada entre 60 y 110'
		Parameters
			"200" "110"
			"40"  "60"
			"90"  "90"
		End

		# `cols` es local de clamped(), pero bash tiene ámbito DINÁMICO: sigue vivo
		# cuando ensure_width llama al doble. Dentro de tput(), $1 sería "cols".
		It "un terminal de $1 columnas da $2"
			clamped() { local cols=$1; tput() { printf '%s' "$cols"; }; rule >/dev/null; printf '%s' "$W"; }
			When call clamped "$1"
			The output should equal "$2"
		End
	End
End

Describe 'parse_args()'
	Include src/scripts/dashboard.sh

	# `*) shift` se los tragaba: `--onl stacks` daba el panel entero y nadie se
	# enteraba de que el filtro no se había aplicado.
	Describe 'lo que no entiende NO lo ignora'
		Parameters
			--onl        "un typo del propio flag"
			--only-stack "un flag parecido que no existe"
			basura       "una palabra suelta"
		End

		It "rechaza $1: $2"
			When call parse_args "$1"
			The status should eq 2
			The stderr should include "$1"
		End
	End

	# `--only` sin valor moría con "unbound variable" de set -u: el mensaje lo
	# daba bash, no la herramienta.
	It 'un --only sin valor lo dice la herramienta, no el intérprete'
		When call parse_args --only
		The status should eq 2
		The stderr should include "--only"
		The stderr should not include "unbound"
	End

	# Sin argumentos pasan las seis secciones enteras y salen intactas: es lo que
	# vigila que no vuelva una sustitución de subcadena sobre ONLY.
	It 'sin argumentos pide todas las secciones'
		When call parse_args
		The variable ONLY should eq "$ALL_SECTIONS"
	End

	It 'también acepta la forma --only=X'
		When call parse_args --only=disk
		The variable ONLY should eq "disk"
	End

	# /system/df y docker stats son las dos llamadas que dominan el tiempo del
	# dashboard: cada sección declara cuál necesita.
	It 'la vista de stacks necesita la CPU pero no el disco'
		request() { FAST=0; parse_args --only stacks; }
		When call request
		The variable NEEDS_DF    should eq "0"
		The variable NEEDS_STATS should eq "1"
	End

	It 'en modo FAST se salta docker stats'
		request() { FAST=1; parse_args --only stacks; }
		When call request
		The variable NEEDS_STATS should eq "0"
	End

	It 'la vista de disco necesita /system/df pero no la CPU'
		request() { FAST=0; parse_args --only disk; }
		When call request
		The variable NEEDS_DF    should eq "1"
		The variable NEEDS_STATS should eq "0"
	End
End

# Antes esto era un `docker ps --filter volume=X` por CADA volumen: 7 volúmenes
# eran ~940 ms y crecía con el número. Ahora es un solo inspect y esta función
# busca en memoria — por eso se puede testear.
Describe 'users_of_volume()'
	Include src/scripts/dashboard.sh

	setup() {
		VOLMAP='/web-1 datos cache
/worker-1 datos
/db-1 pgdata
/suelto-1'
	}
	BeforeEach 'setup'

	Parameters
		datos  "web-1,worker-1" "dos contenedores comparten volumen"
		pgdata "db-1"           ""
		cache  "web-1"          "segundo volumen del mismo contenedor"
		nadie  ""               "volumen huérfano"
		web-1  ""               "no confunde el NOMBRE del contenedor con un volumen"
	End

	It "'$1' -> '$2' $3"
		When call users_of_volume "$1"
		The output should equal "$2"
	End

	It 'no casa por prefijo'
		prefix_case() {
			VOLMAP='/a-1 datos-produccion
/b-1 datos'
			users_of_volume datos
		}
		When call prefix_case
		The output should equal "b-1"
	End
End

# Test de caracterización: se escribió ANTES de partir render_stacks, para que el
# refactor tuviera que demostrar que no cambia la salida.
Describe 'render_stacks()'
	Include src/scripts/dashboard.sh

	setup() {
		PSDATA=$(printf '%s\n' \
			$'web-1\trunning\tUp 2 hours (healthy)\t0.0.0.0:80->80/tcp\tnginx\tproyecto\tweb' \
			$'db-1\texited\tExited (0) 3 days ago\t\tpostgres:16\tproyecto\tdb' \
			$'roto-1\texited\tExited (3) 1 hour ago\t\talpine\tproyecto\troto' \
			$'suelto-1\trunning\tUp 5 minutes\t\tbusybox\t\t')
	}
	BeforeEach 'setup'

	render()     { declare -A CPU=([web-1]="12.5%"); render_stacks 2>/dev/null | sed -E 's/\x1b\[[0-9;]*m//g'; }
	render_raw() { declare -A CPU=([web-1]="12.5%"); render_stacks 2>/dev/null; }

	It 'agrupa por stack y cuenta los vivos'
		When call render
		The output should include "1/3 up"    # proyecto: 1 vivo de 3
		The output should include "1/1 up"    # el contenedor suelto, en su grupo
		The output should include "(loose)"
		The output should include "▸ web "    # usa el nombre de servicio
		The output should include "suelto-1"  # y cae al del contenedor si no hay
	End

	# El bug de los campos desplazados: en cuanto un contenedor no publicaba
	# puertos, la columna de imagen mostraba el proyecto.
	It 'los contenedores sin puertos muestran su IMAGEN, no el proyecto'
		When call render
		The output should include "postgres:16"
		The output should include "alpine"
	End

	It 'pinta la CPU del vivo y una raya en el parado'
		When call render
		The output should include "12.5%"
		The output should include "—"
	End

	It 'el que murió con error va en ROJO'
		When call render_raw
		The output should include "${RD}▹"
	End
End

Describe 'las piezas en que se partió render_stacks'
	Include src/scripts/dashboard.sh

	# $SEP no cruza la frontera de `When`: se usa aquí dentro. (Ver cabecera.)
	field() { sed -E 's/\x1b\[[0-9;]*m//g' | cut -d"$SEP" -f"$1"; }

	Describe 'stack_badge()'
		Parameters
			3 3 "●" "3/3 up"      "todos arriba"
			0 4 "○" "0/4 stopped" "todos parados"
			1 4 "◐" "1/4 up"      "estado mixto"
		End

		It "$5: icono"
			icon() { stack_badge "$1" "$2" | field 1; }
			When call icon "$1" "$2"
			The output should equal "$3"
		End

		It "$5: texto"
			badge_text() { stack_badge "$1" "$2" | field 2; }
			When call badge_text "$1" "$2"
			The output should equal "$4"
		End
	End

	Describe 'cpu_cell()'
		Parameters
			running vivo    "42.7%" ""
			running dormido "0.0%"  "redondea a una decimal"
			exited  vivo    "—"     "un parado no gasta CPU"
			running ausente "—"     "sin muestra en CPU[]"
		End

		It "$1/$2 -> $3 $4"
			cell() {
				declare -A CPU=([vivo]="42.7%" [quemado]="180%" [dormido]="0.04%")
				cpu_cell "$1" "$2" | field 2
			}
			When call cell "$1" "$2"
			The output should equal "$3"
		End
	End

	# El umbral rojo es 100% (un core entero), no 90.
	Describe 'cpu_cell() colorea por gravedad'
		It '180% (más de un core) se pinta en ROJO'
			cell() { declare -A CPU=([quemado]="180%"); cpu_cell running quemado; }
			When call cell
			The output should include "$RD"
		End

		It '42.7% se pinta en AMARILLO'
			cell() { declare -A CPU=([vivo]="42.7%"); cpu_cell running vivo; }
			When call cell
			The output should include "$YE"
		End
	End

	Describe 'severity_cell()'
		Parameters
			running ""  "▸" "vivo: triángulo lleno"
			exited  "0" "▹" "parado: triángulo hueco"
		End

		It "$4"
			cell() { severity_cell "$1" "$2" | field 1; }
			When call cell "$1" "$2"
			The output should equal "$3"
		End
	End

	Describe 'severity_cell() colorea por código de salida'
		Parameters
			0   "$D"  "exit 0 en gris"
			137 "$YE" "137 (SIGKILL) en amarillo"
			3   "$RD" "un error de verdad en rojo"
		End

		It "$3"
			When call severity_cell exited "$1"
			The output should include "$2"
		End
	End

	# La rama que faltaba: ni vivo ni con código de salida. Es el estado real de
	# un contenedor "Created", que nunca llegó a arrancar y por tanto nunca
	# salió con nada. Sin este ejemplo, el `else` no lo pisaba nadie.
	Describe 'severity_cell() sin código de salida'
		It 'un contenedor Created va en gris, no en rojo'
			When call severity_cell created ""
			The output should include "$D"
			The output should not include "$RD"
		End
	End

	Describe 'health_mark()'
		Parameters
			"+" "✓"
			"!" "✗"
			"~" "◌"
			""  " "   # un espacio, para no descuadrar la columna
		End

		It "'$1' -> '$2'"
			mark() { health_mark "$1" | sed -E 's/\x1b\[[0-9;]*m//g'; }
			When call mark "$1"
			The output should equal "$2"
		End
	End
End

# Las secciones que PINTAN. No tocan docker: leen los globales que collect_data
# habría rellenado, así que se les inyectan a mano. Es la misma frontera que hace
# testeable render_stacks, aplicada al resto del panel.
Describe 'las secciones del panel'
	Include src/scripts/dashboard.sh

	plain() { sed -E 's/\x1b\[[0-9;]*m//g'; }

	Describe 'render_header()'
		setup() {
			CTX=default; VER=29.6.2; NCPU=8; DRV=overlayfs; RAM_MB=412
			N_STACKS=3; N_UP=5; N_ALL=9; CPU_HOST=""
			M=()
		}
		BeforeEach 'setup'

		It 'anuncia contexto, motor, núcleos y RAM del motor'
			header() { render_header | plain; }
			When call header
			The output should include "default"
			The output should include "29.6.2"
			The output should include "8 CPU"
			The output should include "412 MB"
		End

		It 'cuenta stacks y contenedores vivos sobre el total'
			header() { render_header | plain; }
			When call header
			The output should include "3 stacks"
			The output should include "5/9"
		End

		# Los dos datos caros del panel. Si no están, la cabecera no puede inventar
		# un cero: se calla, que es distinto de decir "0%".
		It 'sin CPU ni tamaños NO los menciona'
			header() { render_header | plain; }
			When call header
			The output should not include "% "
			The output should not include "on disk"
		End

		It 'con CPU y tamaños sí los pinta'
			header() { CPU_HOST=12.5; M=([disk]="21.4 GB"); render_header | plain; }
			When call header
			The output should include "12.5%"
			The output should include "21.4 GB"
		End
	End

	# La sección que le dice al usuario qué puede borrar. Cada fila solo aparece si
	# hay algo que enseñar: una tabla con ceros invita a limpiar lo que ya está
	# limpio. Y cada una lleva el comando exacto que la resuelve.
	Describe 'render_summary()'
		setup() {
			DCC_CMD="make run"
			M=(
				[disk]="21.4 GB"  [trash]="6.1 GB"
				[cacheRaw]=1 [cacheSz]="4.2 GB" [cacheN]=12
				[stopRaw]=1  [stopSz]="900 MB"  [stopN]=3
				[imgRaw]=1   [imgSz]="1 GB"     [imgNames]="alpine, busybox"
				[volN]=2     [volSz]="30 MB"
			)
		}
		BeforeEach 'setup'

		It 'lista las cuatro fuentes de basura con su tamaño'
			the_summary() { render_summary | plain; }
			When call the_summary
			The output should include "4.2 GB"
			The output should include "900 MB"
			The output should include "alpine, busybox"
			The output should include "30 MB"
		End

		It 'cada fila sugiere el comando que la limpia'
			the_summary() { render_summary | plain; }
			When call the_summary
			The output should include "make run clean-build"
			The output should include "make run volumes-orphan"
		End

		# El prefijo era `make` a secas y el Makefile no tiene NI UN target de
		# producto: sugería `make clean`, que no existe. Lo que se sugiera tiene
		# que existir, o es peor que no sugerir nada.
		It 'lo que sugiere está anunciado de verdad en commands.txt'
			unannounced() {
				local c
				while read -r c; do
					[ -n "$c" ] || continue
					grep -qE "^${c}:" "$REPO_ROOT/src/commands.txt" || printf '%s ' "$c"
				done < <(grep -oE "DCC_CMD [a-z][a-z0-9-]*" "$REPO_ROOT/src/scripts/dashboard.sh" \
				         | cut -d' ' -f2 | sort -u)
			}
			When call unannounced
			The output should be blank
		End

		# El fichero único se llama `dcc`, no `make`. Sugerir `make clean` a quien
		# se bajó un .sh suelto es mandarlo a un comando que no tiene.
		It 'el comando sugerido se adapta a cómo te lo hayan instalado'
			as_bundle() { DCC_CMD=dcc; render_summary | plain; }
			When call as_bundle
			The output should include "dcc clean-build"
			The output should not include "make run clean-build"
		End

		It 'una fuente vacía NO saca fila'
			no_cache() { M[cacheRaw]=0; render_summary | plain; }
			When call no_cache
			The output should not include "4.2 GB"
			The output should include "900 MB"
		End

		# En FAST no hay df.json: no se puede contar nada y decirlo es la respuesta
		# honesta. Pintar una tabla de ceros sería mentir.
		It 'sin datos de tamaño lo dice en vez de inventarse ceros'
			no_sizes() { M=(); render_summary | plain; }
			When call no_sizes
			The output should include "No size data"
			The output should not include "IDENTIFIED WASTE"
		End
	End

	# El código de salida ES la señal: 0 parada limpia, 137 SIGKILL/OOM, cualquier
	# otro es que murió mal. Se nombra el CONTENEDOR y no el servicio, porque "app"
	# se repite en cinco stacks y no identifica nada.
	Describe 'render_alerts()'
		setup() {
			PSDATA=$(printf '%s\n' \
				$'roto-1\texited\tExited (3) 1 hour ago\t\talpine\tproyecto\troto' \
				$'muerto-1\texited\tExited (137) 2 hours ago\t\talpine\tproyecto\tmuerto' \
				$'viejo-1\texited\tExited (0) 3 weeks ago\t\talpine\tantiguo\tviejo' \
				$'web-1\trunning\tUp 2 hours\t\tnginx\tproyecto\tweb')
		}
		BeforeEach 'setup'

		It 'nombra el contenedor y su código de salida'
			alerts() { render_alerts | plain; }
			When call alerts
			The output should include "roto-1 (3)"
			The output should include "died with an error"
		End

		It 'cuenta aparte los que murieron por SIGKILL'
			alerts() { render_alerts | plain; }
			When call alerts
			The output should include "1 killed the hard way (137)"
		End

		# 137 es casi siempre OOM: es un aviso distinto de "petó", y mezclarlos
		# esconde el único que se arregla dando memoria.
		It 'un 137 NO se cuenta como muerte con error'
			alerts() { render_alerts | plain; }
			When call alerts
			The output should not include "muerto-1 (137)"
		End

		It 'los parados desde hace semanas se agrupan por stack'
			alerts() { render_alerts | plain; }
			When call alerts
			The output should include "antiguo"
		End

		# `paste -sd", "` trata su argumento como una LISTA que ROTA: con dos
		# colaba, y con TRES daba "a (1), b (2) c (3)". Por eso el caso son tres.
		It 'con TRES muertos el separador NO cambia a mitad de lista'
			three_dead() {
				PSDATA=$(printf '%s\n' \
					$'uno-1\texited\tExited (1) 1 hour ago\t\talpine\tproyecto\tuno' \
					$'dos-1\texited\tExited (2) 1 hour ago\t\talpine\tproyecto\tdos' \
					$'tres-1\texited\tExited (3) 1 hour ago\t\talpine\tproyecto\ttres')
				render_alerts | plain
			}
			When call three_dead
			The status should be success
			The output should include "uno-1 (1), dos-1 (2), tres-1 (3)"
		End

		# Sin nada que avisar la sección NO se pinta: un panel que siempre tiene una
		# caja de alertas vacía enseña a ignorarla.
		It 'sin nada que avisar no imprime NADA y devuelve 0'
			quiet() { PSDATA=$'web-1\trunning\tUp 2 hours\t\tnginx\tproyecto\tweb'; render_alerts; }
			When call quiet
			The status should be success
			The output should be blank
		End
	End

	Describe 'render_disk()'
		setup() {
			M=([disk]="21.4 GB" [layers]="14 GB" [coTotal]="2 GB" [volTotal]="1.2 GB" [bcTotal]="4.2 GB")
		}
		BeforeEach 'setup'

		It 'desglosa capas, contenedores, volúmenes y caché'
			the_disk() { render_disk | plain; }
			When call the_disk
			The output should include "Image layers"
			The output should include "14 GB"
			The output should include "1.2 GB"
			The output should include "4.2 GB"
		End

		It 'cierra con el total'
			the_disk() { render_disk | plain; }
			When call the_disk
			The output should include "21.4 GB"
		End

		It 'sin datos avisa en vez de pintar una tabla vacía'
			no_sizes() { M=(); render_disk | plain; }
			When call no_sizes
			The output should include "No size data"
		End
	End

	# No tenía NI UN test, y es la sección con dos caminos: con tamaños (jq sobre
	# df.json) y sin ellos (`docker volume ls`). Los dos pintan la misma fila, así
	# que los dos se comprueban.
	Describe 'render_volumes()'
		no_jq() { ! command -v jq >/dev/null 2>&1; }

		setup() {
			TMP=$(mktemp -d)
			M=([disk]="21.4 GB")
			cat >"$TMP/df.json" <<-'JSON'
				{"Volumes":[
				  {"Name":"datos","UsageData":{"Size":31000000,"RefCount":1}},
				  {"Name":"sobras","UsageData":{"Size":9000000,"RefCount":0}}
				]}
			JSON
			# Formato de read_containers: /contenedor y sus volúmenes detrás.
			VOLMAP='/web-1 datos'
			docker() { case "$*" in "volume ls -q") printf 'datos\nsobras\n' ;; esac; return 0; }
		}
		cleanup() { rm -rf "$TMP"; }
		BeforeEach 'setup'
		AfterEach  'cleanup'

		It 'con tamaños: nombre, tamaño y quién lo usa'
			Skip if "no hay jq" no_jq
			the_volumes() { render_volumes | plain; }
			When call the_volumes
			The output should include "datos"
			The output should include "31 MB"
			The output should include "web-1"
		End

		It 'con RefCount 0 lo marca huérfano aunque nadie pregunte'
			Skip if "no hay jq" no_jq
			orphan_row() { render_volumes | plain | grep sobras; }
			When call orphan_row
			The output should include "orphan"
		End

		# El camino sin df.json pintaba la MISMA fila con otro printf: la copia es
		# lo que se va de la otra en cuanto alguien toque el formato.
		It 'sin tamaños sigue diciendo quién usa cada volumen'
			no_sizes() { M=(); render_volumes | plain; }
			When call no_sizes
			The output should include "datos"
			The output should include "web-1"
			The output should include "—"
		End

		It 'sin tamaños el que no usa nadie sale huérfano igual'
			no_sizes() { M=(); render_volumes | plain | grep sobras; }
			When call no_sizes
			The output should include "orphan"
		End

		It 'sin volúmenes lo dice en vez de dejar una cabecera suelta'
			none() { docker() { return 0; }; render_volumes | plain; }
			When call none
			The output should include "(none)"
		End
	End

	# Única sección que consulta el df.json en disco, pero por jq y no por docker:
	# se le da un fichero de mentira y no hace falta motor ninguno.
	Describe 'render_images()'
		no_jq() { ! command -v jq >/dev/null 2>&1; }

		setup() {
			TMP=$(mktemp -d)
			M=([disk]="21.4 GB")
			cat >"$TMP/df.json" <<-'JSON'
				{"Images":[
				  {"RepoTags":["nginx:latest"],"Size":187000000,"Containers":1},
				  {"RepoTags":["postgres:16"],"Size":420000000,"Containers":0},
				  {"RepoTags":null,"Size":9000000,"Containers":0}
				]}
			JSON
		}
		cleanup() { rm -rf "$TMP"; }
		BeforeEach 'setup'
		AfterEach  'cleanup'

		It 'ordena de mayor a menor'
			Skip if "no hay jq" no_jq
			the_images() { render_images | plain; }
			When call the_images
			The line 3 of output should include "postgres:16"   # 420 MB
			The line 4 of output should include "nginx:latest"  # 187 MB
		End

		# ⌀ es "nadie la usa": es la que puedes borrar sin pensarlo.
		It 'marca las imágenes que no usa ningún contenedor'
			Skip if "no hay jq" no_jq
			mark_of() { render_images | plain | grep 'postgres:16'; }
			When call mark_of
			The output should include "⌀"
		End

		It 'una imagen sin etiqueta no rompe la tabla'
			Skip if "no hay jq" no_jq
			the_images() { render_images | plain; }
			When call the_images
			The output should include "<none>:<none>"
		End

		It 'sin datos de tamaño avisa'
			no_sizes() { M=(); render_images | plain; }
			When call no_sizes
			The output should include "No size data"
		End
	End
End
