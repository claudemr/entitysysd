_OBJ = component.o entity.o exception.o event.o package.o pool.o stat.o system.o
OBJ = $(patsubst %,out/%,$(_OBJ))
DDOX = ../ddox/ddox

help:
	@echo "Build and run unit-tests:"
	@echo "    make unittest"
	@echo "Generate ddox documentation:"
	@echo "    make doc"
	@echo "Clean all output files from unittest and doc:"
	@echo "    make clean"

#todo: Dependencies do not work if a module uses a template instance of another
#      module that gets recompiled.
out/%.o: entitysysd/%.d
	dmd -c -odout -unittest $<

unittest: $(OBJ)
	dmd $^ -unittest -main -odout -ofout/entitysysd_unittest
	out/entitysysd_unittest

doc:
	dmd -o- -c -D -Dddoc -X -Xfdoc/docs.json entitysysd/*.d
	$(DDOX) filter --min-protection=Public doc/docs.json \
		--ex entitysysd.pool --ex entitysysd.exception \
		--ex entitysysd.component
	$(DDOX) generate-html --navigation-type=ModuleTree \
		doc/docs.json doc/public

.PHONY: clean doc unittest help

clean:
	rm -rf out 2>/dev/null; true
	rm doc/public/*.* 2>/dev/null; true
	rm -rf doc/public/entitysysd 2>/dev/null; true
