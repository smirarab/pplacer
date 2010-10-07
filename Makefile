RELEASE=placeviz pplacer placeutil 
MACRELEASE=placeviz placeutil

all: $(RELEASE)

mac: $(MACRELEASE)

$(RELEASE):
	if [ ! -e bin ]; then mkdir bin; fi
	make $@.native
	cp `readlink -f $@.native` bin/$@
	rm $@.native

%.native %.byte %.p.native:
	ocamlbuild $@

clean:
	rm -rf bin
	ocamlbuild -clean

%.top: %.byte
	find _build -regex .*cmo | sed 's/_build\///; s/.cmo//' > $*.mltop
	ocamlbuild $@

%.runtop: %.top
	ledit -x -h .toplevel_history ./$*.top

runcaml: 
	ledit -x -h .toplevel_history ocaml

tags:
	taggage *.ml

.PHONY: $(RELEASE) clean runcaml tags
