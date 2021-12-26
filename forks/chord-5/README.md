This is a fork of the CHORD program originally written by Martin Leclerc and Mario Dorion.  It is based on sources obtained in the mid-1990s by me (Daniel Glasser <daniel.glasser@gmail.com>) from an associate, which is described as being version 3.6.

In effect, it takes text files in a specific format and produces formatted output (postscript) with chord names and charts. The sources include a companion tools, "a2chrd", that attempts to take a typed set of lyrics with chord letters on lines above the words, and generate an input file for "chord" that can be used to produce better song sheets.

While writing this file, I discovered https://www.chordpro.org/chordpro/chordpro-reference-implementation/, which talks about the relationship between the original, on which my fork is based, and the ChordPro releases (4.0 and beyond).  They rewrote the original C program into Perl, my version is still entirely in C.

Over a few years, I extended the options and added a few new features to the program to suit my needs.  When I tried to contribute my changes back to the authors, the e-mail bounced, and all of the links that are found in the various README files provided in the source archive I got are dead ends (mostly dead, the others are now much less informal than they had been).

Full credit belongs to the original authors:
 * Martin Leclerc (Martin.Leclerc@canada.sun.com)
 * Mario Dorion   (Mario.Dorion@canada.sun.com)	

I hope they don't mind my makeing my fork available.

I've called my fork "Chord 5.0" because 5.0 > 3.6.  I hope I'm not stepping on anyones toes.  Here is the list of changes from comments in the sources:

 * Reformated source code, adding numerous comments in the process.
 * Changed internal handling of various font names/sizes to use a table instead of global pointers and integers.
 * Changed how the directives are recognized and processed from an if-elseif-elseif-elseif-...-elseif-else chain to a table lookup and a switch.  Further code simplification may follow.
 * Got rid of the default < RC-file < command-line < song-file settings management and replaced it with default (with rc-file and command line overrides) < song-file settings management.  The rc file no longer is processed after each song file.
 * Added support for directory-local and system chord RC files, along with optional environment specification of each. The order that the RC files are read in is system then user then local directory.  The environment variables are named "CHORDRCSYS" for the system, "CHORDRC" for the user, and "CHORDRCLOCAL" for the directory local files.  This was partly done to allow for multiple form definitions in the system rc file.  For now, the system RC file is named "/usr/local/etc/chordrc", but that will eventually be a configuration option.
 * Fixed problems with {textfont: } and {chordfont: } directives
 * Added automatic adjusting of chord definitions where the base-fret offset might not allow the dots to fall within the grid.
 * Made the form (page dimensions) selectable at runtime rather than having to recompile to get Letter vs. A4 output.  This required changing how the form metrics were coded into the source.
 * Added V4 (ChordPro Manager) directive support
 * * {start_of_bridge} / {end_of_bridge} / {sob} / {eob}
 * * {start_of_block: label} / {end_of_block} / {soblk} / {eoblk}
 * * {chord: name 1 2 3 4 5 6 offset}
 * * {old_define} / {new_define}
 * * {two_column_on} / {two_column_off} / {tcon} / {tcoff}
 * Extended the typeface size directives to accept relative size settings as well as absolute.
 *  Added V5 (extended) directives
 * * {version: markup-lang-version}
 * * * This directive is mainly for forward compatibility.  There are some subtle side effects of some of the new features.  Every attempt has been made to keep the default behavior the same unless a new feature overrides it, such as the comment font and size being the same as the lyrics text font and size, and the tab font size being two points smaller than the lyrics text font size, and so on.  If you override one of these items, however, those related sizes are no longer linked.  Future additions to the mark-up language may introduce so many of these that having a version number associated with a given song file will help the program figure out just what old behaviors it needs to exhibit for the file.
 * * {auto_space_on} / {auto_space_off}
 * * * Allows local control within a song file.  If auto-space is turned on on the command line with the '-a' switch, however, {auto_space_off} has no effect.
 * * {comment_font: postscript-font} / {comment_size: points}
 * * * Control the typeface and display size of the comments specified in {comment: } and {comment_box: } directives.  Use of these directives unlinks the comment text from  lyrics text.
 * * {comment_italic_font: postscript-font} / {comment_italic_size: points}
 * * * Control the typeface and display size of the comments specified in {comment_italic: } directives. Use of these directives unlinks the comment text from chord font.
 * * {tab_font: postscript-font} / {tab_size: points}
 * * * Control the typeface and display size of the text displayed between {start_of_tab} and {end_of_tab} directives. Use of these directives unlinks the tab text size from lyrics text size (by default, the tab_size is 2 points smaller than the lyrics text size).
 * * {paper_type: formname}
 * * * (rc file only)
 * * * This directive allows you to select which output form (paper-type) the output is to be printed on.  Built-in values are 'a4', 'letter', and 'mletter'.  'mletter' is the same paper dimensions as 'letter', but has slightly narrower margins to allow a bit more room on the page for lyrics.
 * * {form_spec: formname top width left bottom}
 * * * (rc file only)
 * * * Allows you to define metrics for the form that the output will be printed on.  For the moment, only one 'user' form can be defined, but before this code is released to the general public, multiple forms will be specified within an rc file and selected on the command line or through a later {paper_type: } directive.
 * * {conditional_break: lines}
 * * * This (currently experimental) directive introduces a column or page break if there is insufficient room remaining above the bottom margin for the specified number of lines.
 * * {set_indent: points}
 * * * Sets the indent for the block and bridge.  For now, this is in points, but in the future, various measurement systems will be useable.
 * * {enable_extensions} / {disable_extensions}

Though I maintained this port on Unix, Linux, and Windows for many years, I have not touched it (the code, that is) or built it since around 2003.

If the original authors, or their successors, wish to contact me about my fork, I encourage them to do so.
