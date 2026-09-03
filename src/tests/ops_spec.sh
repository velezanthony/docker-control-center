# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154,SC2215,SC2286,SC2288,SC2317,SC2329  # falsos positivos del DSL
#
# `docker` se TAPA con una función: se comprueba qué se le habría pedido, sin
# pedírselo. Los dobles van en BeforeEach, DESPUÉS del Include, o este los
# machaca; y el registro va a un FICHERO, que en subshell una variable no vuelve.

Describe 'ops.sh'
	Include src/scripts/ops.sh

	setup() {
		TMP=$(mktemp -d)
		LOG="$TMP/docker.log"
		BACKUP_DIR="$TMP"
		: >"$LOG"

		docker() { printf 'docker %s\n' "$*" >>"$LOG"; return 0; }

		# pick() VALIDA, así que los tests declaran qué existe: un nombre que no
		# está en la lista no puede llegar a `docker run -v`.
		list_stacks()     { printf 'proyecto\nvacio\nno-existe-no\n'; }
		list_containers() { printf 'web-1\ndb-1\n'; }
		list_running()    { printf 'web-1\n'; }
		list_volumes()    { printf 'datos\n'; }
		list_images()     { printf 'img:v1\n'; }
	}
	cleanup() { rm -rf "$TMP"; }
	BeforeEach 'setup'
	AfterEach  'cleanup'

	calls() { [ -s "$LOG" ] && printf '%s' "$(<"$LOG")"; return 0; }

	Describe 'pick()'
		Describe 'respeta la preselección si el nombre EXISTE'
			Parameters
				stack     proyecto
				container web-1
				volume    datos
			End

			It "$1 '$2' pasa"
				When call pick "$1" "$2"
				The output should equal "$2"
			End
		End

		It 'rechaza un nombre que no está en la lista'
			When call pick container fantasma
			The status should be failure
			The stderr should include "fantasma"
		End

		It 'sin preselección y sin TTY no se cuelga: avisa con las opciones'
			no_tty() { list_stacks() { printf 'uno\ndos\n'; }; pick stack; }
			When call no_tty
			The status should be failure
			The stderr should include "uno"
		End

		# Comparar contra $(t pick_none_volume) sería tautológico si la clave no
		# existiera, porque t() devuelve el nombre de la clave. Se usa el TEXTO.
		It 'sin candidatos lo dice con el mensaje real del catálogo'
			no_candidates() { list_volumes() { printf ''; }; pick volume; }
			When call no_candidates
			The status should be failure
			The stderr should include "No volumes available"
		End

		It 'un tipo inexistente falla RUIDOSAMENTE'
			When call pick tipo-inventado
			The status should be failure
			The stderr should not be blank
		End

		# `docker run -v "$v":/data` trata cualquier cosa que empiece por / como
		# BIND MOUNT del host. Devolver el preset sin validar significaba que
		# `volume-restore V=/home/usuario` montaba el home y le hacía rm -rf.
		Describe 'VALIDA el nombre que le pasas (era un agujero de seguridad)'
			Parameters
				/etc              "una ruta absoluta"
				/home/usuario     "el home"
				../../../tmp/fuga "un path traversal"
				no-existe         "un nombre inventado"
			End

			It "rechaza $2"
				validate() { list_volumes() { printf 'datos\ncache\n'; }; pick volume "$1"; }
				When call validate "$1"
				The status should be failure
				The stderr should include "$1"
			End
		End

		# `select o in $opts` sin comillas partía "mi volumen" en dos opciones.
		It 'no parte los nombres con espacios'
			with_space() { list_volumes() { printf 'mi volumen\notro\n'; }; pick volume 'mi volumen'; }
			When call with_space
			The output should equal "mi volumen"
		End

		# "no me has dado el dato" y "el humano ha dicho que no" son opuestos y
		# compartían el 2. El stdin va a /dev/null a propósito: `[ -t 0 ]` depende
		# de cómo lances la suite.
		Describe 'cancelar NO es lo mismo que usar mal'
			It 'sin terminal es error de USO: falta el dato'
				no_tty() { pick volume </dev/null; }
				When call no_tty
				The status should eq "$RC_USAGE"
				The stderr should include "Pass the name"
			End

			It 'cerrar el menú sin elegir es CANCELAR, y tiene código propio'
				cancelled() { has_tty() { return 0; }; pick volume </dev/null; }
				When call cancelled
				The status should eq "$RC_CANCELLED"
				# El menú SÍ se pintó (a stderr, como todo lo que no es la elección):
				# es lo que prueba que llegó al `select` y no se fue por la rama del
				# "pásame el nombre".
				The stderr should include "Choose a volume"
				The stdout should be blank
			End

		End
	End

	# La última barrera antes de `docker rm -f` y de `rm -rf /data/*`. La palabra
	# sale del CATÁLOGO: pedir "YES" en una interfaz en español es pedir que
	# confirmen sin leer. No hay prompt que comprobar: `Data` no es un terminal.
	Describe 'confirm()'
		It 'la palabra exacta del catálogo continúa'
			Data "YES"
			When call confirm
			The status should be success
		End

		Describe 'cualquier otra cosa CANCELA'
			Parameters
				"yes"  "en minúsculas"
				"y"    "la inicial"
				"sí"   "la palabra de otro idioma"
				""     "un enter a secas"
			End

			It "'$1' no continúa: $2"
				Data "$1"
				When call confirm
				The status should be failure
			End
		End

		# Pedir "YES" a quien tiene la interfaz en español es pedirle que confirme
		# sin leer. La palabra sale del catálogo, y por eso YES ahí NO vale.
		It 'en español acepta SI'
			Data "SI"
			spanish() { DCC_LANG=es dcc_load_language; confirm; }
			When call spanish
			The status should be success
		End

		It 'y en español YES ya NO vale'
			Data "YES"
			spanish() { DCC_LANG=es dcc_load_language; confirm; }
			When call spanish
			The status should be failure
		End
	End

	# Seis operaciones eran la misma línea con otro verbo. Lo que importa de la
	# pieza común: que el nombre acabe AL FINAL del comando, y que un pick fallido
	# corte antes de tocar docker.
	Describe 'on_container()'
		It 'el nombre elegido va como ÚLTIMO argumento'
			route() { on_container container web-1 docker logs --tail 200; calls; }
			When call route
			The output should include "docker logs --tail 200 web-1"
		End

		It 'un nombre que no existe corta ANTES de llamar a docker'
			ghost() { on_container container fantasma docker logs --tail 200; }
			When call ghost
			The status should eq 1
			The stderr should include "fantasma"
			The result of function calls should be blank
		End

		# op_stop y op_sh piden `running`, no `container`: parar algo ya parado o
		# abrir shell en un cadáver no son operaciones válidas.
		It 'distingue "existe" de "está vivo"'
			on_stopped() { on_container running db-1 docker stop; }
			When call on_stopped
			The status should eq 1
			The result of function calls should be blank
		End
	End

	# Tenía `docker exec -it` FIJO, duplicando lo que dex.sh ya hacía bien: en una
	# tubería o con la entrada redirigida, docker aborta con "the input device is
	# not a TTY". La suite no corre en terminal, así que aquí -t no puede salir.
	Describe 'op_sh() comparte el exec con dex.sh'
		It 'sin terminal pide -i, nunca -i -t'
			shell_in() { op_sh web-1; calls; }
			When call shell_in
			The output should include "docker exec -i web-1 sh -c"
			The output should not include "exec -i -t"
		End

		It 'prefiere bash y cae a sh, como dex'
			shell_in() { op_sh web-1; calls; }
			When call shell_in
			The output should include "exec bash"
			The output should include "exec sh"
		End
	End

	# `docker rm -f`: la operación más destructiva que expone la herramienta.
	Describe 'op_stack_rm()'
		with_two() { stack_ids() { printf 'a\nb\n'; }; }

		It 'dice CUÁNTOS va a borrar y de qué stack'
			warn() { with_two; confirm() { return 1; }; op_stack_rm proyecto; }
			When call warn
			The output should include "2 containers of proyecto"
		End

		It 'promete que los volúmenes se respetan'
			warn() { with_two; confirm() { return 1; }; op_stack_rm proyecto; }
			When call warn
			The output should include "Volumes will NOT be touched"
		End

		# Lo que de verdad hay que garantizar: un NO no borra NADA.
		It 'si no confirmas NO llama a docker, y sale con 0'
			refuse() { with_two; confirm() { return 1; }; op_stack_rm proyecto; }
			When call refuse
			The status should be success
			The result of function calls should be blank
		End

		It 'si confirmas, borra a la fuerza los contenedores del stack'
			accept() { with_two; confirm() { return 0; }; op_stack_rm proyecto >/dev/null; calls; }
			When call accept
			The output should include "docker rm -f a b"
		End

		# Un typo TIENE que fallar: `dcc stack-rm api && ./deploy.sh` no puede
		# seguir adelante creyendo que borró algo.
		It 'un stack sin contenedores devuelve 1 sin tocar docker'
			empty() { stack_ids() { printf ''; }; op_stack_rm vacio; }
			When call empty
			The status should eq 1
			The result of function calls should be blank
		End
	End

	# El tar sale por STDOUT y lo escribe TU shell. Montando ./backups dentro del
	# contenedor, que corre como root, los .tar.gz quedaban a nombre de root y no
	# podías ni borrarlos sin sudo.
	Describe 'op_volume_backup()'
		It 'monta el volumen en SOLO LECTURA'
			backup() { op_volume_backup datos >/dev/null 2>&1; calls; }
			When call backup
			The output should include "-v datos:/data:ro"
		End

		It 'el tar viaja por stdout, no lo escribe el contenedor'
			backup() { op_volume_backup datos >/dev/null 2>&1; calls; }
			When call backup
			The output should include "tar czf - -C /data ."
		End

		# El doble global registra en $LOG pero no escribe a stdout, y backup_one
		# ahora exige que el tar traiga bytes. Aquí hace falta uno que "produzca".
		It 'el fichero acaba en BACKUP_DIR, creado por tu usuario'
			backup() {
				docker() { printf 'docker %s\n' "$*" >>"$LOG"; printf 'TAR-FALSO'; return 0; }
				op_volume_backup datos >/dev/null 2>&1
				[ -s "$BACKUP_DIR/datos.tar.gz" ]
			}
			When call backup
			The status should be success
		End

		# El destino se comprueba ANTES de invocar a docker: si no, un solo fallo
		# soltaba tres mensajes, dos de ellos en crudo del sistema.
		It 'un destino no escribible se detecta ANTES de llamar a docker'
			unwritable() { BACKUP_DIR=/proc/no-se-puede-escribir-aqui; op_volume_backup datos; }
			When call unwritable
			The status should eq 2
			The output should include "Cannot write to"
			The result of function calls should be blank
		End

		It 'un volumen inventado no llega ni a intentarlo'
			ghost() { op_volume_backup no-existe; }
			When call ghost
			The status should eq 1
			The result of function calls should be blank
		End
	End

	Describe 'op_volume_backup_all()'
		# El doble de docker devuelve 0 sin escribir nada, así que el tar sale
		# vacío: es exactamente lo que pasa con el demonio caído.
		failing_docker() { docker() { printf 'docker %s\n' "$*" >>"$LOG"; return 1; }; }

		It 'recorre TODOS los volúmenes, uno por uno'
			all() {
				list_volumes() { printf 'datos\ncache\n'; }
				op_volume_backup_all >/dev/null 2>&1
				calls
			}
			When call all
			The output should include "-v datos:/data:ro"
			The output should include "-v cache:/data:ro"
		End

		# Decía "✓ Backups en X" y devolvía 0 con CERO backups hechos. Alguien
		# ejecuta esto antes de un stack-rm, ve el verde y borra el stack.
		It 'con todos los backups fallando NO dice que ha ido bien'
			all_fail() {
				list_volumes() { printf 'datos\ncache\n'; }
				failing_docker
				op_volume_backup_all 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g'
			}
			When call all_fail
			The status should be failure
			The output should include "2 of 2 backups FAILED"
			The output should not include "✓"
		End

		It 'y devuelve != 0'
			all_fail() {
				list_volumes() { printf 'datos\n'; }
				failing_docker
				op_volume_backup_all >/dev/null 2>&1
			}
			When call all_fail
			The status should be failure
		End

		# La redirección creaba el .tar.gz ANTES de que docker arrancara, así que
		# un fallo dejaba un fichero de 0 bytes con nombre de backup.
		It 'un backup fallido NO deja un .tar.gz de cero bytes'
			no_stub_file() {
				list_volumes() { printf 'datos\n'; }
				failing_docker
				op_volume_backup_all >/dev/null 2>&1
				find "$BACKUP_DIR" -name '*.tar.gz' | wc -l
			}
			When call no_stub_file
			The output should equal "0"
		End

		It 'ni temporales sueltos'
			no_leak() {
				list_volumes() { printf 'datos\n'; }
				failing_docker
				op_volume_backup_all >/dev/null 2>&1
				find "$BACKUP_DIR" -name '.backup.*' | wc -l
			}
			When call no_leak
			The output should equal "0"
		End

		It 'sin destino escribible aborta antes de empezar'
			unwritable() { BACKUP_DIR=/proc/no-se-puede-escribir-aqui; op_volume_backup_all; }
			When call unwritable
			The status should eq 2
			The result of function calls should be blank
		End
	End

	# stop mira solo los VIVOS; start/restart miran todos. Confundirlos era
	# intentar parar contenedores ya parados y soltar un error feo.
	Describe 'stack_action()'
		stub_ids() { stack_ids() { printf 'todos-1\ntodos-2\n'; }; stack_ids_running() { printf 'vivos-1\n'; }; }

		Parameters
			start   "docker start todos-1 todos-2"
			stop    "docker stop vivos-1"
			restart "docker restart todos-1 todos-2"
		End

		It "$1 actúa sobre los ids correctos"
			act() { stub_ids; stack_action "$1" proyecto >/dev/null; calls; }
			When call act "$1"
			The output should include "$2"
		End
	End

	# Un typo en el nombre TIENE que fallar; un no-op, no: si todo devolviera 0,
	# `dcc stack-start api && ./deploy.sh` desplegaría contra un fantasma. Y con
	# el demonio caído hay que IMPRIMIR algo: fallar en silencio deja a quien lo
	# ejecuta sin saber por qué no salió el ✓.
	Describe 'stack_action() cuando docker DICE QUE NO'
		docker_fails() {
			stack_ids()         { printf 'todos-1\ntodos-2\n'; }
			stack_ids_running() { printf 'todos-1\n'; }
			docker() { printf 'docker %s\n' "$*" >>"$LOG"; return 1; }
		}

		It 'lo dice en vez de callarse'
			boom() { docker_fails; stack_action start proyecto; }
			When call boom
			The status should eq 1
			The output should not be blank
		End

		It 'y NO pinta el ✓ de que arrancó'
			boom() { docker_fails; stack_action start proyecto 2>&1; }
			When call boom
			The status should eq 1
			The output should not include "✓"
		End
	End

	# Igual en el `rm -f`: es la operación más destructiva de la herramienta y
	# pintaba el ✓ o nada.
	Describe 'op_stack_rm() cuando el rm falla'
		It 'avisa y devuelve != 0 en vez de pintar el ✓'
			boom() {
				stack_ids() { printf 'a\nb\n'; }
				confirm() { return 0; }
				docker() { return 1; }
				op_stack_rm proyecto 2>&1
			}
			When call boom
			The status should eq 1
			The output should not include "✓"
		End
	End

	Describe 'códigos de salida de stack_action()'
		It 'un stack que ni está en la lista devuelve 1 y no llama a docker'
			ghost() {
				stack_ids() { printf ''; }; stack_ids_running() { printf ''; }
				stack_action start fantasma-total
			}
			When call ghost
			The status should eq 1
			The stderr should not be blank
			The result of function calls should be blank
		End

		It 'parar algo YA parado devuelve 0: el estado final es el pedido'
			already_stopped() {
				stack_ids() { printf 'a\n'; }; stack_ids_running() { printf ''; }
				list_stacks() { printf 'proyecto\nya-parado\n'; }
				stack_action stop ya-parado
			}
			When call already_stopped
			The status should be success
			The output should not be blank
			The result of function calls should be blank
		End
	End

	# El bug que tenía: `rm -rf /data/* && tar xzf` borraba PRIMERO. Con un backup
	# corrupto te quedabas sin volumen Y sin backup.
	Describe 'op_volume_restore() COMPRUEBA el tar antes de borrar nada'
		It 'sin backup avisa de cuál falta y NO llama a docker'
			When call op_volume_restore datos
			The status should be failure
			The output should include "$BACKUP_DIR/datos.tar.gz"
			The result of function calls should be blank
		End

		It 'con el backup CORRUPTO avisa y NO borra nada'
			corrupt_backup() { printf 'esto no es un gzip' >"$BACKUP_DIR/datos.tar.gz"; op_volume_restore datos; }
			When call corrupt_backup
			The status should be failure
			The output should include "is corrupt"
			The result of function calls should be blank
		End

		It 'con un backup válido sí crea el volumen'
			valid_backup() {
				printf 'contenido' | gzip >"$BACKUP_DIR/datos.tar.gz"
				op_volume_restore datos >/dev/null 2>&1 || true
				calls
			}
			When call valid_backup
			The output should include "docker volume create datos"
		End

		# Acababa en `docker run … && ok_msg`, sin rama else: el único comando del
		# fichero que fallaba EN SILENCIO, y el que corre cuando algo ya va mal.
		It 'si la extracción falla dentro del contenedor, lo DICE'
			restore_fails() {
				printf 'contenido' | gzip >"$BACKUP_DIR/datos.tar.gz"
				# El volumen se crea; el `docker run` que extrae, no.
				docker() { case "$*" in "volume create datos") return 0 ;; *) return 1 ;; esac; }
				op_volume_restore datos 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g'
			}
			When call restore_fails
			The status should be failure
			The output should include "half-restored"
			The output should not include "✓"
		End
	End

	Describe 'op_kill_all()'
		It 'no hace nada si no hay nada corriendo, y lo dice'
			nothing_running() {
				docker() { case "$*" in "ps -q") printf '' ;; *) printf 'docker %s\n' "$*" >>"$LOG" ;; esac; return 0; }
				op_kill_all
			}
			When call nothing_running
			The output should include "$(t op_nothing_up)"
			The result of function calls should be blank
		End

		It 'los para a todos si los hay'
			some_running() {
				docker() { case "$*" in "ps -q") printf 'a\nb\n' ;; *) printf 'docker %s\n' "$*" >>"$LOG" ;; esac; return 0; }
				op_kill_all >/dev/null
				calls
			}
			When call some_running
			The output should include "docker stop a b"
		End
	End

	# Mismo patrón que backup_all: el ✓ se pintaba pasara lo que pasara.
	Describe 'la limpieza tampoco miente'
		failing_docker() { docker() { printf 'docker %s\n' "$*" >>"$LOG"; return 1; }; }

		Parameters
			op_clean       "limpieza segura"
			op_clean_build "caché de construcción"
		End

		It "$1 con docker fallando NO pinta el ✓ ($2)"
			fails() { failing_docker; "$1" 2>&1 | sed -E 's/\x1b\[[0-9;]*m//g'; }
			When call fails "$1"
			The status should be failure
			The output should include "did NOT finish"
			The output should not include "✓"
		End
	End

	# `rm -rf /data/* && tar xzf` borraba PRIMERO: un Ctrl-C, un flujo cortado o
	# un OOM entre las dos mitades dejaba el volumen vacío y sin restaurar.
	Describe 'op_volume_restore() no borra antes de tener el contenido'
		valid_backup() { printf 'contenido' | gzip >"$BACKUP_DIR/datos.tar.gz"; }

		It 'extrae a un directorio aparte antes de tocar lo viejo'
			staged() { valid_backup; op_volume_restore datos >/dev/null 2>&1 || true; calls; }
			When call staged
			The output should include ".dcc-restore"
			The output should include "tar xzf - -C /data/.dcc-restore"
		End

		It 'ya no arranca borrándolo todo'
			no_wipe_first() { valid_backup; op_volume_restore datos >/dev/null 2>&1 || true; calls; }
			When call no_wipe_first
			The output should not include "rm -rf /data/* &&"
		End
	End

	# PROPIEDAD DE TODA LA FAMILIA: con el demonio caído, ninguna operación puede
	# decir que hizo algo. Caza op_clean, op_volume_backup_all y op_kill_all de una
	# vez, y al siguiente que se escriba. Ningún linter ve esto: es semántico.
	It 'con docker caído, ninguna operación pinta el ✓'
		all_down() {
			docker() { return 1; }
			systemctl() { return 1; }
			confirm() { return 0; }
			stack_ids() { printf 'a\n'; }; stack_ids_running() { printf 'a\n'; }
			printf 'x' | gzip >"$BACKUP_DIR/datos.tar.gz"

			local c fn out liars=""
			while read -r c; do
				fn="op_${c//-/_}"
				declare -F "$fn" >/dev/null 2>&1 || continue
				# Solo las dos que NO necesitan docker: `ram` lee /proc y `engine`
				# pregunta a systemd. Las que "transmiten" no transmiten nada doblado.
				case "$c" in ram|engine) continue ;; esac
				# Basta con que pinte el ✓: exigir ADEMÁS rc=0 dejaba pasar a
				# op_clean, que lo pintaba y devolvía 1 de casualidad porque su
				# último comando era `docker system df`.
				out=$("$fn" datos 2>&1) || true
				printf '%s' "$out" | grep -q '✓' && liars+=" $c"
			done < <(dcc_announced)
			printf '%s' "$liars"
		}
		When call all_down
		The output should be blank
	End

	# La lista de operaciones es la INTERSECCIÓN de src/commands.txt y las
	# funciones op_*: añadir una son DOS sitios, y si te dejas la línea de
	# commands.txt el comando existe pero no se anuncia. Los dos ejemplos de
	# abajo son justo esas dos mitades.
	Describe 'dispatch()'
		It 'rechaza una operación que no existe'
			When call dispatch operacion-inventada
			The status should be failure
			The stderr should not be blank
		End

		It 'sin argumentos también falla'
			When call dispatch
			The status should be failure
			The stderr should not be blank
		End

		It 'expone 29 operaciones: las anunciadas que además tienen función'
			count_ops() { dispatch_names | wc -l; }
			When call count_ops
			The output should equal "29"
		End

		# Anunciar y ser invocable van juntos: se finge el catálogo y la función.
		It 'un comando anunciado CON función se despacha'
			new_op() {
				dcc_announced() { printf 'made-up-for-test\n'; }
				op_made_up_for_test() { printf 'llamada\n'; }
				dispatch made-up-for-test
			}
			When call new_op
			The output should equal "llamada"
		End

		# El agujero que cerraba esto: cualquier helper interno al que le tocara el
		# prefijo op_ se publicaba como comando sin que nadie lo decidiera.
		It 'una función op_* que NADIE anuncia no es un comando'
			private_helper() {
				op_helper_interno() { printf 'NO DEBERÍA SALIR\n'; }
				dispatch_names | grep -q 'helper-interno' && return 9
				dispatch helper-interno
			}
			When call private_helper
			The status should eq 2
			The output should not include "NO DEBERÍA"
			The stderr should not include "helper-interno"
		End
	End

	# El catálogo de comandos vivía en el Makefile; ahora en src/commands.txt, que
	# es lo que el bundle incrusta como ayuda. Una operación que no esté ahí
	# existe pero nadie la encuentra.
	It 'src/commands.txt anuncia todas las operaciones'
		missing_commands() {
			local missing=""
			while read -r c; do
				grep -q "^${c}:" "$REPO_ROOT/src/commands.txt" || missing+=" $c"
			done < <(dispatch_names)
			printf '%s' "$missing"
		}
		When call missing_commands
		The output should be blank
	End

	# Y al revés: el texto del `##` es solo el RESPALDO. Cada comando anunciado
	# necesita su clave help_<nombre> o al cambiar de idioma se quedaría en inglés.
	It 'cada comando anunciado tiene su clave de traducción'
		untranslated() {
			local c missing=""
			while read -r c; do
				grep -q "\[help_$c\]" "$REPO_ROOT/src/i18n/es.sh" || missing+=" $c"
			done < <(grep -oE '^[a-z][a-z-]*:' "$REPO_ROOT/src/commands.txt" | tr -d ':')
			printf '%s' "$missing"
		}
		When call untranslated
		The output should be blank
	End
End
