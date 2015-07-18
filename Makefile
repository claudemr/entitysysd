_OBJ = component.o entity.o event.o package.o pool.o system.o
OBJ = $(patsubst %,out/%,$(_OBJ))

out/%.o: entitysysd/%.d
	dmd -c -D -Dddoc -odout $<

unittest: $(OBJ)
	dmd $^ -unittest -main -odout -ofout/entitysysd_unittest
	out/entitysysd_unittest

.PHONY: clean unittest

clean:
	rm -rf out
	rm -rf doc
