#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec wish "$0" ${1+"$@"}

# Set global variables
namespace eval ::build {
    variable envReady     0
}

if {[catch {
    package require Tk
    package require Ttk
    package require msgcat
    package require tooltip

    namespace import tooltip::tooltip

    set ::build::envReady 1
} trouble]} {
    puts stderr "Warning: Prerequisites to run this script are not met."
    puts stderr $errorText
    set ::build::envReady 0
}
     
# Set more global variables
namespace eval ::build {
    variable noConsole    0
    variable helpLine     ""
    variable debugConsole -1
    variable kwdSaveType  ""

    # Some string constants
    array set htmlClasses {
        kwdListPara "keywords"
        kwdLabel    "kwdlabel"
        kwdList     "kwdList"
        container   "posSet"
        flexDiv     "boxed"
    }

    array set mediaOptions {
        mediaAttrs ""
        mediaAltText ""
        mediaWidth ""
        mediaHeight ""
        mediaLink ""
        mediaTitle ""
        forceFigure 0
        mediaCaption ""
    }

    # A global array to keep track of widgets, similar to what was done from
    # (nearly the) beginning in "meta-edit"
    array set widget_paths {}

    array set commentDelim {
        html,open  "<!--"
        html,close "-->"
        css,open   "/*"
        css,close  "*/"
    }

}

proc htmlClass {what} {
    return $::build::htmlClasses($what)
}

proc commentDelimiter {where what} {
    return $::build::commentDelim($where,$what)
}

proc set_wp {index path} {
    set ::build::widget_paths($index) $path
}

# Be sure not to request the path to a widget that has not had its
# path set; bad things will happen.
proc get_wp {index} {
    return $::build::widget_paths($index)
}

proc show_console {btn args} {
    global tcl_version
    # Magic tkcon stuff
    namespace eval ::tkcon {}

    if {${::build::debugConsole} < 0} {
        $btn configure -foreground gray10 -background snow
        update
        set ::tkcon::OPT(exec) ""
        #source [file join [file dirname [info nameofexecutable]] tkcon.tcl]
        set ::tkcon::OPT(exec) ""
	set tkconExe [file join [file dirname [info nameofexecutable]] tkcon]
	if {![file exists ${tkconExe}.tcl] && [file exists $tkconExe]} {
	    if {[file type $tkconExe] eq "link"} {
		set tkconExe [file normalize \
				  [file join \
				       [file dirname $tkconExe] \
				       [file link $tkconExe]]]
	    }
	} else {
	    set tkconExe [string cat $tkconExe .tcl]
	}
	source $tkconExe

        set ::build::debugConsole 0
        set ::build::noConsole 0
    }
       
    set fg [$btn cget -foreground]
    set bg [$btn cget -background]
    set menu [get_wp utilMenu]

    $btn configure -foreground $bg -background $fg

    if {!${::build::debugConsole}} {
        tkcon show
        set ::build::debugConsole 1
        $menu entryconfigure "*Console" -label "Hide Debug Console"
    } else {
        tkcon hide
        set ::build::debugConsole 0
        $menu entryconfigure "*Console" -label "Show Debug Console"
    }
    update
}

# Set default build options
#       outDirPath     - string, the pathname of the directory that the
#                        HTML and CSS files will be written
#                        (default is the directory the script is run in)
#       htmlFileName   - string, the name of the HTML file to be generated
#                        in the output directory
#                        (defaults to the output directory name with ".html"
#                        appended to it)
#       cssFileName    - string, the name of the CSS file to be generated
#                        in the output directory
#                        (defaults to the HTML file name with the extension
#                        '.css' ([string cat [file root $htmlFileName] .css]))
#       genMissingInfo - boolean, when true, crude 'info' files will be
#                        created when none was found for an image
#                        (default is false (0))
#       newInfoLoc     - When useAltInfoDir is true, determines where any
#                        generated 'info' files are to be created; when
#                        1, the new file is created in the same directory
#                        as the media file, when 0, in the alternative
#                        directory.  When useAltInfoDir is false, the file
#                        will be created in the media directory.
#       infoFileExt    - The extension for the 'info' filenames
#       kwdLocation    - integer, determines whether the keywords (if any)
#                        are displayed on the top or bottom of the block
#                        (or at all)
#                        (default is top)
#       imgInFigure    - boolean, when true, the <img> is wrapped in
#                        a <figure> element with a <figcaption> at the
#                        bottom; the <img> styles are applied to the
#                        figure element instead in the generated CSS
#                        (default is false (0))
#       linkImgFiles   - boolean, when true, the <img> files are wrapped
#                        between <a> and </a> linking to the image file
#                        in a blank page.
#                        (default is 0)
#       contTitles     - boolean, when true, each flex container gets a
#                        generated <h2> element, when false, no such
#                        headers are generated in the HTML output
#                        (default: false (0))
#       imgElementAttr - string, inserted into the generated <img> tags
#                        right before then closing '>'
#                        (default is 'width="250"')
#       pageTitle      - string, used for the <title> tag in the <head>
#                        section and the <h1> element in the <body>
#                        section of the HTML output; If this is blank
#                        when the processing begins, a title based on the
#                        output directory is generated
#                        (default is "")
#       includeBase    - string, the initial part of the name of files
#                        containing text that is copied to the output
#                        at specific points in the HTML output generation;
#                        to this string, a suffix and extension are appended
#                        for the particular stage, and there is no error
#                        if the file is not found
#                        (default is "local")
#       imgPathAbs     - string, the path to the directory containing the
#                        image file being processed
#                        (default is the output directory)
#       imgPathRel     - string, the relative path from the output directory
#                        (specified in 'outDirPath', above) to the currently
#                        selected image directory; this is generated on the
#                        fly based on the relationship between the values of
#                        'outDirPath' and 'imgPathAbs', and is used in as
#                        the path portion before the image file root name
#                        in the "src" attribute of generated <img> tags
#                        (no default)
#       maxSrchDepth   - Integer, recursion depth for image searches from
#                        the image directory
#                        (defaults to 0)
#       splitContainer - boolean, when true, each subdirectory is in its own
#                        flex container; when false, all image file blocks
#                        are in the same flex container
#                        (default is false)
#       useAltInfoDir  - boolean, when false the program expects the 'info'
#                        text file in the same directory as the image file
#                        it is for, when true, the program looks in an
#                        alternative location specified in the 'altInfoPath'
#                        array element
#                        (default is false (0))
#       altInfoPath    - string, the directory path where the 'info' file
#                        for an image is expected when the array element
#                        'useAltInfoDir' is true (1); ignored otherwise
#                        (default is blank, but is set to the output
#                        or image directory path if it is blank)
#       siteFilePath   - string, the path to the directory where the
#                        site include file(s) are located; these are
#                        optional, and if found, their contents are copied
#                        to the output HTML or CSS file near the beginning
#                        (default is the output directory)
#       siteFileName   - string, the name of the site include file for the
#                        HTML generation when combined with 'siteFilePath',
#                        above as the directory path; if the file is found,
#                        its contents are copied to the <head> section
#                        following the "<title>" element
#                        (default is "")
#       imgGlobPattern - string, the 'glob' pattern to get the list of
#                        image files to be processed in a the image directory
#                        (default is "*.{jpg,png,gif}")
#       nameMapList    - list, if this is set, it must have an even number
#                        of elements; the elements are paird as
#                        '<pattern> <substitution>' - this list is used
#                        in a Tcl 'string match' command to transform the
#                        name of the image file (with its extension removed)
#                        into both the default displayed image name text and
#                        the unique class name for the <div> created for the
#                        image file
#                        (default is an empty list)
#
# Note: Not all elements are set initially, the program sets them before it
#       needs to use them.
array set ::build::context {
    genMissingInfo 0
    newInfoLoc    0
    infoFileExt  ".txt"
    useAltInfoDir 0
    imgInFigure 0
    linkImgFiles 0
    contTitles  0
    kwdLocation 1
    imgElementAttr {width="250"}
    pageTitle   ""
    includeBase local
    altInfoPath   ""
    siteFilePath  ""
    siteFileName  ""
    settingsFile  ""
    maxSrchDepth 0
    splitContainer 0
}

# setter for elements of the '::build::context' global array
#
# Parameters:
#   item        the array index
#   value       the new value for the element
#
proc g_set {item value} {
    set ::build::context($item) $value
}

# conditional setter for elements of the '::build::context' global array;
# only sets the element if it doesn't already exist
#
# Parameters:
#   item        the array index
#   value       the new value for the element
#
proc g_set_cond {item value} {
    if {![info exists ::build::context($item)]} {
        set ::build::context($item) $value
    }
}

# getter for elements of the '::build::context' global array
#
# Parameters:
#   item        the array index
#
# Returns:
#   On success, the value of the array at that index
#
# Note: This proc does not check for existance of the data before accessing
#       the array; if you don't know whether the array element in question
#       has already been set, you can check using the expression:
#               [info exists [g_get_var item]]
#
proc g_get {item} {
    return $::build::context($item)
}

# get the array variable reference for 'item' to be used where the
# name of that array element is needed, such as in '-textvariable' and
# '-variable' settings for Tk widgets and use in 'info exists' contexts.
#
# Parameters:
#   item - the index into the array '::build::context' for the reference
#
# Returns:
#   The name (or reference) to the array element in question:
#        "::build::context(value of 'item'>)"
#   so 'g_get_var bleh' returns '::build::context(bleh)'.
#
# Note: There is no requirement that '::build::context($item)' already exist;
#       this just produces the right 'name'
#
proc g_get_var {item} {
    return ::build::context($item)
}

# The global array 'inc_file_suffixes' contains the strings that are
# appended to the base include file name string (::build::context(includeBase))
# for building the name of files that will, if they exist, have their contents
# copied into the output at certain points of file generation.
# The index denotes the point in output generation that a given suffix is used.
#
#   head  - the suffix used for the 'local' file that is copied into the
#           <head> section of the generated HTML file following the
#           <title> element and anything copied from the site include file
#   css1  - the suffix used for the file that is copied into the beginning
#           of the generated CSS file following the generated comment line
#           and before any generated content
#   css2  - the suffix used for the file that is copied at the end of the
#           generated CSS file after all generated content has been written
#   body1 - the suffix used for the file that is copied into the generated
#           HTML file immediately after the "<body>" tag is written
#   body2 - the suffix used for the file that is copied into the generated
#           HTML file following the "<h1>" element for the page title
#   body3 - the suffix used for the file that is copied into the generated
#           HTML file immediately before the "</body>" tag at the end of
#           the output file
#   link1 - The suffix used to create the file name for an external CSS file;
#           if the file is found to exist at processing time, a "<link>"
#           element referencing that file as a stylesheet is written to 
#           the "<head>" section of the HTML file before the link to the
#           generated CSS file
#   link2 - The suffix used to create the file name for an external CSS file;
#           if the file is found to exist at processing time, a "<link>"
#           element referencing that file as a stylesheet is written to 
#           the "<head>" section of the HTML file following the link to the
#           generated CSS file
#   compatCSS1 - depricated; the suffix appended to the 'includeBase'
#                is used to make a filename.  If a file by that name
#                is found, a stylesheet link to that filename is written
#                to HTML file in the "<head>" section before the stylesheet
#                link to the generated CSS file
#                (Originally, only '.css' was added to 'includeBase' to
#                generate the name of the file linked before the link to
#                the generated CSS file; a new naming convention has been
#                set; checking for the file "local.css" (or now
#                "[string cat <includeBase> .css]") will be removed soon.
array set inc_file_suffixes {
    head  -head.txt
    css1  -css-start.inc
    css2  -css-end.inc
    body1 -body-top.txt
    body2 -body-main.txt
    body3 -body-end.txt
    dir1  -above.txt
    dir2  -below.txt
    link1 -early.css
    link2 -late.css
    compatCSS1  .css
}

set inc_file_descriptions {
    head   "Copied into the <head> element of the generated HTML file."
    css1   "Copied into the generated CSS file before generated styles."
    css2   "Copied into the generated CSS file after all generated styles."
    body1  "Copied into the generated HTML file following <body> tag."
    body2  "Copied into the generated HTML file following <h1> tag."
    body3  "Copied into the generated HTML file before </body> tag."
    dir1   "Per-directory pre-container include HTML."
    dir2   "Per-directory post-container include HTML."
    link1  "If found, a <link> for the stylesheet is generated before local."
    link2  "If found, a <link> for the stylesheet is generated after local."
}

# Log a warning to stderr when running interactively, don't bother when
# started as a GUI; if an interactive session thinks it's running directly,
# set ::build::noConsole to 0
#
# Parameters:
#   text - The message to write to stderr (actually, it's a list, and each
#          list entry is printed separately
#
proc logWarning {args} {
    if {!$::build::noConsole} {
        foreach thing $args {
            puts stderr $thing
        }
    }
}

# Log information to stdout  when running interactively, don't bother when
# started as a GUI; if an interactive session thinks it's running directly,
# set ::build::noConsole to 0
#
# Parameters:
#   text - The message to write to stdout (actually, it's a list, and each
#          list entry is printed separately
#
proc logInfo {args} {
    if {!$::build::noConsole} {
        foreach thing $args {
            puts stdout $thing
        }
    }
}

proc build_getStatList {} {
    return {
        directories
        containers
        blockCount
        infoFilesFound
        infoFilesCreated
        uniqueKeywords
        ignoredInfoLines
        illegalInfoLines
        illegalInfoTypes
        siteHTMLIncluded
        head
        css1
        css2
        body1
        body2
        body3
        dir1
        dir2
        link1
        link2
        compatCSS1
    }
}

# reset build statistics
proc build_resetStats {} {
    global page_stats
    foreach index [build_getStatList] {
        if {$index ne "illegalInfoTypes"} {
            set page_stats($index) 0
        } else {
            set page_stats($index) ""
        }
    }
}

# Show the statistics (really only visible in interactive sessions)
proc build_showStats {} {
    global page_stats
    logInfo "Page build statistics:"

    foreach {key value} [array get page_stats] {
        # sanitize the output (escape spaces and backslashes)
        set value [string map {{ } {\ } "\\" {\\}} $value]
        logInfo "[format "%20s: %s" $key $value]"
    }
}

# Increment a build statistic
proc build_incrStat {what} {
    global page_stats
    incr page_stats($what) 
}

# Add a character to the list of illegal line introducers
proc build_illegalInfoType {char} {
    global page_stats
    if {[string first "$char" $page_stats(illegalInfoTypes) 0] < 0} {
        set page_stats(illegalInfoTypes) \
            [string cat $page_stats(illegalInfoTypes) "$char"]
    } else {
        set page_stats(illegalInfoTypes) \
            [string cat $char $page_stats(illegalInfoTypes)]
    }
    build_incrStat illegalInfoLines
}

# Build an include file name out of its parts
proc incFileName {rel prefix type} {
    global inc_file_suffixes
    return [file join $rel [string cat $prefix $inc_file_suffixes($type)]]
}

# This is the regular expression for info lines
# usage: regexp $infoPat(line) $line matchVar typeVar tailVar
set infoPat(line) {^([.,<>\[\]{}`'"\|\\\-+%^~=&#@/!*\?\$\:\;])(.*)$}
#" ; #emacs has some trouble with the above definition
# This is the regular expression for classy paragraphs
# usage: regexp $infoPat(class) $tailVar matchVar classVar tailVar
set infoPat(class) {^([^\ ]+)(?:\ )(.*)$}
# This is the regular expression for style entries
# usage: regexp $infoPat(style) $tailVar matchVar classVar tailVar
set infoPat(style) $infoPat(class)
# This is the plain-text to HTML entity mapping table
# usage: string map $infoPat(entity) $remain
set infoPat(entity) {... &helip;}

# Initial suffix to catch multiple file types...
g_set imgGlobPattern {*.{jpg,png,gif}}

# Get the name of the current <div> style array
proc classVarName {className} {
    set cvname "$className-css"
    return $cvname
}

# Get the name of the current <img> style array
proc classImgVarName {className} {
    set cvname "$className-cssimg"
    return $cvname
}

# Get the name of the current ordered list variable
proc listVarName {className} {
    set clname "$className-ol"
    return $clname
}

# Get the name of the current unordered list variable
proc ulistVarName {className} {
    set clname "$className-ul"
    return $clname
}

# Get the name of the current keyword list variable
proc keywordVarName {className} {
    set kwlname "$className-kw"
    return $kwlname
}

# Add an ordered list item
proc addListItem {listName itemText} {
    set lvname [listVarName $listName]
    global $lvname
    upvar #0 $lvname listItems

    lappend listItems $itemText
    return [llength listItems]
}

# Add an unrdered list item
proc addUListItem {listName itemText} {
    set lvname [ulistVarName $listName]
    global $lvname
    upvar #0 $lvname listItems

    lappend listItems $itemText
    return [llength listItems]
}

# Add a keyword
proc addKeyword {listName keyword} {
    set kwlvname [keywordVarName $listName]
    global $kwlvname
    upvar #0 $kwlvname keywordList

    if {![info exists $kwlvname]} {
        set $kwlvname {}
    }

    if {[lsearch -nocase $keywordList $keyword] < 0} {
        lappend keywordList $keyword
    }

    if {[lsearch -nocase $::build::keywords $keyword] < 0} {
        lappend ::build::keywords $keyword
        build_incrStat uniqueKeywords
    }
}


# Add a style entry for the current <div>
proc addClassAttr {className attr val} {
    set cvname [classVarName $className]
    global $cvname
    upvar #0 $cvname cssArray
    set cssArray($attr) $val
}

# Add a style entry to the <img> or <figure> for the current <div>
proc addClassImgAttr {className attr val} {
    set cvname [classImgVarName $className]
    global $cvname
    upvar #0 $cvname cssArray
    set cssArray($attr) $val
}

# Get the path to the "info" file for a given image file
proc infoFilePath {imageFilePath} {
    set infoExt [g_get infoFileExt]
    if {[g_get useAltInfoDir]} {
        set infoPath [file tail $imageFilePath]
        set infoPath [string cat [file root $infoPath] $infoExt]
        set infoPath [file join [g_get altInfoPath] $infoPath]
    } else {
        set infoPath [string cat [file rootname $imageFilePath] $infoExt]
    }
    return $infoPath
}

# Break down and store the image presentation options
proc decode_media_options {optionText} {
    foreach option [split $optionText "|"] {
        if {[regexp {^(.+?):(.*)$} $option matched item value]} {
            set item  [string trim $item]
            set value [string trim $value]

            switch -nocase -- $item {
                attrs -
                attributes {
                    set ::build::mediaOptions(mediaAttrs) $value
                }
                alt-text -
                alt {
                    set ::build::mediaOptions(mediaAltText) $value
                }
                width {
                    set ::build::mediaOptions(mediaWidth) $value
                }
                height {
                    set ::build::mediaOptions(mediaHeight) $value
                }
                link {
                    set ::build::mediaOptions(mediaLink) $value
                }
                title {
                    set ::build::mediaOptions(mediaTitle) $value
                }
                figure -
                fig {
                    if {[expr $value] && 1} {
                        set value 1
                    } else {
                        set value 0
                    }
                    set ::build::mediaOptions(forceFigure) $value
                }
                default {
                    # unrecognized option line
                    logWarning "Unrecognized media attribute: $item"
                }
            }
        }
    }
}

# Read or generate meta-data for a named image file.
#
# Parameters:
#   iname    - path name of the image file relative to the HTML/CSS file
#              output directory
#   divClass - The unique class name for the <div> of the image file
#   divTitle - The default title text to be used in the <h3> at the top of
#              the <div> for the image; may be overridden by meta-data from
#              the info file (if any)
#
# The information returned as a list:
#       [list $displayList $titleText $addlClasses]
# where:
#   displayList is a list of the 'blocks' that will be written as HTML
#               elements.  Each block in 'displayList' has two entries, ie:
#                    [list $line $type]
#               where
#                 'line' is the text for an HTML element to be written to
#                        the HTML stream depending on 'type'; not used
#                        for some values of 'type'
#                 'type' indicates how the text in 'line' is translated
#                        to HTML:
#                        @    Normal paragram ("<p>$line<p>")
#                        !    Verbatim HTML line ("$line")
#                        +    Insert the ordered list ('line' ignored)
#                        .    Insert the unordered list ('line' ignored)
#                        xxx  Paragraph with a non-default class; 'xxx'
#                             is a place-holder here, it's anything that
#                             isn't listed above, and that string is
#                             used as the class for the paragraph:
#                                <p class="$type">$line</p>
#                             This corresponds to "%class ..." in the info
#                             files.
#   titleText contains the <div> "title"; the default value is '$divTitle'
#             (from the proc parameter), but this may be overridden by
#             an entry in the info file starting with a '='.
#   addClasses contains a list of zero or more extra classes for the
#              <div>.  Every generated <div> has at least two classes
#              specified in the 'class' attribute: 'boxed' and the unique
#              class name, in that order.  The "info" file may specify one
#              or more additional classes to be added between the two listed
#              above by lines starting with a '^' followed immediately by the
#              name of the extra class.  These extra classes appear, in order
#              following 'boxed' in the list. The <div> unique class is always
#              last in the list.
#
# In addition to the returned list detailed above, there are two lists and
# two arrays that are created in global scope for each <div>; these are not
# created or accessed directly in the proc "getMetaInfo", but instead by
# a number of helper procs, such as:
#     addListItem  --    builds a list of ordered list items in a global
#                        variable the name of which is effectively
#                        "${divClass}-ol"
#     addUListItem --    builds a list of unordered list items in a global
#                        variable the name of which is effectively
#                        "${divClass}-ul"
#     addClassAttr    -- builds an array of style entries for $divClass in
#                        a global variable named "${divClass}-css"
#     addClassImgAttr -- builds an array of style entries for "$divClass img"
#                        in a global variable named "${divClass}-cssimg"
#
# The two global variables directly referenced in the proc itself are:
#    infoPat     A global array used to store various patterns and such -
#       (line)     A regexp used to decode lines read from the info file.
#       (class)    A regexp used to split the '%' lines to get the class name.
#       (style)    A regexp used to split the attribute from value in style
#                  entries ('/' and '~').
#       (entity)   A fixed list of replacement patterns to be used with
#                  "string map" to make better HTML from paragraph and list
#                  text; not applied to raw text.
#    ::build::context Options set that affect the page generation
#       (genMissingInfo)
#                  When the value of this is non-zero, the procedure will
#                  create a crude "info" text file for the image file
#                  referenced by 'iname' if it cannot find one in the
#                  image directory.  When the value is 0, no attempt is made
#                  to create a missing info file.
#       (imgInFigure)
#                  When the value of this is non-zero, the <img> element
#                  for the image file is wrapped in a <figure> with the
#                  divTitle used as the figure caption.
#
proc getMetaInfo {iname divClass divTitle} {
    global infoPat

    # Strip the extension from the image file name and slap on an extension
    # to make the name of the "info" file assoicated with the image.
    set infoFileName [infoFilePath $iname]
    set dList {}
    set tText {}
    set bClass {}
 
    set ::build::mediaOptions(mediaAttrs) ""
    set ::build::mediaOptions(mediaAltText) ""
    set ::build::mediaOptions(mediaWidth) ""
    set ::build::mediaOptions(mediaHeight) ""
    set ::build::mediaOptions(mediaLink) ""
    set ::build::mediaOptions(mediaTitle) ""
    set ::build::mediaOptions(forceFigure) 0
    set ::build::mediaOptions(mediaCaption) ""

    if {[file exists $infoFileName]} {
        set tfd [open $infoFileName "r"]
        set line ""
        while {[set cnt [gets $tfd line]] >= 0} {
            if {$cnt > 0} {
                if {![regexp $infoPat(line) $line matched bgn remain]} {
                    set bgn [string range $line 0 0]
                    set remain $line
                }
            } else {
                set bgn {@}
                set remain {&nbsp;}
            }                

            # Note that we always must treat the input data as strings,
            # not lists. This prevents problems when Tcl converts a string
            # that is not a well formed Tcl list to a list; even strings
            # that are well formed lists get messed up if there are
            # quoted sections or various braces within them.
            switch -exact -- $bgn {
                + {
                    # Add ordered list item
                    set remain [string map $infoPat(entity) $remain]
                    set ll [addListItem $divClass $remain]
                    if {1 == $ll} {
                        # set line list appears at
                        lappend dList [list {} +]
                    }
                }
                . {
                    # Add uordered list item
                    set remain [string map $infoPat(entity) $remain]
                    set ll [addUListItem $divClass $remain]
                    if {1 == $ll} {
                        # set line list appears at
                        lappend dList [list {} .]
                    }
                }
                @ {
                    # Add paragraph (no class specified)
                    set remain [string map $infoPat(entity) $remain]
                    lappend dList [list $remain {}]
                }
                % {
                    # Add paragraph (explicit class specified)
                    regexp $infoPat(class) $remain matched class remain
                    set remain [string map $infoPat(entity) $remain]
                    lappend dList [list $remain $class]
                }
                = {
                    # Override "title"
                    set tText $remain
                }
                ~ {
                    # Add to CSS style for this item
                    regexp $infoPat(class) $remain matched attr remain
                    addClassAttr $divClass $attr $remain
                }
                / {
                    # Add to CSS style to the <img> for this item
                    regexp $infoPat(class) $remain matched attr remain
                    addClassImgAttr $divClass $attr $remain
                }
                ^ {
                    # Add additional class to <div> for the item
                    lappend bClass $remain
                }
                ! {
                    # Add a raw line of HTML (not in a <p>)
                    lappend dList [list $remain !]
                }
                * {
                    # Add keywords
                    foreach kwd [split $remain ,] {
                        addKeyword $divClass [string trim $kwd]
                    }
                }
                # -
                ; -
                : {
                    # # Comment, do nothing
                    # : is data for other programs, and is ignored here
                    # ; is also data for other programs, and is ignored here
                    build_incrStat ignoredInfoLines
                }

                & {
                    set sel [string range $remain 0 0]
                    set remain [string range $remain 1 end]
                    switch -- $sel {
                        0 {
                            # media file attributes
                            decode_media_options $remain
                        }
                        1 {
                            # media (figure) caption text
                            set ::build::mediaOptions(mediaCaption) \
                                [string trim $remain]
                        }
                        default {
                            logWarning "Unrecognized extended markup: &${sel}"
                        }
                    }
                }

                default {
                    # unrecognized line type
                    logWarning "'$bgn'? dropping: $line"
                    build_illegalInfoType $bgn
                }
            }
        }
        close $tfd
        logInfo "Found description in $infoFileName"
        build_incrStat infoFilesFound
    } else {
        if {0 != [g_get genMissingInfo]} {
            if {[g_get useAltInfoDir] && [g_get newInfoLoc] == 1} {
                set infoFileName \
                    [string cat [file rootname $iname] [g_get infoFileExt]]
            }
            set tfd [open $infoFileName "w"]
            puts $tfd "=$divTitle"
            puts $tfd "@Description of $divTitle as shown in $iname"
            puts $tfd ".\"<tt>$infoFileName</tt>\""
            puts $tfd "@<strong>Update this file!</strong>"
            close $tfd
            logInfo "Created template image info file \"$infoFileName\""
            build_incrStat infoFilesCreated
        }
    }
    if {[llength $dList] < 1} {
        lappend dList [list "Description of $divTitle as shown in $iname" {}]
    }

    return [list $dList $tText $bClass]
}

# write an <img> element or <video> element to the HTML output stream
proc htmlMedia {hfd imgFile altText} {
    switch -nocase -- [file extension $imgFile] {
        .mp4 {
            htmlVideo $hfd $imgFile $altText "video/mp4"
        }
        .ogg {
            htmlVideo $hfd $imgFile $altText "video/ogg"
        }
        .webm -
        .vp8 {
            htmlVideo $hfd $imgFile $altText "video/webm"
        }

        default {
            htmlImage $hfd $imgFile $altText
        }
    }
}

# write an <img> element to the output stream.  If the setting 'imgInFigure'
# is true (1), it is written as a <figure> element with the <img> and a
# <figcaption> element within its body.  The setting 'linkImgFiles' makes
# the <img> a hyperlink to the image file.
proc htmlImage {hfd imgFile altText} {
    set imgAttrs \
        [concat [g_get imgElementAttr] $::build::mediaOptions(mediaAttrs)]

    if {[set temp $::build::mediaOptions(mediaWidth)] ne ""} {
        if {[regexp {^(.*)(width="[0-9]+")(.*)$} $imgAttrs d a b c]} {
            logWarning "Discarding existing $b from attrs"
            set imgAttrs [concat $a $c]
        }
        set imgAttrs [concat $imgAttrs "width=\"$temp\""]
    }
    if {[set temp $::build::mediaOptions(mediaHeight)] ne ""} {
        if {[regexp {^(.*)(height="[0-9]+")(.*)$} $imgAttrs d a b c]} {
            logWarning "Discarding existing $b from attrs"
            set imgAttrs [concat $a $c]
        }
        set imgAttrs [concat $imgAttrs "height=\"$temp\""]
    }

    set link [g_get linkImgFiles]
    set pre ""
    set post ""

    if {[set temp $::build::mediaOptions(mediaTitle)] ne ""} {
        set titleText $temp
    } else {
        set titleText $imgFile
    }

    if {[set temp $::build::mediaOptions(mediaAltText)] ne ""} {
        set altText $temp
    }

    if {[set temp $::build::mediaOptions(mediaLink)] ne ""} {
        set linkURL $temp
        set linkTitle ""
        set link 1
    } else {
        set linkURL $imgFile
        set linkTitle " title=\"View $imgFile\""
    }

    if {$link} {
        set pre \
            "<a href=\"$linkURL\" $linkTitle target=\"_blank\">"
        set post "</a>"
    }

    if {[g_get imgInFigure] || $::build::mediaOptions(forceFigure)} {
        if {[set temp $::build::mediaOptions(mediaCaption)] ne ""} {
            set caption $temp
        } else {
            set caption $altText
        }
        set pre [string cat " <figure>\n" $pre]
        set post [string cat $post "  <figcaption>$caption</figcaption>\n"]
        set post [string cat $post " </figure>"]
    }

    set imgAttrs [concat $imgAttrs "title=\"$titleText\" alt=\"$altText\""]
    puts $hfd \
        "$pre<img src=\"$imgFile\" $imgAttrs>$post"
}


proc htmlVideo {hfd vidFile altText vidType} {
    set imgAttrs [g_get imgElementAttr]

    set link [g_get linkImgFiles]
    set pre ""
    set post ""

    if {[g_get imgInFigure]} {
        set pre " <figure>\n"
        if {$link} {
            set capLink \
                "<a href=\"$vidFile\" title=\"View $vidFile\" target=\"_blank\">"
            set capLinkE "</a>"
        } else {
            set capLink ""
            set capLinkE ""
        }

        set post "  <figcaption>${capLink}$altText${capLinkE}</figcaption>\n"
        set post [string cat $post " </figure>"]
    }

    puts $hfd "$pre\n<video controls $imgAttrs>"
    puts $hfd " <source src=\"$vidFile\" type=\"$vidType\">"
    puts $hfd "This browser seems not to support HTML5 video."
    puts $hfd "</video>\n$post"
}

# write an HTML header paragraph element; the header level is specified
# by the 'lvl' parameter, the body of the element is taken from 'text'
proc htmlHeader {hfd lvl text} {
    puts $hfd "<h$lvl>$text</h$lvl>"
}

# Unset the global keyword list variable for the current block
proc forgetKeywords {blockName} {
    set kwvname [keywordVarName $blockName]
    global $kwvname
    if {[info exists $kwvname]} {
        unset $kwvname
    }
}

# Create the keyword list in the HTML output if there are any keywords
# to be written; if the keyword list is empty, don't write anything
#
# Parameters:
#   hfd       - the handle of the open HTML output stream
#   blockName - the name the block class on which the names of the global
#               vars for the current image <div> are based
#
proc htmlKeywords {hfd blockName} {
    set kwvname [keywordVarName $blockName]
    global $kwvname
    upvar #0 $kwvname keywordList

    if {[info exists keywordList]} {
        # The list exists
        if {[llength $keywordList] > 0} {
            # There are keywords in the keyword list
            set nf 0
            set kwdP [htmlClass kwdListPara]
            set kwdL [htmlClass kwdLabel]
            set kwdT [htmlClass kwdList]

            set kwp \
                "<span class=\"$kwdL\">Keywords:</span><span class=\"$kwdT\">"
            foreach keyword $keywordList {
                if {$nf} {
                    set kwp [string cat $kwp ","]
                }
                set kwp [concat $kwp $keyword]
                set nf 1
            }
            puts $hfd "<p class=\"$kwdP\">$kwp</span></p>"
        }
    }
}

# emit an ordered list if any ordered list elements are define, otherwise
# don't write anything (no empty <ol> elements).
#
# Parameters:
#   hfd      - the handle of the open HTML output stream
#   listName - the name of a list variable defined in global scope that
#              contains a list of element body text strings
#
# Note: For housekeeping reasons, the global list variable is unset after
#       the list has been written; this is intended to prevent memory
#       leaks; there is currently at most 1 ordered list defined, and
#       it will only be written to the output file one time.
proc htmlOrderedList {hfd listName} {
    set lvname [listVarName $listName]
    global $lvname
    upvar #0 $lvname listItems

    if {[info exists listItems]} {
        if {[llength $listItems] > 0} {
            puts $hfd "<ol>"
            foreach item $listItems {
                puts $hfd " <li>$item</li>"
            }
            puts $hfd "</ol>"
        }
        unset listItems
    }
}

# emit an unordered list if any ordered list elements are define, otherwise
# don't write anything (no empty <ul> elements).
#
# Parameters:
#   hfd      - the handle of the open HTML output stream
#   listName - the name of a list variable defined in global scope that
#              contains a list of element body text strings
#
# Note: For housekeeping reasons, the global list variable is unset after
#       the list has been written; this is intended to prevent memory
#       leaks; there is currently at most 1 uordered list defined, and
#       it will only be written to the output file one time.
proc htmlUnorderedList {hfd listName} {
    set lvname [ulistVarName $listName]
    global $lvname
    upvar #0 $lvname listItems

    if {[info exists listItems]} {
        if {[llength $listItems] > 0} {
            puts $hfd "<ul>"
            foreach item $listItems {
                puts $hfd " <li>$item</li>"
            }
            puts $hfd "</ul>"
        }
        unset listItems
    }
}

# write the style entry for the current image/div to the CSS output stream
#
# Parameters:
#   cfd       - The descriptor for the open CSS output stream
#   className - A string representing the unique name of the class associated
#               with the current image file name being processed
#
# Note: For housekeeping reasons, the global array variable that holds
#       the style information used is unset after the stylesheet text
#       has been written; this is intended to prevent memory leaks.
#       The style arrays (one for the block the other for the <img> or
#       <figure> tags within the block) are separate from the array that
#       contains the remainder of the information for the image file
#       being processed; removing those global array variables here frees
#       the caller of having to keep track of them after it's used them.
proc cssClassEntry {cfd className} {
    set cvname [classVarName $className]
    global $cvname
    upvar #0 $cvname cssArray

    puts $cfd ".$className \{"
    if {[array exists cssArray]} {
        foreach {attrName attrVal} [array get cssArray] {
            puts $cfd "$attrName: $attrVal;"
        }
    }
    puts $cfd "\}"
    puts $cfd ""

    unset cssArray
}

# write the style entries for an <img> or <figure> in the current the current
# div to the CSS output stream
#
# Parameters:
#   cfd       - The descriptor for the open CSS output stream
#   className - A string representing the unique name of the class associated
#               with the current image file name being processed
#
# Note: See note in the comments for 'cssClassEntry', above, for information
#       about housekeeping and what happens to the global style array when
#       the output has been written.
proc cssClassImgEntry {cfd className} {
    set cvname [classImgVarName $className]
    global $cvname
    upvar #0 $cvname cssArray

    if {[g_get imgInFigure]} {
        set element "figure"
    } else {
        set element "img"
    }
    puts $cfd ".$className $element \{"
    if {[array exists cssArray]} {
        foreach {attrName attrVal} [array get cssArray] {
            puts $cfd "$attrName: $attrVal;"
        }
    }
    puts $cfd "\}"
    puts $cfd ""
    if {[g_get imgInFigure]} {
        puts $cfd ".$className figcaption \{"
        puts $cfd " text-align: center;"
        puts $cfd "\}"
        puts $cfd ""
    }

    unset cssArray
}

# Check for the existance of a text file; if the file is found, copy its
# contents to the specified output stream.
#
# Parameters:
#   ofd     - the descriptor of the open output stream to write to
#   incFile - the name of the file to conditionally copy to the output stream
#   comType - indicates the content type; "html", "css", or "" - determines
#             the type of delimiters are used for comments that are written
#             before or after the text copied from the include file; if "",
#             no comments are written
#   stat    - the name of the statistic to update when the include file is
#             found
# Note: The comment markers are different for CSS style sheets vs. HTML
#       files, and between most of the HTML file and the stylesheet sections
#       of HTML files.
proc includeFile {ofd incFile comType stat} {
    if {[file exists $incFile]} {
        set bgn ""
        set end ""

        if {$comType ne ""} {
            set bgn [commentDelimiter $comType open]
            set end [commentDelimiter $comType close]
            puts $ofd "${bgn} Content from \"$incFile\" - Begin ${end}"
        }

        set inFile [open $incFile r]
        set includeText [read $inFile]
        close $inFile
        build_incrStat $stat
        foreach line [split $includeText \n] {
            puts $ofd $line
        }
        if {$comType ne ""} {
            puts $ofd "${bgn} Content from \"$incFile\" - End   ${end}"
        }
    }
}

# Open the output CSS file for writing.  If the file exists, it is truncated
# (the existing contents are lost), otherwise it is created.
# The initial part of the CSS file is generated, including the optional
# include file contents and definitions for the flex container <div> class
# styles
#
# Parameters:
#   cfile   - The name of the CSS file to be written
#   relPath - The relative path to the image director where the include
#             file might be found
# Returns:
#   The file descriptor for the open CSS output stream
#
proc cssNew {cfile relPath} {
    set cfd [open $cfile "w"]

    puts $cfd "/* generated on [clock format [clock seconds]] */"

    # Include the contents of "<base>-css-start.inc" (if it exists)
    # at the top of the generated CSS file
    includeFile $cfd [incFileName $relPath [g_get includeBase] css1] css css1

    puts $cfd ".[htmlClass container] \{"
    puts $cfd "  display: flex;"
    puts $cfd "  flex-flow: row wrap;"
    puts $cfd "  flex-wrap: wrap;"
    puts $cfd "  justify-content: space-between;"
    puts $cfd "  align-items: stretch;"
#    puts $cfd "  background-color: rgb(180,180,180);"
    puts $cfd "\}"
    puts $cfd ""
    puts $cfd ".[htmlClass flexDiv] \{"
    puts $cfd "  padding-right: 1em;"
    puts $cfd "  padding-left: 1em;"
    puts $cfd "\}"
    puts $cfd ""

    return $cfd
}

# Close the CSS file output stream, conditionally including definitions from
# an external text file
#
# Parameters:
#   cfd     - The CSS output stream descriptor
#   relPath - The relative path to the image director where the include
#             file might be found
proc cssFinish {cfd relPath} {
    # Include the contents from "<base>-css-end.inc" (if it exists)
    # immediately before the end of the generated CSS file
    includeFile $cfd [incFileName $relPath [g_get includeBase] css2] css css2

    close $cfd
}

# Emit a "<link>" element to the HTML output stream
#
# Parameters:
#   ofd     - open file descriptor for the HTML output stream
#   extFile - path name of the external file to link
#   extRel  - the value of the "rel" attribute, usually 'stylesheet'
#   extType - the value of the "type" attribute, usually 'text/css'
#   force   - controls whether the <link> element is generated if the
#             file named by 'extFile' is not found; when 'force' is 1,
#             the <link> element is always written, if 0, then it is
#             only written when the file is found during processing
#   stat    - the statistic to update if the link is written
#
proc htmlLink {ofd extFile extRel extType force stat} {
    if {$force || [file exists $extFile]} {
        puts $ofd " <link rel=\"$extRel\" href=\"$extFile\" type=\"$extType\">"
        if {$stat ne ""} {
            build_incrStat $stat
        }
    }
}

# Create the HTML output file, populate the <head> section and open the <body>
# section.
#
# Parameters:
#   hfile     - the name of the HTML file to create
#   cfile     - the name of the CSS file that will be generated
#   relPath   - path to look for local 'include' files
#   titleText - string used in the body of the <title> and <h1> elements
#
# Returns:
#   On success, returns the open file descriptor for the HTML output stream
#
proc htmlNew {hfile cfile relPath titleText} {
    set baseInc [g_get includeBase]
    set hfd [open $hfile "w"]

    # start the file with a doctype declaration for HTML
    puts $hfd "<!DOCTYPE html>"

    # open the <html> document element
    puts $hfd "<html>"
    # open the <head> element in the <html> element body
    puts $hfd "<head>"
    # add a comment to say when this file was created
    puts $hfd "<!-- generated on [clock format [clock seconds]] -->"
    # add the <title> element
    puts $hfd " <title>$titleText</title>"

    # include the site-wide include file contents, if applicable
    if {[g_get siteFileName] ne ""} {
        # If there is a site include file, include it
        if {[g_get siteFilePath] eq ""} {
            g_set siteFilePath [pwd]
        }
        includeFile $hfd [file join [g_get siteFilePath] [g_get siteFileName]] \
            html siteHTMLIncluded
    }

    # add a <link> to the collection .css file (deprecated)
    htmlLink $hfd [incFileName $relPath collection compatCSS1] \
        stylesheet text/css 0 compatCSS1

    # Add a <link> element to reference an external stylesheet if a file
    # with the right name for the 'link1' stage is found
    htmlLink $hfd [incFileName $relPath $baseInc link1] \
        stylesheet text/css 0 link1

    # Include "<base>-head.inc" (if one exists)
    # after the first style sheet <link>
    # but before the generated style sheet <link>
    includeFile $hfd [incFileName $relPath $baseInc head] html head

    # Create the <link> element referencing the generated CSS file; it doesn't
    # actually exist yet, so we force the issue
    htmlLink $hfd $cfile stylesheet "text/css" 1 ""

    # Add a <link> element to reference an external stylesheet if a file
    # with the right name for the 'css2' stage is found
    htmlLink $hfd [incFileName $relPath $baseInc link2] \
        stylesheet "text/css" 0 link2

    # Close the '<head> element, open the <body> element
    puts $hfd "</head>"
    puts $hfd "<body>"

    # Include "<base>-start.inc" (if one exists)
    # immediately after the "<body>" tag
    includeFile $hfd [incFileName $relPath $baseInc body1] html body1

    # Put in the title header
    htmlHeader $hfd 1 $titleText

    # If the file "<base>-main.inc" exists in the image directory,
    # include its contents after the title and before the flex container
    # division.
    includeFile $hfd [incFileName $relPath $baseInc body2] html body2

    # return the open file descriptor
    return $hfd
}

# Write out the last part of the generated HTML by closing the flex container,
# conditionally copying text from an external include file, closing the <body>
# and <html> elements, then closing the output file stream.
#
# Parameters:
#   hfd     - The HTML output stream descriptor
#   relPath - The relative path to the image director where the include
#             file might be found
proc htmlFinish {hfd relPath} {
    set baseInc [g_get includeBase]

    # Include "<base>-start.inc" (if one exists)
    # immediately after the "<body>" tag
    includeFile $hfd [incFileName $relPath $baseInc body3] html body3

    # Close the <body> element
    puts $hfd "</body>"
    # Close the <html> element (and thus the HTML document)
    puts $hfd "</html>"
    # close the output stream
    close $hfd
}

# This procedure is responsible for collecting the meta-data for an image
# file, working out a unique class name based on the file name, and
# writing a '<div>' with that unique class name to the HTML output stream.
# The generated <div> includes the image (as a floating <img> element)
# and the text information from the meta-data.
# Style sheet entries with presentation attribute of the unique <div> class
# and the embedded <img> element within it are written to the CSS stream.
#
# Parameters:
#   hfd      - The open file descriptor for the HTML file output stream
#   hcd      - The open file descriptor for the CSS file output stream
#   rel      - The relative path from the output directory to the
#              image directory
#   imgName  - The name of the image file for the new <div>
#   firstMap - A list of text replacements, ala "string map", that will
#              be used as part of converting the file name to a default
#              title for the <div> and for the unique class name. Must have
#              be an even number of elements or be empty.
#                eg: '{{-extra-something"} {}}' will remove '-extra-something'
#                    from the file name before doing other replacements.
#
proc make_image_div {hfd hcd rel imgName {firstMap {}}} {
    # strip the extension
    set baseName [file root $imgName]

    # use mapping to create the default title for this <div>
    set mungString [concat $firstMap {{-} { } {_} { }}]
    set divTitle [string map $mungString $baseName]

    # Sanitize the title to generate the unique class name
    set divClass [string cat "d-" \
                       [string map {{ } {-} ( {} ) {} & _} $divTitle]]

    # Make the qualified relative path name for the image file
    set filePath [file join $rel $imgName]

    # Set some default style attributes to the class for the <div>
    addClassAttr $divClass flex "0 1 500px"
#    addClassAttr $divClass background-color "rgba(180,210,190,0.9)"
#    addClassAttr $divClass background-image "url($filePath)"
#    addClassAttr $divClass background-repeat "no-repeat"
#    addClassAttr $divClass background-size "contain"
    addClassAttr $divClass max-width "500px"
    addClassAttr $divClass height "auto"

    # set the default style attribute for the <img> within the <div>
    addClassImgAttr $divClass float right

    set iDesc [getMetaInfo $filePath $divClass $divTitle]
    set dList [lindex $iDesc 0]
    set tText [lindex $iDesc 1]
    set bClass [lindex $iDesc 2]
    set dClass [htmlClass flexDiv]

    if {[llength $tText] == 0} {
        set tText $divTitle
    }
    if {$bClass == {}} {
        puts $hfd "<div class=\"$dClass $divClass\">"
    } else {
        puts $hfd "<div class=\"$dClass $bClass $divClass\">"
    }
    puts $hfd " <h3>$tText</h3>"
    # htmlImage $hfd "$filePath" $tText
    htmlMedia $hfd "$filePath" $tText
    if {[g_get kwdLocation] == 1} {
        htmlKeywords $hfd $divClass
    }
    foreach dl $dList {
        if {[lindex $dl 1] == {}} {
            puts $hfd " <p>[lindex $dl 0]</p>"
        } else {
            set cl [lindex $dl 1]
            set bd [lindex $dl 0]
            switch -- $cl {
                + {
                    # put the ordered list here
                    htmlOrderedList $hfd $divClass
                }
                . {
                    # put the unordered list here
                    htmlUnorderedList $hfd $divClass
                }
                ! {
                    # raw HTML
                    puts $hfd "$bd"
                }
                default {
                    # this is a classy paragraph 
                    puts $hfd " <p class=\"$cl\">$bd</p>"
                }
            }
        }
    }
    if {[g_get kwdLocation] == 2} {
        htmlKeywords $hfd $divClass
    }

    puts $hfd "</div><!-- $divClass -->"

    cssClassEntry $hcd $divClass
    cssClassImgEntry $hcd $divClass

    # release resources that hold the keyword list
    forgetKeywords $divClass

    # count the block generated
    build_incrStat blockCount
}

# Open a flex container
proc start_flex_container {hfd imgDirPath} {
    if {$imgDirPath ne ""} {
        includeFile $hfd [incFileName $imgDirPath [g_get includeBase] dir1] \
            html dir1
    }
    g_set currentImgDir $imgDirPath
    puts $hfd "<div class=\"[htmlClass container]\">"
    build_incrStat containers
}

# Close a flex container
proc end_flex_container {hfd} {

    set imgPath [g_get currentImgDir]
    puts $hfd "</div><!-- posSet $imgPath -->"
    if {$imgPath ne ""} {
        includeFile $hfd [incFileName $imgPath [g_get includeBase] dir2] \
            html dir2
    }
    g_set currentImgDir ""
}

# Split the container
proc split_container {hfd nextDirName} {
    # todo, sort of...
    if {[g_get currentImgDir] ne ""} {
        end_flex_container $hfd
        puts $hfd ""
    }
    if {[g_get contTitles]} {
        puts $hfd "<h2>Folder: $nextDirName</h2>"
    }
    start_flex_container $hfd $nextDirName
}

# Build the list of image files based on a pattern.
proc find_image_files {relPath pattern {depth 0}} {
    # The building of the image file list is done from within the
    # image directory itself; this saves having to strip the path
    # components off the individual file names. Only the 'glob'
    # need be done from there, so the current directory is restored
    # once the globbing is done.
    set odir [pwd] ; # Don't forget where we started
    cd $relPath ;    # Switch to the image directory
    set subFileList {}

    if {[g_get maxSrchDepth] > $depth} {
        set subList [glob -nocomplain -types {d} *]
        foreach sub $subList {
            set subFiles [find_image_files $sub $pattern [expr $depth + 1]]
            if {[llength $subFiles] && [g_get splitContainer]} {
                lappend subFileList [file join $relPath $sub]
            }
            foreach subName $subFiles {
                lappend subFileList [file join $relPath $subName]
            }
        }
    }

    set fileList [glob -nocomplain $pattern] ; # get the list of image files

    if {!$depth && [llength $fileList] && [g_get splitContainer]} {
        lappend subFileList $relPath
    }

    foreach subName $fileList {
        lappend subFileList [file join $relPath $subName]
    }
    cd $odir ;       # Return to the output directory

    # count the directory
    build_incrStat directories
    
    return $subFileList
}

# This is the main coordinating proc for creating the HTML and CSS files.
# It drives the gathering of information from the image, info and other
# files and the writing of the output files.
# Parameters:
#   hfile - The name of the HTML file to generate; any existing file with
#           the same name will be overwritten
#   cfile - The name of the CSS file to generate; any existing file with
#           the same name will be overwritten
#   relPath - The relative path from the current directory to the image
#             file directory; an absolute path may make for unusable
#             HTML generated in some (maybe most) cases
#   pattern - The file selection pattern used to "glob" the image files
#             that are to be selected for this page generation.
#             Defaults to all GIF, PNG, and JPG files
#   repList - List of "string map" style replacements; must be well formed
#             or an error is likely
proc build_page {hfile cfile relPath \
                     {pattern {*.{png,gif,jpg,jpeg}}} {repList {}}} {
    # clear the list of all keywords encountered
    set ::build::keywords {}

    # reset the build statistics
    build_resetStats

    # Determine the page title
    if {[string trim [g_get pageTitle]] eq ""} {
        g_set pageTitle "Catalog of $relPath"
    }

    # open and populate the beginning of the new HTML file.
    # The file is created in the current directory
    set hfd [htmlNew $hfile $cfile $relPath [g_get pageTitle]]

    # open and populate the beginning of the new CSS file
    # The file is created in the current directory
    set cfd [cssNew $cfile $relPath]

    # If the user forgot to put a wildcard in the selection pattern,
    # add one to the beginning.
    # TODO: This ought to look for any of the special characters
    #       recognized by 'glob', not just '*'
    if {[string first * $pattern] < 0} {
        set pattern "*$pattern"
    }

    set fileList [find_image_files $relPath $pattern]

    if {![g_get splitContainer]} {
        start_flex_container $hfd $relPath
    } else {
        g_set currentImgDir ""
    }

    # Step through the selected image file names to create a <div>
    # specific to each one from the meta-data contained in the
    # associated text "info" file. If no info file for a selected
    # image is found, some basic (and generic) meta-data will be
    # provided.
    foreach pname $fileList {
        if {[file isdirectory $pname]} {
            split_container $hfd $pname
        } else {
            set pfile [file tail $pname]
            set filePath [file dirname $pname]
            make_image_div $hfd $cfd $filePath $pfile $repList
        }
    }
    end_flex_container $hfd

    # Finish off the HTML file contents and close it
    htmlFinish $hfd $relPath

    # Finish off the CSS file contents and close it
    cssFinish $cfd $relPath

    # display the stats in some cases
    build_showStats
}

# Make the second path relative to the first path if possible
proc make_relative {pathA pathB} {
    set pathA [file normalize $pathA]
    set pathB [file normalize $pathB]
    set chunkA [file split $pathA]
    set chunkB [file split $pathB]
    set relPath {}
    set maxLen [llength $chunkA]
    if {[llength $chunkB] > $maxLen} {
        set maxLen [llength $chunkB]
    }
    set cursor 0
    if {$pathA eq $pathB} {
        set relPath .
    } else {
        while {[lindex $chunkA $cursor] eq [lindex $chunkB $cursor]} {
            incr cursor 1
        }
        if {$cursor == 0} {
            set relPath $pathB
        } elseif {[lindex $chunkA $cursor] eq ""} {
            for {} {$cursor < $maxLen} {incr cursor 1} {
                set relPath [file join $relPath [lindex $chunkB $cursor]]
            }
        } elseif {[lindex $chunkB $cursor] eq ""} {
            for {} {$cursor < $maxLen} {incr cursor 1} {
                set relPath [file join $relPath ..]
            }
        } else {
            for {set tmp $cursor} {$tmp < [llength $chunkA]} {incr tmp 1} {
                set relPath [file join $relPath ..]
            }
            for {} {$cursor < [llength $chunkB]} {incr cursor 1} {
                set relPath [file join $relPath [lindex $chunkB $cursor]]
            }
        }
    }
    return $relPath;
}

# procedure to update the message area of the application window
proc display_gui_message {message {delay 0}} {
    set messageWin [get_wp messageWin]
    $messageWin configure -text $message
    update
    if {$delay > 0} {
        after [expr $delay * 1000] [list $messageWin configure -text ""]
    }
}


# load the settings from a file
proc load_page_settings {w ask args} {
    display_gui_message "Loading page settings..." 0

    if {[info exists saveSettings(settingsFile)] && \
            $saveSettings(settingsFile) ne ""} {
        set saveFile [g_get settingsFile]
        set savePath [file dirname $saveFile]
        set defFile [file tail $saveFile]
    } else {
        set defFile "_buildmeta.set"
        set savePath [g_get outDirPath]
        if {$savePath eq ""} {
            set savePath [pwd]
        }
        set ask 1
    }
    if {$ask} {
        set saveFile [tk_getOpenFile -initialdir $savePath \
                          -filetypes {
                              {{Settings Files} {.set}}
                              {{Text Files}     {.txt}}
                              {{All Files}      {*}}} \
                          -initialfile $defFile -parent [get_wp mainWindow] \
                          -title "Read settings from..."]
        if {$saveFile eq ""} {
            display_gui_message "Load Cancelled" 10
            return
        }
    }

    set fd [open $saveFile r]
    array set savedSettings [read -nonewline $fd]
    close $fd
    foreach {key value} [array get savedSettings] {
        g_set $key $value
    }
    g_set settingsFile $saveFile
    display_gui_message "Settings loaded" 10
    update_some_menu_entries 0 outDirPath altInfoPath imgPathAbs
}

# write the current settings out to a file
proc save_page_settings {w ask args} {
    display_gui_message "Saving page settings..." 0
    array set saveSettings [array get ::build::context]
    if {[info exists saveSettings(currentImgDir)]} {
        unset saveSettings(currentImgDir)
    }

    if {[info exists saveSettings(settingsFile)] && \
            $saveSettings(settingsFile) ne ""} {
        set saveFile $saveSettings(settingsFile)
        unset saveSettings(settingsFile)
        set savePath [file dirname $saveFile]
        set defFile [file tail $saveFile]
    } else {
        set defFile "_buildmeta.set"
        set savePath [g_get outDirPath]
        if {$savePath eq ""} {
            set savePath [pwd]
        }
        set ask 1
    }

    if {$ask} {
        set saveFile [tk_getSaveFile -initialdir $savePath \
                          -defaultextension ".set" \
                          -filetypes {
                              {{Settings Files} {.set}}
                              {{Text Files}     {.txt}}
                              {{All Files}      {*}}} \
                          -initialfile $defFile -parent [get_wp mainWindow] \
                          -title "Save settings as..."]
        if {$saveFile eq ""} {
            display_gui_message "Save Cancelled" 10
            return
        }

        # add an extension if none was provided
        if {[file extension $saveFile] eq ""} {
            set saveFile [string cat $saveFile .set]
        }
    }

    g_set settingsFile $saveFile
    set fd [open $saveFile w]
    puts $fd [array get saveSettings]
    close $fd

    display_gui_message "Settings saved" 10
}

# Control some menu item availability based on current settings
proc update_some_menu_entries {caller args} {
    set menu [get_wp utilMenu]
    foreach {what where} {
        outDirPath  "*Output*"
        imgPathAbs  "*Media*"
        altInfoPath "*Info*"
    } {
        set path [string trim [g_get $what]]
        if {$path ne "" && [file isdirectory $path]} {
            set state normal
        } else {
            set state disabled
        }
        logInfo "Configuring the $what entry ($where) as $state"
        $menu entryconfigure $where -state $state
    }
}

# procedure to display the directory chooser for the document directory
# where the HTML and CSS files will be generated
proc select_doc_root {win} {
    set dirname [tk_chooseDirectory -initialdir [g_get outDirPath] \
                     -title {Select the directory for the HTML files} \
                     -parent $win]
    if {$dirname ne {}} {
        if {$dirname ne [g_get outDirPath]} {
            if {[g_get imgPathAbs] ne ""} {
                g_set [make_relative $dirname [g_get imgPathAbs]]
            }
            g_set outDirPath $dirname
        }
    }
    update_some_menu_entries 0 outDirPath
    return [g_get outDirPath]
}

# procedure to display the directory chooser for the image directory
# from which the image names and info files will be read when constructing
# the output.
proc image_file_dir {win prior} {
    if {$prior eq ""} {
        set prior [g_get outDirPath]
    }
    set dirname [tk_chooseDirectory -initialdir $prior \
                     -title {Select the directory for the imaage files} \
                     -parent $win]
    if {$dirname eq ""} {
        set dirname $prior
    }
    return $dirname
}

# command procedure for the "Document Dir" button
proc do_sel_root {win} {
    set newRoot [select_doc_root $win]
}

# command procedure for the "Media Dir" button
proc do_sel_image {win} {
    set dirname [image_file_dir $win [g_get imgPathAbs]]
    if {$dirname ne ""} {
        g_set imgPathAbs $dirname
        # The absolute path to the image dir is shown along with
        # the relative path that will be used in the generated
        # HTML
        g_set imgPathRel [make_relative [g_get outDirPath] $dirname]
    }
    update_some_menu_entries 0 imgAbsPath
}

# command procedure for the "Alt Info Dir" button
proc do_alt_info {win} {
    if {[g_get altInfoPath] eq ""} {
        g_set altInfoPath [g_get imgPathAbs]
    }
    set dirname [tk_chooseDirectory \
                     -initialdir [g_get altInfoPath] \
                     -title {Select alternate Info files direcotry} \
                     -parent $win]
    if {$dirname eq ""} {
        set dirname [g_get altInfoPath]
    } else {
        g_set altInfoPath $dirname
        # if it's been chosen, they probably want to use it.
        g_set useAltInfoDir

        # control some menu entries
        update_some_menu_entries 0 altInfoPath
    }
    return $dirname
}

# command procedure for the "Site Dir" button
proc do_site_path {win} {
    if {[g_get siteFilePath] eq ""} {
        g_set siteFilePath [pwd]
    }
    set filename [tk_getOpenFile \
                      -initialdir [g_get altInfoPath] \
                      -filetypes {
                          {{Include Files} {.inc}}
                          {{Text Files}    {.txt}}
                          {{All Files}     {*}}} \
                      -title {Select site include file} \
                      -parent $win]
    if {$filename eq ""} {
        g_set siteFileName {}
    } else {
        g_set siteFilePath [file dirname $filename]
        g_set siteFileName [file tail $filename]
    }
}


# Command procedures for the "Process" button
proc do_build_files {win} {
    # By default, the document directory name is used as
    # the name for the generated HTML file
    if {[g_get htmlFileName] eq ""} {
        g_set htmlFileName "[file tail [g_get outDirPath]].html"
    }
    # If no extension has been included for the HTML file,
    # ".html" is assumed
    if {[file extension [g_get htmlFileName]] eq ""} {
        g_set htmlFileName [string cat [g_get htmlFileName] .html]
    }
    # If no CSS file name has been provided, use the name of the
    # HTML file with the extension replaced by ".css".  If a name
    # for the CSS file has been provided by is missing an extension,
    # assume ".css"
    if {[g_get cssFileName] eq ""} {
        # No name specified, base it on the HTML file name
        g_set cssFileName "[file root [g_get htmlFileName]].css"
    } elseif {[file extension [g_get cssFileName]] eq ""} {
        # No extension specified, use ".css"
        g_set cssFileName [string cat [g_get cssFileName] .css]
    }

    # notify the user something is happening
    display_gui_message "Processing files..." 0
    [get_wp goButton] configure -state disabled

    set oldWd [pwd] ; # save the working directory
    cd [g_get outDirPath] ; # move to the document root to do the work
    # Based on the image, info, and other files in the image directory,
    # build the HTML page in the selected document root directory
    # Arguments:
    #   1) The name of the HTML file to be generated
    #   2) The name of the CSS file to be generated
    #   3) The relative path from the selected document root directory
    #      to the selected image directory
    #   4) The file selection pattern.
    #   5) The text replacement list
    build_page [g_get htmlFileName] [g_get cssFileName] \
        [g_get imgPathRel] [g_get imgGlobPattern] [g_get nameMapList]

    cd $oldWd ; # return to the original working directory
    # Set notification to "done"
    display_gui_message "Done" 10
    [get_wp goButton] configure -state normal
}

# Make a new font that is based on an existing one
proc make_similar_font {orig new args} {
    if {[lsearch [font names] $new] >= 0} {
        eval font configure $new $args
    } else {
        array set fontInfo [font actual $orig]
        foreach {opt val} $args {
            set fontInfo($opt) $val
        }
        set new [eval font create $new [array get fontInfo]]
    }
    return $new
}

# Process to display the GUI for the application
proc make_gui {{win .}} {
    # Before we forget, 'register' the toplevel
    set_wp mainWindow $win

    # creat the "all keywords" list
    set ::build::keywords {}

    # (don't) store the main window path for later consumption
    #g_set mainWindow $win

    set mono [font create appMono -family {Courier New} \
                  -size 10 -weight normal -slant roman \
                  -underline 0 -overstrike 0]
    set sans [font create appSans -family Arial -size 10 \
                  -weight normal -slant roman \
                  -underline 0 -overstrike 0]
    set sansB [font create appSansB -family Arial -size 10 \
                   -weight bold -slant roman \
                   -underline 0 -overstrike 0]
    wm title $win "build: Generate HTML and CSS from Info Files"
    wm iconname $win "build"
    set divFrmBG "snow"
    set pathBG "snow2"
    set relBG  "gray96"

    set frm [labelframe $win.mf -text "Build Parameters"]
    set divFrm [labelframe $frm.divide -text "Output Parameters" \
                    -relief sunken \
                    -borderwidth 5 \
                    -background $divFrmBG]

    set baseButton [button $frm.bbut -text "HTML Dir" \
                        -background black -foreground white \
                        -font $sansB \
                        -command [list do_sel_root $win]]
    set baseText [entry $frm.baseDir -width 100 \
                      -readonlybackground $pathBG \
                      -font $mono \
                      -textvariable [g_get_var outDirPath] \
                      -state readonly]
    set_wp outDirPath $baseText

    set imgButton [button $frm.ibut -text "Media Dir" \
                       -background black -foreground white \
                       -font $sansB \
                       -command [list do_sel_image $win]]
    set imgText [entry $frm.imageDir -width 100 \
                     -readonlybackground $pathBG \
                     -font $mono \
                     -textvariable [g_get_var imgPathAbs] \
                     -state readonly]
    set_wp imgPathAbs $imgText

    set imgRelL [button $frm.imageRelL -text "Relative Path" \
                     -font $sans \
                     -state disabled \
                     -relief flat]
    set imgRel  [entry $frm.imageRel -width 50 \
                     -readonlybackground $relBG \
                     -font $mono \
                     -textvariable [g_get_var imgPathRel] \
                     -state readonly]
    set externL [label $frm.extBaseL -text "Ext/Inc Base" -font $sans]

    set extern  [entry $frm.extBase -width 40 \
                     -font $mono \
                     -textvariable [g_get_var includeBase]]
    set sitePathL [button $frm.sitePathL -text "Site File Path" \
                       -font $sans \
                       -relief flat \
                       -state disabled]
    set siteButton [button $frm.siteB -text "Site Inc File" \
                        -background gray -foreground white \
                        -font $sansB \
                        -command [list do_site_path $win]]
    set siteFile [entry $frm.siteFile -width 40 \
                      -font $mono \
                      -textvariable [g_get_var siteFileName]]
    set altButton [button $frm.altInfB -text "Alt Info Dir" \
                       -background green -foreground white \
                       -font $sansB \
                       -command [list do_alt_info $win]]
    set altInfoPath [entry $frm.altInfoPath -width 100 \
                         -font $mono \
                         -textvariable [g_get_var altInfoPath]]
    set_wp altInfoPath $altInfoPath

    set sitePath [entry $frm.sitePath -width 100 \
                      -font $mono \
                      -textvariable [g_get_var siteFilePath] \
                      -readonlybackground $pathBG \
                      -state readonly]

    set_wp siteFilePath $sitePath

    set htmlNameL [label $divFrm.htmlL -text {HTML File Name: } \
                       -font $sans -background $divFrmBG]
    set htmlName [entry $divFrm.htmlE -width 40 \
                      -font $mono \
                      -textvariable [g_get_var htmlFileName] ]
    set_wp htmlFileName $htmlName

    set cssNameL  [label $divFrm.cssL  -text {CSS File Name: } \
                       -font $sans -background $divFrmBG]
    set cssName [entry $divFrm.cssE -width 40 \
                     -font $mono \
                     -textvariable [g_get_var cssFileName] ]
    set_wp cssFileName $cssName

    set suffixL [label $frm.suffixL -text "Media File Pattern" -font $sans]
    set suffix  [entry $frm.suffix -width 40 \
                     -font $mono \
                     -textvariable [g_get_var imgGlobPattern] ]
    set_wp imgGlobPattern $suffix

    set replaceL [label $frm.replaceL -text "Replacement List" -font $sans]
    set replace  [entry $frm.replace -width 40 \
                      -font $mono \
                      -textvariable [g_get_var nameMapList] ]

    set_wp nameMapList $replace

    set pageTtlL [label $divFrm.pageTitleL -text "Page Title" \
                      -font $sans -background $divFrmBG]
    set pageTtl  [entry $divFrm.pageTitle -width 40 \
                      -font $mono \
                      -textvariable [g_get_var pageTitle]]
    set_wp pageTitle $pageTtl

    set imgAttrL [label $divFrm.imgAttrL -text "<img> Attributes" \
                      -font $sans -background $divFrmBG]
    set imgAttr  [entry $divFrm.imgAttr -width 40 \
                      -font $mono \
                      -textvariable [g_get_var imgElementAttr]]
    set_wp imgElementAttr $imgAttr

    set genInfo [checkbutton $divFrm.genInfo \
                     -background $divFrmBG \
                     -font $sans \
                     -variable [g_get_var genMissingInfo] \
                     -text "Generate Missing Info Files"]

    set useFigs [checkbutton $divFrm.useFigure \
                     -background $divFrmBG \
                     -font $sans \
                     -variable [g_get_var imgInFigure] \
                     -text "Wrap <img> in <figure />"]

    set lnkImg [checkbutton $divFrm.linkImages \
                    -background $divFrmBG \
                    -font $sans \
                    -variable [g_get_var linkImgFiles] \
                    -text "Link <img> Files"]

    set genTitle [checkbutton $divFrm.genTitle \
                      -background $divFrmBG \
                      -font $sans \
                      -variable [g_get_var contTitle] \
                      -text "Generate Container Titles"]


    set useAltInfo [checkbutton $divFrm.useAltInfo \
                        -text "Use Alternate Info File Dir" \
                        -font $sans \
                        -background $divFrmBG \
                        -variable [g_get_var useAltInfoDir]]

    set splitSub [checkbutton $divFrm.splitSub -text "Split Containers" \
                      -font $sans \
                      -background $divFrmBG \
                      -variable [g_get_var splitContainer]]

    # Recursive image search options
    set mdFrm [frame $frm.maxDepthF]
    set maxDepthL [label $mdFrm.maxDepthL -text "Directory Search Depth: "]
    set maxDepth [spinbox $mdFrm.maxDepth -from 0 -to 4 -increment 1 \
                      -width 3 \
                      -textvariable [g_get_var maxSrchDepth]]
    set_wp maxSrchDepth $maxDepth

    grid $maxDepthL  -row 1 -column 1 -sticky nes
    grid $maxDepth   -row 1 -column 3 -sticky news

    # keyword position box
    set kwdLocF [labelframe $divFrm.kwlocFrm \
                     -background $divFrmBG \
                     -text "Keyword List Location"]
    set kwdLocNone [radiobutton $kwdLocF.none \
                        -variable [g_get_var kwdLocation] \
                        -background $divFrmBG \
                        -text "None" -value 0]
    set kwdLocTop [radiobutton $kwdLocF.top \
                       -variable [g_get_var kwdLocation] \
                       -background $divFrmBG \
                       -text "Top" -value 1]
    set kwdLocBottom [radiobutton $kwdLocF.bottom \
                          -variable [g_get_var kwdLocation] \
                          -background $divFrmBG \
                          -text "Bottom" -value 2]
    grid $kwdLocNone -row 1 -column 1 -sticky nsw
    grid $kwdLocTop  -row 1 -column 3 -sticky ns
    grid $kwdLocBottom -row 1 -column 5 -sticky nse
    grid columnconfigure $kwdLocF 1 -weight 2
    grid columnconfigure $kwdLocF 3 -weight 3
    grid columnconfigure $kwdLocF 5 -weight 2
    grid columnconfigure $kwdLocF 0 -minsize 10 -weight 1
    grid columnconfigure $kwdLocF 6 -minsize 10 -weight 1

    # make the statistic display area
    set statBG $pathBG
    #        set kwdBG "snow"
    set kwdBG "gray94"
    set kwdFG "dim gray"
    set statFrm [labelframe $divFrm.statsF -background $statBG \
                     -text "Build Statistics"]
    set sta(L,blockCount) [label $statFrm.lbl_1 \
                               -text "Media Blocks created:" \
                               -justify right \
                               -background $statBG]
    set sta(L,ignoredInfoLines) [label $statFrm.lbl_2 \
                                     -text "Ignored info lines:" \
                                     -justify right \
                                     -background $statBG]
    set sta(L,illegalInfoLines) [label $statFrm.lbl_3 \
                                     -text "Illegal info lines:" \
                                     -justify right \
                                     -background $statBG]
    set sta(L,illegalInfoTypes) [label $statFrm.lbl_4 \
                                     -text "Illegal line intros:" \
                                     -justify right \
                                     -background $statBG]
    set sta(L,infoFilesFound) [label $statFrm.lbl_5 \
                                   -text "Existing Info files found:" \
                                   -justify right \
                                   -background $statBG]
    set sta(L,infoFilesCreated) [label $statFrm.lbl_6 \
                                     -text "Default Info files created:" \
                                     -justify right \
                                     -background $statBG]
    set sta(L,siteHTMLIncluded) [label $statFrm.lbl_7 \
                                     -text "Site <head> file included:" \
                                     -justify right \
                                     -background $statBG]
    set sta(L,head) [label $statFrm.lbl_8 \
                         -text "Local <head> file included:" \
                         -justify right \
                         -background $statBG]
    set sta(L,css1) [label $statFrm.lbl_9 \
                         -text "Page top CSS included:" \
                         -justify right \
                         -background $statBG]
    set sta(L,css2) [label $statFrm.lbl_10 \
                         -text "Page bottom CSS included:" \
                         -justify right \
                         -background $statBG]
    set sta(L,dir1)  [label $statFrm.lbl_11 \
                          -text "Per Dir Top HTML included:" \
                          -justify right \
                          -background $statBG]
    set sta(L,dir2)  [label $statFrm.lbl_12 \
                          -text "Per Dir Bottom HTML included:" \
                          -justify right \
                          -background $statBG]
    set sta(L,body1) [label $statFrm.lbl_13 \
                          -text "Page top HTML included:" \
                          -justify right \
                          -background $statBG]
    set sta(L,body2) [label $statFrm.lbl_14 \
                          -text "Page middle HTML included:" \
                          -justify right \
                          -background $statBG]
    set sta(L,body3) [label $statFrm.lbl_15 \
                          -text "Page bottom HTML included:" \
                          -justify right \
                          -background $statBG]
    set sta(L,link1) [label $statFrm.lbl_16 \
                          -text "Page early CSS linked:" \
                          -justify right \
                          -background $statBG]
    set sta(L,link2) [label $statFrm.lbl_17 \
                          -text "Page late CSS linked:" \
                          -justify right \
                          -background $statBG]
    set sta(L,uniqueKeywords) [label $statFrm.lbl_18 \
                                   -text "Unique keywords:" \
                                   -cursor hand2 \
                                   -justify right \
                                   -background $kwdBG \
                                   -foreground $kwdFG]
    set sta(L,directories) [label $statFrm.lbl_20 \
                                -text "Directories scanned:" \
                                -justify right \
                                -background $statBG]
    set sta(L,containers) [label $statFrm.lbl_21 \
                               -text "Flex containers created:" \
                               -justify right \
                               -background $statBG]

    # legacy; may go away
    set sta(L,compatCSS1) [label $statFrm.lbl_19 \
                               -text "Legacy CSS linked:" \
                               -justify right \
                               -background $statBG]
    
    # labels in columns 1 and 5, data shows in columns 3 and 7
    set col 3
    set row 1
    set statList [build_getStatList]

    # the maxRow calc below is actually
    #   (((len(statList)+1)/2)*2)+1
    # (starting on row 1, using every-other row, want 2 columns)
    set maxRow [expr [llength $statList] | 1]

    foreach idx [build_getStatList] {
        incr cnt
        grid columnconfigure $statFrm $col -weight 1
        grid columnconfigure $statFrm [expr $col - 1] -weight 0
        grid columnconfigure $statFrm [expr $col - 2] -weight 1
        grid columnconfigure $statFrm [expr $col - 3] -minsize 4 -weight 0
        grid columnconfigure $statFrm [expr $col + 1] -minsize 4 -weight 0

        set sta(E,$idx) [entry $statFrm.$idx -width 4 \
                             -readonlybackground $statBG \
                             -textvariable page_stats($idx) \
                             -state readonly \
                             -relief flat]
        grid $sta(L,$idx) -row $row -column [expr $col - 2] -sticky nes
        grid $sta(E,$idx) -row $row -column $col -sticky news
        incr row 2
        if {$row > $maxRow} {
            # back to top, next column
            set row 1
            incr col 4
        }
    }

    $sta(E,illegalInfoTypes) configure -width 10 -font {courier 9}

    set ukwdLFnt [make_similar_font [$sta(L,uniqueKeywords) cget -font] \
                      ukwdLFnt -weight bold]

    $sta(L,uniqueKeywords) configure -font $ukwdLFnt

    $sta(E,uniqueKeywords) configure -cursor hand2 \
        -readonlybackground $kwdBG -foreground $kwdFG

    # make the buttons and things for the bottom of the window
    set btnFrm [frame $frm.buttons]
    set messageB [message $btnFrm.msg -justify center \
                      -font $sansB \
                      -width 340 \
                      -foreground green ]
    # Register the message widget path so it can be easily requested elsewhere
    set_wp messageWin $messageB

    # This button duplicates an entry in the "utilities" menu
    set tkConButton [button $btnFrm.tkconButton -text "Debug" -width 10 \
                         -foreground grey30 \
                         -background grey70 \
                         -command [list show_console $btnFrm.tkconButton]]
    set_wp debugButton $tkConButton

    set goButton [button $btnFrm.goButton -text "Process" \
                      -foreground white -background Green \
                      -width 18 -font $sansB \
                      -command [list do_build_files $win]]
    set_wp goButton $goButton

    set closeButton [button $btnFrm.closeButton -text "Exit" \
                         -background "sandy brown" -foreground black \
                         -font $sansB -width 10 \
                         -command [list destroy $win]]
    set_wp closeButton $closeButton

    set helpB [button $btnFrm.helpB -text " Help " -font $sans \
                   -command [list display_help [get_wp mainWindow]] \
                   -background $relBG \
                   -cursor question_arrow \
                   -relief groove]
    set_wp helpButton $helpB

    grid $baseButton -row 1 -column 1 -sticky news

    grid $baseText   -row 1 -column 3 -sticky news -columnspan 4
    grid $imgButton  -row 3 -column 1 -sticky news
    grid $imgText    -row 3 -column 3 -sticky news -columnspan 4
    grid $imgRelL    -row 5 -column 1 -sticky nes
    grid $imgRel     -row 5 -column 3 -sticky news -columnspan 3
    grid $mdFrm      -row 5 -column 6 -sticky news
    grid $altButton  -row 7 -column 1 -sticky news
    grid $altInfoPath -row 7 -column 3 -sticky news -columnspan 4
    grid $sitePathL   -row 9 -column 1 -sticky nse
    grid $sitePath -row 9 -column 3 -sticky news -columnspan 4
    grid $siteButton  -row 11 -column 1 -sticky news
    grid $siteFile    -row 11 -column 3 -sticky nws
    grid $suffixL    -row 11 -column 4 -sticky nes
    grid $suffix     -row 11 -column 6 -sticky nwse
    grid $replaceL   -row 13 -column 4 -sticky nes
    grid $replace    -row 13 -column 6 -sticky nwse
    grid $externL    -row 13 -column 1 -sticky nes
    grid $extern     -row 13 -column 3 -sticky nws

    # in divFrm
    grid $htmlNameL  -row 1 -column 1 -sticky nes
    grid $htmlName   -row 1 -column 3 -sticky nws
    grid $cssNameL   -row 1 -column 5 -sticky nes
    grid $cssName    -row 1 -column 7 -sticky nwse

    grid $pageTtlL   -row 3 -column 1 -sticky nes
    grid $pageTtl    -row 3 -column 3 -sticky nws
    grid $imgAttrL   -row 3 -column 5 -sticky nes
    grid $imgAttr    -row 3 -column 7 -sticky nwse
    grid $useAltInfo -row 5 -column 7 -sticky nws
    grid $genInfo    -row 6 -column 7 -sticky nws
    grid $splitSub   -row 7 -column 7 -sticky nws
    grid $genTitle   -row 8 -column 7 -sticky nws
    grid $lnkImg     -row 9 -column 7 -sticky nws
    grid $useFigs    -row 10 -column 7 -sticky nws
    grid $kwdLocF    -row 11 -column 7 -sticky news

    #        grid $statFrm    -row 5 -column 3 -rowspan 7 -sticky news
    grid $statFrm    -row 5 -column 1 -columnspan 5 -rowspan 7 -sticky news

    grid rowconfigure $divFrm 0 -minsize 10
    grid rowconfigure $divFrm 2 -minsize 10
    grid rowconfigure $divFrm 4 -minsize 10
    grid rowconfigure $divFrm 6 -minsize 10
    grid rowconfigure $divFrm 8 -minsize 10
    grid rowconfigure $divFrm 10 -minsize 10
    grid rowconfigure $divFrm 12 -minsize 10
    grid columnconfigure $divFrm 0 -minsize 5
    grid columnconfigure $divFrm 2 -minsize 5
    grid columnconfigure $divFrm 4 -minsize 10
    grid columnconfigure $divFrm 6 -minsize 5
    grid columnconfigure $divFrm 8 -minsize 5

    grid rowconfigure $frm 0 -minsize 10
    grid rowconfigure $frm 2 -minsize 5
    grid rowconfigure $frm 4 -minsize 10
    grid rowconfigure $frm 6 -minsize 10
    grid rowconfigure $frm 8 -minsize 10
    grid rowconfigure $frm 10 -minsize 10
    grid rowconfigure $frm 12 -minsize 10

    # Row 14 separates the input from output areas of the window
    #        grid $divFrm -row 14 -column 1 -columnspan 6 -sticky news
    grid $divFrm -row 15 -column 1 -columnspan 6 -sticky news
    grid rowconfigure $frm 14 -minsize 15

    # Buttons at bottom are in row 29 with extra space before and after
    grid $closeButton -row 1 -column 1 -sticky nws
    grid columnconfigure $btnFrm 1 -minsize 20 -weight 1
    grid columnconfigure $btnFrm 2 -minsize 15 -weight 0
    grid $tkConButton -row 1 -column 3 -sticky ns
    grid columnconfigure $btnFrm 4 -minsize 10 -weight 0
    # column 5 used to contain the "save settings" button
    # column 7 used to contain the "load settings" button
    grid columnconfigure $btnFrm 10 -minsize 15 -weight 0
    grid $goButton  -row 1 -column 11 -sticky nws
    grid columnconfigure $btnFrm 11 -minsize 15 -weight 1
    grid columnconfigure $btnFrm 12 -minsize 5 -weight 0
    grid $messageB -row 1 -column 13 -sticky news
    grid columnconfigure $btnFrm 13 -minsize 170 -weight 1
    grid $helpB -row 1 -column 15 -sticky nes
    grid $btnFrm -row 29 -column 1 -columnspan 6 -sticky news
    grid rowconfigure $frm 28 -minsize 20
    grid rowconfigure $frm 30 -minsize 10

    grid columnconfigure $frm 0 -minsize 10 -weight 0
    grid columnconfigure $frm 1 -weight 1
    grid columnconfigure $frm 2 -minsize 5 -weight 0
    grid columnconfigure $frm 3 -weight 2
    grid columnconfigure $frm 4 -minsize 5 -weight 0
    grid columnconfigure $frm 7 -minsize 10
    pack $frm -fill both

    # bind events to various widgets
    bind $sta(L,uniqueKeywords) <ButtonPress-1> \
        [list display_keywords [get_wp mainWindow]]
    bind $sta(E,uniqueKeywords) <ButtonPress-1> \
        [list display_keywords [get_wp mainWindow]]

    # add tool tips
    tooltip $baseButton "Select HTML/CSS Output Directory"
    tooltip $baseText "The currenly selected output directory (R/O)"
    tooltip $imgButton "Select the directory to scan for images"
    tooltip $imgText "The currenly selected image directory (R/O)"
    tooltip $imgRel "The relative path that will be used in the HTML output (R/O)"
    tooltip $altButton "Select an alternate path for finding info files\nSee checkbox below to enable"
    tooltip $altInfoPath "The alternate path for finding info files\nSee checkbox below to enable"
    tooltip $sitePath "The path to a site specific include file"
    tooltip $siteButton "Select a site specific include file"
    tooltip $siteFile "The name of the selected site specific include file"
    tooltip $suffixL "Media file select pattern"
    tooltip $suffix "The glob pattern to select the image files"
    tooltip $replaceL "String map to morph the image file name\ninto a default title"
    tooltip $replace "Must be valid list of pairs for \[string map\]"
    tooltip $externL "The basename used for the various local include files"
    tooltip $helpB "Display Help"
    tooltip $extern "Enter base name used as prefix for include files"
    tooltip $htmlNameL "Name for HTML file to be created"
    tooltip $htmlName "Enter name for HTML file to be created"
    tooltip $cssNameL "Name for CSS file to be created"
    tooltip $cssName "Enter name for CSS file to be created"
    tooltip $pageTtlL "Page Title"
    tooltip $pageTtl "Enter Page Title Text"
    tooltip $imgAttrL "Attributes inserted into <img> tags"
    tooltip $imgAttr "Attributes inserted into <img> tags"
    tooltip $genInfo "Create missing info files"
    tooltip $genTitle "Add directory-name titles\nto each flex container"
    tooltip $useFigs "Embed <img> tags within <figure>"
    tooltip $lnkImg "Make <img> a link to the image file"
    tooltip $useAltInfo "Search alternate directory for info files"
    tooltip $kwdLocNone "Do not output keyword list in HTML"
    tooltip $kwdLocTop  \
        "Display keyword list after block title\nat top of <div>"
    tooltip $kwdLocBottom  \
        "Display keyword list at bottom of <div>"
    tooltip $statFrm   "Some statistics from the page build process"
    tooltip $closeButton "Exit the program"
    tooltip $goButton    "Generate output files"
    tooltip $messageB    "Status message area"
    tooltip $sta(L,uniqueKeywords) "Show list of keywords"
    tooltip $sta(E,uniqueKeywords) "Show list of keywords"

    # Now, as part of a gradual GUI redesign, create some menues that
    # will eventually replace some of the buttons (save/load settings,
    # possibly "Help", etc.
    set mainMenu [menu $win.mainMenu -tearoff 0]
    set_wp mainMenu $mainMenu

    set fileMenu [menu $mainMenu.fileMenu -tearoff 0]
    $mainMenu add cascade -label "File" -menu $fileMenu -underline 0
    set_wp fileMenu $fileMenu

    # The following option duplicates the action of the "HTML DIR" button,
    # Image DIR button, etc, but I don't actually intend to get rid of
    # those buttons because is easier to click on them than to go to a
    # menu and find the right entry.
    $fileMenu add command -label "Output Directory..." \
        -command [list do_sel_root $win]
    $fileMenu add command -label "Image Path Base..." \
        -command [list do_sel_image $win]
    $fileMenu add separator
    $fileMenu add command -label "Alternate INFO File Path..." \
        -command [list do_alt_info $win]
    $fileMenu add check -label "Use Alternate Info File Path" \
        -variable [g_get_var useAltInfoDir] -background snow
    $fileMenu add separator
    $fileMenu add command -label "Site include file..." \
        -command [list do_site_path $win]
    $fileMenu add separator
    $fileMenu add command -label "Save Settings..." \
        -command [list save_page_settings $win 1]
    $fileMenu add command -label "Load Settings..." \
        -command [list load_page_settings $win 1]
    $fileMenu add separator
    $fileMenu add command -label "Exit" -command [list destroy $win]

    # create the "output options" menu
    set optMenu [menu $mainMenu.optionsMenu -tearoff 0]
    $mainMenu add cascade -label "Output Options" -menu $optMenu -underline 0
    set_wp optionsMenu $optMenu
    $optMenu add check -label "Container per Media Directory" \
        -variable [g_get_var splitContainer]
    $optMenu add check -label "Media Directory Titles" \
        -variable [g_get_var contTitle]
    $optMenu add check -label "Create <figure> Elements" \
        -variable [g_get_var imgInFigure]
    $optMenu add check -label "Link Media Files" \
        -variable [g_get_var linkImgFiles]
    $optMenu add separator
    set keyMenu [menu $optMenu.keywordLocations -tearoff 0]
    $optMenu add cascade -label "Keyword List Location" \
        -menu $keyMenu -underline 0
    $keyMenu add radio -label "Keywords at Beginning" \
        -variable [g_get_var kwdLocation] -value 1 -background snow
    $keyMenu add radio -label "Keywords at End" \
        -variable [g_get_var kwdLocation] -value 2 -background snow
    $keyMenu add radio -label "No Keywords" \
        -variable [g_get_var kwdLocation] -value 0 -background snow
    $optMenu add separator
    $optMenu add check -label "Create Missing INFO Files" \
        -variable [g_get_var genMissingInfo]
    $optMenu add radio -label "Create with Media" \
        -variable [g_get_var newInfoLoc] -value 1 -background snow
    $optMenu add radio -label "Create in Alt INFO Directory" \
        -variable [g_get_var newInfoLoc] -value 0 -background snow

    # Create the utilities menu
    set utilMenu [menu $mainMenu.utilMenu -tearoff 0]
    $mainMenu add cascade -label "Utilities" -menu $utilMenu -underline 0
    set_wp utilMenu $utilMenu

    $utilMenu add command -label "Display Keywords..." \
        -command [list display_keywords [get_wp mainWindow]] \
        -underline 0
    $utilMenu add command -label "Save Keywords..." -underline 0 \
        -command [list save_keywords_as $win]
    $utilMenu add separator
    if {[tk windowingsystem] eq "win32"} {
        $utilMenu add command -label "Browse Selected Output Path" \
            -command [list launch_browser $win outDirPath] \
            -state disabled -underline 16
        $utilMenu add command -label "Browse Selected Media Path" \
            -command [list launch_browser $win imgPathAbs] \
            -state disabled -underline 16
        $utilMenu add command -label "Browse Info File Path" \
            -command [list launch_browser $win altInfoPath] \
            -state disabled -underline 8
        $utilMenu add separator
    }
    $utilMenu add command -label "Load Debug Console" -underline 5 \
        -command [list show_console $tkConButton]
    
    # create the help menu
    set helpMenu [menu $mainMenu.helpMenu -tearoff 0]
    $mainMenu add cascade -label "Help" -menu $helpMenu -underline 0
    set_wp helpMenu $helpMenu
    $helpMenu add command -label "Display Help..." \
        -command [list display_help [get_wp mainWindow]]

    # Tell the toplevel about the new menu...
    $win configure -menu $mainMenu

    # Bind some 'entry' widgets so that we can validate the address in their
    # textvariable when they've been edited
    bind [get_wp imgPathAbs] <FocusOut> [list update_some_menu_entries 1 %W]
    bind [get_wp altInfoPath] <FocusOut> [list update_some_menu_entries 1 %W]
    bind [get_wp outDirPath] <FocusOut> [list update_some_menu_entries 1 %W]

    # Add some bindings for convenience
    bind [get_wp mainWindow] <Control-Key-s> [list save_page_settings %W 0]

    # Display "ready" in the message window for 10 seconds
    display_gui_message "*** Ready ***" 10
}

proc launch_browser {w pathSelect} {
    set browsePath [string trim [g_get $pathSelect]]
    if {$browsePath ne "" && [file isdirectory $browsePath]} {
        logInfo "exec explorer.exe [file nativename $browsePath] &"
        if {[catch {exec explorer.exe [file nativename $browsePath] &} pid]} {
            global errorInfo
            display_gui_message "Unable to launch" 15
            logWarning "Unable to launch the file browser" \
                $pid $errorInfo
        } else {
            display_gui_message "PID $pid" 10
        }
    } else {
        display_gui_message "No path for $pathSelect" 10
    }
}

proc display_help {parent args} {
    global inc_file_suffixes
    global inc_file_descriptions

    set w [toplevel $parent.helpWin]

    set helpBook [ttk::notebook $w.helpBook]
    ttk::notebook::enableTraversal $helpBook

    set incHelpTab [ttk::frame $helpBook.incHelpTab]
    set incHelp [text $incHelpTab.incHelp -state normal \
                     -tabs {6c} \
                     -font {helvetica 10} \
                     -height 16 -width 90]
    set okBut [ttk::button $w.okButton -text "Dismiss" \
                   -command [list destroy $w]]

    $incHelp tag configure nameTag -font {courier 10 bold} -tabs {6c}
    $incHelp tag configure desTag -font {helvetica 10} -tabs {6c}

    set incBase "<incBase>"

    foreach {loc helpText} $inc_file_descriptions {
        set namePat [string cat $incBase $inc_file_suffixes($loc)]
        $incHelp insert end "  "
        $incHelp insert end "  $namePat" nameTag
        $incHelp insert end "\t$helpText\n"
    }
    $incHelp configure -state disabled

    grid $incHelp -row 1 -column 1 -sticky news

    set guiHelpTab [ttk::frame $helpBook.guiHelpTab]
    set guiHelp [text $guiHelpTab.guiHelp -state normal \
                     -wrap word \
                     -yscrollcommand "$guiHelpTab.scrollY set" \
                     -height 16 -width 90]
    set guiScrl [ttk::scrollbar $guiHelpTab.scrollY \
                     -orient vert -command "$guiHelp yview"]
    set linespace3 \
        [expr {[font metrics [$guiHelp cget -font] -linespace] / 2}]
    set cwidth [font measure [$guiHelp cget -font] 0]
    set listSep 24
    set tabStop1 [expr {$cwidth * $listSep}]
    set tabStop2 [expr {$cwidth * ($listSep + 2)}]

    $guiHelp configure -font {helvetica 10} -spacing3 $linespace3
    $guiHelp tag configure normal -font {helvetica 10}
    $guiHelp tag configure listText \
        -font {helvetica 10} \
        -spacing3 $linespace3 \
        -lmargin1 $tabStop2 \
        -lmargin2 $tabStop2
    $guiHelp tag configure listLabel \
        -tabs [list $tabStop1 left $tabStop2] \
        -font {courier 10} \
        -spacing3 0 \
        -tabstyle wordprocessor \
        -lmargin1 0 \
        -lmargin2 $tabStop2
    $guiHelp tag configure header -font {helvetica 11 bold}
    selfHelp "" {^#!(.)(.*)$} {$guiHelp insert end %L}
    $guiHelp configure -state disabled

    grid $guiHelp -row 1 -column 1 -sticky news
    grid $guiScrl -row 1 -column 2 -sticky news

    set infoHelpTab [ttk::frame $helpBook.infoHelpTab]
    set infoHelp [text $infoHelpTab.infoHelp -state normal \
                      -wrap word \
                      -yscrollcommand "$infoHelpTab.scrollY set" \
                      -height 16 -width 90]
    set infoScrl [ttk::scrollbar $infoHelpTab.scrollY \
                      -orient vert -command "$infoHelp yview"]
    set line3 [expr {[font metrics [$infoHelp cget -font] -linespace] / 2}]
    set cwid [font measure [$infoHelp cget -font] 0]
    set listBreak 36
    set tab1 [expr {$cwid * $listBreak}]
    set tab2 [expr {$cwid * ($listBreak + 2)}]

    $infoHelp configure -font {helvetica 10} -spacing3 $line3
    $infoHelp tag configure normal -font {helvetica 10}
    $infoHelp tag configure listText \
        -font {helvetica 10} \
        -spacing3 $line3 \
        -lmargin1 $tab2 \
        -lmargin2 $tab2
    $infoHelp tag configure listLabel \
        -tabs [list $tab1 left $tab2] \
        -font {courier 10} \
        -spacing3 0 \
        -tabstyle wordprocessor \
        -lmargin1 [expr {$cwid * 2}] \
        -lmargin2 $tab2
    $infoHelp tag configure header -font {helvetica 11 bold}
    selfHelp "" {^#\?(.)(.*)$} {$infoHelp insert end %L}
    $infoHelp configure -state disabled

    grid $infoHelp -row 1 -column 1 -sticky news
    grid $infoScrl -row 1 -column 2 -sticky news

    foreach tab [list $infoHelpTab $incHelpTab $guiHelpTab] {
        grid rowconfigure $tab 0 -minsize 4
        grid rowconfigure $tab 2 -minsize 4
        grid columnconfigure $tab 0 -minsize 4 -weight 0
        grid columnconfigure $tab 1 -weight 1
        grid columnconfigure $tab 3 -minsize 4 -weight 0
    }

    $helpBook add $guiHelpTab -text "GUI" -underline 0 \
        -sticky news
    $helpBook add $infoHelpTab -text "Info Files" -underline 1 \
        -sticky news
    $helpBook add $incHelpTab -text "Include Files" -underline 0 \
        -sticky news

    grid $helpBook -row 1 -column 1 -sticky news -columnspan 5
    grid $okBut -row 3 -column 5 -sticky news
    grid rowconfigure $w 0 -minsize 5
    grid rowconfigure $w 2 -minsize 5
    grid rowconfigure $w 4 -minsize 5
    grid columnconfigure $w 0 -minsize 5 -weight 0
    grid columnconfigure $w 6 -minsize 5 -weight 0
}

proc save_keywords_as {parent args} {
    set saveFile [tk_getSaveFile -initialdir [g_get outDirPath] \
                      -defaultextension ".kwd" \
                      -typevariable ::build::kwdSaveType \
                      -filetypes {
                          {{Keyword File}   {.kwd}}
                          {{Text File}      {.txt}}
                          {{List File}      {.lst}}
                          {{All Files}      {*}}} \
                      -parent [get_wp mainWindow] \
                      -title "Save keyword list as..."]

    if {$saveFile eq ""} {
        return
    }

    set ofd [open $saveFile w]
    set ext [file extension $saveFile]

    if {$ext eq ".kwd"} {
        puts $ofd $::build::keywords
    } elseif {$ext eq ".lst"} {
        foreach word $::build::keywords {
            puts $ofd $word
        }
    } else {
        set line ""
        set sep  ""
        set osep ", "
        foreach word $::build::keywords {
            if {([string length $line] + [string length $word] + 2) > 78} {
                puts $ofd $line
                set line ""
                set sep ""
            }
            set line [string cat $line $sep $word]
            set sep $osep
        }
        if {$line ne ""} {
            puts $ofd $line
        }
    }
    close $ofd
}


proc display_keywords {parent args} {
    set w [toplevel $parent.kwdWin]
    wm title $w "Keywords"

    set kwdFrm [ttk::labelframe $w.kwdFrame \
                    -text "[llength $::build::keywords] Unique Keywords"]
    set kwdTxt [text $kwdFrm.kwdDisplay -state normal \
                    -tabs {2.5c} \
                    -wrap word \
                    -font {helvetica 10} \
                    -height 8 -width 60]
    set okBut [ttk::button $w.okButton -text "Dismiss" \
                   -command [list destroy $w]]

    set sep ""
    $kwdTxt delete 1.0 end

    foreach word [lsort -ascii $::build::keywords] {
        $kwdTxt insert end [string cat $sep $word]
        set sep ",\t"
    }

    $kwdTxt configure -state disabled

    grid columnconfigure $w 0 -minsize 5 -weight 0
    grid columnconfigure $w 6 -minsize 5 -weight 0
    grid $kwdTxt -row 1 -column 1 -sticky news
    grid $kwdFrm -row 1 -column 1 -sticky news -columnspan 5
    grid $okBut -row 3 -column 5 -sticky news
    grid rowconfigure $w 0 -minsize 5
    grid rowconfigure $w 2 -minsize 5
    grid rowconfigure $w 4 -minsize 5
    if {[llength $::build::keywords] > 0} {
        set saveBut [ttk::button $w.save -text "Save List" \
                         -command [list save_keywords_as $w]]
        grid $saveBut -row 3 -column 1 -sticky news
    }
}

proc runWithGUI {args} {
    # create the stats array because some widgets reference the array
    # elements before they would otherwise exist
    build_resetStats

    # default to starting in the current directory
    g_set_cond outDirPath [pwd]


    # Display the GUI as the main (root) window for this application
    make_gui .
}
    
# selfHelp: Extract 'help' text from specially marked comments in a Tcl file
#
# Description:
#   This proc opens a text file (usually the script that is running) and
#   reads it looking for specially marked comment lines.  The contents of
#   these lines are used to populate a properly configured 'text' widget.
#
#   There are 4 text tags used by 'selfHelp':
#      "normal"    For lines other than headers or definition list entries
#      "header"    For lines identified as headers
#      "listLabel" for the term part of a definition list entry
#      "listText"  for the definition part of a definition list entry
#
#   It is the responsibility of the caller to arrange a proger 'text' widget;
#   the 'selfHelp' procedure simply assumes that its 'cmd' parameter is
#   an invocation of a text widget with the 'insert' command in place.
#
# Parameters:
#   srcFile : The name of the file to look for the comments in; if this is
#             the empty string, 'selfHelp' uses the value of 'argv0' instead.
#   regex   : The regular expression to use to recognize and decompose the
#             comment lines; this should look like "{^#!(.)(.*)$}", where the
#             '!' might be some other (properly escaped) character.
#             Examples:
#               {^#\?(.)(.*)$}  Matches lines that begin with "#?"
#               {^#!(.)(.*)$}   Matches lines that begin with "#!"
#             The '(.)' extracts a single character that is used to determine
#             what to do with the rest of the data, the '(.*)' extracts the
#             remainder of the characters on the line.  Look up 'regexp' if
#             you need to better understand Tcl regular expressions.
#   cmd     : This is the command prefix for inserting characters into a
#             tk 'text' widget; the non-terminal '%L' will be replaced by
#             the data to be inserted, and a text tag will be appended
#             to the command.  The insertion is done with 'uplevel 1', so
#             occurs in the caller's scope and context.
#             Example:
#                {$textWidget insert end %L}
#             results in insertions of the form:
#                $textWidget insert end $charsToInsert textTag
#
# Comment lines that begin lines with "#?" and "#!", below (and anywhere
# in this file) are used as the source for the help screen texts.
# The first character of help lines is always '#', the second character
# identifies which 'help' text the data belongs to; for example '!' may be
# for User help, '?' might be for input data help.  For brevity, assume
# that where the descriptions below have '#?', it could be '#!', '#*',
# etc.
#
# The two character prefix is followed by a third character that selects
# how the remaining text on the line is presented:
#
#   ' ' The line following the space is trimmed of excess whitespace then
#       inserted into the help 'text' widget. 'selfHelp' doesn't know when
#       a paragraph is done unless mark-up tells it.  This is done done with
#       either an explicit '\n' at the end of the last line of a paragraph,
#       or a comment line that begins with "#?."
#
#   '!' The remainder of the line is inserted with the text tag 'header'.
#
#   '+' The remainder of the line is inserted with the text tag 'listLabel',
#       and is intended to be term (left side) of a tabular definition list
#       similar to the one this description is part of.
#
#   '-' The remainder of the line is inserted with the text tag 'listText',
#       and is intended to be the definition (right side) of a tabular
#       definition list similar to the one this description is part of.
#
proc selfHelp {srcFile regex cmd} {
    global argv0

    if {$srcFile eq ""} {
        set srcFile $argv0
        if {[file extension $srcFile] eq ""} {
            set srcFile [string cat $srcFile .tcl]
        }
    }

    if {![catch {set fd [open $srcFile "r"]} val]} {
        set xcmd [string map [list %L \$::build::helpLine] $cmd]
        set prevCtrl ""
        set newLine 0
        while {[gets $fd line] >= 0} {
            if {[regexp $regex $line dummy ctrl remain]} {
                set remain [string trim $remain]
                set remain [string map {\\t \t \\n \n} $remain]

                if {$ctrl eq "."} {
                    set remain [string cat $remain \n]
                }
                if {$ctrl eq $prevCtrl && !$newLine} {
                    set remain [string cat " " $remain]
                }

                set ::build::helpLine $remain

                if {[string range $remain end end] eq "\n"} {
                    set newLine 1
                } else {
                    set newLine 0
                }
                set tagName normal

                switch -exact -- $ctrl {
                    ! {
                        set tagName header
                    }
                    + {
                        set ::build::helpLine \
                            [string cat $remain "\t-\t"]
                        set tagName listLabel
                    }
                    - {
                        set tagName listText
                    }
                    default {
                    }
                }
                uplevel 1 $xcmd $tagName
                set prevCtrl $ctrl
            }
        }
        close $fd
    }
}

# Some information in place of real documentation:
#
# This Tcl script produces two files, an HTML file and a CSS file, in the
# current directory that contains an entry for each image file in a
# directory (usually given as a relative path from the current directory)
# that has a suffix matching a pattern specified as the 4th argument to
# the "build_page" proc. The path to the image directory is the 3rd argument.
# The first two argument to "build_page" are the names of the HTML and CSS files
# to be generated, respectively:
#   build_page <html-file> <css-file> <img-rel-path> <file-match-pattern>
#
# If the image directory contains a file named "<base>-body-main.txt", the lines
# of that file are copied into the HTML file between the "<h1>" element with
# the page title and the flex container "<div>" (class 'posSet') within which
# a "<div>" with a unique class name (based on the image file name) is created
# for each image file found in the referenced image directory that has a
# suffix that matches the provided pattern. The "<div>" for each image has
# the 'class' attribute set to a list consisting of two or more classes:
#     "boxed <exp-class-opt> <unique-class>"
# The generated .css file has fixed default definitions for the "posSet" and
# "boxed" classes, plus entries for each of the unique item classes generated
# (one for each matched image file). There may be (are, really) some other
# things that are being created in the generated .css file.
#
# If the image directory contains a file named "<body>-early.css", a "<link>"
# element to use it as a stylesheet is generated in the HTML files
# '<head>' element before the link to the generated CSS file.
#
# If the image directory contains a file named "<body>-late.css", a
# "<link>" element to use it as a stylesheet is generated in the HTML files
# '<head>' element after the link to the generated CSS file. This allows
# overriding of generated styles.
#
# For each selected image file, the script looks for a file with the same
# root name and the extension ".txt". If this file exists, it may contain
# information used in the generation of the "<div>" element for the image
# in the HTML and the associated style in the generated CSS file. This is
# the "info" file.
#
# Each line in the info file must begin with a character that signifies
# how that line is to be interpreted (aka, the line type).
# The order of the lines is somewhat significant, in that multiple lines
# of the same type are used in the order they appear. Lists are anchored
# by the first item encountered for them.
#
# The following line type specifiers are currently recognized:
#   #<anything>                             - Comment, ignored
#   ^<extra_class>                          - Add a class to the '<div>' for
#                                             the item
#   =<item_header_text>                     - Override the default <h3> text;
#                                             if multiple '=' lines appear,
#                                             the last one is used
#   @<normal_paragraph_text>                - Add a new paragraph to the body
#                                             of the <div> for the image; no
#                                             class is specified in the '<p>'
#                                             element (multiple allowed)
#   %<class><space><classed_paragraph_text> - Add a new paragraph with an
#                                             explicit class to the '<div>'
#                                             element for the image
#                                             (multiple allowed)
#   +<ordered_list_item_text>               - Add an item to the optional
#                                             ordered list; the ordered
#                                             list appears between any
#                                             paragraphs ('@' or '%') that
#                                             are encountered in the info
#                                             file before the first '+' line
#                                             and any paragraphs encountered
#                                             after the first '+' line follow
#                                             (multiple allowed)
#   .<unordered_list_item_text>             - Add an item to the optional
#                                             unordered list; the list appears
#                                             at the location (paragraph wise)
#                                             of the first '.' line
#                                             (multiples allowed)
#   ~<css_attribute><space><attribute_val>  - Append a style specification
#                                             to the unique class for the
#                                             image (multiple allowed)
#   /<css_attribute><space><attribute_val>  - Append a style specification for
#                                             the <img> within the unique class
#                                             for the image (multiple allowed)
#   !<raw-html>                               Insert raw HTML
#   *<keyword-list>                           A list of comma separated
#                                             keywords (multiples allowed)
#   :<anything>                               Data intended for other programs,
#   ;<anything>                               treated as comments by this
#                                             program (multiples allowed)
# Any line in the file that does not begin with one of the above characters
# is ignored (actually, it may be reported, but not used otherwise).
#
# Note that the ordered and unordered lists appear within the paragraphs in
# the order that the line for the first item for that list appears. Each
# '<div>' has up to one of each type of list.
#
# If no ".txt" file is found for a given image, the program generates content
# that is pretty minimal; it is intended to be used as a skeleton, replaced
# by content through hand editing.  Of course, that hand edited content is
# lost if the files are regenerated.
#

# Info file help text begins with "#?"
# GUI help text begins with "#!"

#?! The following line type specifiers are currently recognized:\n
#?.
#?+ #<anything>
#?- Comment, ignored\n
#?+ ^<ExtraClass>
#?- Add a class to the '<div>' for the item\n
#?+ =<ItemHeaderText>
#?- Override the default '<h3>' text; -if multiple '=' lines appear,
#?- the last one is used\n
#?+ @<ParagraphText>
#?- Add a new paragraph to the body of the '<div>' for the image; no
#?- class is specified in the '<p>' element (multiple allowed)\n
#?+ %<Class><space><ParagraphText>
#?- Add a new paragraph with an explicit class to the '<div>'
#?- element for the image (multiple allowed)\n
#?+ +<OrderedListItem>
#?- Add an item to the optional ordered list; the ordered list appears
#?- following all paragraphs ('@' or '%') that are encountered in the info
#?- file before the first '+' line, and before any paragraphs that follow
#?- where the first '+' was encountered.
#?- (multiple allowed)\n
#?+ .<UnorderedListItem> 
#?- Add an item to the optional unordered list; the unordered list appears
#?- following the last paragraph that is encountered in the info file before
#?- the first '.' line, and before any paragraphs that follow.
#?-(multiples allowed)\n
#?- Note: There is only one each of the ordered and unordered lists
#?- defined per info file, and they are independent of eachother.
#?- The lists appear in the order and positions where their first items
#?- are encountered in the info file.\n
#?+ ~<StyleName><space><StyleSetting>
#?- Append a CSS style specification to the stylesheet entry for the unique
#?- class defined for the '<div>' associated with the info file.
#?- (multiple allowed)\n
#?+ /<StyleName><space><StyleSetting>
#?- Append a style specification for '<img>' or '<figure>' elements within
#?- the '<div>' associated with the info file.
#?- (multiple allowed)\n
#?+ !<ArbitraryText>
#?- Inserts the line with the inital '!' removed otherwise unmollested into
#?- the output HTML file at the relative location where it is encountered
#?- in the info file.
#?- (multiples allowed)\n
#?+  *<KeywordList>
#?- A list of comma separated keywords that are optionally displayed in
#?- the '<div>' associated with the info file.
#?- (multiples allowed)\n
#?+ :<Anything> or ;<Anything>
#?- Data intended for other programs, treated as comments by this program,
#?- or in other words, ignored.
#?- (multiples allowed)\n
#?.
#? Any line in the file that does not begin with one of the above characters
#? is ignored (actually, it may be reported, but not used otherwise).
#?.
#? Note that the ordered and unordered lists appear within the paragraphs in
#? the order that the line for the first item for that list appears. Each
#? '<div>' has up to one of each type of list.
#?.


#!!GUI Controls
#!.
#!+HTML Dir
#!-Pressing this button allows setting of the directory that the HTML and
#!-CSS files will be written to. The defaults for most other paths is based
#!-off of this setting. This is also the path at which certain include
#!-and CSS files are searched for by default.\n
#!-Defaults to the directory the program is run in.\n
#!+Image Dir
#!-Pressing this button allows selection of the top level image directory
#!-under which media files that match the file pattern (see below) will
#!-have content in the generated HTML file.  By default, the program will
#!-search for an 'info' file containing text and meta-data content for
#!-each media file in the same directory the media file is found in.
#!-See the "Directory Search Depth", "Media File Pattern", "Alt Info Dir",
#!-and "Use Alternate Info File Dir" controls.\n
#!-Defaults to the HTML output directory if not explicitly set.\n
#!+Relative Path
#!-This control displays the path relative from the output directory
#!-(see "HTML Dir", above) to the directory selected by "Media Dir"
#!-(see above, also). This field displays the path that will be used
#!-in external file references to media files. On windows, if the selected
#!-image directory is on a different drive, a fully qualified directory path,
#!-including the drive letter, will be used.\n
#!-This field is not user editable.\n
#!+Image Search Depth
#!-This control sets how many levels of directories below the selected 
#!-image search path, selected by "Media Dir" (see above) the program will
#!-descend to on a depth-first search for media files.\n
#!-Default for this control is 0 (just search in the selected directory).\n
#!+Split Containers
#!-Selects how the media information blocks are nested in flex containers.
#!-When not selected, all media files found that match the file selection
#!-pattern (see "Media File Pattern", below) are in a single HTML "flex"
#!-container division. If this option is selected, a separate flex container
#!-for each searched directory that contains selected media is generated.\n
#!-There are several additional behaviors controlled by this option that
#!-will be described elsewhere.\n
#!-The default for this control is unselected.\n
#!+Alt Info Dir
#!-Selects an alternate path that is searchd for the 'info' file assocated
#!-with each media file selected in the image file search. The path selected
#!-by this control is only used when the "Use Alternate Info File Dir"
#!-option is selected.\n
#!+Site File Path
#!-Displays the directory path of the site include file (if one is selected).
#!-This is a silly arrangement, and will change.\n
#!+Site Inc File
#!-This selects the site include file. This, along with the
#!-"Site File Path" control (above) will be changed soon.\n
#!+Image File Pattern
#!-This field holds the file name pattern used when searching for media files.
#!-The format of this string is very similar to that used in most command
#!-shells that follow Unix shell conventions.\n
#!-The default pattern selects all supported image formats (so long as the
#!-file extensions are in lower case: JPEG, GIF, and PNG. The program also
#!-supports HTML compatible video files (that's MP4, OGG Vorbis, and
#!-WEBM format files), but they are not selected by the default pattern.\n
#!+Ext/Inc Base
#!-This field sets the prefix part of the name of the various include files
#!-that are copied into the generated HTML and CSS files if found. This value
#!-is also used for CSS files that are (if found during processing) linked to
#!-by the generated HTML file.\n
#!+Replacement List
#!-This control allows setting a list of text replacements done on the media
#!-file name to produce better class names and default file titles.  The
#!-list must have an even number of members, as it is used directly in
#!-a Tcl "string map" command. See Tcl documentation for more information.\n
#!-The default for this is an empty list (blank).\n
#!.
#!!Output Parameters Frame\n
#!+HTML File Name
#!-The name of the HTML file to generate.\n
#!+CSS File Name
#!-The name of the CSS file to generate.\n
#!+Page Title
#!-The title text to put at the top of the generated HTML page.\n
#!+<img> Attributes
#!-HTML <img> attribute test to insert into generated '<img>' tags;
#!-the program always includes "src" and "alt" attributes. CSS stylesheets
#!-can replace a number (but not all) of these attributes.\n
#!-The default for this is 'width="250"'.\n
#!+Use Alternate Info File Dir\n
#!-Switches where the program looks for info files (and creates them if the
#!-"Generate Missing Info Files" option is selected).\n
#!-This option defaults to off (unselected).\n
#!+Generate Missing Info Files\n
#!-When this option is selected, the program generates a default (and ugly)
#!-info file in the selected location (see above) for each selected media file
#!-if it cannot locate and existing info file.\n
#!-The default for this option is unselected.\n
#!+Generate Container Titles\n
#!-When this option is selected, an '<h2>' element with the name of the
#!-image directory that has content in the following flex container
#!-is written to the HTML file before the "above.txt" file (if any)
#!-is copied, and before the flex container '<div>' element for that directory
#!-is opened. This option is only meaningful when "Split Containers"
#!-(see above) is selected.\n
#!-Default for this option is unselected.\n
#!+Link <img> Files
#!-When selected, generated '<img>' elements are made to be hyperlinks to
#!-load the image file on a new page (tab) in the browser. For video file,
#!-this is done by putting the hyperlink on the '<figure>' caption; if the
#!-"Wrap <img> in <figure>" option is not selected, no hyperlink for video
#!-files is generated.\n
#!-The default for this option is unselected.\n
#!+Wrap <img> in <figure>
#!-When this option is selected, the program wraps each media file display
#!-element ('<img>' or '<video>') in a '<figure>' element.  A '<figcaption>'
#!-element is generated as well.  When this is selected, the '<img>'
#!-style information from the info files is used instead for generating
#!-CSS style classes for the '<figure>' elements.\n
#!-The default for this option is unselected.\n
#!+Keyword Location
#!-Selects the relative location of the keyword display for an image.\n
#!-The default selection is 'Top'\n
#!.
#!!Bottom Button Bar
#!.
#!+Close
#!-Exits the program\n
#!+Save Settings
#!-Saves the current settings to a file.\n
#!+Load Settings
#!-Loads settings from a saved settings file.\n
#!+Process
#!-Produce HTML and CSS files using the current settings.\n
#!+Help
#!-How you got to see this.\n

if {$::build::envReady && [file extension $argv0] eq ".tcl"} {
    # Since this is running from a .tcl file, it's assumed that it's ok
    # simply to launch the GUI

    package require Tk
    package require Img

    set iconFile [file root $argv0].ico
    if {[file exists $iconFile]} {
	if {$tcl_platform(platform) eq "windows"} {
	    wm iconbitmap . -default $iconFile
	} else {
	    set iconImage [image create photo -file $iconFile]
	    wm iconphoto . $iconImage
	}
    }

    # stderr and stdout are not useful
    set ::build::noConsole 1

    # Define the GUI and fire it up.
    runWithGUI $argv0 $argv

    # End of GUI invocation
} else {
}

# Local Variables:
# mode: tcl
# End:
