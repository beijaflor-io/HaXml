SOFTWARE = HaXml
VERSION  = 1.25.3

#CPP      = cpp -traditional
CPP     = cpphs --text --noline	# useful e.g. on MacOS X

DIRS = Text Text/XML Text/XML/HaXml Text/XML/HaXml/Html \
	Text/XML/HaXml/Xtract Text/XML/HaXml/DtdToHaskell \
	Text/XML/HaXml/XmlContent Text/XML/HaXml/Schema

SRCS = \
	src/Text/XML/HaXml.hs src/Text/XML/HaXml/Combinators.hs \
	src/Text/XML/HaXml/Posn.hs src/Text/XML/HaXml/Lex.hs \
	src/Text/XML/HaXml/Parse.hs src/Text/XML/HaXml/Pretty.hs \
	src/Text/XML/HaXml/Types.hs src/Text/XML/HaXml/Validate.hs \
	src/Text/XML/HaXml/Namespaces.hs \
	src/Text/XML/HaXml/Wrappers.hs \
	src/Text/XML/HaXml/Verbatim.hs src/Text/XML/HaXml/Escape.hs \
	src/Text/XML/HaXml/OneOfN.hs \
	src/Text/XML/HaXml/ParseLazy.hs \
	src/Text/XML/HaXml/ByteStringPP.hs \
	src/Text/XML/HaXml/TypeMapping.hs \
	src/Text/XML/HaXml/XmlContent.hs \
	src/Text/XML/HaXml/XmlContent/Parser.hs \
	src/Text/XML/HaXml/XmlContent/Haskell.hs \
	src/Text/XML/HaXml/SAX.hs \
	src/Text/XML/HaXml/ShowXmlLazy.hs \
	src/Text/XML/HaXml/Util.hs \
	src/Text/XML/HaXml/Html/Generate.hs src/Text/XML/HaXml/Html/Parse.hs \
	src/Text/XML/HaXml/Html/Pretty.hs \
	src/Text/XML/HaXml/Html/ParseLazy.hs \
	src/Text/XML/HaXml/Xtract/Combinators.hs \
	src/Text/XML/HaXml/Xtract/Lex.hs \
	src/Text/XML/HaXml/Xtract/Parse.hs \
	src/Text/XML/HaXml/DtdToHaskell/TypeDef.hs \
	src/Text/XML/HaXml/DtdToHaskell/Convert.hs \
	src/Text/XML/HaXml/DtdToHaskell/Instance.hs \
	src/Text/XML/HaXml/Schema/XSDTypeModel.hs \
	src/Text/XML/HaXml/Schema/HaskellTypeModel.hs \
	src/Text/XML/HaXml/Schema/Parse.hs \
	src/Text/XML/HaXml/Schema/PrettyHaskell.hs \
	src/Text/XML/HaXml/Schema/PrettyHsBoot.hs \
	src/Text/XML/HaXml/Schema/Environment.hs \
	src/Text/XML/HaXml/Schema/NameConversion.hs \
	src/Text/XML/HaXml/Schema/TypeConversion.hs \
	src/Text/XML/HaXml/Schema/PrimitiveTypes.hs \
	src/Text/XML/HaXml/Schema/Schema.hs \

TOOLSRCS = \
	src/tools/DtdToHaskell.hs src/tools/Xtract.hs src/tools/Validate.hs \
	src/tools/Canonicalise.hs src/tools/MkOneOf.hs \
	src/tools/CanonicaliseLazy.hs \
	src/tools/XsdToHaskell.hs \

AUX =	configure Makefile src/Makefile src/pkg.conf docs/* examples/* \
	README LICENCE* COPYRIGHT script/echo.c rpm.spec Build.bat \
	HaXml.cabal Setup.hs
ALLFILES = $(SRCS) $(TOOLSRCS) $(AUX)

.PHONY: all libs tools haddock install register

COMPILERS = $(shell cat obj/compilers)
LIBS  = $(patsubst %, libs-%, $(COMPILERS))
TOOLS = $(patsubst %, tools-%, $(COMPILERS))
INSTALL = $(patsubst %, install-%, $(COMPILERS))
FILESONLY = $(patsubst %, install-filesonly-%, $(COMPILERS))

all: $(LIBS) $(TOOLS)
libs: $(LIBS)
tools: $(TOOLS)
install: $(INSTALL)
install-filesonly: $(FILESONLY)
libs-ghc:
	cd obj/ghc; $(MAKE) HC=$(shell cat obj/ghccmd) libs
libs-nhc98:
	cd obj/nhc98; $(MAKE) HC=nhc98 libs
libs-hugs:
	@echo "No building required for Hugs version of HaXml libs."
tools-ghc:
	cd obj/ghc; $(MAKE) HC=$(shell cat obj/ghccmd) toolset
tools-nhc98:
	cd obj/nhc98; $(MAKE) HC=nhc98 toolset
tools-hugs:
	@echo "No building required for Hugs version of HaXml tools."
install-ghc:
	cd obj/ghc; $(MAKE) HC=$(shell cat obj/ghccmd) install-ghc
install-nhc98:
	cd obj/nhc98; $(MAKE) HC=nhc98 install-nhc98
install-hugs:
	hugs-package src
	cd obj/hugs; $(MAKE) install-tools-hugs
install-filesonly-ghc:
	cd obj/ghc; $(MAKE) HC=$(shell cat obj/ghccmd) install-filesonly-ghc
install-filesonly-nhc98:
	cd obj/nhc98; $(MAKE) HC=nhc98 install-filesonly-nhc98
install-filesonly-hugs: install-hugs
haddock:
	mkdir -p docs/HaXml
	for dir in $(DIRS); \
		do mkdir -p docs/HaXml/src/$$dir; \
		done
	for file in $(SRCS); \
		do $(CPP) -D__NHC__=120 -DMYVERSION="\"$(VERSION)\"" $$file >$$file.uncpp.hs; \
		   HsColour -anchor -html $$file >docs/HaXml/`dirname $$file`/`basename $$file .hs`.html; \
		done
	haddock --html --title=HaXml --odir=docs/HaXml \
		--source-module="src/%{MODULE/.//}.html" \
		--source-entity="src/%{MODULE/.//}.html#%{NAME}" \
		$(patsubst %, %.uncpp.hs, $(SRCS))
	rm -f $(patsubst %, %.uncpp.hs, $(SRCS))

# packaging a distribution

srcDist: $(ALLFILES) haddock
	rm -f $(SOFTWARE)-$(VERSION).tar $(SOFTWARE)-$(VERSION).tar.gz
	mkdir $(SOFTWARE)-$(VERSION)
	tar cf - $(ALLFILES) | ( cd $(SOFTWARE)-$(VERSION); tar xf - )
	tar cf $(SOFTWARE)-$(VERSION).tar $(SOFTWARE)-$(VERSION)
	rm -rf $(SOFTWARE)-$(VERSION)
	gzip $(SOFTWARE)-$(VERSION).tar

zipDist: $(ALLFILES) haddock
	rm -f $(SOFTWARE)-$(VERSION).zip
	mkdir $(SOFTWARE)-$(VERSION)
	tar cf - $(ALLFILES) | ( cd $(SOFTWARE)-$(VERSION); tar xf - )
	zip -r $(SOFTWARE)-$(VERSION).zip $(SOFTWARE)-$(VERSION)
	rm -rf $(SOFTWARE)-$(VERSION)


# clear up rubbish
clean:
	rm -rf obj/ghc obj/nhc98 obj/hugs
	cd examples;    rm -f *.hi *.o
realclean: clean
	rm -f DtdToHaskell Xtract Validate Canonicalise MkOneOf
	rm -f CanonicaliseLazy

