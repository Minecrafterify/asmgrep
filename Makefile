# asmgrep build system

NASM      ?= nasm
LD        ?= ld
CC        ?= gcc
CXX       ?= g++
PYTHON    ?= python3
JAVAC     ?= javac
JAR       ?= jar

PREFIX    ?= /usr
DESTDIR   ?=
BINDIR    ?= $(PREFIX)/bin
LIBDIR    ?= $(PREFIX)/lib
INCLUDEDIR?= $(PREFIX)/include
JAVADIR   ?= $(PREFIX)/share/java

VERSION   := 1.0.0
SOMAJOR   := 1
BUILD     := build
OBJDIR    := $(BUILD)/obj
INSTALL   ?= install

NASMFLAGS := -f elf64 -Icore/include/ -Wall
ifdef DEBUG
NASMFLAGS += -g -F dwarf
endif

CORE_SRC  := search_scalar search_sse2 lines mmap file utils
CORE_OBJ  := $(addprefix $(OBJDIR)/core/,$(addsuffix .o,$(CORE_SRC)))
LIB_OBJ   := $(CORE_OBJ) $(OBJDIR)/core/api.o
CLI_OBJ   := $(CORE_OBJ) $(OBJDIR)/cli/main.o $(OBJDIR)/cli/args.o $(OBJDIR)/cli/output.o

CLI       := $(BUILD)/asmgrep
LIBFILE   := $(BUILD)/libasmgrep.so.$(VERSION)
LIBSONAME := libasmgrep.so.$(SOMAJOR)

JAVA_HOME_GUESS := $(patsubst %/bin/javac,%,$(realpath $(shell command -v $(JAVAC) 2>/dev/null)))
JAVA_HOME ?= $(JAVA_HOME_GUESS)
JNI_LIB   := $(BUILD)/libasmgrep-jni.so
JAR_FILE  := $(BUILD)/asmgrep.jar

HAVE_JAVAC := $(shell command -v $(JAVAC) >/dev/null 2>&1 && test -f "$(JAVA_HOME)/include/jni.h" && echo yes)

.PHONY: all cli library python java test benchmark install uninstall clean check-tools

all: check-tools cli library
ifeq ($(HAVE_JAVAC),yes)
all: java
endif

check-tools:
	@command -v $(NASM) >/dev/null 2>&1 || { echo "error: nasm not found (set NASM=...)" >&2; exit 1; }
	@command -v $(LD) >/dev/null 2>&1 || { echo "error: ld not found (set LD=...)" >&2; exit 1; }

cli: check-tools $(CLI)
library: check-tools $(LIBFILE) $(BUILD)/libasmgrep.so $(BUILD)/$(LIBSONAME)

$(OBJDIR)/core/%.o: core/src/%.asm core/include/internal.inc
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) $< -o $@

$(OBJDIR)/cli/%.o: cli/%.asm core/include/internal.inc
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) $< -o $@

$(CLI): $(CLI_OBJ)
	$(LD) -z noexecstack -z relro -z now -o $@ $^

$(LIBFILE): $(LIB_OBJ) core/libasmgrep.map
	$(LD) -shared -z noexecstack -z relro -z now -soname $(LIBSONAME) \
		--version-script=core/libasmgrep.map -o $@ $(LIB_OBJ)

$(BUILD)/$(LIBSONAME): $(LIBFILE)
	ln -sf $(notdir $<) $@

$(BUILD)/libasmgrep.so: $(BUILD)/$(LIBSONAME)
	ln -sf $(LIBSONAME) $@

# ---- Java ------------------------------------------------------------------

JAVA_SRC := $(wildcard bindings/java/src/com/asmgrep/*.java)

java: check-tools library
	@command -v $(JAVAC) >/dev/null 2>&1 || { echo "error: javac not found (install a JDK 11+)" >&2; exit 1; }
	@test -f "$(JAVA_HOME)/include/jni.h" || { echo "error: jni.h not found; set JAVA_HOME to a JDK" >&2; exit 1; }
	@$(MAKE) --no-print-directory $(JAR_FILE) $(JNI_LIB)

$(JAR_FILE): $(JAVA_SRC)
	@mkdir -p $(BUILD)/java-classes
	$(JAVAC) --release 11 -d $(BUILD)/java-classes $(JAVA_SRC)
	$(JAR) cf $@ -C $(BUILD)/java-classes .

$(JNI_LIB): bindings/java/jni/asmgrep_jni.c include/asmgrep.h $(BUILD)/libasmgrep.so
	$(CC) -O2 -Wall -Wextra -fPIC -shared -Iinclude -I$(JAVA_HOME)/include -I$(JAVA_HOME)/include/linux \
		$< -o $@ -L$(BUILD) -lasmgrep -Wl,-rpath,'$$ORIGIN'

python: library
	@echo "Python package: bindings/python/asmgrep (pure ctypes, nothing to build)"

# ---- Tests and benchmarks --------------------------------------------------

test: all
	@tests/run_tests.sh

benchmark: cli
	@benchmarks/benchmark.sh

# ---- Installation ----------------------------------------------------------

PYTHON_SITE = $(shell $(PYTHON) -c "import sysconfig; print(sysconfig.get_path('purelib', 'posix_prefix', {'base': '$(PREFIX)', 'platbase': '$(PREFIX)'}))")

install: all
	$(INSTALL) -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(LIBDIR) $(DESTDIR)$(INCLUDEDIR)
	$(INSTALL) -m 0755 $(CLI) $(DESTDIR)$(BINDIR)/asmgrep
	$(INSTALL) -m 0755 $(LIBFILE) $(DESTDIR)$(LIBDIR)/libasmgrep.so.$(VERSION)
	ln -sf libasmgrep.so.$(VERSION) $(DESTDIR)$(LIBDIR)/$(LIBSONAME)
	ln -sf $(LIBSONAME) $(DESTDIR)$(LIBDIR)/libasmgrep.so
	$(INSTALL) -m 0644 include/asmgrep.h include/asmgrep.hpp $(DESTDIR)$(INCLUDEDIR)/
	$(INSTALL) -d $(DESTDIR)$(PYTHON_SITE)/asmgrep
	$(INSTALL) -m 0644 bindings/python/asmgrep/*.py $(DESTDIR)$(PYTHON_SITE)/asmgrep/
ifeq ($(HAVE_JAVAC),yes)
	$(INSTALL) -d $(DESTDIR)$(JAVADIR)
	$(INSTALL) -m 0644 $(JAR_FILE) $(DESTDIR)$(JAVADIR)/asmgrep.jar
	$(INSTALL) -m 0755 $(JNI_LIB) $(DESTDIR)$(LIBDIR)/libasmgrep-jni.so
endif
	@if [ -z "$(DESTDIR)" ] && [ "$$(id -u)" = 0 ]; then ldconfig 2>/dev/null || true; fi
	@echo "Installed asmgrep $(VERSION) under $(PREFIX)"

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/asmgrep
	rm -f $(DESTDIR)$(LIBDIR)/libasmgrep.so.$(VERSION) $(DESTDIR)$(LIBDIR)/$(LIBSONAME) \
		$(DESTDIR)$(LIBDIR)/libasmgrep.so $(DESTDIR)$(LIBDIR)/libasmgrep-jni.so
	rm -f $(DESTDIR)$(INCLUDEDIR)/asmgrep.h $(DESTDIR)$(INCLUDEDIR)/asmgrep.hpp
	rm -rf $(DESTDIR)$(PYTHON_SITE)/asmgrep
	rm -f $(DESTDIR)$(JAVADIR)/asmgrep.jar
	@if [ -z "$(DESTDIR)" ] && [ "$$(id -u)" = 0 ]; then ldconfig 2>/dev/null || true; fi

clean:
	rm -rf $(BUILD)
