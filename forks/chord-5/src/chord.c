static char SccsId[] = "@(#)chord.c	4.0\t Feb. 2003";
static char copyright[] = "Copyright 1991-1995 by Martin Leclerc & Mario Dorion";
/***************************************************************************
 * File: chord.c
 * Project: chord
 *
 * Description:
 *   This is the main module of the 'chord' utility that reads
 *   text files containing songs with "chordPro" mark-up and
 *   produces PostScript for song sheets with the chords
 *   positioned above the lyrics and chord grids at the end
 *   for the chords used in the song.
 *
 * File history:
 *
 * o 1995: chord 3.6 released
 *
 * o 2002-02    Daniel A. Glasser
 *     New version, based on the original code, by Daniel Glasser,
 *     renamed to version 5.0 due to the number of changes and
 *     additions.  Skipped version 4.0 because it's been a while since
 *     version 3.6 was released.
 *     - Reformated source code, adding numerous comments in the process.
 *     - Changed internal handling of various font names/sizes to use a
 *       table instead of global pointers and integers.
 *     - Changed how the directives are recognized and processed from an
 *       if-elseif-elseif-elseif-...-elseif-else chain to a table lookup
 *       and a switch.  Further code simplification may follow.
 *     - Got rid of the default < RC-file < command-line < song-file settings
 *       management and replaced it with default (with rc-file and command line
 *       overrides) < song-file settings management.  The rc file no longer is
 *       processed after each song file.
 *     - Added support for directory-local and system chord RC files, along with
 *       optional environment specification of each.
 *       The order that the RC files are read in is system then user then local
 *       directory.  The environment variables are named "CHORDRCSYS" for the
 *       system, "CHORDRC" for the user, and "CHORDRCLOCAL" for the directory
 *       local files.  This was partly done to allow for multiple form 
 *       definitions in the system rc file.  For now, the system RC file
 *       is named "/usr/local/etc/chordrc", but that will eventually be
 *       a configuration option.
 *     - Fixed problems with {textfont: } and {chordfont: } directives
 *     - Added automatic adjusting of chord definitions where the base-fret offset
 *       might not allow the dots to fall within the grid.
 *     - Made the form (page dimensions) selectable at runtime rather than having
 *       to recompile to get Letter vs. A4 output.  This required changing how the
 *       form metrics were coded into the source.
 *     - Added V4 (ChordPro Manager) directive support
 *       + {start_of_bridge} / {end_of_bridge} / {sob} / {eob}
 *       + {start_of_block: label} / {end_of_block} / {soblk} / {eoblk}
 *       + {chord: name 1 2 3 4 5 6 offset}
 *       + {old_define} / {new_define}
 *       + {two_column_on} / {two_column_off} / {tcon} / {tcoff}
 *     - Extended the typeface size directives to accept relative size settings
 *       as well as absolute.
 *     - Added V5 (extended) directives
 *       + {version: markup-lang-version}
 *         This directive is mainly for forward compatibility.  There are some
 *         subtle side effects of some of the new features.  Every attempt has
 *         been made to keep the default behavior the same unless a new feature
 *         overrides it, such as the comment font and size being the same as
 *         the lyrics text font and size, and the tab font size being two
 *         points smaller than the lyrics text font size, and so on.  If you
 *         override one of these items, however, those related sizes are no
 *         longer linked.  Future additions to the mark-up language may
 *         introduce so many of these that having a version number associated
 *         with a given song file will help the program figure out just what
 *         old behaviors it needs to exhibit for the file.
 *       + {auto_space_on} / {auto_space_off}
 *         Allows local control within a song file.  If auto-space is turned
 *         on on the command line with the '-a' switch, however, {auto_space_off}
 *         has no effect.
 *       + {comment_font: postscript-font} / {comment_size: points}
 *         Control the typeface and display size of the comments
 *         specified in {comment: } and {comment_box: } directives.
 *         Use of these directives unlinks the comment text from
 *         lyrics text.
 *       + {comment_italic_font: postscript-font} / {comment_italic_size: points}
 *         Control the typeface and display size of the comments
 *         specified in {comment_italic: } directives.
 *         Use of these directives unlinks the comment text from
 *         chord font.
 *       + {tab_font: postscript-font} / {tab_size: points}
 *         Control the typeface and display size of the text
 *         displayed between {start_of_tab} and {end_of_tab} directives.
 *         Use of these directives unlinks the tab text size from
 *         lyrics text size (by default, the tab_size is 2 points smaller
 *         than the lyrics text size).
 *       + {paper_type: formname}
 *         (rc file only)
 *         This directive allows you to select which output form (paper-type)
 *         the output is to be printed on.  Built-in values are 'a4', 'letter',
 *         and 'mletter'.  'mletter' is the same paper dimensions as 'letter',
 *         but has slightly narrower margins to allow a bit more room on the
 *         page for lyrics.
 *       + {form_spec: formname top width left bottom}
 *         (rc file only)
 *         Allows you to define metrics for the form that the output will be
 *         printed on.  For the moment, only one 'user' form can be defined,
 *         but before this code is released to the general public, multiple
 *         forms will be specified within an rc file and selected on the
 *         command line or through a later {paper_type: } directive.
 *       + {conditional_break: lines}
 *         This (currently experimental) directive introduces a column
 *         or page break if there is insufficient room remaining above the
 *         bottom margin for the specified number of lines.
 *       + {set_indent: points}
 *         Sets the indent for the block and bridge.  For now, this is in
 *         points, but in the future, various measurement systems will be
 *         useable.
 *       + {enable_extensions} / {disable_extensions}
 **************************************************************************/

#include "chord.h"

static FILE *source_fd;

/* The built-in forms supported */
/*   name,     top-margin, bottom-margin, left-margin,     right-extent */
page_info form_table[] =
{
    {"a4",     A4_TOP,     A4_BOTTOM,     A4_L_MARGIN,     A4_WIDTH },
    {"letter", LETTER_TOP, LETTER_BOTTOM, LETTER_L_MARGIN, LETTER_WIDTH},
    {"mletter", MLETTER_TOP, MLETTER_BOTTOM, MLETTER_L_MARGIN, MLETTER_WIDTH},
    {NULL, 0, 0, 0, 0} /* must be last in the list */
};

/* the default page description, based on compiler locale */
page_info page_desc = {"default", TOP, BOTTOM, L_MARGIN, WIDTH};

char text_line[MAXLINE],  /* Lyrics Buffer */
    chord[MAXTOKEN],	  /* Buffer for the name of the chord */
    title1[MAXLINE];	  /* Holds the first title line */

char source[MAXTOKEN],
    directive[MAXLINE];	/* Buffer for the directive */

char i_input;		/* Input line pointer */

/* place to store the font info at runtime */
font_info font_table[NUMFONTS];

char
    mesgbuf[MAXTOKEN],
    *mesg,
    *current_file,
    *chord_line[MAXLINE],
    *command_name;

int c,			/* Current character in input file */
    i_chord,		/* Index to 'chord' */
    i_directive,		/* Index to 'directive' */
    i_text, 		/* Index to 'text_line' */
    in_chord,		/* Booleans indicating parsing status */
    left_foot_even = -1,	 /* 0 for even page numbers on the right */
				/* 1 for even page numbers on the left */
    no_grid, no_grid_default,
    page_label = 1,		/* physical page number */
    lpage_label = 1,	/* logical page number */
    i_chord_ov,		/* Overflow Booleans */
    pagination = 1,		/* virtual pages per physical pages */
    transpose = 0,		/* transposition value */
    vpos,			/* Current PostScript position, in points */
    col_vpos,		/* Beginning height of column, in points */
    min_col_vpos = TOP,	/* lowest colums ending */
    hpos,
    h_offset = 0, 		/* horizontal offset for multi-col output */
    start_of_chorus,	/* Vertical positions of the chorus */
    end_of_chorus,
    cur_text_size = 0,
    grid_size,
    n_pages = 1,		/* total physical page counter */
    v_pages = 1,		/* virtual pages */
    n_lines = 1,		/* line number in input file */
    max_columns = 1,	/* number of columns */
    n_columns = 0,		/* counter of columns */
    song_pages = 1,		/* song page counter */
    blank_space = 0,	/* consecutive blank line counter */
    warning_level = 0;      /* how much warning do we want? */

int h_indent = 0;           /* indent for blocks (bridge/block) */
int h_indent_default = 0;   /* indent for blocks (bridge/block) */
int language_version = DEF_CP_VER;   /* language version */
int language_version_default = DEF_CP_VER;

int 		/* BOOLEANS */
    number_all = FALSE,	/* number the first page (set with -p 1) */
    lyrics_only = FALSE,
    dump_only = FALSE,
    in_tab = FALSE,
    in_block = FALSE,       /* block active */
    postscript_dump = FALSE,
    auto_space = FALSE,	/* applies lyrics_only when no chords */
    auto_space_default = FALSE,
    need_soc = FALSE,
    do_toc = FALSE,
    no_easy_grids = FALSE,
    i_directive_ov = FALSE,
    i_text_ov = FALSE,
    in_directive = FALSE,
    in_chordrc = FALSE,
    first_time_in_chordrc = TRUE,
    in_chorus = FALSE,
    has_directive = FALSE,
    has_chord = FALSE,
    title1_found = FALSE,
    number_logical = FALSE,
    new_define_format = FALSE,   /* for Chord Pro Manager support */
    auto_adjust = TRUE,          /* Auto-adjust some chord definitions */
    enable_extensions = FALSE,   /* Enable extensions */
    debug_mode = FALSE;

float
    chord_inc,
    scale = 1.0,		/* Current scale factor */
    rotation = 0.0,		/* Current rotation */
    page_ratio;                 /* (TOP+BOTTOM)/WIDTH */

extern int nb_chord, first_ptr;
extern struct chord_struct *so_chordtab;
extern struct toc_struct *so_toc ;

extern char *optarg;
extern int optind, opterr;

/* --------------------------------------------------------------------------------*/
void ps_fputc(fd, c)
    FILE *fd;
    int c;
{
    if (c >128)
    {
	fprintf (fd, "\\%o", c);
    }
    else 
	switch ((char)c)
	{
	    case ')' :
		fprintf (fd, "\\%c", c); break;
	    case '(' :
		fprintf (fd, "\\%c", c); break;
	    case '\\' :
		fprintf (fd, "\\\\", c); break;
	    default:
		fprintf (fd, "%c",c);
	}
}
/* --------------------------------------------------------------------------------*/
void ps_fputs(fd, string)
    FILE *fd;
    char *string;
{
    int i;

    /* sprintf (mesg, "ps_fputs:%s ",string); debug(mesg); */

    for (i= 0; string[i] != '\0'; i++)
	ps_fputc (fd, string[i]);

}


/* --------------------------------------------------------------------------------*/
void ps_puts(string)
    char *string;
{
    ps_fputs(stdout, string);
}
/* --------------------------------------------------------------------------------*/
void set_text_font(size)
    int size;
{
    if (( size != cur_text_size))
    {
	/* we may be setting a special size rather than using the
	 * normal text size, so we use the passed size here.
	 */
	printf ("/TEXT_FONT { /%s findfont %d scalefont } def\n",
		font_table[FONT_TEXT].name, size);
	re_encode (font_table[FONT_TEXT].name);

	/* if we're being maximally compatible with the old program
	 * track the changes in the text font with the comment and
	 * tab (mono-spaced) fonts.
	 */
	if ((!enable_extensions) && (size == font_table[FONT_TEXT].size))
	{
	    set_comment_font();
	    set_comment_italic_font();
	    set_tab_font();
	}

	/* keep track of the size that Postscript now knows about */
	cur_text_size = size;

	/* sprintf(mesg, "Changing text size to %d", size); debug (mesg); */
    }
}

/* --------------------------------------------------------------------------------*/
void use_text_font()
{
    if (! in_tab)
    {   /* not tab */
	printf ("TEXT_FONT setfont\n"); /* use the text font */
    }
    else
    {   /* seems to be tab */
	use_tab_font();                /* use the mono-spaced font */
    }
}

/* --------------------------------------------------------------------------------*/
void set_tab_font()
{
    int size;

    if (enable_extensions)
    {   /* the size of the tab font is independant of the text font */
	size = font_table[FONT_MONO].size;
    }
    else
    {   /* the size of the tab font follows the size of the text font */
#define	MONO_SIZE_DECR	2	/* TABsize is smaller by this nb of points */
	size = font_table[FONT_TEXT].size - MONO_SIZE_DECR;
#undef MONO_SIZE_DECR
    }

    printf ("/MONO_FONT { /%s findfont %d scalefont } def\n",
	    font_table[FONT_MONO].name, size);
    re_encode (font_table[FONT_MONO].name);
} /* end of set_tab_font() */

/* --------------------------------------------------------------------------------*/
void use_tab_font()
{
    printf ("MONO_FONT setfont\n");
} /* end of use_tab_font */

/* --------------------------------------------------------------------------------*/
void set_comment_font()
{
    if (!enable_extensions)
    {   /* for non-extended, the text font is used for the comments */
	strcpy(font_table[FONT_COMMENT].name,
	       font_table[FONT_TEXT].name);
	font_table[FONT_COMMENT].size = font_table[FONT_TEXT].size;
    }

    printf ("/COMMENT_FONT { /%s findfont %d scalefont } def\n", 
	    font_table[FONT_COMMENT].name,
	    font_table[FONT_COMMENT].size);
    re_encode (font_table[FONT_COMMENT].name);
} /* end of set_comment_font */

/* --------------------------------------------------------------------------------*/
void use_comment_font()
{
    printf ("COMMENT_FONT setfont\n");
} /* end of use_comment_font() */

/* --------------------------------------------------------------------------------*/
void set_comment_italic_font()
{
    if (!enable_extensions)
    {   /* for non-extended, the chord font is used for the italic comments,
	 * though the text font size is used
	 */
	strcpy(font_table[FONT_COMMENT_ITAL].name,
	       font_table[FONT_CHORD].name);
	font_table[FONT_COMMENT_ITAL].size = font_table[FONT_TEXT].size;
    }

    printf ("/COMMENT_ITALIC_FONT { /%s findfont %d scalefont } def\n", 
	    font_table[FONT_COMMENT_ITAL].name,
	    font_table[FONT_COMMENT_ITAL].size);
    re_encode (font_table[FONT_COMMENT_ITAL].name);
} /* end of set_comment_font */

/* --------------------------------------------------------------------------------*/
void use_comment_italic_font()
{
    printf ("COMMENT_ITALIC_FONT setfont\n");
} /* end of use_comment_font() */


/* --------------------------------------------------------------------------------*/
void do_translate(vert, horiz)
    float vert, horiz;
{
    printf ("%f %f translate\n", vert , horiz );
    debug ("changing translation");
}
/* --------------------------------------------------------------------------------*/
void do_start_of_page()
/*logical page ! */
{
    v_pages++;
    lpage_label++;

    if (v_pages == 1)
    {
	n_pages++;
	page_label++;
	printf ("%%%%Page: \"%d\" %d\n",n_pages, n_pages);
	printf ("%%%%BeginPageSetup\n");
	if (pagination > 1)
	{
	    printf ("gsave\n");
	    printf ("%f %f scale\n", scale, scale);
	    printf ("%f rotate\n",rotation);
	}
	printf ("%%%%EndPageSetup\n");
    }

    if (pagination== 4)
    {
	if (v_pages== 1) do_translate(page_desc.l_margin, (page_desc.top+page_desc.bottom)*1.05);
	else if (v_pages== 2) do_translate(page_desc.width-page_desc.l_margin, 0.0);
	else if (v_pages== 3) do_translate(-(page_desc.width-page_desc.l_margin), -page_desc.top*1.05);
	else if (v_pages== 4) do_translate(page_desc.width-page_desc.l_margin, 0.0);
    }

    if (pagination== 2)
	if (v_pages == 1)
	{
	    do_translate (0.0, -(page_desc.top+page_desc.bottom+page_desc.l_margin/scale));
	}
	else if (v_pages == 2)
	    do_translate(page_desc.width, 0.0);

    vpos = page_desc.top;
    min_col_vpos = page_desc.top;
    hpos = page_desc.l_margin;
    n_columns = 0;
    song_pages++;
    set_text_font(font_table[FONT_TEXT].size); /*28/4/94 ML */
    if ( in_chorus )
    {
	start_of_chorus = vpos;
    }
}

/* --------------------------------------------------------------------------------*/
void use_chord_font()
{
    printf ("CHORD_FONT setfont\n");
}

/* --------------------------------------------------------------------------------*/
void set_chord_font()
{
    printf ("/CHORD_FONT { /%s findfont %d scalefont } def\n",
	    font_table[FONT_CHORD].name,
	    font_table[FONT_CHORD].size);
    re_encode (font_table[FONT_CHORD].name);
    if (!enable_extensions)
    {
	set_comment_italic_font();
    }
}

/* --------------------------------------------------------------------------------*/
void do_help (command) 
    char *command;
{
    fprintf (stderr, "Usage: %s [options] file [file ...]\n", command);
    fprintf (stderr, "Options:\n");
    fprintf (stderr, "	-A                 : About CHORD...\n");
    fprintf (stderr, "	-a                 : Automatic single space lines without chords\n");
    fprintf (stderr, "	-c n               : Set chord size [9]\n");
    fprintf (stderr, "	-C postscript_font : Set chord font\n");
    fprintf (stderr, "	-D                 : Dumps chords definitions (PostScript)\n");
    fprintf (stderr, "	-d                 : Dumps chords definitions (Text)\n");
    fprintf (stderr, "      -e                 : Disable extensions\n");
    fprintf (stderr, "	-E                 : Enable extensions\n");
    fprintf (stderr, "	-G                 : Disable printing of chord grids\n");
    fprintf (stderr, "	-g                 : Don't print grids for builtin \"easy\" chords.\n");
    fprintf (stderr, "	-h                 : This message\n");
    fprintf (stderr, "	-i                 : Generates a table of contents\n");
    fprintf (stderr, "	-J                 : Turn off auto-adjust\n");
    fprintf (stderr, "	-L                 : Even pages numbers on left\n");
    fprintf (stderr, "	-l                 : Only print lyrics\n");
    fprintf (stderr, "	-n                 : Number logical pages, not physical\n");
    fprintf (stderr, "	-o filename        : Saves the output to file\n");
    fprintf (stderr, "	-P formname        : specifies the form (A4, letter)\n");
    fprintf (stderr, "	-p n               : Starting page number [1]\n");
    fprintf (stderr, "	-s n               : Set chord grid size [30]\n");
    fprintf (stderr, "	-t n               : Set text size [12]\n");
    fprintf (stderr, "	-T postscript_font : Set text font\n");
    fprintf (stderr, "	-V                 : Print version and patchlevel\n");
    fprintf (stderr, "	-W n               : Set warning verbosity level\n");
    fprintf (stderr, "	-x n               : Transpose by 'n' half-tones\n");
    fprintf (stderr, "	-2                 : 2 pages per sheet\n");
    fprintf (stderr, "	-4                 : 4 pages per sheet\n");

    exit(0);
}

/* --------------------------------------------------------------------------------*/
void do_about ()
{
    printf("CHORD: A lyrics and chords formatting program.\n");
    printf("===== \n");
    printf("\n");;
    printf("CHORD will read an ASCII file containing the lyrics of one or many\n");
    printf("songs plus chord information. CHORD will then generate a photo-ready,\n");
    printf("professional looking, impress-your-friends sheet-music suitable for printing\n");
    printf("on your nearest PostScript printer.\n");
    printf("\n");
    printf("To learn more about CHORD, look for the man page or do \"chord -h\" for\n");
    printf("the list of options.\n");
    printf("\n");
    printf("			--0--\n");
    printf("\n");
    printf("Copyright (C) 1991-1995 by Martin Leclerc & Mario Dorion\n");
    printf("Modifications 2003 by Daniel Glasser\n");
    printf("\n");
    printf("This program is free software; you can redistribute it and/or modify\n");
    printf("it under the terms of the GNU General Public License as published by\n");
    printf("the Free Software Foundation; either version 2 of the License, or\n");
    printf("(at your option) any later version.\n");
    printf("\n");
    printf("This program is distributed in the hope that it will be useful,\n");
    printf("but WITHOUT ANY WARRANTY; without even the implied warranty of\n");
    printf("MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the\n");
    printf("GNU General Public License for more details.\n");
    printf("\n");
    printf("You should have received a copy of the GNU General Public License\n");
    printf("along with this program; if not, write to the Free Software\n");
    printf("Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.\n");
    printf("\n");
    printf("Send all questions, comments and bug reports to the original authors:\n");

    printf("	Martin.Leclerc@Sun.COM and Mario.Dorion@Sun.COM\n");
    printf("\n");
}

/* --------------------------------------------------------------------------------*/
#define STYLE_COMMENT        1    /* the "normal" {comment} style */
#define STYLE_COMMENT_ITALIC 2    /* the italic {comment_italic} style */
#define STYLE_COMMENT_BOX    3    /* the boxed {comment_box} style */
void do_comment(comment, style)
    char 	*comment;
    int	style;
{
    if (comment == NULL)
    {
	error ("Null comment.");
	return;
    }
    for (; *comment == ' '; comment++); /* strip leading blanks */
    advance(blank_space);
    blank_space = 0;
    text_line[i_text] = '\0';

    switch (style) {
	case STYLE_COMMENT:
	    advance(font_table[FONT_COMMENT].size);
	    use_comment_font();
	    printf (".9  setgray\n");
	    printf ("%d  setlinewidth\n", font_table[FONT_COMMENT].size);
	    printf ("newpath\n");
	    printf ("%d %d moveto\n", hpos - 2, vpos +
		    font_table[FONT_COMMENT].size / 2 - 2);
	    printf ("(");
	    ps_puts(comment);
	    printf (" ) stringwidth rlineto\n");
	    printf ("stroke\n");
	    printf ("%d %d moveto\n", hpos, vpos);
	    printf ("0  setgray\n");
	    printf ("1 setlinewidth\n");
	    printf ("(");
	    ps_puts(comment);
	    printf (") show\n");
	    break;

	case STYLE_COMMENT_ITALIC:
	    advance(font_table[FONT_COMMENT_ITAL].size);
	    use_comment_italic_font();
	    printf ("%d %d moveto\n", hpos, vpos);
	    printf ("(");
	    ps_puts(comment);
	    printf (") show\n");
	    break;

	case STYLE_COMMENT_BOX:
	    advance(font_table[FONT_COMMENT].size);
	    use_comment_font();
	    printf ("newpath\n");
	    printf ("%d %d moveto\n",hpos + 2, vpos - 2);
	    printf ("(");
	    ps_puts(comment);
	    printf (") stringwidth /vdelta exch def /hdelta exch def\n");
	    printf ("hdelta vdelta rlineto 0 %d rlineto hdelta neg 0 rlineto closepath\n",
		    font_table[FONT_COMMENT].size);
	    printf ("stroke\n");
	    printf ("%d %d moveto\n", hpos, vpos);
	    printf ("0  setgray\n");
	    printf ("(");
	    ps_puts(comment);
	    printf (") show\n");
	    break;

	default:
	    sprintf(mesg, "internal error: invalid comment type %d", style);
	    error (mesg);
	    break;
    }
	
    use_text_font();
    i_text = 0;
}

/* --------------------------------------------------------------------------------*/
void do_chorus_line()
{
    printf ("1  setlinewidth\n");
    printf ("newpath\n");
    printf ("%d %d moveto\n", hpos - 10, start_of_chorus);
    printf ("0 %d rlineto\n", -(start_of_chorus - end_of_chorus));
    printf ("closepath\n");
    printf ("stroke\n");
}
/* --------------------------------------------------------------------------------*/
void do_chord (i_text, chord)
    int i_text;
    char *chord;
{
    int j;
    struct chord_struct *ct_ptr;
    if ((transpose != 0) && (strcmp(toupper_str(chord), NO_CHORD_STR)))
	if (do_transpose (chord) != 0)
	{
	    sprintf (mesg, "Don't know how to transpose [%s]", chord);
	    error (mesg);
	}
			
    for (j= i_text; chord_line[j] != NULL; j++);
		
    if (j < MAXLINE)
	if (strcmp(toupper_str(chord), NO_CHORD_STR)) 
	{
	    ct_ptr = add_to_chordtab(chord);
	    chord_line[j] = ct_ptr->chord->chord_name;
	}
	else	chord_line[j] = NO_CHORD_STR;
	
}

/* --------------------------------------------------------------------------------*/
void print_chord_line ()
{
    int i, j;		/* Counter */
	
    printf ("/minhpos %d def\n", hpos);

    for (j= 0; j<MAXLINE; j++)
    {
	if (chord_line[j] != NULL )
	{
	    use_text_font();

	    printf ("(" ); 
	    for (i= 0; (i<j) && (text_line[i] != '\0');
		 ps_fputc (stdout,text_line[i++]));

	    printf (") stringwidth  pop %d add \n", hpos);
	    printf ("dup minhpos lt\n");
	    printf ("     {pop minhpos} if\n");
	    printf ("dup /minhpos exch (");
	    ps_puts(chord_line[j]);
	    printf (") stringwidth pop add def\n");
	    printf ("%d moveto\n",vpos);


	    use_chord_font();
	    printf ("(");
	    ps_puts(chord_line[j]);
	    printf (") show\n");
		
	    chord_line[j]= NULL;
	}
    }
}

/* --------------------------------------------------------------------------------*/
void init_ps()
{
    printf ("%%!PS-Adobe-1.0\n");
    printf ("%%%%Title: A song\n");
    printf ("%%%%Creator: Martin Leclerc & Mario Dorion\n");
    printf ("%%%%Pages: (atend)\n");
    printf ("%%%%BoundingBox: 5 5 605 787\n");
    printf ("%%%%EndComments\n");
    printf ("/inch {72 mul } def\n");

    print_re_encode();
    set_chord_font();
    set_text_font(font_table[FONT_TEXT].size);
    set_tab_font();
    set_comment_font();
    set_comment_italic_font();
    do_init_grid_ps();

    printf ("%%%%EndProlog\n");

    printf ("%%%%Page: \"%d\" %d\n",n_pages, n_pages);
    printf ("%%%%BeginPageSetup\n");
    if (pagination > 1)
    {
	printf ("gsave\n");
	printf ("%f %f scale\n", scale, scale);
	printf ("%f rotate\n", rotation);
    }
    printf ("%%%%EndPageSetup\n");

    vpos = page_desc.top;
    hpos = page_desc.l_margin;
    n_columns=0;

    if (pagination== 4)
	do_translate ( page_desc.l_margin, page_desc.top+page_desc.bottom);
    else if (pagination== 2) 
    {
	do_translate (0.0, -(page_desc.top+page_desc.bottom+page_desc.l_margin/scale));
    }
}


/* --------------------------------------------------------------------------------*/
void do_page_numbering(pnum)
    int pnum;
{
    printf ("1  setlinewidth\n");
    printf ("0  setgray\n");
    printf ("newpath\n");
    printf ("%f %f 10 sub moveto\n", page_desc.l_margin, page_desc.bottom); 
    printf ("%f 0 rlineto\n", page_desc.width - page_desc.l_margin * 2);
    printf ("stroke\n");

    set_text_font(DEF_TEXT_SIZE - 2);
    use_text_font();
    if (page_label % 2 == left_foot_even)  /* left side */
    {
	printf ("1 inch %f 3 div moveto\n", page_desc.bottom); 
	if (pagination == 2)
	    printf ("-500 0 rmoveto\n");
	printf ("(Page %d)\n", pnum);
    }
    else                               /* right side */
    { 
	printf ("(Page %d) dup stringwidth pop\n", pnum);
	printf ("%f exch sub 1 inch sub %f 3 div moveto\n",
		page_desc.width, page_desc.bottom); 
    }
    printf ("show\n");
}
/* --------------------------------------------------------------------------------*/
void do_end_of_phys_page()
/* physical */
{
    /*debug ("end_of_phys_page");*/

    /* restore full page mode  if necessary */
    if (pagination > 1)
	printf ("grestore\n");

    if (! number_logical)
    {
	if (number_all) 
	    do_page_numbering(page_label);
	else if (song_pages > 1)
	    do_page_numbering(song_pages);
    }

    printf ("showpage\n");
    printf ("%%%%EndPage: \"%d\" %d\n",n_pages, n_pages);

    lpage_label += pagination-v_pages;
}

/* --------------------------------------------------------------------------------*/
void do_end_of_page(force_physical)
    int	force_physical;
/* Logical */
{

    if ((song_pages > 1) && title1_found) 
    {
	set_text_font(DEF_TEXT_SIZE - 2);
	use_text_font();
	printf ("(");
	ps_puts(&title1[0]);
	printf (") dup stringwidth pop 2 div\n");
	printf ("%f 2 div exch sub %f 3 div moveto\n",
		page_desc.width, page_desc.bottom);
	printf ("show\n");
	set_text_font(font_table[FONT_TEXT].size);
    }

    if (number_logical)
    {
	if (number_all)
	    do_page_numbering(lpage_label);
	else if (song_pages > 1)
	    do_page_numbering(song_pages);
    }

    if ( in_chorus )
    {
	end_of_chorus = vpos;
	do_chorus_line();
    }

    if ((v_pages == pagination) || force_physical) 
    {
	do_end_of_phys_page();
	v_pages = 0;
    }
    n_columns = 0;
    min_col_vpos = page_desc.top;
    col_vpos = page_desc.top;
}

/* --------------------------------------------------------------------------------*/
void do_end_of_column()
{
    if (n_columns == (max_columns-1))
    {
	do_end_of_page(FALSE);
	do_start_of_page();
    }
    else
    {
	n_columns++;
	if (vpos < min_col_vpos )
	    min_col_vpos = vpos;
	vpos = col_vpos;
	hpos = page_desc.l_margin + (n_columns * h_offset);
    }
}
/* --------------------------------------------------------------------------------*/
void do_end_of_song()
{
    if ((! lyrics_only && ! no_grid)) 
    {
	if (min_col_vpos < vpos )
	    vpos = min_col_vpos;
	draw_chords();
    }
    do_end_of_page(FALSE);
}
		 
void init_paper_size()
{
    min_col_vpos = page_desc.top;	/* lowest colums ending */
    page_ratio = ((page_desc.top+page_desc.bottom)/page_desc.width);
}

void set_paper_type(form)
    char *form;
{
    int i;
    char *form_name;
    form_name = tolower_str(form);
    i = 0;
    while (form_table[i].form_name != NULL)
    {
	if (!strcmp(form_name, form_table[i].form_name))
	{  /* found it */
	    page_desc = form_table[i]; /* structure copy */
	    return;
	}
	++i;
    }
    sprintf(mesg, "Page type %s is not supported", form);
    error(mesg);
} /* end of set_paper_type() */

void init_defaults()
{
    char *tmp;
    tmp = strcpy(font_table[FONT_TEXT_DEFAULT].name, DEF_TEXT_FONT);
    strcpy(font_table[FONT_TEXT].name, tmp);
    font_table[FONT_TEXT_DEFAULT].size = DEF_TEXT_SIZE;
    tmp = strcpy(font_table[FONT_CHORD_DEFAULT].name, DEF_CHORD_FONT);
    strcpy(font_table[FONT_CHORD].name, tmp);
    font_table[FONT_CHORD_DEFAULT].size = DEF_CHORD_SIZE;
    tmp = strcpy(font_table[FONT_MONO_DEFAULT].name, MONOSPACED_FONT);
    strcpy(font_table[FONT_MONO].name, tmp);
#define	MONO_SIZE_DECR	2	/* TABsize is smaller by this nb of points */
    font_table[FONT_MONO_DEFAULT].size = DEF_TEXT_SIZE - MONO_SIZE_DECR;
#undef MONO_SIZE_DECR
    strcpy(font_table[FONT_COMMENT_DEFAULT].name, 
	   strcpy(font_table[FONT_COMMENT].name, DEF_TEXT_FONT));
    font_table[FONT_COMMENT_DEFAULT].size = DEF_TEXT_SIZE;
    font_table[FONT_COMMENT].size = DEF_TEXT_SIZE;
    strcpy(font_table[FONT_COMMENT_ITAL_DEF].name, 
	   strcpy(font_table[FONT_COMMENT_ITAL].name, DEF_CHORD_FONT));
    font_table[FONT_COMMENT_ITAL_DEF].size = DEF_TEXT_SIZE;
    font_table[FONT_COMMENT_ITAL].size = DEF_TEXT_SIZE;

    grid_size = DEF_GRID_SIZE;
    no_grid = no_grid_default = FALSE;
    auto_space = auto_space_default = FALSE;
    n_columns = 0;
    max_columns = 1;
    dummy_kcs.chord_name[0]='\0';
    h_indent = h_indent_default = 0;
    language_version = language_version_default = DEF_CP_VER;
} /* end of init_defaults() */

void reset_to_defaults()
{
    char *tmp;
    tmp = font_table[FONT_TEXT_DEFAULT].name;
    strcpy(font_table[FONT_TEXT].name, tmp);
    font_table[FONT_TEXT].size = font_table[FONT_TEXT_DEFAULT].size;
    tmp = font_table[FONT_CHORD_DEFAULT].name;
    strcpy(font_table[FONT_CHORD].name, tmp);
    font_table[FONT_CHORD].size = font_table[FONT_CHORD_DEFAULT].size;
    tmp = font_table[FONT_MONO_DEFAULT].name;
    strcpy(font_table[FONT_MONO].name, tmp);
    font_table[FONT_MONO].size = font_table[FONT_MONO_DEFAULT].size;
    strcpy(font_table[FONT_COMMENT].name, 
	   font_table[FONT_COMMENT_DEFAULT].name);
    font_table[FONT_COMMENT].size = font_table[FONT_COMMENT_DEFAULT].size;
    strcpy(font_table[FONT_COMMENT_ITAL].name, 
	   font_table[FONT_COMMENT_ITAL_DEF].name);
    font_table[FONT_COMMENT_ITAL].size = font_table[FONT_COMMENT_ITAL_DEF].size;

    n_columns = 0;
    max_columns = 1;
    dummy_kcs.chord_name[0]='\0';
    no_grid = no_grid_default;
    auto_space = auto_space_default;
    h_indent = h_indent_default;
    language_version = language_version_default;
} /* end of reset_to_defaults */


/* --------------------------------------------------------------------------------*/
void do_new_song()
{
    do_end_of_song();
    nb_chord= first_ptr= 0;
    song_pages = 0;
    in_tab = FALSE;
    in_block = FALSE;
    title1[0] = '\0';
    do_start_of_page();

    /* reset default */
    reset_to_defaults();
    clean_known_chords();
    clean_chordtab();

    set_text_font(font_table[FONT_TEXT].size);
    set_tab_font();
    set_chord_font();
    set_comment_font();
    set_comment_italic_font();
}
/* --------------------------------------------------------------------------------*/
void advance(amount)
    int amount;
{
    vpos = vpos - amount;     /* Affect text positionning ! */
    if (vpos < page_desc.bottom )
    {
	/* do_end_of_page(FALSE); */
	do_end_of_column();
	/* do_start_of_page(); */
    }
}

/* --------------------------------------------------------------------------------*/
void print_text_line()
{
    int i;

    text_line[i_text] = '\0';

    for (i= 0; text_line[i] == ' '; i++);

    if (!((auto_space || in_tab)  && !has_chord))
    {
	advance(blank_space);
	blank_space = 0;
	advance (font_table[FONT_CHORD].size + 1);

	if ( ( text_line[i] != '\0' )
	     && ( vpos - font_table[FONT_TEXT].size <= page_desc.bottom))
	    advance (font_table[FONT_TEXT].size);

	if (need_soc)
	{
	    start_of_chorus = vpos + font_table[FONT_CHORD].size;
	    need_soc = FALSE;
	}
	if ((! lyrics_only) && has_chord)
	    print_chord_line();
    }

    if ( text_line[i] == '\0')
    {
	blank_space += font_table[FONT_TEXT].size - 2;
    }
    else
    {
	advance (blank_space);
	blank_space = 0;
	advance (font_table[FONT_TEXT].size - 1);
	if (need_soc)
	{
	    start_of_chorus = vpos + font_table[FONT_TEXT].size;
	    need_soc = FALSE;
	}
	use_text_font();
	printf ("%d %d moveto\n", hpos, vpos);
	printf ("(");
	ps_puts(&text_line[0]);
	printf (") show\n");
    }

    i_text = 0;
    i_text_ov = FALSE;
    /* hpos = page_desc.l_margin; */
    has_chord = FALSE;
}

/* --------------------------------------------------------------------------------*/
void do_title(title)
    char	*title;
{

    set_text_font (font_table[FONT_TEXT].size+5);
    use_text_font();
    printf ("(");
    ps_puts(title);
    printf (") dup stringwidth pop 2 div\n");
    printf ("%f 2 div exch sub %d moveto\n", page_desc.width, vpos);
    printf ("show\n");
    vpos = vpos - font_table[FONT_TEXT].size - 5;
    /* skip blanks */
    while ( *title == ' ') title++;

    strcpy (&title1[0], title);
    title1_found = TRUE;
    set_text_font (font_table[FONT_TEXT].size);
    if (do_toc && song_pages == 1)	/* generate index entry */
	add_title_to_toc(title, number_logical ? lpage_label : page_label);
}
/* --------------------------------------------------------------------------------*/
void do_subtitle(sub_title)
    char	*sub_title;
{
    use_text_font();
    printf ("(");
    ps_puts(sub_title);
    printf (") dup stringwidth pop 2 div\n");
    printf ("%f 2 div exch sub %d moveto\n", page_desc.width , vpos);
    printf ("show\n");
    vpos = vpos - font_table[FONT_TEXT].size;
    if (do_toc && song_pages == 1)
	add_subtitle_to_toc(sub_title);
}
	

/* This table contains the various names of commands and
   the dispatch number for each, thus allowing there to be
   aliases of each command.  Note that there is no order
   restriction on this table except that the COMND_INVALID
   entry must be the last one in the table.  If the table
   is ordered as most frequently used to least frequently
   used, the efficiency of the program will be increased
   substantially.
*/

directive_entry command_table[] = {
    {COMND_START_OF_CHORUS, "start_of_chorus"},
    {COMND_START_OF_CHORUS, "soc"},
    {COMND_END_OF_CHORUS,   "end_of_chorus"},
    {COMND_END_OF_CHORUS,   "eoc"},
    {COMND_TEXTFONT,        "textfont"},
    {COMND_TEXTFONT,        "tf"},
    {COMND_CHORDFONT,       "chordfont"},
    {COMND_CHORDFONT,       "cf"},
    {COMND_CHORDSIZE,       "chordsize"},
    {COMND_CHORDSIZE,       "cs"},
    {COMND_TEXTSIZE,        "textsize"},
    {COMND_TEXTSIZE,        "ts"},
    {COMND_COMMENT,         "comment"},
    {COMND_COMMENT,         "c"},
    {COMND_COMMENT_ITALIC,  "comment_italic"},
    {COMND_COMMENT_ITALIC,  "ci"},
    {COMND_COMMENT_BOX,     "comment_box"},
    {COMND_COMMENT_BOX,     "cb"},
    {COMND_NEW_SONG,        "new_song"},
    {COMND_NEW_SONG,        "ns"},
    {COMND_TITLE,           "title"},
    {COMND_TITLE,           "t"},
    {COMND_SUBTITLE,        "subtitle"},
    {COMND_SUBTITLE,        "st"},
    {COMND_DEFINE,          "define"},
    {COMND_DEFINE,          "d"},
    {COMND_NO_GRID,         "no_grid"},
    {COMND_NO_GRID,         "ng"},
    {COMND_GRID,            "grid"},
    {COMND_GRID,            "g"},
    {COMND_NEW_PAGE,        "new_page"},
    {COMND_NEW_PAGE,        "np"},
    {COMND_START_OF_TAB,    "start_of_tab"},
    {COMND_START_OF_TAB,    "sot"},
    {COMND_END_OF_TAB,      "end_of_tab"},
    {COMND_END_OF_TAB,      "eot"},
    {COMND_COLUMN_BREAK,    "column_break"},
    {COMND_COLUMN_BREAK,    "colb"},
    {COMND_COLUMNS,         "columns"},
    {COMND_COLUMNS,         "col"},
    {COMND_NEW_PHYS_PAGE,   "new_physical_page"},
    {COMND_NEW_PHYS_PAGE,   "npp"},
    {COMND_CHORD,           "chord"},           /* Chord Pro Manager compat */
    {COMND_START_OF_BRIDGE, "start_of_bridge"}, /* Chord Pro Manager compat */
    {COMND_START_OF_BRIDGE, "sob"},             /* Chord Pro Manager compat */
    {COMND_END_OF_BRIDGE,   "end_of_bridge"},   /* Chord Pro Manager compat */
    {COMND_END_OF_BRIDGE,   "eob"},             /* Chord Pro Manager compat */
    {COMND_START_OF_BLOCK,  "start_of_block"},  /* Chord Pro Manager compat */
    {COMND_START_OF_BLOCK,  "soblk"},           /* Chord Pro Manager compat */
    {COMND_END_OF_BLOCK,    "end_of_block"},    /* Chord Pro Manager compat */
    {COMND_END_OF_BLOCK,    "eoblk"},           /* Chord Pro Manager compat */
    {COMND_TWO_COLUMN_ON,   "two_column_on"},   /* Chord Pro Manager compat */
    {COMND_TWO_COLUMN_ON,   "tcon"},            /* Chord Pro Manager compat */
    {COMND_TWO_COLUMN_OFF,  "two_column_off"},  /* Chord Pro Manager compat */
    {COMND_TWO_COLUMN_OFF,  "tcoff"},           /* Chord Pro Manager compat */
    {COMND_OLD_DEFINE,      "old_define"},      /* Chord Pro Manager compat */
    {COMND_NEW_DEFINE,      "new_define"},      /* Chord Pro Manager compat */
    {COMND_START_OF_INDENT, "start_of_indent"}, /* unsupported */
    {COMND_START_OF_INDENT, "soi"},             /* unsupported */
    {COMND_END_OF_INDENT,   "end_of_indent"},   /* unsupported */
    {COMND_END_OF_INDENT,   "eoi"},             /* unsupported */
    {COMND_AUTO_SPACE_ON,   "auto_space_on"},   /* dag extension 02/2003 */
    {COMND_AUTO_SPACE_OFF,  "auto_space_off"},  /* dag extension 02/2003 */
    {COMND_COMMENT_FONT,    "comment_font"},    /* 02/2003 */
    {COMND_COMMENT_SIZE,    "comment_size"},    /* 02/2003 */
    {COMND_COMMENT_ITAL_FONT, "comment_italic_font"}, /* chordrc only 02/2003 */
    {COMND_COMMENT_ITAL_SIZE, "comment_italic_size"}, /* 02/2003 */
    {COMND_PAPER_TYPE,      "paper_type"},     /* chordrc only 02/2003 */
    {COMND_FORM_SPEC,       "form_spec"},      /* chordrc only 02/2003 */
    {COMND_COND_BREAK,      "conditional_break"}, /* 02/2003 */
    {COMND_SET_INDENT,      "set_indent"},        /* 02/2003 */
    {COMND_EXTEND,          "enable_extensions"}, /* chordrc only 02/2003 */
    {COMND_EXTEND_OFF,      "disable_extensions"}, /* chordrc only 02/2003 */
    {COMND_VERSION,         "version"},        /* 02/2003 */
    {COMND_INVALID,         NULL}              /* must be last */
};

/* --------------------------------------------------------------------------------*/
short lookup_command(cmd)
    char *cmd;   /* the command string to match */
{
    short com = COMND_INVALID;  /* dispatch for command, default to invalid */
    int i = 0;                  /* list index, start at beginning */

    /* loop until either we get a name match or come to the end
       of the list */
    while (command_table[i].command_name != NULL)
    {
	/* see if this one matches the one we have */
	if (!strcmp(cmd, command_table[i].command_name))
	{   /* this one matches */
	    com = command_table[i].command_number; /* get the dispatch # */
	    break;       /* break out of the loop */
	}
	++i;  /* go on to the next command string in the table */
    }
    return com;  /* return what we found (or didn't find) */
} /* end of lookup_command */

/* --------------------------------------------------------------------------------*/
void do_directive(directive)
    char *directive;
{
    int   i;
    short com;
    char  *command, *comment;

    command= tolower_str(strtok(directive, ": "));
    com = lookup_command(command);
    switch (com)
    {
	case COMND_START_OF_CHORUS:
	    /* start_of_chorus = vpos - blank_space; */
	    need_soc = TRUE;
	    in_chorus = TRUE;
	    break;

	case COMND_END_OF_CHORUS:
	    if ( in_chorus )
	    {
		end_of_chorus = vpos;
		do_chorus_line();
		in_chorus = FALSE;
	    }
	    else
		error ("Not in a chorus.");
	    break;

	case COMND_TEXTFONT:
	    if (in_chordrc)
	    {
		strncpy(font_table[FONT_TEXT_DEFAULT].name, strtok(NULL, ": "),
			sizeof(font_table[FONT_TEXT_DEFAULT].name));
	    }
	    else
	    {
		strncpy(font_table[FONT_TEXT].name,
			strtok(NULL, ": "),
			sizeof(font_table[FONT_TEXT].name));
		cur_text_size = 0;
		set_text_font(font_table[FONT_TEXT].size);
	    }
	    break;

	case COMND_CHORDFONT:
	    if (in_chordrc)
	    {
		strncpy(font_table[FONT_CHORD_DEFAULT].name, strtok(NULL, ": "),
			sizeof(font_table[FONT_CHORD_DEFAULT].name));
	    }
	    else
	    {
		strncpy(font_table[FONT_CHORD].name,
			strtok(NULL, ": "),
			sizeof(font_table[FONT_CHORD].name));
		set_chord_font();
	    }
	    break;

	case COMND_CHORDSIZE:
	    comment = strtok(NULL, ": ");
	    i = atoi(comment);
	    if ( i == 0 )
		error ("invalid value for chord_size");
	    else
	    {
		if ((*comment == '+') || (*comment == '-'))
		{
		    if ((warning_level > 4) || (!enable_extensions))
		    {
			error("realative sizing is an extended feature");
		    }
		    if (in_chordrc) 
			font_table[FONT_CHORD_DEFAULT].size += i;
		    else
		    {
			font_table[FONT_CHORD].size += i;
			set_chord_font();
		    }
		}
		else
		{
		    if (in_chordrc) 
			font_table[FONT_CHORD_DEFAULT].size = i;
		    else
		    {
			font_table[FONT_CHORD].size = i;
			set_chord_font();
		    }
		}
	    }
	    break;

	case COMND_TEXTSIZE:
	    comment = strtok(NULL, ": ");
	    i = atoi(comment);
	    if ( i == 0 )
		error ("invalid value for text_size");
	    else
	    {
		if ((*comment == '+') || (*comment == '-'))
		{
		    if ((warning_level > 4) || (!enable_extensions))
		    {
			error("realative sizing is an extended feature");
		    }
		    if (in_chordrc) 
			font_table[FONT_TEXT_DEFAULT].size += i;
		    else
		    {
			font_table[FONT_TEXT].size += i;
			set_text_font(font_table[FONT_TEXT].size);
		    }
		}
		else
		{
		    if (in_chordrc) 
			font_table[FONT_TEXT_DEFAULT].size = i;
		    else
		    {
			font_table[FONT_TEXT].size = i;
			set_text_font(font_table[FONT_TEXT].size);
		    }
		}
	    }
	    break;

	case COMND_COMMENT:
	    comment = strtok(NULL, "\0");
	    do_comment(comment, STYLE_COMMENT);
	    break;

	case COMND_COMMENT_ITALIC:
	    comment = strtok(NULL, "\0");
	    do_comment(comment, STYLE_COMMENT_ITALIC);
	    break;

	case COMND_COMMENT_BOX:
	    comment = strtok(NULL, "\0");
	    do_comment(comment, STYLE_COMMENT_BOX);
	    break;

	case COMND_NEW_SONG:
	    do_new_song();
	    break;

	case COMND_TITLE:
	    do_title(strtok(NULL, "\0"));
	    break;

	case COMND_SUBTITLE:
	    do_subtitle(strtok(NULL, "\0"));
	    break;

	case COMND_DEFINE:
	    do_define_chord();
	    break;

	case COMND_NO_GRID:
	    if (in_chordrc)
		no_grid = no_grid_default = TRUE;
	    else
		no_grid = TRUE;
	    break;

	case COMND_GRID:
	    if (in_chordrc)
		no_grid = no_grid_default = FALSE;
	    else
		no_grid = FALSE;
	    break;

	case COMND_NEW_PAGE:
	    do_end_of_page(FALSE);
	    do_start_of_page();
	    break;

	case COMND_START_OF_TAB:
	    if ( in_tab )
		error ("Already in a tablature !");
	    else
		in_tab = TRUE;
	    break;

	case COMND_END_OF_TAB:
	    if (! in_tab )
		error ("Not in a tablature !")	;
	    else
		in_tab = FALSE;
	    break;

	case COMND_COLUMN_BREAK:
	    do_end_of_column();
	    break;

	case COMND_COLUMNS:
	    i = atoi(strtok(NULL, ": "));
	    if ( i <= 1 )
		error ("invalid value for number of columns");
	    else
	    {
		max_columns = i;
		n_columns = 0;
		col_vpos = vpos;
		h_offset = (int)((page_desc.width - page_desc.l_margin) /
				 max_columns);
	    }
	    break;

	case COMND_NEW_PHYS_PAGE:
	    do_end_of_page(TRUE);
	    do_start_of_page();
	    break;

	case COMND_CHORD:
	    do_chord_define();
	    break;

	case COMND_TWO_COLUMN_ON:
	    if (max_columns < 2)
	    {
		max_columns = 2;
		n_columns = 0;
		col_vpos = vpos;
		h_offset = (int)((page_desc.width - page_desc.l_margin) /
				 max_columns);
	    }
	    else
	    {
		error("already in multiple column mode");
	    }
	    break;

	case COMND_TWO_COLUMN_OFF:
	    if (max_columns > 1)
	    {
		max_columns = 1;
		n_columns = 0;
		col_vpos = vpos;
		h_offset = (int)( page_desc.width - page_desc.l_margin);
	    }
	    else
	    {
		error("not in multiple column mode");
	    }
	    break;

	case COMND_OLD_DEFINE:
	    if (warning_level > 4)
	    {
		error("old_define is a Chord Pro Manager feature");
	    }
	    new_define_format = FALSE;
	    break;

	case COMND_NEW_DEFINE:
	    if (warning_level > 4)
	    {
		error("new_define is a Chord Pro Manager feature");
	    }
	    new_define_format = TRUE;
	    break;

	case COMND_START_OF_INDENT:
	case COMND_END_OF_INDENT:
	    sprintf (mesg, "Unsupported Directive : [%s]", command);
	    error(mesg);
	    break;

	case COMND_START_OF_BLOCK:
	    if (warning_level > 4)
	    {
		error("start_of_block is a Chord Pro Manager feature");
	    }
	    if ( in_block )
		error ("Already in a block !");
	    else
	    {
		comment = strtok(NULL, "\0");
	        do_comment(comment, STYLE_COMMENT);
		in_block = TRUE;
	    }
	    break;

	case COMND_END_OF_BLOCK:
	    if (warning_level > 4)
	    {
		error("end_of_block is a Chord Pro Manager feature");
	    }
	    if ( !in_block )
		error ("Not in a block !");
	    else
		in_block = FALSE;
	    break;

	case COMND_START_OF_BRIDGE:
	case COMND_END_OF_BRIDGE:
	    if (warning_level > 4)
	    {
		error("start_of_bridge is a Chord Pro Manager feature");
	    }
	    sprintf (mesg, "Unimplemented CPM Directive : [%s]", command);
	    error(mesg);
	    break;

	case COMND_TAB_FONT:
	    if (warning_level > 4)
	    {
		error("tab_font is not supported by Chord Pro Manager");
	    }
	    if (in_chordrc)
	    {
		strncpy(font_table[FONT_MONO_DEFAULT].name, strtok(NULL, ": "),
			sizeof(font_table[FONT_MONO_DEFAULT].name));
	    }
	    else if (enable_extensions)
	    {
		strncpy(font_table[FONT_MONO].name,
			strtok(NULL, ": "),
			sizeof(font_table[FONT_MONO].name));
		set_tab_font();
	    }
	    else
	    {
		error("extended commands not enabled: tab_font");
	    }
	    break;

	case COMND_TAB_SIZE:
	    if (warning_level > 4)
	    {
		error("tab_size is not supported by Chord Pro Manager");
	    }
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: tab_size");
	    }
	    else
	    {
		comment = strtok(NULL, ": ");
		i = atoi(comment);
		if ( i == 0 )
		    error ("invalid value for tab_size");
		else
		{
		    if ((*comment == '+') || (*comment == '-'))
		    {
			if (warning_level > 4)
			{
			    error("realative sizing is an extended feature");
			}
			if (in_chordrc) 
			    font_table[FONT_MONO_DEFAULT].size += i;
			else
			{
			    font_table[FONT_MONO].size += i;
			    set_tab_font();
			}
		    }
		    else
		    {
			if (in_chordrc) 
			    font_table[FONT_MONO_DEFAULT].size = i;
			else
			{
			    font_table[FONT_MONO].size = i;
			    set_tab_font();
			}
		    }
		}
	    }
	    break;

	case COMND_COMMENT_FONT:
	    if (warning_level > 4)
	    {
		error("comment_font is not supported by Chord Pro Manager");
	    }
	    if (in_chordrc)
	    {
		strncpy(font_table[FONT_COMMENT_DEFAULT].name, strtok(NULL, ": "),
			sizeof(font_table[FONT_COMMENT_DEFAULT].name));
	    }
	    else if (enable_extensions)
	    {
		strncpy(font_table[FONT_COMMENT].name,
			strtok(NULL, ": "),
			sizeof(font_table[FONT_COMMENT].name));
		set_comment_font();
	    }
	    else
	    {
		error("extended commands not enabled: comment_font");
	    }
	    break;

	case COMND_COMMENT_SIZE:
	    if (warning_level > 4)
	    {
		error("comment_size is not supported by Chord Pro Manager");
	    }
	    comment = strtok(NULL, ": ");
	    i = atoi(comment);
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: comment_size");
	    }
	    else
	    {
		if ( i == 0 )
		    error ("invalid value for comment_size");
		else
		{
		    if ((*comment == '+') || (*comment == '-'))
		    {
			if ((warning_level > 4) || (!enable_extensions))
			{
			    error("realative sizing is an extended feature");
			}
			if (in_chordrc) 
			    font_table[FONT_COMMENT_DEFAULT].size += i;
			else
			{
			    font_table[FONT_COMMENT].size += i;
			    set_comment_font();
			}
		    }
		    else
		    {
			if (in_chordrc) 
			    font_table[FONT_COMMENT_DEFAULT].size = i;
			else
			{
			    font_table[FONT_COMMENT].size = i;
			    set_comment_font();
			}
		    }
		}
	    }
	    break;

	case COMND_COMMENT_ITAL_FONT:
	    if (warning_level > 4)
	    {
		error("comment_italic_font is not supported by Chord Pro Manager");
	    }
	    if (in_chordrc)
	    {
		strncpy(font_table[FONT_COMMENT_ITAL_DEF].name, strtok(NULL, ": "),
			sizeof(font_table[FONT_COMMENT_ITAL_DEF].name));
	    }
	    else if (enable_extensions)
	    {
		strncpy(font_table[FONT_COMMENT_ITAL].name,
			strtok(NULL, ": "),
			sizeof(font_table[FONT_COMMENT_ITAL].name));
		set_comment_italic_font();
	    }
	    else
	    {
		error("extended commands not enabled: comment_italic_font");
	    }
	    break;

	case COMND_COMMENT_ITAL_SIZE:
	    if (warning_level > 4)
	    {
		error("comment_italic_size is not supported by Chord Pro Manager");
	    }
	    comment = strtok(NULL, ": ");
	    i = atoi(comment);
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: comment_size");
	    }
	    else
	    {
		if ( i == 0 )
		    error ("invalid value for comment_italic_size");
		else
		{
		    if ((*comment == '+') || (*comment == '-'))
		    {
			if (warning_level > 4)
			{
			    error("realative sizing is an extended feature");
			}
			if (in_chordrc) 
			    font_table[FONT_COMMENT_ITAL_DEF].size += i;
			else
			{
			    font_table[FONT_COMMENT_ITAL].size += i;
			    set_comment_italic_font();
			}
		    }
		    else
		    {
			if (in_chordrc) 
			    font_table[FONT_COMMENT_ITAL_DEF].size = i;
			else
			{
			    font_table[FONT_COMMENT_ITAL].size = i;
			    set_comment_italic_font();
			}
		    }
		}
	    }
	    break;

	case COMND_PAPER_TYPE:
	    if (in_chordrc)
	    {
		set_paper_type(strtok(NULL, ": "));
	    }
	    else
	    {
		error("paper_type directive can only be used in .chordrc file");
	    }
	    break;

	case COMND_FORM_SPEC:
	    if (in_chordrc)
	    {
		char *p1;
                char *n1;
		double top, wid, lmarg, bmarg;
		p1 = strtok(NULL, ": ");
		if (p1 != NULL)
		{
		    n1 = malloc(strlen(p1)+1);
		    strcpy(n1, tolower_str(p1));
		    p1 = strtok(NULL, ": ");
		    if (p1 == NULL)
		    {
			free(n1);
			error("Syntax error in form definition: no top extent");
			break;
		    }
		    top = atof(p1);

		    p1 = strtok(NULL, ": ");
		    if (p1 == NULL)
		    {
			free(n1);
			error("Syntax error in form definition: no width extent");
			break;
		    }
		    wid = atof(p1);

		    p1 = strtok(NULL, ": ");
		    if (p1 == NULL)
		    {
			free(n1);
			error("Syntax error in form definition: no left margin");
			break;
		    }
		    lmarg = atof(p1);

		    p1 = strtok(NULL, ": ");
		    if (p1 == NULL)
		    {
			free(n1);
			error("Syntax error in form definition: no bottom margin");
			break;
		    }
		    bmarg = atof(p1);

		    if ((top <= 72.0)
			|| (wid <= 72.0)
			|| (bmarg < 0.0)
			|| (bmarg >= top)
			|| (lmarg < 0.0)
			|| (lmarg >= wid))
		    {
			error("Invalid form size specification");
			break;
		    }

		    if (warning_level > 7)
		    {
			fprintf(stderr,
				"form '%s' is defined as %f x %f points (%f x %f inches)\n",
				n1, wid, top, wid / 72.0, top / 72.0);
			fprintf(stderr,
				"margins are: left=%f pt (%f in), bottom=%f pt (%f in)\n",
				lmarg, lmarg / 72.0, bmarg, bmarg / 72.0);
		    }
		    page_desc.form_name = n1;
		    page_desc.top = top;
		    page_desc.bottom = bmarg;
		    page_desc.l_margin = lmarg;
		    page_desc.width = wid;
		}
	    }
	    else
	    {
		error("form_spec directive can only be used in .chordrc file");
	    }
	    break;

	case COMND_AUTO_SPACE_ON:
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: auto_space_on");
	    }
	    else
	    {
		auto_space = TRUE;
		if (warning_level > 4)
		{
		    error("auto_space_on is not supported by Chord Pro Manager");
		}
	    }
	    break;

        case COMND_AUTO_SPACE_OFF:
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: auto_space_on");
		break;
	    }
	    auto_space = auto_space_default;
	    if (warning_level > 4)
	    {
		error("auto_space_on is not supported by Chord Pro Manager");
	    }
	    break;

	case COMND_COND_BREAK:
	    if (in_chordrc)
	    {
		error("conditional_break makes no sense in .chordrc");
		break;
	    }
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: conditional_break");
		break;
	    }
	    if (warning_level > 4)
	    {
		error("conditional_break is not supported by Chord Pro Manager");
	    }
	    comment = strtok(NULL, ": ");
	    i = atoi(comment);
	    if ( i == 0 )
	    {
		error ("invalid value for conditional_break");
		break;
	    }
	    fprintf(stderr, "*** conditional_break with a value of %d\n", i);
	    if (in_tab)
	    {
		i *= font_table[FONT_MONO].size;
	    }
	    else
	    {
		if (lyrics_only)
		{
		    i *= font_table[FONT_TEXT].size;
		}
		else
		{
		    i *= font_table[FONT_TEXT].size + font_table[FONT_CHORD].size + 1;
		}
	    }
	    fprintf(stderr, "*debug** conditional_break will use %d points\n", i);
	    if (vpos - i <= page_desc.bottom)
	    {
		do_end_of_column();
	    }
	    break;

	case COMND_SET_INDENT:
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: set_indent");
		break;
	    }
	    if (warning_level > 4)
	    {
		error("set_indent is not supported by Chord Pro Manager");
	    }
	    comment = strtok(NULL, ": ");
	    i = atoi(comment);
	    fprintf(stderr, "*debug** set_indent with a value of %d points\n", i);
	    if (in_chordrc)
	    {
		h_indent = h_indent_default = i;
	    }
	    else
	    {
		h_indent = i;
	    }
	    break;

	case COMND_EXTEND:
	    if (warning_level > 6)
	    {
		error("extensions enabled");
	    }
	    enable_extensions = TRUE;
	    break;

	case COMND_EXTEND_OFF:
	    if (warning_level > 6)
	    {
		error("extensions disabled");
	    }
	    enable_extensions = FALSE;
	    break;

	case COMND_VERSION:
	    if (!enable_extensions)
	    {
		error("extended commands not enabled: version");
	    }
	    if (warning_level > 4)
	    {
		error("version is not supported by Chord Pro Manager");
	    }
	    comment = strtok(NULL, ": ");
	    i = atoi(comment);
	    fprintf(stderr, "*debug** set compatibility to version %d\n", i);
	    if (in_chordrc)
	    {
		language_version = language_version_default = i;
	    }
	    else
	    {
		language_version = i;
	    }
	    break;

	default:
	    sprintf (mesg, "Invalid Directive : [%s]", command);
	    error(mesg);
	    has_directive = FALSE;
	    break;
    }
}

/* --------------------------------------------------------------------------------*/
void put_in_string(array, p_index, c, max_index, p_ov_flag)
    char array[MAXLINE];
    int *p_index;
    int c;
    int max_index;
    int *p_ov_flag;
{
    if (*p_index < max_index)
	array[(*p_index)++] = (char) c;
    else
    {
	if (!*p_ov_flag)
	{
	    error ("Buffer Overflow");
	    *p_ov_flag = TRUE;
	}
    }
}
/* --------------------------------------------------------------------------------*/
void do_eol()
{
    if ( in_directive )
	error ("Line ends while in a directive !"); 
    if ( in_chord)
	error ("Line ends while in a chord !"); 
    if (has_directive == FALSE)
    {
	if (in_chordrc) 
	{
	    if (strcmp(text_line, "\0"))
		error("line is NOT a directive");
	}
	else if (! in_tab || ! lyrics_only)
	    print_text_line();
    }
    else
	has_directive = FALSE;
    n_lines++;
    i_input = 0;
    in_directive = FALSE;
    in_chord = FALSE;
    i_text = 0;
    i_text_ov = FALSE;
    text_line[0]='\0';
}
/* --------------------------------------------------------------------------------*/
void process_file(source_fd)
    FILE *source_fd;
{
    /*debug("start of process_file");*/

    n_lines = 0;

    while ( (c= getc(source_fd)) != EOF)
    {
	i_input++;
	switch ((char)c) {

	    case '[':
		if (!in_tab) {
		    if ( in_chord )
			error("Opening a chord within a chord!");
		    else
			in_chord = TRUE;
		    i_chord = 0;
		}
		else put_in_string(text_line, &i_text, c, MAXLINE, &i_text_ov);
		break;
		
	    case ']':
		if (! in_tab) {
		    if ( in_chord )
		    {
			in_chord = FALSE;
			chord[i_chord]= '\0';
			do_chord(i_text, &chord[0]);
			has_chord = TRUE; 
			i_chord = 0;
			i_chord_ov = FALSE;
		    }
		    else
			error("']' found with no matching '['");
		}
		else put_in_string(text_line, &i_text, c, MAXLINE, &i_text_ov);
		break;
		
	    case '{':
		in_directive = TRUE;
		i_directive = 0;
		has_directive = TRUE;
		break;

	    case '}':
		if ( in_directive)
		{
		    in_directive = FALSE;
		    directive[i_directive]= '\0';
		    for (; (c= getc(source_fd)) != '\n'; );
		    i_input = 0;
		    do_directive(&directive[0]);
		    has_directive = FALSE;
		    n_lines++;
		    i_directive = 0;
		    i_directive_ov = FALSE;
		}
		else
		    error("'}' found with no matching '{'");
		break;

	    case '\n':
		do_eol();
		break;
	    case '(':
	    case ')':
		if (in_directive)
		{
		    put_in_string(directive, &i_directive, c, MAXTOKEN, &i_directive_ov);
		    break;
		}
		else if (in_chord) /* allow parens in chord names */
		{
		    put_in_string (chord, &i_chord, c, CHORD_NAME_SZ, &i_chord_ov);
		    break;
		}
		else
		{
		    put_in_string (text_line, &i_text, c, MAXLINE, &i_text_ov);
		    break;
		}
	
		/* This case HAS to be the last before the default statement !!! */

	    case '#':
		if (i_input == 1)
		{
		    for (; (c= getc(source_fd)) != '\n'; );
		    n_lines++;
		    i_input = 0;
		    break;
		}

	    default :
		if (in_chord )
		{
		    if ( c != ' ' )
		    {
			put_in_string(chord, &i_chord, c, CHORD_NAME_SZ, &i_chord_ov);
		    }
		}
		else if (in_directive)
		{
		    put_in_string(directive, &i_directive, c, MAXTOKEN, &i_directive_ov);
		}
		else
		{
		    put_in_string(text_line, &i_text, c, MAXLINE, &i_text_ov);
		}
		break;
	}
    }
    if (i_input != 0 ) do_eol();
    if (! in_chordrc) print_text_line();
}

/* --------------------------------------------------------------------------------*/
/* read the file $HOME/.chordrc as a set of directive */
void process_rcfile(chordrc)
    char *chordrc;
{
    FILE *chordrc_fd;
    int n_lines_save;

    current_file = chordrc;
    chordrc_fd = fopen (chordrc, "r");
    if (chordrc_fd != NULL)
    {
	n_lines_save= n_lines;
	n_lines= 1;
	in_chordrc = TRUE;
	process_file(chordrc_fd);
	in_chordrc = FALSE;
	n_lines= n_lines_save;
	fclose(chordrc_fd);
    }
    current_file = &source[0];
    first_time_in_chordrc = FALSE;
}

#define CHORD_RC_USER   "/.chordrc"
#define CHORD_RC_SYS    "/usr/local/etc/chordrc"
#define CHORD_RC_DIR    "./.chordrc"

void read_chordrc()
{
    char chordrc[MAXTOKEN];
    char *tmp;

    /* support system-wide rc files */
    if ((tmp = getenv("CHORDRCSYS")) == NULL)
    {
	process_rcfile(CHORD_RC_SYS);
	process_rcfile(chordrc);
    }
    else
    {
	process_rcfile(tmp);
    }

    /* allow environment to override placement of RC users file */
    if ((tmp = getenv("CHORDRC")) == NULL)
    {
	strcpy (chordrc, getenv ("HOME"));
	strcat (chordrc, CHORD_RC_USER);
    }
    process_rcfile(chordrc);

    /* handle RC files in the current working directory */
    if ((tmp = getenv("CHORDRCLOCAL")) == NULL)
    {
	process_rcfile(CHORD_RC_DIR);
	process_rcfile(chordrc);
    }
    else
    {
	process_rcfile(tmp);
    }
}

/* --------------------------------------------------------------------------------*/
main(argc, argv)
    int argc;
    char **argv;
{
    int c,i;

    init_defaults();
    mesg = mesgbuf;
    init_known_chords();
/* handle the chordrc file */
    read_chordrc();
/* Option Parsing */

    command_name= argv[0];

    /* parse the command line */
    while ((c = getopt(argc, argv, "aAc:C:dDeEgGhiJlLno:P:p:s:t:T:Vx:24W:"))
	   != -1)
	switch (c) {

	    case 'd':
		dump_only = TRUE;
		break;

	    case 'D':
		dump_only = TRUE;
		postscript_dump = TRUE;
		break;

	    case 'e':
		enable_extensions = FALSE;
		break;

	    case 'E':
		enable_extensions = TRUE;
		break;

	    case 'c':
		i = atoi (optarg);
		if ( i == 0 )
		    error_rt("invalid value for chord_size");
		else
		    font_table[FONT_CHORD_DEFAULT].size = i;
		break;

	    case 'C':
		strncpy(font_table[FONT_CHORD_DEFAULT].name, optarg,
			sizeof(font_table[FONT_CHORD_DEFAULT].name));
		break;

	    case 'J':
		auto_adjust = FALSE;
		break;

	    case 'h':
		do_help(argv[0]);
		break;

	    case 'P':   /* paper-type */
		set_paper_type(optarg);
		break;

	    case 't':
		i = atoi (optarg);
		if ( i == 0 )
		    error_rt("invalid value for text_size");
		else
		    font_table[FONT_TEXT_DEFAULT].size = i;
		break;

	    case 'T':
		strncpy(font_table[FONT_TEXT_DEFAULT].name, optarg,
			sizeof(font_table[FONT_TEXT_DEFAULT].name));
		break;

	    case 'W':
		warning_level = atoi (optarg);
		break;

	    case 'x':
		i = atoi (optarg);
		if ( i == 0 )
		    error_rt("invalid value for transposition");
		else
		    transpose = i;
		break;

	    case 's':
		i = atoi (optarg);
		if ( i == 0 )
		    error_rt("invalid value for grid_size");
		else
		    grid_size = i;
		break;

	    case 'g':
		no_easy_grids = TRUE;
		break;

	    case 'G':
		no_grid_default = TRUE;
		break;

	    case 'l':
		lyrics_only= TRUE;
		break;

	    case 'n':
		number_logical = TRUE;
		break;

	    case 'V':
		print_version();
		exit(0);
		break;

	    case '2':
		pagination = 2;
		scale = (page_desc.width - page_desc.l_margin) /
		    (page_desc.top + page_desc.bottom);
		rotation= 90.0;
		break;

	    case '4':
		pagination = 4;
		scale = ((page_desc.width - page_desc.l_margin)/2.1) /
		    (page_desc.width - page_desc.l_margin);
		break;

	    case 'i': /* generate in index */

		do_toc = TRUE;
		number_all = TRUE;
		break;

	    case 'a':
		auto_space = auto_space_default = TRUE;
		break;

	    case 'p':
		i = atoi (optarg);
		if ( i == 0 )
		    error_rt("invalid value for initial page number");
		else {
		    page_label = i;
		    number_all = TRUE;
		}
		break;

	    case 'L':
		left_foot_even = 0;
		number_all= TRUE;
		break;

	    case 'o':
		if ( freopen(optarg, "w", stdout) == NULL)
		{
		    fprintf (stderr, "Unable to open \"%s\" for output\n", optarg);
		    exit(1);
		}
		break;

	    case 'A':
		do_about();
		exit(0);
		break;

	    case '?':
		do_help(argv[0]);
		break;
	}

/* Is there anything? */

    if (argc == 1)
	do_help(argv[0]);

/* Is there input? */

    if ((optind == argc) && isatty(0) && !dump_only)
    {
	fprintf (stderr, "Error: CHORD does not expect you to type the song on your keyboard.\n");
	fprintf (stderr, "Please either specify an input filename on the command line\n");
	fprintf (stderr, "or have the input redirected or piped in.\n");
	fprintf (stderr, "Exemples:\n");
	fprintf (stderr, "   %% chord my_song.cho > myfile.ps\n");
	fprintf (stderr, "   %% chord < mysong.cho > myfile.ps\n");
	fprintf (stderr, "Do \"chord -h\" to learn about CHORD's options\n");
	exit(1);
    }

/* Is there output? */

    if (isatty(1) && (!dump_only || postscript_dump))  /* 1 == stdout  */
    {
	fprintf (stderr, "Error: CHORD will not send PostScript to your terminal.\n");
	fprintf (stderr, "Please either redirect (>) or pipe (|) the output.\n");
	fprintf (stderr, "Exemples:\n");
	fprintf (stderr, "   %% chord my_song.cho > myfile.ps\n");
	fprintf (stderr, "   %% chord my_song.cho | lpr\n");
	exit(1);
    }


/* File Processing */

    init_paper_size();  /* set up the page parameters */

    if (dump_only) 
    {
	dump_chords(postscript_dump);
	exit(0);
    }

    reset_to_defaults();

    init_ps();

    chord_inc = font_table[FONT_CHORD].size * 1.5;

    for ( ; optind < argc; optind++ )
    {
	strcpy(source, argv[optind]);
	read_input_file(source, source_fd);
	if (optind < argc - 1)
	    do_new_song();
    }


    do_end_of_song();
	 
    if (do_toc)	/* generate index  page */
    {
	build_ps_toc();
	do_end_of_page(FALSE);
    }

    if (v_pages != 0)
    {
	do_end_of_phys_page();
    }


    printf ("%%%%Trailer\n");
    printf ("%%%%Pages: %d 1\n", n_pages);
    printf ("%%%%EOF\n");

    exit (0);	
    return(0);
} /* end of main() */
