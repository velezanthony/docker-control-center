#!/usr/bin/env bash
# dashboard.sh — FUENTE ÚNICA de presentación; dash, ps, volumes, images y status
# son vistas sobre `--only`. FAST=1 salta lo que dependa de tamaños.
# El texto sale del catálogo, y ningún número es estimación de Docker.
set -uo pipefail

# shellcheck source=src/scripts/common.sh
declare -F pad >/dev/null 2>&1 || . "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Se CARGAN, no se lanzan: evita dos forks por `dash`. El `declare -F` va en la
# misma línea porque en el fichero único ya es cierto y el source no se dispara.
# shellcheck source=src/scripts/engine-ram.sh
declare -F engine_ram    >/dev/null 2>&1 || . "$DCC_DIR/engine-ram.sh"
# shellcheck source=src/scripts/container-cpu.sh
declare -F container_cpu >/dev/null 2>&1 || . "$DCC_DIR/container-cpu.sh"

# Perezosa: en el fichero único se cargan todos los scripts en cada invocación,
# y `dcc version` no pinta una regla en su vida.
W=""
ensure_width() {
	[ -n "$W" ] && return 0
	W=$(tput cols 2>/dev/null || echo 100)
	(( W > 110 )) && W=110
	(( W < 60 ))  && W=60
	return 0   # o el estado lo fijaría el último (( )), falso entre 60 y 110
}

# Nada de `printf %${W}s | tr ' ' '─'`: tr opera sobre BYTES y ─ ocupa 3 en UTF-8.
rule() { ensure_width; printf "%s" "$D"; for ((i = 0; i < W; i++)); do printf '─'; done; printf "%s\n" "$R"; }

section() {
	printf "\n${B}%s${R}" "$1"
	[ -n "${2:-}" ] && printf " ${D}%s${R}" "$2"
	printf "\n"
}

# --- Qué secciones se piden ---------------------------------------------------
ALL_SECTIONS="summary,alerts,stacks,volumes,images,disk"

# Fuente ÚNICA de qué pinta cada vista. Devuelve != 0 si no es una vista, para
# que quien pregunta siga probando sin listas paralelas.
dcc_view_sections() {
	case "$1" in
		dash)       printf '%s' "$ALL_SECTIONS" ;;
		status)     printf 'summary,disk' ;;
		ps | psa)   printf 'stacks' ;;
		images)     printf 'images' ;;
		volumes)    printf 'volumes' ;;
		*) return 1 ;;
	esac
}
want() { [[ ",$ONLY," == *",$1,"* ]]; }

# Sin `local`: las funciones de pintado leen estos globales, y así los tests les
# inyectan datos sin tocar docker.
parse_args() {
	FAST=${FAST:-0}
	ONLY="all"
	while [ $# -gt 0 ]; do
		case "$1" in
			# Sin comprobar $#, un `--only` suelto moría con "unbound variable"
			# de `set -u`: un mensaje del intérprete, no de la herramienta.
			--only)
				[ $# -ge 2 ] || { printf 'dashboard: --only necesita un valor\n' >&2; return 2; }
				ONLY="$2"; shift 2 ;;
			--only=*) ONLY="${1#--only=}"; shift ;;
			# --only es interfaz INTERNA: lo que no se reconoce es un bug de quien
			# llama, no la entrada de un usuario. Ignorarlo daba el panel entero.
			*) printf 'dashboard: argumento desconocido: %s\n' "$1" >&2; return 2 ;;
		esac
	done
	# `--only` es INTERNO: lo invoca bundle_main con lo que da dcc_view_sections,
	# que ya son nombres canónicos. Si se hace público, sus alias van al catálogo.
	[ "$ONLY" = "all" ] && ONLY="$ALL_SECTIONS"

	# df.json (la llamada cara) solo se pide si alguna sección lo necesita.
	NEEDS_DF=0
	for s in summary volumes images disk; do want "$s" && NEEDS_DF=1; done

	# docker stats (~2 s) solo si se pintan stacks; en FAST se salta.
	NEEDS_STATS=0
	want stacks && [ "$FAST" != "1" ] && NEEDS_STATS=1
	return 0
}

# Por el socket y no por el CLI, que formatea los tamaños a texto ("407MB") e
# impide sumarlos. Su .Reclaimable NO se usa: con containerd no cuadra.
# Tarda ~8-15 s en frío, así que arranca al fondo cuanto antes.
start_slow_fetches() {
	DF_PID=""; STATS_PID=""
	if (( NEEDS_DF )) && [ "$FAST" != "1" ]; then
		if [ -S "$SOCK" ] && command -v curl >/dev/null && command -v jq >/dev/null; then
			curl -s --unix-socket "$SOCK" 'http://localhost/system/df' -o "$TMP/df.json" 2>/dev/null &
			DF_PID=$!
		else
			printf "${YE}%s${R}\n" "$(t warn_no_sizes)" >&2
			FAST=1
		fi
	fi
	# De los cgroups, que es 4 veces más rápido. Si no hay cgroup v2,
	# container-cpu.sh no imprime nada y ahí sí se cae a docker stats.
	if (( NEEDS_STATS )); then
		{
			container_cpu >"$TMP/stats.txt" 2>/dev/null
			[ -s "$TMP/stats.txt" ] || docker stats --no-stream \
				--format '{{.Name}}\t{{.CPUPerc}}' >"$TMP/stats.txt" 2>/dev/null
		} &
		STATS_PID=$!
	fi
}

# Aparte del resto de `docker info` por RENDIMIENTO: es lo mínimo que hace falta
# para disparar el curl, y juntarlo todo serializaba tres llamadas antes.
read_context() {
	CTX=$(docker context show 2>/dev/null || echo "?")
	SOCK=$(docker context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null || echo "")
	SOCK=${SOCK#unix://}
}

read_engine_info() {
	INFO=$(docker info --format '{{.ServerVersion}}|{{.NCPU}}|{{.Driver}}' 2>/dev/null) || return 1
	IFS='|' read -r VER NCPU DRV <<<"$INFO"
	RAM_MB=$(engine_ram 0 2>/dev/null)
}

read_containers() {
	PSDATA=$(docker ps -a --format \
		'{{.Names}}\t{{.State}}\t{{.Status}}\t{{.Ports}}\t{{.Image}}\t{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.service"}}')

	# Mapa volumen -> contenedores en UNA llamada, no una por volumen.
	# `--format '{{.Mounts}}'` no sirve: trunca los nombres.
	VOLMAP=$(docker ps -aq 2>/dev/null | xargs -r docker inspect \
		--format '{{.Name}}{{range .Mounts}}{{if eq .Type "volume"}} {{.Name}}{{end}}{{end}}' 2>/dev/null)

	N_ALL=$(awk 'NF' <<<"$PSDATA" | wc -l)
	N_UP=$(awk -F'\t' '$2=="running"' <<<"$PSDATA" | wc -l)
	N_STACKS=$(awk -F'\t' '$6!=""{print $6}' <<<"$PSDATA" | sort -u | wc -l)
}

# Lo único que importa aquí es el ORDEN: lo caro al fondo cuanto antes.
collect_data() {
	TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
	read_context
	start_slow_fetches
	read_engine_info || { printf "${RD}%s${R}\n" "$(tf err_daemon "${CTX:-?}")"; exit 1; }
	read_containers
	return 0
}

# Sobre VOLMAP en memoria: pura respecto a docker, se le inyecta desde los tests.
users_of_volume() {
	awk -v want="$1" '{
		for (i = 2; i <= NF; i++)
			if ($i == want) { sub(/^\//, "", $1); out = out (out ? "," : "") $1 }
	} END { print out }' <<<"$VOLMAP"
}

# Rellena M. Devuelve 1 si no hay datos y el llamador cae a modo sin-tamaños.
declare -A M
compute_metrics() {
	[ -n "$DF_PID" ] && { wait "$DF_PID" 2>/dev/null || true; }
	[ -s "$TMP/df.json" ] && jq -e . "$TMP/df.json" >/dev/null 2>&1 || return 1
	while IFS=$'\t' read -r k v; do M[$k]=$v; done < <(jq -r "$JQ_METRICS" "$TMP/df.json" | awk 'NF')
	return 0
}

# CPU[n] es el % crudo de docker (100% == un núcleo). CPU_HOST es la suma
# normalizada por NCPU: qué % de toda la máquina comen los contenedores.
declare -A CPU
CPU_HOST=""
load_stats() {
	[ -n "$STATS_PID" ] && { wait "$STATS_PID" 2>/dev/null || true; }
	[ -s "$TMP/stats.txt" ] || return 1
	while IFS=$'\t' read -r n c; do [ -n "$n" ] && CPU[$n]=$c; done <"$TMP/stats.txt"
	# LC_NUMERIC=C, o en es_ES saldría "0,9" junto a los puntos que da jq.
	CPU_HOST=$(LC_NUMERIC=C awk -F'\t' -v n="$NCPU" \
		'{gsub(/%/,"",$2); s+=$2} END{printf "%.1f", (n>0 ? s/n : 0)}' "$TMP/stats.txt")
	return 0
}

# "Up 15 hours (healthy)" -> "up 15h" + marca de salud, separados por TAB.
# El color NUNCA va aquí: printf cuenta los escapes ANSI como visibles.
fmt_status() {
	awk -v created="$(t st_created)" -v restarting="$(t st_restarting)" '{
		s=$0; h=""
		if (s ~ /unhealthy/)      h="!"
		else if (s ~ /starting/)  h="~"
		else if (s ~ /healthy/)   h="+"
		gsub(/ \(health.*\)|\(healthy\)|\(unhealthy\)|\(health: starting\)/, "", s)
		# Los tres casos con artículo van ANTES que la abreviatura genérica. Si no,
		# " minutes?" se come el " minute" de "About a minute" y deja "About am".
		gsub(/Less than a second/,"<1s",s)
		gsub(/About a minute/,"~1m",s); gsub(/About an hour/,"~1h",s)
		gsub(/ hours?/,"h",s); gsub(/ minutes?/,"m",s); gsub(/ seconds?/,"s",s)
		gsub(/ days?/,"d",s);  gsub(/ weeks?/,"w",s);   gsub(/ months?/,"mo",s)
		gsub(/ years?/,"y",s)
		gsub(/ ago/,"",s); gsub(/^Up /,"up ",s); gsub(/^Exited /,"exit ",s)
		gsub(/^Created/,created,s); gsub(/^Restarting/,restarting,s)
		gsub(/[()]/,"",s); gsub(/ +/," ",s); sub(/ +$/,"",s)
		print s "\t" h
	}'
}

# "0.0.0.0:8085->8080/tcp, [::]:8085->8080/tcp" -> "8085→8080"
fmt_ports() {
	# POSIX match/RSTART/RLENGTH a propósito: mawk (el awk por defecto de Ubuntu)
	# no soporta match($0, re, arr) de 3 argumentos, que es extensión de GNU.
	tr ',' '\n' <<<"$1" | awk '
		{
			if (match($0, /:[0-9]+->[0-9]+/)) {
				split(substr($0, RSTART + 1, RLENGTH - 1), p, "->")
				if (!(p[1] in seen)) { seen[p[1]]=1; o=o (o?" ":"") p[1] "→" p[2] }
			}
		}
		END { print o }'
}

# "Exited (137) 2 days ago" -> "137". El 8 mide "Exited (" y el 9 eso más el
# paréntesis: en UN sitio, porque lo usan dos awk distintos. Mismo truco que
# JQ_BYTES: el programa se compone anteponiendo la función.
AWK_EXIT_CODE='function xcode(s) { return match(s, /Exited \([0-9]+\)/) ? substr(s, RSTART + 8, RLENGTH - 9) : "" }'

exit_code() { awk "$AWK_EXIT_CODE"'{ c = xcode($0); if (c != "") print c }' <<<"$1"; }

# --- Secciones ----------------------------------------------------------------
render_header() {
	printf "\n${B}${CY}  DOCKER${R}  ${D}·${R}  %s  ${D}·${R}  %s ${B}%s${R}  ${D}·${R}  %s CPU  ${D}·${R}  %s  ${D}·${R}  %s ${B}%s MB${R}\n" \
		"$CTX" "$(t hdr_engine)" "$VER" "$NCPU" "$DRV" "$(t hdr_ram_host)" "${RAM_MB:-?}"
	rule
	printf "  ${B}%s %s${R} ${D}·${R} ${B}%s/%s${R} %s" \
		"$N_STACKS" "$(t hdr_stacks)" "$N_UP" "$N_ALL" "$(t hdr_containers_up)"
	[ -n "$CPU_HOST" ]    && printf " ${D}·${R} %s ${B}%s%%${R} ${D}%s${R}" "$(t hdr_cpu)" "$CPU_HOST" "$(t hdr_of_host)"
	[ -n "${M[disk]:-}" ] && printf " ${D}·${R} ${B}%s${R} %s" "${M[disk]}" "$(t hdr_on_disk)"
	printf "\n"
}

render_summary() {
	[ -n "${M[disk]:-}" ] || { printf "\n  ${YE}%s${R}\n" "$(t no_size_data)"; return; }
	printf "\n  ${B}%s${R} ${D}%s${R}\n" "$(t trash_title)" "$(t trash_sub)"
	row() { # nombre, tamaño, detalle, acción
		printf "    %s %s  ${D}%s${R}" "$(pad "$1" "$W_LABEL")" "${YE}$(rpad "$2" "$W_SIZE")${R}" "$(pad "$3" "$W_DETAIL")"
		[ -n "${4:-}" ] && printf "  ${CY}%s${R}" "$4"
		printf "\n"
	}
	(( ${M[cacheRaw]:-0} > 0 )) && row "$(t row_cache)"   "${M[cacheSz]}" "$(tf row_cache_detail "${M[cacheN]}")"   "$DCC_CMD clean-build"
	(( ${M[stopRaw]:-0}  > 0 )) && row "$(t row_stopped)" "${M[stopSz]}"  "$(tf row_stopped_detail "${M[stopN]}")"  "$DCC_CMD clean"
	(( ${M[imgRaw]:-0}   > 0 )) && row "$(t row_images)"  "${M[imgSz]}"   "${M[imgNames]}"                          "$DCC_CMD clean"
	(( ${M[volN]:-0}     > 0 )) && row "$(t row_volumes)" "${M[volSz]}"   "$(tf row_volumes_detail "${M[volN]}")"   "$DCC_CMD volumes-orphan"
	printf "    %s ${B}%s${R}  ${D}%s${R}\n" "$(pad "" "$W_LABEL")" "$(rpad "${M[trash]}" "$W_SIZE")" "$(t trash_verified)"
}

render_alerts() {
	# El código de salida ES señal: 0 = parada limpia, 137 = SIGKILL/OOM, resto =
	# murió mal. Se usa $1 (nombre del contenedor) y no $7 (servicio): "app" y
	# "dev" se repiten entre stacks y no identifican nada.
	local errc killc old
	errc=$(awk -F'\t' "$AWK_EXIT_CODE"'{
			c = xcode($3)
			if (c != "" && c != "0" && c != "137") print $1 " (" c ")"
		}' <<<"$PSDATA" | join_list)
	killc=$(awk -F'\t' '$3 ~ /Exited \(137\)/' <<<"$PSDATA" | wc -l)
	old=$(awk -F'\t' '$3 ~ /Exited/ && $3 ~ /(weeks?|months?)/ {print ($6 != "" ? $6 : $1)}' <<<"$PSDATA" | sort -u | join_list)

	[ -n "$errc" ] || (( killc > 0 )) || [ -n "$old" ] || return 0
	printf "\n"
	# La etiqueta se alinea con pad() y no con espacios a mano: cada idioma tiene
	# su longitud y a mano se descuadraría al traducir.
	[ -n "$errc" ]  && printf "  ${RD}⚠${R}  %s ${D}%s${R}\n" "$(pad "$(t alert_died)" "$W_ALERT")" "$errc"
	(( killc > 0 )) && printf "  ${YE}⚠${R}  %s ${D}%s${R}\n" "$(pad "$(tf alert_killed "$killc")" "$W_ALERT")" "$(t alert_killed_sub)"
	[ -n "$old" ]   && printf "  ${YE}⚠${R}  %s ${D}%s${R}\n" "$(pad "$(t alert_old)" "$W_ALERT")" "$old"
	# El estado de salida lo fijaba el ÚLTIMO `[ -n … ] &&`, así que la función
	# devolvía 1 justo cuando SÍ había algo que avisar y 0 cuando no había nada:
	# exactamente al revés de lo que cualquiera supondría.
	return 0
}

# Las piezas siguientes devuelven texto en vez de imprimir: eso es lo que las
# hace testeables. Van separadas por SEP porque el color va dentro y no se puede
# usar el espacio como separador.
stack_badge() {
	local up=$1 total=$2
	if   (( up == total )); then printf '%s' "${GR}●${R}${SEP}${GR}$(tf stack_up "$up" "$total")${R}"
	elif (( up == 0 ));     then printf '%s' "${D}○${R}${SEP}${D}$(tf stack_stopped "$total")${R}"
	else                         printf '%s' "${YE}◐${R}${SEP}${YE}$(tf stack_up "$up" "$total")${R}"
	fi
}

# El umbral rojo es 100 y no 90 porque el % de docker es "de UN core": pasado un
# núcleo entero, empieza a doler.
cpu_cell() {
	local state=$1 name=$2 cnum
	if [ "$state" != "running" ] || [ -z "${CPU[$name]:-}" ]; then
		printf '%s' "${D}${SEP}—"; return
	fi
	cnum=${CPU[$name]%\%}
	printf '%s' "$(awk -v x="${cnum:-0}" 'BEGIN{x+=0; print (x>=100?"'"$RD"'":x>=25?"'"$YE"'":x>=1?"'"$GR"'":"'"$D"'")}')"
	printf '%s' "$SEP"
	LC_NUMERIC=C awk -v x="${cnum:-0}" 'BEGIN{printf "%.1f%%", x+0}'
}

# El color del estado codifica la GRAVEDAD, no solo si está vivo: parada limpia
# en gris, SIGKILL en amarillo, cualquier otro código en rojo.
severity_cell() {
	local state=$1 ec=$2
	if [ "$state" = "running" ]; then printf '%s' "${GR}▸${R}${SEP}${R}"
	elif [ "$ec" = "0" ];        then printf '%s' "${D}▹${R}${SEP}${D}"
	elif [ "$ec" = "137" ];      then printf '%s' "${YE}▹${R}${SEP}${YE}"
	elif [ -n "$ec" ];           then printf '%s' "${RD}▹${R}${SEP}${RD}"
	else                              printf '%s' "${D}▹${R}${SEP}${D}"
	fi
}

health_mark() {
	case "$1" in
		'+') printf '%s' "${GR}✓${R}" ;; '!') printf '%s' "${RD}✗${R}" ;;
		'~') printf '%s' "${YE}◌${R}" ;; *)   printf ' ' ;;
	esac
}

render_container_row() {
	local name=$1 state=$2 status=$3 ports=$4 image=$5 svc=$6
	local st health po ec dot sc cpu cpc
	IFS=$'\t' read -r st health < <(fmt_status <<<"$status")
	po=$(fmt_ports "$ports")
	ec=$(exit_code "$status")
	IFS="$SEP" read -r cpc cpu < <(cpu_cell "$state" "$name")
	IFS="$SEP" read -r dot sc  < <(severity_cell "$state" "$ec")

	# pad() rellena el campo; el color se envuelve POR FUERA del texto ya alineado.
	printf "   %b %s %b%s%b %b%s%b %b %s ${D}%s${R}\n" \
		"$dot" "$(pad "${svc:-$name}" "$W_SERVICE")" \
		"$sc"  "$(pad "$st" "$W_STATUS")" "$R" \
		"$cpc" "$(rpad "$cpu" "$W_CPU")" "$R" \
		"$(health_mark "$health")" "$(pad "${po:--}" "$W_PORTS")" \
		"$(pad "$image" "$W_IMAGE")"
}

render_stacks() {
	local loose projects proj label rows total up icon cnt
	loose=$(t stack_loose)
	projects=$(awk -F'\t' -v l="$loose" '{print ($6==""?"\x7f" l:$6)}' <<<"$PSDATA" | sort -u)
	section "$(t sec_stacks_title)" "$(t sec_stacks_sub)"
	while read -r proj; do
		[ -z "$proj" ] && continue
		label=${proj#$'\x7f'}
		rows=$(awk -F'\t' -v p="$proj" -v l="$loose" '{k=($6==""?"\x7f" l:$6)} k==p' <<<"$PSDATA")
		total=$(wc -l <<<"$rows")
		up=$(awk -F'\t' '$2=="running"' <<<"$rows" | wc -l)

		IFS="$SEP" read -r icon cnt < <(stack_badge "$up" "$total")
		printf "\n %b ${B}%s${R}  %b\n" "$icon" "$(pad "$label" "$W_STACK")" "$cnt"

		# A 0x1f antes de leer: con IFS de tabulador bash colapsa dos seguidos, y
		# un contenedor sin puertos corre toda la fila (ver SEP en common.sh).
		local name state status ports image _proj svc
		while IFS="$SEP" read -r name state status ports image _proj svc; do
			[ -z "$name" ] && continue
			render_container_row "$name" "$state" "$status" "$ports" "$image" "$svc"
		done < <(tr '\t' '\037' <<<"$rows")
	done <<<"$projects"
}

render_volumes() {
	section "$(t sec_volumes_title)"
	# Una tabla con solo cabecera parece rota: si no hay volúmenes, dilo.
	if [ -z "$(docker volume ls -q)" ]; then
		printf "   ${D}%s${R}\n" "$(t vol_none)"; return
	fi
	printf "   ${D}%s %10s  %s${R}\n" "$(pad "$(t col_name)" "$W_VOLUME")" "$(t col_size)" "$(t col_usedby)"

	# nombre<TAB>tamaño<TAB>refs. Con df.json salen los tres; sin él no hay
	# tamaño ni recuento, y quién lo usa se saca igual de VOLMAP. Una sola fila
	# impresa: con dos printf, los formatos se van el uno del otro.
	volume_rows() {
		if [ -n "${M[disk]:-}" ]; then
			jq -r "$JQ_BYTES"' .Volumes[] | [.Name, (.UsageData.Size | h), (.UsageData.RefCount|tostring)] | @tsv' "$TMP/df.json"
		else
			docker volume ls -q | while IFS= read -r v; do printf '%s\t—\t\n' "$v"; done
		fi | sort
	}

	local v hs refs users
	while IFS=$'\t' read -r v hs refs; do
		users=$(users_of_volume "$v")
		[ "$refs" = "0" ] && users="${YE}$(t vol_orphan)${R}"
		printf "   %s %10s  %b\n" "$(pad "$v" "$W_VOLUME")" "$hs" "${users:-${YE}$(t vol_orphan)${R}}"
	done < <(volume_rows)
}

render_images() {
	[ -n "${M[disk]:-}" ] || { section "$(t sec_images_title)"; printf "   ${YE}%s${R}\n" "$(t no_size_data)"; return; }
	section "$(t sec_images_title)" "$(t sec_images_sub)"
	local repo hs cont mark
	jq -r "$JQ_BYTES"' .Images | sort_by(-.Size)[:6][]
		| [((.RepoTags // ["<none>:<none>"])[0]), (.Size | h), (.Containers|tostring)] | @tsv' "$TMP/df.json" \
	| while IFS=$'\t' read -r repo hs cont; do
		if [ "$cont" = "0" ]; then mark="${YE}⌀${R}"; else mark=" "; fi
		printf "   %b %10s  %s\n" "$mark" "$hs" "$(pad "$repo" "$W_REPO" | awk '{sub(/ +$/,""); print}')"
	done
}

render_disk() {
	[ -n "${M[disk]:-}" ] || { section "$(t sec_disk_title)"; printf "   ${YE}%s${R}\n" "$(t no_size_data)"; return; }
	section "$(t sec_disk_title)" "$(t sec_disk_sub)"
	printf "   %s %10s\n" "$(pad "$(t disk_layers)" "$W_LABEL")" "${M[layers]}"
	printf "   %s %10s\n" "$(pad "$(t disk_containers)" "$W_LABEL")" "${M[coTotal]}"
	printf "   %s %10s\n" "$(pad "$(t disk_volumes)" "$W_LABEL")" "${M[volTotal]}"
	printf "   %s %10s\n" "$(pad "$(t disk_cache)" "$W_LABEL")" "${M[bcTotal]}"
	printf "   %s ${B}%10s${R}\n" "$(pad "" "$W_LABEL")" "${M[disk]}"
}

# --- Orquestación -------------------------------------------------------------
render_all() {
	(( NEEDS_DF )) && [ "$FAST" != "1" ] && { compute_metrics || FAST=1; }
	(( NEEDS_STATS )) && load_stats

	render_header
	want summary && render_summary
	want alerts  && render_alerts
	want stacks  && render_stacks
	want volumes && render_volumes
	want images  && render_images
	want disk    && render_disk

	rule
	if [ "$ONLY" = "$ALL_SECTIONS" ]; then
		printf "  ${D}%s${R}\n\n" "$(t footer_full)"
	else
		printf "  ${D}%s${R}\n\n" "$(t footer_partial)"
	fi
	return 0
}

dashboard_main() {
	parse_args "$@" || return $?
	collect_data
	render_all
}

# Define al cargarse y solo ejecuta si lo lanzas directo: es lo que permite a los
# tests hacer source y probar fmt_status(), pad() o los render_* sin arrancar
# docker. Sin la guarda, un simple source tardaba 1,6 s.
if [ -z "${DCC_BUNDLE:-}" ] && [ "${BASH_SOURCE[0]}" = "${0}" ]; then
	dashboard_main "$@"
fi
