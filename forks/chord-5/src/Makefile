# if you are compiling under DOS, you may have to replace all the ".o" extension
# by ".obj"
# Select the required paper size for your printer
PAPERSIZE = US
#PAPERSIZE = A4

# If your system does not have a getopt fonction, uncomment the next line
#GETOPT = getopt.o

# Use a ansi or K&R compiler
CC = gcc 
CFLAGS =

# where to put the resulting program
BINDIR = /usr/local/bin

# where to put the man page
MANDIR = /usr/local/man
MANEXT = 1

# You should not have to change anything below this line

# name of the program
PROGRAMS = chord  a2crd

INCL = chord.h getopt.h patchlevel.h
SRC = common.c xpose.c iso.c chord.c grid.c getopt.c toc.c chord.man Makefile a2crd.c
OBJ = common.o xpose.o iso.o chord.o grid.o toc.o  ${GETOPT}
SONGS = songs/space-oddity songs/heaven songs/everybody-hurts
DOCS = README chord_guide.ps license.txt a2crd.man a2crd.txt
RELNAME = chord36

all: $(PROGRAMS)

chord : $(OBJ) Makefile
	$(CC) $(CFLAGS) -o $@ $(OBJ)

a2crd: a2crd.o Makefile
	$(CC) $(CFLAGS) -o $@ a2crd.o common.o

chord.o    : chord.h
common.o   : chord.h
grid.o     : chord.h
xpose.o	   : chord.h
getopt.o   : getopt.h
toc.o	   : chord.h

install : all
	cp $(PROGRAMS) $(BINDIR)
	rm -f $(MANDIR)/cat$(MANEXT)/chord.$(MANEXT)
	cp chord.man $(MANDIR)/man$(MANEXT)/chord.$(MANEXT)
	chmod 666 $(MANDIR)/man$(MANEXT)/chord.$(MANEXT)
	cp a2crd.man $(MANDIR)/man$(MANEXT)/a2crd.$(MANEXT)
	chmod 666 $(MANDIR)/man$(MANEXT)/a2crd.$(MANEXT)

shar : $(SRC)
	rm -f $(RELNAME).part*
	shar -F -L 60 -o $(RELNAME).part $(SRC) $(INCL) $(SONGS) $(DOCS)

tar : $(SRC)
	tar cvf $(RELNAME).tar $(SRC) $(INCL) $(SONGS) $(DOCS)
	rm $(RELNAME).tar.Z
	compress -v $(RELNAME).tar

lint : $(SRC)
	lint $(SRC)

clean:
	rm -f core *.o chord a2crd 

