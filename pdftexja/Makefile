# pdfTeX-ja build / install.
#
# Committed (text, generated, checked for zero regeneration diff):
#   ptjfm-ujis.def ptjfm-ujisv.def   default JFM data (from LuaTeX-ja)
#   pdftexja-kinsoku.tex             default kinsoku table (from LuaTeX-ja)
# Built (not committed; derived from TeX Live fonts at build time):
#   fonts/  aux vertical TTF/TFM/enc shards + font profiles, HaranoAji TTFs
#
# Do not call the TEXMF tree variable TEXMF (kpathsea variable clash).
PTJ_TEXMF ?= $(shell kpsewhich -var-value=TEXMFHOME)

STY := pdftexja.sty pdftexja-core.sty pdftexja-jfmglue.sty \
	pdftexja-ruby.sty pdftexja-adjust.sty
JFMDEFS := ptjfm-ujis.def ptjfm-ujisv.def
KINSOKU := pdftexja-kinsoku.tex
TOOLS := pdftexja-jfmconv.lua pdftexja-mkkinsoku.lua pdftexja-mkfontprofile.py
FONTSETS := ipaex ipa haranoaji
FONTSTAMP := fonts/.stamp

.PHONY: all jfm kinsoku fonts check check-data check-fonts test install uninstall tds clean

all: jfm kinsoku fonts

jfm: $(JFMDEFS)
ptjfm-ujis.def: pdftexja-jfmconv.lua
	texlua pdftexja-jfmconv.lua --jfm=ujis --out=$@
ptjfm-ujisv.def: pdftexja-jfmconv.lua
	texlua pdftexja-jfmconv.lua --jfm=ujisv --out=$@

kinsoku: $(KINSOKU)
$(KINSOKU): pdftexja-mkkinsoku.lua
	texlua pdftexja-mkkinsoku.lua --out=$@

# The generator is deterministic (fixed dates, sorted output). ttf2tfm
# bakes its output path into the TFM header, so the outdir is relative.
fonts: $(FONTSTAMP)
$(FONTSTAMP): pdftexja-mkfontprofile.py
	@for fs in $(FONTSETS); do \
	  python3 pdftexja-mkfontprofile.py --fontset $$fs --outdir fonts || exit 1; \
	done
	@touch $@

# regeneration diff zero for the committed data
check-data:
	@tmp=`mktemp -d "$${TMPDIR:-/tmp}/pdftexja-check.XXXXXXXX"`; \
	trap 'rm -rf "$$tmp"' EXIT HUP INT TERM; \
	rc=0; \
	texlua pdftexja-jfmconv.lua --jfm=ujis --out=$$tmp/ptjfm-ujis.def || rc=1; \
	texlua pdftexja-jfmconv.lua --jfm=ujisv --out=$$tmp/ptjfm-ujisv.def || rc=1; \
	texlua pdftexja-mkkinsoku.lua --out=$$tmp/$(KINSOKU) || rc=1; \
	for f in $(JFMDEFS) $(KINSOKU); do \
	  cmp "$$tmp/$$f" "$$f" || { echo "FAIL: regenerated $$f differs"; rc=1; }; \
	done; \
	[ $$rc -eq 0 ] && echo "check-data: regeneration diff zero"; exit $$rc

# deterministic regeneration of the font assets
check-fonts: fonts
	@tmp=`mktemp -d "$${TMPDIR:-/tmp}/pdftexja-fonts.XXXXXXXX"`; \
	trap 'rm -rf "$$tmp"' EXIT HUP INT TERM; \
	cp -r fonts "$$tmp/regen" || exit 1; \
	rm -f $(FONTSTAMP); $(MAKE) fonts || exit 1; \
	diff -r -x .stamp "$$tmp/regen" fonts || { \
	  echo "FAIL: font regeneration is not byte-identical"; exit 1; }; \
	python3 tests/check-fontprofiles.py fonts $(addprefix pdftexja-fontprofile-,$(addsuffix .def,$(FONTSETS))) || exit 1; \
	echo "check-fonts: deterministic regeneration + structural checks OK"

test: all
	sh tests/run-tests.sh

check: check-data check-fonts test

install: all
	mkdir -p $(PTJ_TEXMF)/tex/latex/pdftexja
	install -m 644 $(STY) $(JFMDEFS) $(KINSOKU) $(PTJ_TEXMF)/tex/latex/pdftexja
	install -m 644 fonts/pdftexja-fontprofile-*.def $(PTJ_TEXMF)/tex/latex/pdftexja
	mkdir -p $(PTJ_TEXMF)/fonts/truetype/pdftexja
	install -m 644 fonts/*.ttf $(PTJ_TEXMF)/fonts/truetype/pdftexja
	mkdir -p $(PTJ_TEXMF)/fonts/tfm/pdftexja
	install -m 644 fonts/*.tfm $(PTJ_TEXMF)/fonts/tfm/pdftexja
	mkdir -p $(PTJ_TEXMF)/fonts/enc/pdftexja
	install -m 644 fonts/*.enc $(PTJ_TEXMF)/fonts/enc/pdftexja
	mkdir -p $(PTJ_TEXMF)/scripts/pdftexja
	install -m 644 $(TOOLS) $(PTJ_TEXMF)/scripts/pdftexja
	mkdir -p $(PTJ_TEXMF)/doc/latex/pdftexja
	install -m 644 README.md fonts/LICENSE-aux-*.txt $(PTJ_TEXMF)/doc/latex/pdftexja

uninstall:
	rm -rf $(PTJ_TEXMF)/tex/latex/pdftexja $(PTJ_TEXMF)/fonts/truetype/pdftexja \
	  $(PTJ_TEXMF)/fonts/tfm/pdftexja $(PTJ_TEXMF)/fonts/enc/pdftexja \
	  $(PTJ_TEXMF)/scripts/pdftexja $(PTJ_TEXMF)/doc/latex/pdftexja

tds: all
	$(MAKE) install PTJ_TEXMF=./tds

clean:
	rm -rf fonts tds
