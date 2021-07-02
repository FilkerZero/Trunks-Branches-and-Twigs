#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include "patchlevel.h"

#define US 1   /* we're in the US */

#define TRUE 1
#define FALSE 0

#define MAXLINE 256
#define MAXFONTS 16   /* Maximum number of different fonts in one execution */
#define MAXTOKEN 256
#define MAX_CHORD 1024
#define CHORD_NAME_SZ   10
#define MAXNOTE 8
#define DEF_CP_VER      5       /* default ChordPro markup version */
#define LONG_FINGERS	4
#define FRET_NONE_STR	"-"		/* fret value for unplayed strings */
#define FRET_NONE	-2		/* internal numeric value */
#define FRET_X_STR	"X"		/* fret value for muted strings */
#define FRET_X		-1		/* internal value (must be -1) */
#define NO_CHORD_STR	"N.C."		/* Indicates No-Chord */
#define BASE_FRET_STR	"base-fret"
#define FRETS_STR	"frets"

#define MAXFONTNAME         256   /* Maximum font name size */
#define FONT_TEXT             0
#define FONT_TEXT_DEFAULT     1
#define FONT_CHORD            2
#define FONT_CHORD_DEFAULT    3
#define FONT_MONO             4
#define FONT_MONO_DEFAULT     5
#define FONT_COMMENT          6
#define FONT_COMMENT_DEFAULT  7
#define FONT_COMMENT_ITAL     8
#define FONT_COMMENT_ITAL_DEF 9
#define NUMFONTS             10

typedef struct font_info {
    char name[MAXFONTNAME];
    int  size;
} font_info;


#define	OFFSET_X	36.0	/* 0.5 inches in points */

typedef struct page_info {
    char *form_name;        /* a name for this page shape */
    double top;             /* top of "printable", in points */
    double bottom;          /* bottom of "printable", in points */
    double l_margin;        /* left margin of "printable", in points */
    double width;           /* right margin of "printable", in points */
} page_info;

/* US Letter */
#define LETTER_TOP 756.0         /* 10.5 inches in points */
#define LETTER_BOTTOM 40.0        /* 0.5 inch in points */
#define LETTER_L_MARGIN 72.0      /* 1 inch in points */
#define LETTER_WIDTH 612.0        /* 8.5 inches in points */

/* US Letter with 1/2 " margins */
#define MLETTER_TOP      792.0
#define MLETTER_BOTTOM    36.0
#define MLETTER_L_MARGIN  36.0
#define MLETTER_WIDTH    612.0

	/* Note: Not having access to an actual A4 PostScript printer
		 the CHORD authors had to rely on input from beta-testers
		 on what were the proper values to use for these fields.
		 We though 813 was the right value for TOP.
		 Some beta testers agreed, some thought it was better
		 to leave the US value (756). We left 756 in and commented
		 out the 813 entry. If the A4 page does not look to good for
		 your taste, you may want to recompile with the other value.
		 Thanks for your co-operation ... The authors */

#define A4_TOP 756.0         /* 10.5 inches in points */
/* #define A4_TOP 813 */        /* 28.7 cm or 11.30 inches in points */
#define A4_BOTTOM 36.0      /* 1.25 cm or 0.5 inch in points */
#define A4_L_MARGIN 72.0     /* 2.5 cm or 1 inch in points */
#define A4_WIDTH 595.0       /* 21 cm or 8.27 inches in points */
#ifdef US
#define TOP           LETTER_TOP
#define BOTTOM        LETTER_BOTTOM
#define L_MARGIN      LETTER_L_MARGIN
#define WIDTH         LETTER_WIDTH
#else
#define TOP           A4_TOP
#define BOTTOM        A4_BOTTOM
#define L_MARGIN      A4_L_MARGIN
#define WIDTH         A4_WIDTH
#endif /* US */

#define DELIM_STR       ": \t"

#define DEF_TEXT_SIZE 12
#define DEF_CHORD_SIZE 9
#define DEF_GRID_SIZE 30
#define DEF_TEXT_FONT "Times-Roman"
#define DEF_CHORD_FONT "Helvetica-Oblique"
#define MONOSPACED_FONT "Courier"

#define CHORD_BUILTIN	0
#define CHORD_DEFINED	1
#define CHORD_IN_CHORDRC	2

#define CHORD_EASY	0
#define CHORD_HARD	1

struct kcs {
	struct 	kcs *next;
	char	chord_name[CHORD_NAME_SZ];
	int	displ;
	int	s1,s2,s3,s4,s5,s6;
	int	origin;
	int	difficult;
	} dummy_kcs;

struct chord_struct {
	struct chord_struct *next;
	struct kcs *chord;
	} dummy_chord_struct;

struct sub_title_struct {
	struct sub_title_struct *next_sub;
	char *sub_title;
	};

struct toc_struct {
	struct toc_struct *next;
	struct sub_title_struct *sub_titles; 
	char *title;
	int page_label;
	};

typedef struct directive_entry {
    short command_number;  /* the dispatch number (COMND_xxx) for this command */
    char *command_name;    /* the string for the command in question */
} directive_entry;

#define COMND_INVALID           -1   /* No match in table */
#define COMND_START_OF_CHORUS    0   /* start_of_chorus, soc */
#define COMND_END_OF_CHORUS      1   /* end_of_chorus, eoc */
#define COMND_TEXTFONT           2   /* textfont, tf */
#define COMND_CHORDFONT          3   /* chordfont, cf */
#define COMND_CHORDSIZE          4   /* chordsize, cs */
#define COMND_TEXTSIZE           5   /* textsize, ts */
#define COMND_COMMENT            6   /* comment, c */
#define COMND_COMMENT_ITALIC     7   /* comment_italic, ci */
#define COMND_COMMENT_BOX        8   /* comment_box, cb */
#define COMND_NEW_SONG           9   /* new_song, ns */
#define COMND_TITLE             10   /* title, t */
#define COMND_SUBTITLE          11   /* subtitle, st */
#define COMND_DEFINE            12   /* define, d */
#define COMND_NO_GRID           13   /* no_grid, ng */
#define COMND_GRID              14   /* grid, g */
#define COMND_NEW_PAGE          15   /* new_page, np */
#define COMND_START_OF_TAB      16   /* start_of_tab, sot */
#define COMND_END_OF_TAB        17   /* end_of_tab, eot */
#define COMND_COLUMN_BREAK      18   /* column_break, colb */
#define COMND_COLUMNS           19   /* columns, col */
#define COMND_NEW_PHYS_PAGE     20   /* new_physical_page, npp */
#define COMND_START_OF_INDENT   21   /* start_of_indent, soi */
#define COMND_END_OF_INDENT     22   /* end_of_indent, eoi */

/* added for Chord Pro Manager compatibility */
#define COMND_START_OF_BRIDGE   23   /* start_of_bridge, sob */
#define COMND_END_OF_BRIDGE     24   /* end_of_bridge, eob */
#define COMND_START_OF_BLOCK    25   /* start_of_block */
#define COMND_END_OF_BLOCK      26   /* end_of_block */
#define COMND_CHORD             27   /* chord */
#define COMND_OLD_DEFINE        28   /* old_define */
#define COMND_NEW_DEFINE        29   /* new_define */
#define COMND_TWO_COLUMN_ON     30   /* two_column_on, tcon */
#define COMND_TWO_COLUMN_OFF    31   /* two_column_off, tcoff */

/* added by dag (Feb 2003) for use in .chordrc only */
#define COMND_AUTO_SPACE_ON     62   /* enable auto-spacing */
#define COMND_AUTO_SPACE_OFF    63   /* disable auto-spacing */
#define COMND_TAB_FONT          64   /* tab_font */
#define COMND_TAB_SIZE          65   /* tab_size */
#define COMND_COMMENT_FONT      66   /* comment_font */
#define COMND_COMMENT_SIZE      67   /* comment_size */
#define COMND_COMMENT_ITAL_SIZE 68   /* comment_italic_size */
#define COMND_COMMENT_ITAL_FONT 69   /* comment_italic_font */
#define COMND_PAPER_TYPE        70   /* paper_type */
#define COMND_FORM_SPEC         71   /* form_spec */
#define COMND_COND_BREAK        72   /* conditional_break */
#define COMND_SET_INDENT        73   /* set_indent */
#define COMND_EXTEND           128   /* enable_extensions */
#define COMND_EXTEND_OFF       129   /* disable_extensions */
#define COMND_VERSION          130   /* version */

/* external/forward function declarations/prototypes */
int do_define_chord();
int do_chord_define();
void build_ps_toc();
void do_chorus_line();
void do_end_of_page();
void do_end_of_phys_page();
void do_end_of_song();
void do_init_grid_ps();
void do_new_song();
void do_start_of_page();
void do_subtitle();
void do_title();
void draw_chords();
void dump_chords();
void init_known_chords();
void init_ps();
void print_chord_line ();
void print_re_encode();
void print_text_line();
void print_version();
void read_chordrc();
void set_chord_font();
void set_comment_italic_font();
void use_chord_font();
void use_tab_font();
void use_comment_font();
void use_comment_italic_font();
void use_text_font();
void do_start_of_indent();
void do_end_of_indent();
void init_defaults();

#ifdef  __STDC__
struct chord_struct *add_to_chordtab(char *chord);
void add_title_to_toc(char *title, int page_label);
void add_subtitle_to_toc(char *subtitle);
int do_transpose(char *chord);
struct kcs *get_kc_entry (char *chord);
void advance(int amount);
void debug(char *dbg_str);
void do_chord (int i_text, char *chord);
void do_comment(char *comment, int style);
void do_directive(char *directive);
void do_help (char *command) ;
void dump_fret(int fretnum);
void error(char *error);
void error_rt(char *error);
void moveto(int new_hpos, int new_vpos);
void process_file(FILE *source_fd);
void ps_fputc(FILE *fd, int c);
void ps_fputs(FILE *fd, char *string);
void ps_puts(char *string);
void put_in_string(char array[], int *p_index, int c, int max_index, int *p_ov_flag);
void re_encode(char *font);
void read_input_file(char source[], FILE *source_fd);
void set_text_font(int size);
void set_tab_font(void);
void set_comment_font(void);
short lookup_command(char *cmd);
char *tolower_str(char *string);
char *toupper_str(char *string);
extern      char *strtok(char *s1, const char *s2);
#else /* __STDC__ */
struct chord_struct *add_to_chordtab();
int do_transpose();
struct kcs *get_kc_entry ();
void advance();
void debug();
void do_chord ();
void do_comment();
void do_directive();
void do_help ();
void do_translate();
void dump_fret();
void error();
void error_rt();
void moveto();
void process_file();
void ps_fputc();
void ps_fputs();
void ps_puts();
void put_in_string();
void re_encode();
void read_input_file();
void set_text_font();
void set_tab_font();
void set_comment_font();
short lookup_command();
char *tolower_str();
char *toupper_str();
extern char *strtok();

#endif /* ANSI_C */
