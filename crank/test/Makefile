#
# unit test for crank.min
#

include .config
include $(crank)/debug.min

@@ ?= @
Q := $(findstring @,$(@@))
O = .built
OX = $O/.exists
mindeps = $(crank)/*.min


all: $O/defsOK $O/crankOK $O/copyOK $O/uiOK $O/phonyOK $O/projectOK $(OX)
	@true

$O/defsOK: defs_q.mak $(crank)/defs.min $(OX)
	$Q $(MAKE) -f defs_q.mak && touch $@

$O/crankOK: crank_q.mak $(mindeps) $(OX)
	$Q $(MAKE) -f crank_q.mak && touch $@

$O/copyOK: copy.mak $(mindeps) $(OX)
	$Q $(MAKE) -f copy.mak Copy Copy=copy.mak Copy.out='.built/$$I'
	$Q if [ ! -f $O/copy.mak ] ; then $(call dbg_fail,COPY01) ; fi
	$Q EVAR=X $(MAKE) -f copy.mak foo | $(call dbg_grep,EVAR= XAB,COPY02)
	$Q touch $@

$O/uiOK: ui.mak $(mindeps) $(OX)
	$Q $(MAKE) -f ui.mak open=ui | $(call dbg_grep,opening copy.mak,UI01)
	$Q $(MAKE) -f ui.mak open=ui.mak | $(call dbg_grep,opening ui.mak,UI02)
	$Q $(MAKE) -f ui.mak '$$(call get,quatloo,Copy,ui.mak)' 2>&1 | $(call dbg_grep,Undefined Property,UI03)
	$Q touch $@

$O/phonyOK: phony.mak $(mindeps) $(OX)
	$Q $(MAKE) crank=$(crank) -f phony.mak b V='1 2'  | sort | tr -d '\n' | $(call dbg_grep,A_1.*A_2.*B_1.*B_2,PHONY01)
	$Q $(MAKE) crank=$(crank) -f phony.mak a V='X' | $(call dbg_grep,A_X,PHONY02)
	$Q touch $@

$O/projectOK: project_q.mak $(crank)/project.mak $(mindeps) $(OX)
	$Q make -f $<
	$Q touch $@

$(OX):
	$Q mkdir -p $O
	$Q touch $@

clean:
	$Q $(MAKE) -f phony.mak clean
	$Q rm -rf $O
