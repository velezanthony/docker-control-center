# Makefile — SOLO el trabajo de desarrollo. Los comandos del producto viven en
# src/commands.txt y se usan por el fichero único: `make bundle && dcc dash`.

SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Colores ----------------------------------------------------------------------
C_RESET := \033[0m
C_BOLD  := \033[1m
C_DIM   := \033[2m
C_CYAN  := \033[36m
C_GREEN := \033[32m
C_YELL  := \033[33m
C_RED   := \033[31m

# El producto vive bajo src/; fuera quedan las herramientas, lo generado y docs.
SRC := $(CURDIR)/src

# Vendorizado, NO instalado en el sistema: `make deps` lo trae verificando sha256.
SHELLSPEC := $(CURDIR)/vendor/shellspec/shellspec

# En cada receta que imprima texto: son shells independientes.
I18N := . $(SRC)/scripts/common.sh;

# Posicional ACOTADO: solo cuando el primer objetivo es uno de estos, el resto de
# palabras pasan a ser reglas no-op. Fuera, make sigue avisando de tus typos.
ifneq ($(filter run dev lang,$(firstword $(MAKECMDGOALS))),)
  RUN_ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  ifneq ($(RUN_ARGS),)
    $(eval $(RUN_ARGS):;@:)
  endif
endif

##@ Setup

# Se le pasa este Makefile: solo tiene targets de desarrollo. La ayuda del
# producto sale de src/commands.txt y la pinta el fichero único.
.PHONY: help
help: ## Show this help
	@bash $(SRC)/scripts/help.sh $(firstword $(MAKEFILE_LIST))

.PHONY: deps
deps: ## Download the dev dependencies to vendor/ (see dependencies.txt)
	@bash $(CURDIR)/deps.sh $(FORCE)

$(SHELLSPEC):
	@bash $(CURDIR)/deps.sh

# El idioma es COMPARTIDO: se guarda en ~/.config/dcc/config, así que cambiarlo
# aquí lo cambia también en el fichero único, y al revés.
.PHONY: lang
lang: ## Show or change the interface language (shared with the bundle)
	@bash $(SRC)/scripts/lang.sh $(RUN_ARGS)

.PHONY: hooks
hooks: ## Install the pre-commit git hook (plain bash, nothing to install)
	@$(I18N) \
	printf '#!/usr/bin/env bash\nexec make -C "%s" check\n' "$(CURDIR)" >$(CURDIR)/.git/hooks/pre-commit; \
	chmod +x $(CURDIR)/.git/hooks/pre-commit; \
	printf "$(C_GREEN)%s$(C_RESET)\n" "$$(tf hooks_ok "$(CURDIR)/.git/hooks/pre-commit")"

##@ Tests

# Sin docker: datos inyectados. T filtra por fichero (T=common).
.PHONY: test
test: $(SHELLSPEC) ## Run the unit tests (no docker needed) [T=name]
	@$(SHELLSPEC) $(if $(T),$(SRC)/tests/$(T)_spec.sh)

# bundle_spec.sh es ~20 de los ~25 s de la suite. Se filtra por FICHERO porque
# `--tag` de ShellSpec solo sabe incluir, no excluir.
.PHONY: test-fast
test-fast: $(SHELLSPEC) ## Run only the fast tests (skips the bundle build)
	@$(SHELLSPEC) $(filter-out %/bundle_spec.sh,$(wildcard $(SRC)/tests/*_spec.sh))

# Qué se mide está en .shellspec. kcov SOBRESCRIBE el informe con lo que cubra
# cada invocación, así que un `--kcov <un_spec>` a mano deja una foto parcial
# idéntica en forma a la buena: mira su campo `command` antes de creértelo.
.PHONY: coverage
coverage: $(SHELLSPEC) ## Line coverage of src/scripts/ with kcov
	@$(I18N) \
	command -v kcov >/dev/null || { say need_kcov; exit 1; }
	@rm -rf $(CURDIR)/coverage
	@$(SHELLSPEC) --kcov

##@ Quality

# Los .jq se validan COMO SE EJECUTAN, con bytes.jq delante: por separado dan
# "h/0 is not defined". shellcheck en paralelo con N-2 núcleos (37 s -> 10 s, y
# dejando aire a lo que estés haciendo). Debe salir SIEMPRE limpio.
#
# Cubre también build.sh y deps.sh, que estaban FUERA: el empaquetador y el
# descargador de dependencias, o sea lo que genera lo que publicas y lo que se
# baja la gente.
#
# `-S style` es el umbral MÁS BAJO: enseña todo. Las `-o` son comprobaciones que
# shellcheck trae apagadas; están las SEIS que aquí dan cero falsos positivos.
# Las otras cinco, medidas y descartadas con motivo:
#
#   require-variable-braces      554 avisos  cosmético
#   check-extra-masked-returns   173         SC2312 por `$(t clave)` en printf
#   require-double-brackets      126         el proyecto usa [ ] a propósito
#   quote-safe-variables          20         cosmético
#   add-default-case               5         `case` de filtro: caer por defecto ES lo correcto
#
# Un linter con falsos positivos es un linter que se ignora.
.PHONY: lint
lint: ## Run shellcheck over every script
	@$(I18N) \
	if ! command -v shellcheck >/dev/null; then say lint_missing; exit 1; fi; \
	for q in $(SRC)/scripts/*.jq; do \
		case "$$q" in *bytes.jq) prog=$$(cat "$$q"; echo empty) ;; \
		              *)         prog=$$(cat $(SRC)/scripts/bytes.jq "$$q") ;; esac; \
		jq -n "$$prog" >/dev/null || { printf "$(C_RED)jq: %s$(C_RESET)\n" "$$q"; exit 1; }; \
	done; \
	if printf '%s\n' $(SRC)/scripts/*.sh $(SRC)/tests/*.sh $(CURDIR)/build.sh $(CURDIR)/deps.sh \
	   | xargs -P "$$(J=$$(nproc 2>/dev/null || echo 4); echo $$(( J > 2 ? J - 2 : 1 )))" \
	           -n 1 shellcheck -x -S style \
	             -o deprecate-which -o useless-use-of-cat -o check-set-e-suppressed \
	             -o avoid-nullary-conditions -o avoid-negated-conditions \
	             -o check-unassigned-uppercase; then \
		printf "$(C_GREEN)%s$(C_RESET)\n" "$$(t lint_ok)"; \
	else \
		printf "$(C_RED)%s$(C_RESET)\n" "$$(t lint_fail)"; exit 1; \
	fi

# Los specs quedan fuera: shfmt desangra el DSL a la columna 0.
.PHONY: fmt
fmt: ## Format the scripts with shfmt (specs excluded: shfmt breaks the DSL)
	@$(I18N) \
	command -v shfmt >/dev/null || { say need_shfmt; exit 1; }; \
	shfmt -w -ln bash -i 0 -ci $(SRC)/scripts/*.sh $(CURDIR)/build.sh $(CURDIR)/deps.sh; \
	printf "$(C_GREEN)%s$(C_RESET)\n" "$$(t fmt_ok)"

.PHONY: check
check: ## Lint + parseo + tests + empaquetado: todo antes de un commit
	@$(MAKE) --no-print-directory lint
	@$(I18N) \
	for f in $(SRC)/scripts/*.sh $(SRC)/tests/*.sh; do bash -n "$$f" || exit 1; done; \
	printf "$(C_GREEN)%s$(C_RESET)\n" "$$(t check_ok)"
	@$(MAKE) --no-print-directory test

##@ Release

BUNDLE_OUT := $(CURDIR)/dist/docker-control-center.sh

# ~/.local/bin porque en Debian/Ubuntu ya está en el PATH (~/.profile lo añade)
# y en Fedora también. En Arch o Alpine lo añades tú: por eso `link` comprueba.
LINK_DIR   ?= $(HOME)/.local/bin

# El bundle es un FICHERO con prerequisitos, no un target .PHONY: make solo lo
# regenera si algo de lo que entra dentro es más reciente. Así `run` no puede
# ejecutar un dist/ obsoleto —que era silencioso: editabas src/, olvidabas
# reconstruir y `make run` seguía corriendo el código viejo sin decir nada.
BUNDLE_SRC := $(CURDIR)/build.sh $(SRC)/commands.txt \
              $(wildcard $(SRC)/scripts/*.sh) $(wildcard $(SRC)/scripts/*.jq) \
              $(wildcard $(SRC)/i18n/*.sh)

$(BUNDLE_OUT): $(BUNDLE_SRC)
	@bash $(CURDIR)/build.sh

.PHONY: bundle
bundle: $(BUNDLE_OUT) ## Build dist/docker-control-center.sh: the whole tool in one file

# `|| true` porque el producto usa el código de salida como dato (1 = no existe,
# 2 = falta un argumento) y make lo tomaría por un fallo de la receta.
.PHONY: run
run: $(BUNDLE_OUT) ## Run the built bundle, rebuilding it if it went stale
	@$(BUNDLE_OUT) $(RUN_ARGS) || true

# Fuerza la reconstrucción aunque make la crea al día: el bucle de quien está
# tocando el código y quiere estar seguro.
.PHONY: dev
dev: ## Rebuild unconditionally and run: make dev dash
	@bash $(CURDIR)/build.sh >/dev/null
	@$(BUNDLE_OUT) $(RUN_ARGS) || true

# Enlace y NO copia: `make bundle` regenera dist/ y dcc apunta ya a lo nuevo.
.PHONY: link
link: $(BUNDLE_OUT) ## Symlink the bundle as `dcc` on your PATH
	@$(I18N) \
	mkdir -p "$(LINK_DIR)"; \
	ln -sf "$(BUNDLE_OUT)" "$(LINK_DIR)/dcc"; \
	printf "$(C_GREEN)%s$(C_RESET)\n" "$$(tf link_ok "$(BUNDLE_OUT)")"; \
	printf "$(C_DIM)%s$(C_RESET)\n" "$$(t link_hint)"; \
	case ":$$PATH:" in *":$(LINK_DIR):"*) ;; *) \
		printf "$(C_YELL)%s$(C_RESET)\n" "$$(tf link_not_in_path "$(LINK_DIR)")"; \
		printf "%s\n" "$$(t link_path_fix)"; \
		printf "$(C_CYAN)      echo 'export PATH=\"%s:\$$PATH\"' >> ~/.bashrc$(C_RESET)\n" "$(LINK_DIR)" ;; \
	esac

