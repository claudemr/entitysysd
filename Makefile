DDOX = ../ddox/ddox

help:
	@echo "Generate ddox documentation:"
	@echo "    make doc"
	@echo "Clean all output files from doc:"
	@echo "    make clean"

doc:
	dmd -o- -c -D -Dddoc -X -Xfdoc/docs.json entitysysd/*.d
	$(DDOX) filter --min-protection=Public doc/docs.json \
		--ex entitysysd.pool --ex entitysysd.exception \
		--ex entitysysd.component
	$(DDOX) generate-html --navigation-type=ModuleTree \
		doc/docs.json doc/public

.PHONY: clean doc help

clean:
	rm doc/public/*.* 2>/dev/null; true
	rm -rf doc/public/entitysysd 2>/dev/null; true
