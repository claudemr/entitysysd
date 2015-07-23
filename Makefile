_OBJ = component.o entity.o exception.o event.o package.o pool.o system.o
OBJ = $(patsubst %,out/%,$(_OBJ))

out/%.o: entitysysd/%.d
	dmd -c -odout -unittest $<

unittest: $(OBJ)
	dmd $^ -unittest -main -odout -ofout/entitysysd_unittest
	out/entitysysd_unittest

doc:
	dmd -o- -c -D -Dddoc -X -Xfdoc/docs.json entitysysd/*.d
	../ddox/ddox filter --min-protection=Public doc/docs.json \
		--ex entitysysd.pool --ex entitysysd.exception \
		--ex entitysysd.component
	../ddox/ddox generate-html --navigation-type=ModuleTree \
		doc/docs.json doc/public

.PHONY: clean unittest doc

clean:
	rm -rf out
	rm -rf doc
