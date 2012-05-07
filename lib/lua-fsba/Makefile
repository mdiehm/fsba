SIGNAL_DESTINATION ?= ../../
DESTINATION = $(SIGNAL_DESTINATION)

LIBRARY = fsba.so
OBJECTS = $(LIBRARY)

INSTALL = install -c -v
CC = gcc
CFLAGS = -W -Wall  -pedantic -std=c99 -D_GNU_SOURCE `pkg-config --cflags lua5.1` -fPIC

all: fsba.so

install: $(LIBRARY)
	$(INSTALL) -m 755 $(LIBRARY) $(DESTINATION)

clean:
	-rm $(OBJECTS)

fsba.so: fsba.c
	$(CC) $(CFLAGS) -shared -o $@ $^
