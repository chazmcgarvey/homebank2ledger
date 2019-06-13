
# This is not a Perl distribution, but it can build one using Dist::Zilla.

COVER   = cover
CPANM   = cpanm
DZIL    = dzil
PERL    = perl
PROVE   = prove

all: dist

bootstrap:
	$(CPANM) $(CPANM_FLAGS) -n Dist::Zilla
	$(DZIL) authordeps --missing |$(CPANM) $(CPANM_FLAGS) -n
	$(DZIL) listdeps --develop --missing |$(CPANM) $(CPANM_FLAGS) -n

clean:
	$(DZIL) $@

cover:
	$(COVER) -test

debug:
	$(PERL) -Ilib -d bin/homebank2ledger

dist:
	$(DZIL) build

distclean: clean
	rm -rf cover_db

run:
	$(PERL) -Ilib bin/homebank2ledger

test:
	$(PROVE) -l$(if $(findstring 1,$(V)),v) t

.PHONY: all bootstrap clean cover debug dist distclean run test

