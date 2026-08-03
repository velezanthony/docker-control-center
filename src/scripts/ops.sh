#!/usr/bin/env bash
# ops.sh — las operaciones sobre Docker; el Makefile solo despacha aquí.
# Salidas: 0 hecho o ya estaba así · 1 no existe · 2 error de uso.
set -uo pipefail

RC_NOT_FOUND=1
RC_USAGE=2
RC_CANCELLED=2   # pick() no pudo resolver el nombre: falta el dato

# shellcheck source=src/scripts/common.sh
. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BACKUP_DIR=${BACKUP_DIR:-$DCC_ROOT/backups}

# Para operar DENTRO de un volumen. Dependencia REAL: sin red, volume-tree,
# backup y restore fallan. Sustituible por cualquier imagen con sh, tar y du.
HELPER_IMAGE=${HELPER_IMAGE:-alpine}

# --- Piezas reutilizables -----------------------------------------------------

# Por ETIQUETA y no con `docker compose -p X`: los devcontainers apuntan a yml
# efímeros que ya no existen, y la etiqueta siempre está.
stack_ids()         { docker ps -aq --filter label=com.docker.compose.project="$1"; }
stack_ids_running() { docker ps -q  --filter label=com.docker.compose.project="$1"; }

list_containers() { docker ps -a --format '{{.Names}}'; }
list_running()    { docker ps --format '{{.Names}}'; }
list_volumes()    { docker volume ls -q; }
list_images()     { docker images --format '{{.Repository}}:{{.Tag}}'; }
list_stacks()     { docker ps -a --format '{{.Label "com.docker.compose.project"}}' | awk 'NF' | sort -u; }

# Si te dan un valor se usa; si no, menú. Sin TTY avisa en vez de colgarse.
# `case` y no "list_$kind" compuesto, que ante un typo fallaba en silencio.
pick() {
	local kind=$1 preset=${2:-} lister opts o
	case "$kind" in
		container) lister=list_containers ;;
		running)   lister=list_running    ;;
		volume)    lister=list_volumes    ;;
		image)     lister=list_images     ;;
		stack)     lister=list_stacks     ;;
		*) printf 'pick: tipo desconocido "%s"\n' "$kind" >&2; return $RC_USAGE ;;
	esac
	opts=$("$lister")

	# SE VALIDA contra lo que existe, aunque cueste una llamada a docker:
	# `docker run -v /home/x:/data` es un BIND MOUNT del host, y detrás va un
	# `rm -rf /data/*`.
	if [ -n "$preset" ]; then
		while IFS= read -r o; do
			[ "$o" = "$preset" ] && { printf '%s' "$preset"; return 0; }
		done <<<"$opts"
		say "pick_unknown_$kind" "$preset" >&2
		return $RC_NOT_FOUND
	fi

	if [ -z "$opts" ]; then say "pick_none_$kind" >&2; return $RC_NOT_FOUND; fi
	if [ ! -t 0 ]; then
		printf "%s\n" "${YE}$(t pick_no_tty)${R}" >&2
		# sed y no `sd`: sd no viene en ninguna distribución (hay un test).
		printf "%s\n" "$opts" | sed 's/^/    /' >&2
		return $RC_USAGE
	fi
	printf "${B}%s${R}\n" "$(t "pick_choose_$kind")" >&2
	# Array y no `select o in $opts`: sin comillas, un volumen llamado
	# "mi volumen" se partiría en dos opciones del menú.
	local -a choices=()
	while IFS= read -r o; do [ -n "$o" ] && choices+=("$o"); done <<<"$opts"
	PS3=$'\n> '
	select o in "${choices[@]}"; do [ -n "${o:-}" ] && { printf '%s' "$o"; return 0; }; done
	return $RC_CANCELLED
}

# La palabra sale del catálogo (SI / YES): pedir "yes" en una interfaz en
# español es pedir que confirmen sin leer.
confirm() {
	local answer
	read -r -p "$(t confirm_prompt)" answer
	[ "$answer" = "$(t confirm_word)" ]
}

ok_msg()   { printf "${GR}%s${R}\n" "$(tf "$@")"; }
warn_msg() { printf "${RD}%s${R}\n" "$(tf "$@")"; }

# stack-start/stop/restart y NO up/down: en compose eso significa CREAR y
# DESTRUIR. Un stack que no existe es error; uno ya en ese estado, éxito.
stack_action() {
	local action=$1 preset=${2:-} name ids
	name=$(pick stack "$preset") || return $?
	ids=$(stack_ids "$name")
	if [ -z "$ids" ]; then say op_no_containers "$name"; return $RC_NOT_FOUND; fi
	if [ "$action" = stop ]; then
		ids=$(stack_ids_running "$name")
		[ -z "$ids" ] && { say op_nothing_running "$name"; return 0; }
	fi
	# shellcheck disable=SC2086  # ids son varias palabras a propósito
	case "$action" in
		start)   docker start   $ids >/dev/null && ok_msg op_started   "$name" ;;
		stop)    docker stop    $ids >/dev/null && ok_msg op_stopped   "$name" ;;
		restart) docker restart $ids >/dev/null && ok_msg op_restarted "$name" ;;
	esac
}

op_stack_start()   { stack_action start   "${1:-}"; }
op_stack_stop()    { stack_action stop    "${1:-}"; }
op_stack_restart() { stack_action restart "${1:-}"; }

op_stack_logs() {
	local name c
	name=$(pick stack "${1:-}") || return $?
	docker ps -a --filter label=com.docker.compose.project="$name" --format '{{.Names}}' \
	| while read -r c; do
		printf "\n${B}${CY}── %s ──${R}\n" "$c"
		docker logs --tail 30 "$c" 2>&1 | tail -30
	done
}

op_stack_rm() {
	local name ids n
	name=$(pick stack "${1:-}") || return $?
	ids=$(stack_ids "$name")
	[ -z "$ids" ] && { say op_no_containers "$name"; return $RC_NOT_FOUND; }
	n=$(printf '%s\n' "$ids" | wc -l)
	warn_msg warn_rm_stack "$n" "$name"
	printf "${D}%s${R}\n" "$(t warn_rm_keep)"
	confirm || return 0
	# shellcheck disable=SC2086
	docker rm -f $ids >/dev/null && ok_msg op_removed "$name"
}

# --- Contenedores -------------------------------------------------------------

# $1 = tipo para pick · $2 = preselección · $3… = comando; el nombre va al final.
on_container() {
	local kind=$1 preset=${2:-}; shift 2
	local n; n=$(pick "$kind" "$preset") || return $?   # 1 no existe, 2 falta el dato
	"$@" "$n"
}

# jq no es opcional aquí: mejor decirlo que morir con "orden no encontrada".
need_jq() { command -v jq >/dev/null || { warn_msg need_jq; return $RC_USAGE; }; }

inspect_json()  { need_jq || return $?; docker inspect "$1" | jq .; }
exec_shell()    { docker exec -it "$1" sh -c 'command -v bash >/dev/null && exec bash || exec sh'; }

op_logs()    { on_container container "${1:-}" docker logs --tail 200; }
op_tail()    { on_container container "${1:-}" docker logs -f --tail 50; }
op_inspect() { on_container container "${1:-}" inspect_json; }
op_start()   { on_container container "${1:-}" docker start; }
op_restart() { on_container container "${1:-}" docker restart; }
op_stop()    { on_container running   "${1:-}" docker stop; }
op_sh()      { on_container running   "${1:-}" exec_shell; }

op_kill_all() {
	local ids
	# El demonio caído NO es "no hay nada corriendo": con `ids=$(docker ps -q)` a
	# secas, docker fallando daba una lista vacía y esto decía "Nothing is
	# running" con rc=0. Informar de un estado que no has podido consultar.
	ids=$(docker ps -q) || { warn_msg err_docker_down; return $RC_NOT_FOUND; }
	# Nada corriendo sí es el estado que pedías: éxito, no error.
	[ -z "$ids" ] && { say op_nothing_up; return 0; }
	# shellcheck disable=SC2086
	docker stop $ids
}

# --- Volúmenes ----------------------------------------------------------------

op_volume_inspect() { need_jq || return $?; local v; v=$(pick volume "${1:-}") || return $?; docker volume inspect "$v" | jq .; }

op_volume_tree() {
	local v; v=$(pick volume "${1:-}") || return $?
	docker run --rm -v "$v":/data:ro "$HELPER_IMAGE" sh -c 'du -sh /data; ls -la /data'
}

# El tar sale por STDOUT y lo escribe tu shell: montando ./backups dentro, los
# .tar.gz quedaban a nombre de root y no podías ni borrarlos.
#
# Se escribe a un temporal y se mueve solo si sale bien. La redirección crea el
# fichero ANTES de que docker arranque, así que un fallo dejaba un .tar.gz de
# cero bytes con nombre de backup esperando a engañar a alguien.
backup_one() {
	local v=$1 out="$BACKUP_DIR/$1.tar.gz" tmp
	tmp=$(mktemp "$BACKUP_DIR/.backup.XXXXXX" 2>/dev/null) || return 1
	if docker run --rm -v "$v":/data:ro "$HELPER_IMAGE" tar czf - -C /data . >"$tmp" 2>/dev/null \
		&& [ -s "$tmp" ]; then
		mv "$tmp" "$out"
		return 0
	fi
	rm -f "$tmp"
	return 1
}

op_volume_backup() {
	local v out; v=$(pick volume "${1:-}") || return $?
	# El destino, antes de invocar a docker: si no, un fallo soltaba tres mensajes.
	if ! mkdir -p "$BACKUP_DIR" 2>/dev/null || [ ! -w "$BACKUP_DIR" ]; then
		warn_msg backup_dir_unwritable "$BACKUP_DIR"; return $RC_USAGE
	fi
	out="$BACKUP_DIR/$v.tar.gz"
	backup_one "$v" 2>/dev/null || { warn_msg backup_failed_one "$v"; return $RC_NOT_FOUND; }
	printf "${GR}✓${R} %s (%s)\n" "$out" "$(du -h "$out" | cut -f1)"
}

# Contaba los fallos y luego pintaba el ✓ igual: con docker caído decía
# "✓ Backups en X" y devolvía 0 habiendo hecho CERO backups. Alguien ejecuta
# esto antes de un stack-rm, ve el verde y borra el stack.
op_volume_backup_all() {
	local v failed=0 total=0
	if ! mkdir -p "$BACKUP_DIR" 2>/dev/null || [ ! -w "$BACKUP_DIR" ]; then
		warn_msg backup_dir_unwritable "$BACKUP_DIR"; return $RC_USAGE
	fi
	while read -r v; do
		[ -z "$v" ] && continue
		total=$(( total + 1 ))
		printf "${D}→ %s${R}\n" "$v"
		backup_one "$v" || { say backup_failed; failed=$(( failed + 1 )); }
	done < <(list_volumes)

	if (( failed > 0 )); then
		warn_msg backup_failed_some "$failed" "$total"
		return $RC_NOT_FOUND
	fi
	ok_msg backup_done "$BACKUP_DIR"
	du -sh "$BACKUP_DIR"
}

# Se extrae PRIMERO a un directorio aparte y solo se borra lo viejo cuando el tar
# ha terminado bien. Antes era `rm -rf /data/* && tar xzf`: un Ctrl-C, un flujo
# cortado o un OOM entre las dos mitades dejaba el volumen vacío y sin restaurar
# — justo en el comando que se ejecuta cuando algo ya ha salido mal.
#
# Cuesta el doble de espacio mientras dura. El `gzip -t` previo solo valida el
# envoltorio, no que la extracción llegue al final.
op_volume_restore() {
	local v src; v=$(pick volume "${1:-}") || return $?
	src="$BACKUP_DIR/$v.tar.gz"
	[ -f "$src" ] || { warn_msg restore_missing "$src"; return $RC_NOT_FOUND; }
	if ! gzip -t "$src" 2>/dev/null; then warn_msg restore_corrupt "$src"; return $RC_NOT_FOUND; fi
	docker volume create "$v" >/dev/null
	docker run --rm -i -v "$v":/data "$HELPER_IMAGE" sh -c '
		set -e
		rm -rf /data/.dcc-restore
		mkdir /data/.dcc-restore
		tar xzf - -C /data/.dcc-restore
		find /data -mindepth 1 -maxdepth 1 ! -name .dcc-restore -exec rm -rf {} +
		cp -a /data/.dcc-restore/. /data/
		rm -rf /data/.dcc-restore
	' <"$src" && ok_msg restore_done "$v"
}

op_volumes_orphan() { docker volume ls -qf dangling=true; }

# --- Limpieza -----------------------------------------------------------------

# El ✓ se pintaba pasara lo que pasara: con docker caído los tres prune fallaban
# y aun así salía "✓ Limpieza segura hecha".
op_clean() {
	local rc=0
	docker container prune -f || rc=1
	docker image prune -f     || rc=1
	docker network prune -f   || rc=1
	(( rc )) && { warn_msg clean_failed; return $RC_NOT_FOUND; }
	printf "${GR}%s${R}\n" "$(t clean_done)"
	docker system df
}

op_clean_build() {
	docker builder prune -af || { warn_msg clean_failed; return $RC_NOT_FOUND; }
	docker system df
}

op_clean_hard() {
	printf "${RD}%s${R}\n" "$(t warn_clean_hard)"
	confirm || return 0
	docker system prune -af || { warn_msg clean_failed; return $RC_NOT_FOUND; }
	docker system df
}

op_rm_image() { local i; i=$(pick image "${1:-}") || return $?; docker rmi "$i"; }

# --- Panorama y motor ---------------------------------------------------------

# Como op_* las deriva el despacho, y desaparecen de las listas a mano.
op_ram() {
	if ! declare -F engine_ram >/dev/null 2>&1; then
		# shellcheck source=src/scripts/engine-ram.sh
		. "$DCC_DIR/engine-ram.sh"
	fi
	engine_ram 1
}

op_ctx()   { docker context ls; }
op_stats() { docker stats --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}'; }

op_stacks() {
	docker ps -a --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}' \
	| awk -F'\t' 'NF && $1!=""' | sort -u \
	| while IFS=$'\t' read -r proj dir; do
		printf "  ${B}%s${R} ${D}%s${R}\n" "$(pad "$proj" "$W_STACK")" "$dir"
	done
}

# Sin `--format 'table …'`: esa cabecera la pone docker y sale en inglés. Los
# datos van PRIMERO, o con docker caído se pinta una tabla vacía en vez de un error.
op_networks() {
	local rows
	rows=$(docker network ls --format '{{.Name}}\t{{.Driver}}\t{{.Scope}}') || return $?
	printf "   ${D}%s %s %s${R}\n" "$(pad "$(t col_name)" "$W_NAME")" "$(pad "$(t col_driver)" "$W_DRIVER")" "$(t col_scope)"
	while IFS=$'\t' read -r n d s; do
		[ -z "$n" ] && continue
		printf "   %s %s %s\n" "$(pad "$n" "$W_NAME")" "$(pad "$d" "$W_DRIVER")" "$s"
	done <<<"$rows"
}

# Pensado para el motor NATIVO (dockerd sobre systemd), no para Docker Desktop.
op_engine() {
	if systemctl is-active docker >/dev/null 2>&1; then
		printf "${GR}%s${R}  %s\n" "$(t engine_up)" "$(docker info --format "$(t engine_info)" 2>/dev/null)"
	else
		printf "${RD}%s${R}\n" "$(t engine_down)"
	fi
	if systemctl is-enabled docker >/dev/null 2>&1; then
		printf "${D}%s${R}\n" "$(t engine_boot_yes)"
	else
		printf "${YE}%s${R}\n" "$(t engine_boot_no)"
	fi
}

# --- Despacho -----------------------------------------------------------------

# src/commands.txt manda sobre QUÉ existe; `op_<nombre>` solo aporta la
# implementación. Al revés —derivando la lista de `declare -F op_*`— cualquier
# helper interno llamado op_algo se publicaba como comando sin querer, y había
# DOS fuentes de verdad que un test vigilaba en vez de que no pudieran divergir.
dispatch_names() {
	local c
	while read -r c; do
		[ -n "$c" ] || continue
		declare -F "op_${c//-/_}" >/dev/null 2>&1 && printf '%s\n' "$c"
	done < <(dcc_announced)
}

usage() {
	printf "%s\n" "$DCC_CMD <operación> [preselección]" >&2
	printf "  %s\n" "$(dispatch_names | tr '\n' ' ')" >&2
}

dispatch() {
	local cmd=${1:-} fn
	[ -n "$cmd" ] || { usage; return $RC_USAGE; }
	shift
	# Anunciado Y con implementación. Un op_* sin línea en commands.txt no es un
	# comando: es una función interna a la que le tocó ese prefijo.
	fn="op_${cmd//-/_}"
	if [ "$(type -t "$fn")" != function ] || ! dcc_announced | grep -qxF "$cmd"; then
		usage; return $RC_USAGE
	fi
	"$fn" "$@"
}

# Define al cargarse; ejecuta solo si lo lanzas directo.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	dispatch "$@"
fi
