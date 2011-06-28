include ../config.mk

OBJS = server_io buf_io http http_svr http_client
INTF = $(foreach obj, $(OBJS),$(obj).cmi)
LIBS = http_svr.cma http_svr.cmxa

all: $(INTF) $(LIBS)

bins: $(PROGRAMS)

libs: $(LIBS)

http_svr.cmxa: $(foreach obj,$(OBJS),$(obj).cmx)
	$(OCAMLOPT) $(OCAMLOPTFLAGS) -a -o $@ $(foreach obj,$(OBJS),$(obj).cmx)

http_svr.cma: $(foreach obj,$(OBJS),$(obj).cmo)
	$(OCAMLC) -a -o $@ $(foreach obj,$(OBJS),$(obj).cmo)

%.cmo: %.ml %.cmi
	$(OCAMLC) -c $(RPCLIGHTFLAGS) -thread -I ../rpc-light -I ../stdext -I ../log -o $@ $<

%.cmi: %.mli
	$(OCAMLC) -c -I ../rpc-light -thread -o $@ $<

%.cmx: %.ml %.cmi
	$(OCAMLOPT) $(OCAMLOPTFLAGS) $(RPCLIGHTFLAGS) -c -thread -I ../rpc-light -I ../stdext -I ../log -o $@ $<

%.o: %.c
	$(CC) $(CFLAGS) -c -o $@ $<

META: META.in
	sed 's/@VERSION@/$(VERSION)/g' < $< > $@

.PHONY: install
install: path = $(DESTDIR)$(shell ocamlfind printconf destdir)
install: $(LIBS) META
	mkdir -p $(path)
	ocamlfind install -destdir $(path) -ldconf ignore http-svr META $(INTF) $(LIBS) *.a *.cmx $(SPOT)

.PHONY: uninstall
uninstall:
	ocamlfind remove http-svr

.PHONY: doc
doc: $(INTF)
	python ../doc/doc.py $(DOCDIR) "http-svr" "package" "$(OBJS)" "." "log,stdext" ""

clean:
	rm -f *.o *.so *.a *.cmo *.cmi *.cma *.cmx *.cmxa *.annot $(SPOT) $(LIBS) $(PROGRAMS)
