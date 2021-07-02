#!/bin/sh
# The next line is executed by /bin/sh, but not tcl \
exec wish "$0" ${1+"$@"}

#puts stderr "$argv0 started with $argv"
#parray env

# This is a combination of 'edit.tcl' and 'generate.tcl'
package require Tk
package require Img
package require tooltip
package require Ttk

# package require inifile

namespace import tooltip::tooltip


#source "vplayer.tcl"
namespace eval Vplyr {
    # The following code is based on "showcam.tcl" by Pat Thoyts;
    # the original comments at the top of the source file (modified for
    # format) are:
    #------------------------------------------------------------------------
    ## showcam.tcl - Copyright (C) 2009 Pat Thoyts
    ##                                      <patthoyts@users.sourceforge.net>
    ##
    ##     Demonstration of mplayer embedding into a Tk application.
    ##
    ##  mplayer can be embedded in a Tk window if it is passed the window id
    ##  of a frame. We can then control it via its slave mode over standard
    ##  input and output. There are a number of possible commands but here
    ##  we use 'screenshot' to have it save a snapshot to a unique filename
    ##  and reply on the pipe with the filename. We can read the filename
    ##  and delete the file to suck captures into Tk images.
    #------------------------------------------------------------------------
    # I have adapted Pat's demo code without permission, extending it to
    # make it into a Tcl package (though I've not yet actually done that here)
    #
    # This version has been tested with mplayer 1.4 on Windows and mplayer 1.3
    # on the Raspberry Pi 64 bit OS (based on Debian). Because installations
    # vary from platform to platform, it is not always easy for the Tcl script
    # to locate where mplayer is.  See the proc "::Vplyr::SetupMplayer" for
    # help with that.
    #

    # The following sets up the default name of the mplayer executable
    # based on the platform it is running on.
    variable mplayer_exe_name ; if {![info exists mplayer_exe_name]} {
        if {$::tcl_platform(platform) == "windows"} {
            set mplayer_exe_name mplayer.exe
        } else {
            set mplayer_exe_name mplayer
        }
    }

    # The application using this package can override the default executable
    # name by setting the variable "::Vplyr::mplayer_exe" before using the
    # interfaces in this namespace.
    variable mplayer_exe ; if {![info exists mplayer_exe]} {
        set mplayer_exe $mplayer_exe_name
    }

    # Other "::Vplyr" namespace variables

    # Is a video being played?
    variable playing ; if {![info exists playing]} {set playing 0}

    # The UID of the slave "mplayer" task
    variable uid     ; if {![info exists uid]} {set uid 0}

    # The file hande for the pipe through which commands and status
    # are passed between the slave and master tasks
    variable mplayer ; if {![info exists mplayer]} {set mplayer ""}

    # Array to store the video attributes for the current media file
    variable vidAttrs
    array set vidAttrs {0 nil}

    # Synchronization variable used to determine when the video file has
    # already been queried for its precious information (height, width, etc.)
    variable infoSync ; if {![info exists infoSync]} {set infoSync -1}

    # The enclosing frame into which mplayer is embedded
    variable vFrame ; if {![info exists vFrame]} {set vFrame {}}

    # When 1, the video is paused, when 0, it is not
    variable isPaused ; if {![info exists isPaused]} {set isPaused 0}

    # When 1, the audio is muted, when 0, it is not
    variable isMuted ; if {![info exists isMuted]} {set isMuted 0}

    # Array of client callback commands for the following events:
    #   Playback Started ('started')
    #   End of Playback ('done')
    #   Playback Paused/Unpaused ('pause')
    #   Audio Muted/Unmuted ('mute')
    #   Video Window Reconfigure ('reconfig')
    variable clientCB ; if {![info exists clientCB]} {
        array set clientCB {done {} pause {} mute {} started {} reconfig {}}
    }

    # Sanitize a filename so that it can be used in the "open" call that
    # creates the command pipe to the slave "mplayer" instancee
    proc Sanitize {fname} {
        set sname [string map {\[ \\\[  \] \\\] \$ \\\$} $fname]
        return $sname
    }

    # Lookup a file given a string formatted like the "PATH" environment
    # variable ('pathString') and the name of the file to look for ('fiileName')
    #
    # The full path name is returned for the first occurance found;
    # if the file is not found along the path, an empty string is returned
    proc LookupFile {pathString fileName} {
        if {$::tcl_platform(platform) == "windows"} {
            set sep {;}
        } else {
            set sep {:}
        }

        foreach dir [split $pathString $sep] {
            set fullName [file join $dir $fileName]
            if {[file exists $fullName]} {
                return $fullName
            }
        }
        return ""
    }

    # Set the playback done callback; No parameters are passed to the
    # registered callback proc
    proc SetVideoDoneCallback {cb} {
        variable clientCB
        set clientCB(done) $cb
    }

    # Set the pause callback; One argument is passed to the
    # registered callback proc, 1 for paused, 0 for not paused
    proc SetVideoPauseCallback {cb} {
        variable clientCB
        set clientCB(pause) $cb
    }

    # Set the mute callback; One argument is passed to the
    # registered callback proc, 1 for muted, 0 for not muted
    proc SetVideoMuteCallback {cb} {
        variable clientCB
        set clientCB(mute) $cb
    }

    # Set the playback started callback
    proc SetVideoStartedCallback {cb} {
        variable clientCB
        set clientCB(started) $cb
    }

    # Set the video reconfig callback
    proc SetVideoReconfigCallback {cb} {
        variable clientCB
        set clientCB(reconfig) $cb
    }

    # Collect information about a video file
    proc QueryInfo {fname} {
	variable vidAttrs
	variable infoSync
        variable mplayer_exe

	set cmdline "$mplayer_exe -noconfig all -cache-min 0 -vo null -ao null "
	append cmdline "-frames 0 -msglevel identify=6 \"$fname\""
	set chan [open |$cmdline r+]
	fconfigure $chan -blocking 0 -buffering line
	set allDone 0

	while {$allDone == 0} {
	    set d [read $chan]
	    if {[eof $chan]} {
		break
	    }
	    foreach line [split $d \n] {
		set line [string trim $line]
		set poz [string first = $line]
                #::puts stdout "$line\nPoz=$poz"
		if {$poz > 3} {
		    # skip the "ID_" at the beginning of each value
		    set prop [string range $line 3 [expr $poz - 1]]
		    if {$prop == "EXIT"} {
			set allDone 1
			close $chan
			set vidAttrs(0) $fname
			set infoSync 1
			return
		    } else {
			incr poz
			set val [string range $line $poz end]
			set vidAttrs($prop) $val
		    }
		}
	    }
	}
	if {[eof $chan]} {
	    fileevent $chan readable {}
	    close $chan
	    set vidAttrs(0) $fname
	    set infoSync 1
	}
    }

    # Retrieve an attribute from a video file
    # Parameters:
    #   filename - The name of the video file (including path)
    #   thing    - The attribute to be queried
    #   deflt    - A default value to be returned if the value of 'thing'
    #              is unknown (optional)
    proc GetVideoInfo {filename thing {deflt {}}} {
	variable vidAttrs
	variable infoSync

        # Make sure the command line is parsed correctly
        set filename [Sanitize $filename]

        # Check to see if the file has already been queried to avoid running
        # mplayer to get the attributes every time someone wants the width
        # or height (or length, etc.)
	if {$vidAttrs(0) != $filename} {
            # This is not the file previously scanned
            array unset vidAttrs ; # clear out the old data
	    array set vidAttrs {0 nil}
	    set infoSync -1     ; # Data is not in sync
	    QueryInfo $filename ; # Get the info using mplayer
	}

	if {$vidAttrs(0) == $filename} {
            # The attributes array contains data from the requested file
	    if {[info exists vidAttrs($thing)]} {
                # The requested attribute has a value stored
		return $vidAttrs($thing) ;# Return the attribute value
	    } else {
                # The requested attribute has no value stored
		::puts stderr \
                    "$thing isn't defined for [file extension $filename] files"
	    }
	} else {
            # The attributes array doesn't contain data from the requested file
	    ::puts stderr "vidAttrs(0) isn't $filename, it's $vidAttrs(0)!"
	}
        # If we got here, there is no stored value from the requested file,
        # so return the default supplied by the user or an empty result when
        # no default value was provided
	return $deflt
    }

    # Toggle playback pause
    # If there is a registerd client callback for pause events, invoke that
    # callback command with a single argument, 0 for playback not paused,
    # 1 for playback paused
    proc PauseVideo {} {
	variable mplayer
        variable isPaused
        variable clientCB
        if {$isPaused == 1} {
            set isPaused 0
        } else {
            set isPaused 1
        }
	if {$mplayer ne ""} { puts $mplayer "pause" }
        if {"$clientCB(pause)" ne ""} {
            $clientCB(pause) $isPaused
        }
    }

    # Frame step the video
    proc StepVideo {} {
	variable mplayer
	if {$mplayer ne ""} { puts $mplayer "frame_step" }
    }

    # Move forward or back in the video playback
    # Note that the time is somewhat unreliable
    proc SeekVideo {time} {
        variable mplayer
        # mplayer 1.3 on the RaspberryPI OS (AARCH64, spring 2021) seems
        # to always seek 2 times the requested # of seconds using the
        # relative seek, so the following line adjusts for that...
        set time [expr $time / 2.0]
	if {$mplayer ne ""} { puts $mplayer "pausing_keep seek $time 0" }
    }

    # Toggle audio mute during video playback
    # If the application has set the mute event playback, that command
    # is invoked with a single parameter, 0 for audio unmuted, 1 for
    # audio muted
    proc MuteVideo {} {
	variable mplayer
        variable isMuted
        variable clientCB
        if {$isMuted == 1} {
            set isMuted 0
        } else {
            set isMuted 1
        }

	if {$mplayer ne ""} { puts $mplayer "pausing_keep mute" }
        if {"$clientCB(mute)" ne ""} {
            $clientCB(mute) $isMuted
        }
    }

    # lower the audio volume by 5% during playback
    proc VolumeDown {} {
	variable mplayer
	if {$mplayer ne ""} { puts $mplayer "pausing_keep volume -5.0 0" }
    }

    # raise the audio volume by 5% during playback
    proc VolumeUp {} {
	variable mplayer
	if {$mplayer ne ""} { puts $mplayer "pausing_keep volume 5.0 0" }
    }

    # Toggle the on-screen display (multi-step)
    proc OnScreenDisplay {} {
	variable mplayer
	if {$mplayer ne ""} { puts $mplayer "pausing_keep osd" }
    }

    # Set video looping
    # Parameter:
    #   loop: Selects the looping behavior depending on value
    #          -1 = no looping
    #           0 = endless loopoing
    #       N > 0 = loop N times and stop
    proc VideoSetLooping {loop} {
        variable mplayer
	if {$mplayer ne ""} { puts $mplayer "pausing_keep loop $loop 1" }
    }

    # Rewind the video during playback
    # I wanted to be able to do this after the video has ended,
    # but I've not been able to get that to work; once the video
    # has ended, the player must be torn down and set back up
    proc VideoRewind {} {
        variable mplayer
	if {$mplayer ne ""} { puts $mplayer "pausing_keep seek 0 2" }
    }

    # Terminate a video playback and tear down the player
    proc VideoStop {} {
        variable mplayer
        variable clientCB
	if {$mplayer ne ""} { puts $mplayer "stop" }
        EndOfVideo
        #if {$clientCB(done) != ""} {
        #    $clientCB(done)
        #}
    }

    # Take a screen shot
    proc Screenshot {} {
	variable mplayer
	if {$mplayer ne ""} { puts $mplayer "pausing_keep screenshot 0" }
    }

    # Screenshot event handler, invoked by the monitor loop when the
    # slave reports that it has created the snapshot
    # Displays a pop-up with the snapshot image
    # (I should probably add a client callback for this event)
    proc OnScreenshot {filename} {
	variable uid
	set image [image create photo -file $filename]
	# ::file delete $filename
	set dlg [toplevel .dlg_$image -class Dialog]
	wm title $dlg "Screenshot #[incr uid]"
	wm transient $dlg .
	pack [label $dlg.image -image $image] -fill both
	::puts stdout "Screenshot created as $filename"
    }

    # Read lines from mplayer stdout during playback and do things based on
    # what the slave tells us
    proc ReadPipe {chan} {
        variable mplayer
        variable vFrame
        variable clientCB

        # Read everything the slave has sent since last read
	set d [read $chan]

        # Split the mplayer output into lines
	foreach line [split $d \n] {
            ::puts stdout $line
            # clean up the line
	    set line [string trim $line]
            # Detect screenshot events
	    if {[regexp {^\*\*\* screenshot '(.*?)' \*\*\*} $line -> fname]} {
		# delay to permit the file to appear, then invoke the
                # screenshot handler
		after 250 [list ::Vplyr::OnScreenshot $fname]
	    }

            # Look for lines we recognize (other than snapshots)
            if {[lindex $line 0] == "VIDEO:"} {
                # "VIDEO: <something> WxH
                set sizeToken [lindex $line 2]

                # parse the dimension token
                if {[regexp {^([0-9]+?)x([0-9]+?)$} $sizeToken -> wide high]} {
                    ::puts stdout "$sizeToken : w=$wide h=$high"
                    # Reconfigure the video player frame to match the video
                    if {[info exists vFrame]} {
                        ::puts stdout "Reconfiguring $vFrame to $high x $wide"
                        $vFrame configure -width $wide -height $high
                        # If there's a client callback for the 'reconfig' event
                        # then invoke it with option style parameters
                        # This is done for future extension beyond this sizze
                        # reconfiguration
                        if {$clientCB(reconfig) != {}} {
                            catch {$clientCB(reconfig) -frame $vFrame \
                                -width $wide -height $high}
                        }
                    }
                } else {
                    # The size token did not match the expected expression
                    ::puts stdout "$sizeToken : Not a good regular expr"
                }
            } elseif {[lindex $line 0] == "Exiting..."} {
                # The end of playback has been reached
                # Turn off the input monitoring by clearing out the readable
                # event
		fileevent $chan readable {}
                # close the channel to mplayer
		close $chan
                # make sure we forget about the channel
		set mplayer ""

                # Call the end-of-video handler
		EndOfVideo

                # Clean up the vplyr package
		::Vplyr::Exit
	    }
	}
        # If the channel has closed behind our back, shut down
	if {[eof $chan]} {
            # The channel has indeed closed, probably means that mplayer
            # has exited unexpectedly
	    fileevent $chan readable {}
	    close $chan
	    set mplayer ""
	}
    }

    # Eeyboard event handler for player window
    proc KeyInput {w key char} {
        switch -- $key {
            "Down" {
                ::puts stdout "Volume Down"
                VolumeDown
            }
            "Up" {
                ::puts stdout "Volume Up"
                VolumeUp
            }
            "Left" {
                ::puts stdout "Backward by 10 seconds"
                SeekVideo -10.0
            }
            "Right" {
                ::puts stdout "Forward by 10 seconds"
                SeekVideo 10.0
            }
            i -
            I {
                ::puts stdout "Info"
                ::parray ::Vplyr::vidAttrs
            }
            default {
                ::puts stdout "Key pressed on $w: $key ('$char')"
            }
        }
    }

    # Embed a slave mplayer instance in the specified frame
    proc Embed {w src} {
        variable mplayer
        variable mplayer_exe
        variable clientCB
        variable isPaused
        variable isMuted

        #puts stderr "DEBUG: Got to Embed"

        set isPaused 0  ;# isn't paused yet
        set isMuted 0   ;# isn't muted yet

        # Notify the client that it's not paused
        if {$clientCB(pause) != {}} {
            catch {$clientCB(pause) $isPaused}
        }
        # or muted ... yet
        if {$clientCB(mute) != {}} {
            catch {$clientCB(mute) $isMuted}
        }

	set r [catch {
            # build the mplayer command line
	    set cmd $mplayer_exe
	    lappend cmd -quiet -slave -idle -vf screenshot -wid [winfo id $w] \
		$src
            # Create a pipe to the slave mplayer
	    set pipe [open |$cmd r+]

            # Configure the pipe to buffer by lines and be non-blocking
	    fconfigure $pipe -blocking 0 -buffering line

            # Remember the slave pipe file channel
	    set mplayer $pipe

            # Set up the input event handler on the slave pipe
	    fileevent $pipe readable [list ::Vplyr::ReadPipe $pipe]

            # If the client has registered a callback command for video
            # playback started, invoke it with the following arguments:
            #   player frame pathname
            #   video file name
            #   slave pipe file channel
            if {$clientCB(started) != {}} {
                catch {$clientCB(started) $w $src $pipe}
            }
	} err]

	if {$r} {
            # the command didn't work, no slave "mplayer"
	    tk_messageBox -icon error -title "Show video error" \
		-message "$err $::errorCode $::errorInfo"
	} else {
            # The command worked, we have a pipe to the slave "mplayer"
            # Set up event bindings on the player frame
	    #bind $w <ButtonPress> {::Vplyr::PauseVideo}
            bind $w <Enter> {::puts stdout entered ; focus %W}
            bind $w <Leave> {::puts stdout left ; focus [winfo parent %W]}
            bind $w q {::puts stdout "Quitting so soon?"}
            bind $w <Pause> {::Vplyr::PauseVideo}
	    bind $w <Button-1> {::Vplyr::PauseVideo}
            bind $w <Button-2> {::puts stdout "B2: %W %x %y"}
            bind $w <Button-3> {::puts stdout "B3: %W %x %y"}
            bind $w <Button-4> {::puts stdout "B4: %W %x %y"}
            bind $w <Button-5> {::puts stdout "B5: %W %x %y"}
            catch {bind $w <MouseWheel> {::puts stdout "MW: %W %D"}}
            bind $w <KeyPress> {::Vplyr::KeyInput %W %K %A}
            bind $w <Down> {::Vplyr::KeyInput %W %K %A}
            bind $w <Up> {::Vplyr::KeyInput %W %K %A}
            bind $w <FocusIn> {::puts stdout "focus in: %W"}
            bind $w <FocusOut> {::puts stdout "focus out: %W"}
	}
    }

    proc EndOfVideo {} {
        variable clientCB
	variable playing
	::puts stdout "Video done"
        catch {::puts $mplayer quit}
	set playing 0
        if {$clientCB(done) != ""} {
            $clientCB(done)
        }
    }

    # Exit the player session, stopping the slave mplayer and
    # cleaning up the resources
    # If the client has registered a Playback End event, invoke the command
    # (no parameters)
    proc Exit {} {
	variable mplayer
        variable clientCB
	if {[info exists mplayer] && $mplayer ne ""} {
	    set playing 0
	    catch {::puts $mplayer quit}
            catch {close $mplayer}
            set mplayer ""
            if {$clientCB(done) != ""} {
                $clientCB(done)
            }
	    return [after idle [list after 10 [list ::Vplyr::Exit]]]
	}
    }

    # wait for the video playback to complete
    # Parameter: 'wx', the window handle, but it's not used
    proc WaitForVideoDone {wx} {
	variable playing
	variable mplayer
	if {[info exists mplayer]} {
	    if {$mplayer ne ""} {
		{$playing ne 0} {
		    vwait playing
		}
	    }
	}
    }

    # Bind the window mapped event to the proc that starts and embeds the
    # slave mplayer instance in the video fram ('wx') playing the file
    # 'filename'
    proc Video {wx filename} {
	::bind $wx <Map> "
            ::bind %W <Map> {}
            ::Vplyr::Embed %W \"$filename\"
        "
	return $wx
    }

    # Create the frame for the embedded video to be played in
    # Parameters:
    #   wx        The path to the video window (frame)
    #   filename  The fully qualified video file name
    #   args      A string of frame options and values to be used when creating
    #             the playback frame
    # Returns:
    #    The path name of the created video frame
    proc vidframe {wx filename args} {
	variable playing
        variable vFrame

        # Make sure the file name isn't going to cause trouble
        set filename [Sanitize $filename]

        # if the frame already exists, get rid of it
        if {[winfo exists $wx]} {
            bind $wx <Destroy> {}
            destroy $wx
        }

        # Say that the video is being played
	set playing 1

        # build the frame creation command with its arguments
	set framecmd [list frame $wx]
	foreach arg $args {
	    lappend framecmd $arg
	}

        # Create the frame
	set mx [eval $framecmd]

        # Bind the event that destroys the window to shut down the player
        bind $mx <Destroy> [list ::Vplyr::Exit]

        # Keep track of the video frame we just created
        set vFrame $mx

        # Prepare to start up the video when the video frame is mapped
	return [::Vplyr::Video $mx $filename]
    }

    #------
    # The proc "::Vplyr::SetupMplayer" is intended to help the client script
    # set things up so the location of the executable is known.  It takes
    # an optional parameter, which is a file name for the mplayer program.
    # This may be just the executable name with no path information, or
    # include an absolute or relative path to the executable. If called with
    # no argument, or with an empty argument, a default is used:
    # On Windows, the default executable name is "mplayer.exe", on all other
    # systems, "mplayer" (no extension).
    #
    # The following steps are taken in order to attempt to locate the mplayer
    # executable, stopping and returning 1 if it is found, and returning 0
    # if none of the steps work.
    #
    # * When the mplayer executable is found in the current working directory,
    #   that iimage is used
    # * When the environment variable "MPLAYER_EXECUTABLE" is set, its value
    #   is taken to be fully qualified name
    # * When the environment variable "MPLAYER" is set, its value is taken
    #   to be fully qualified name
    # * When the environment variable "MPLAYER_PATH" is set, the value of
    #   that is used as a search path (ala the PATH environment variable)
    #   and the default base name ("mplayer" or "mplayer.exe") is searched
    #   for along that path
    # * The default base name ("mplayer" or "mplayer.exe") is searched for
    #   along the path stored in the environment ("PATH")
    #
    # "::Vplyr:SetupMplayer" should be invoked before using the other
    # interfaces provided by the "::Vplyr" namespace.
    proc SetupMplayer {{exe {}}} {
        variable mplayer_exe_name
        variable mplayer_exe

        # Handle the case where "mplayer_exe" is already set correctly
        if {($exe == {}) && [file exists $mplayer_exe] &&
            [file executable $mplayer_exe]} {
            set mplayer_exe_name [file tail $mplayer_exe]
            return 1
        }

        if {$exe == {}} {
            set exe $::Vplyr::mplayer_exe_name
        }

        if {[file exists $exe]} {
            # fine the way it is
        } elseif {[info exists ::env(MPLAYER_EXECUTABLE)]} {
            set exe $::env(MPLAYER_EXECUTABLE)
            #::puts stdout "Found $exe from MPLAYER_EXECUTABLE"
        } elseif {[info exists ::env(MPLAYER)]} {
            set exe $::env(MPLAYER)
            #::puts stdout "Found $exe from MPLAYER"
        } elseif {[info exists ::env(MPLAYER_PATH)]} {
            set temp [LookupFile $::env(MPLAYER_PATH) $exe]
            if {$temp != {}} {
                #::puts stdout "Found $exe through MPLAYER_PATH"
                set exe $temp
            } else {
                #::puts stdout "Didn't $exe through MPLAYER_PATH"
            }
        } else {
            set temp [LookupFile $::env(PATH) $exe]
            if {$temp == {}} {
                #::puts stdout "Didn't find $exe on PATH"
            } else {
                #::puts stdout "Found $exe on PATH as $temp"
                set exe $temp
            }
        }

        if {![file exists $exe]} {
            #tk_messageBox -icon error -title "Cannot find mplayer" \
            #    -message "Unable to locate the executable for $exe"
            ::puts stderr "Didn't find $exe"
            return 0
        } elseif {![file executable $exe]} {
            ::puts stderr "Found $exe, but it's not executable"
            return 0
        }
        set mplayer_exe $exe
        set mplayer_exe_name [file tail $mplayer_exe]

        #::puts stdout "Found $mplayer_exe_name as $mplayer_exe"
        return 1
    }

    # Export the interface
    namespace export Video vidframe SetVideoDoneCallback VideoSetLooping
    namespace export PauseVideo MuteVideo KeyInput SetVideoStartedCallback
    namespace export SetVideoMuteCallback SetVideoReconfigCallback
    namespace export SetupMplayer
}
# end of vplayer.tcl

# Some site specific stuff to set the known working mplayer since I have
# more than one in my PATH on the Windows box, and one of them doesn't work
# as well as the other
if {$::tcl_platform(platform) == "windows"} {
   set ::Vplyr::mplayer_exe "C:/Apps/mplayer-svn-38151-X86_64/mplayer.exe"
}

# Metadata editor definitions that should be in a namespace, but aren't yet
set alt_classes {alt1 alt2 alt3 alt4}
set alt_classes_next 1
array set alt_class_assoc {alt1 alt1 alt2 alt2 alt3 alt3 alt4 alt4}

# Supported media file types of various sorts
set imageMediaTypes {.jpg .jpeg .jfif .png}
set animMediaTypes {.gif}
set videoMediaTypes {.mp4 .ogv .webm .flv .wmv .mpg .mpeg .avi .mov}

foreach ext $imageMediaTypes {
    set browse_supportedFileTypes($ext) {Still Image}
}
foreach ext $animMediaTypes {
    set browse_supportedFileTypes($ext) Animation
}
foreach ext $videoMediaTypes {
    set browse_supportedFileTypes($ext) Video
}

# default media file types
set browse_fileTypes {
    {{Supported Media} {.jpg .jpeg .jfif .png .gif
        .mp4 .ogv .webm .flv .wmv .mpeg .mpg .avi .mov}}
    {{Image Files} {.jpg .jpeg .jfif .png .gif}}
    {{Video Files} {.mp4 .ogv .webm .flv .wmv .mpeg .mpg .avi .mov}}
    {{All Files}   {*}}
}

# Get a general type for known (and supported) media file types
proc fileTypeText {filename} {
    global browse_supportedFileTypes
    set result {}
    set ext [file extension $filename]
    if {[info exists browse_supportedFileTypes($ext)]} {
        set result $browse_supportedFileTypes($ext)
    }
    return $result
}

# Set up the media file browser support globals
proc initBrowseSupport {} {
    global browse_fileTypes
    set imageTypes [list .jpg .jpeg .jfif .png .gif]
    set videoTypes [list .mp4 .ogv .webm .flv .wmv .mpeg .mpg .avi .mov]

    if {$::tcl_platform(platform) == "windows"} {
        set ::Vplyr::mplayer_exe "C:/Apps/mplayer-svn-38151-X86_64/mplayer.exe"
    }
    set vidSupport [::Vplyr::SetupMplayer]
    if {$vidSupport} {
        set supported [concat $imageTypes $videoTypes]
    } else {
        set supported $imageTypes
    }
    set browse_fileTypes [list [list {Supported Media} $supported]]
    if {$vidSupport} {
        set browse_fileTypes \
            [concat $browse_fileTypes [list [list {Image Files} $imageTypes]]]
        set browse_fileTypes \
            [concat $browse_fileTypes [list [list {Video Files} $videoTypes]]]
    }
    set browse_fileTypes [concat $browse_fileTypes [list [list {All Files} {*}]]]
}

# Meta-editor context
namespace eval ::MetaEdit {
    variable noConsole          0
    variable logLevel           2
    variable debugConsole      -1

    # The 'Store' global array is used to provide the '-textvariable'
    # and '-listvariable' storage for the block data and listbox editor widgets.
    array set Store {
        blockTitle {}
        blockClass {}
        blockStyle {}
        blockText  {}
        mediaSize "N/A"
        mediaType "none"

        mediaWidth      ""
        mediaHeight     ""
        mediaLink       ""
        mediaCaption    ""
        mediaTitle      ""
        mediaAltText    ""
        mediaAttributes ""
        mediaWidth      ""
        mediaHeight     ""
        forceFigure     0

        mediaOptionsModified  0
        mediaScale      ""

        fileSize "0"
        keywordList {}
        activeTag  normal
        currentInfoFile  ""
        currentMediaFile ""
        pauseControl ""
        nextControl ""
        infoFileDisposition -1
        panelsUndocked  0
        tagMode    0
        isAnimation 0
        animIsRunning    0
        animFrameNumber  0
        animFrameList {}
        animFrameCount 0
        animFrameDelay 0
        animCycleTime 0
        mediaTime        ""
        animAfterName {}
    }

    array set Backup {
        blockTitle      ""
        blockClass      ""
        mediaWidth      ""
        mediaHeight     ""
        mediaLink       ""
        mediaCaption    ""
        mediaTitle      ""
        mediaAltText    ""
        mediaAttributes ""
        mediaWidth      ""
        mediaHeight     ""
        forceFigure     0
    }
}

# Set the logging level
proc setLogLevel {{level 2}} {
    set ::MetaEdit::logLevel $level
}

# Set whethet the standard output streams (stdout, stderr) are meaningful
# mode 0 they are, mode 1 they are not
proc setLogMode {{mode 1}} {
    set ::MetaEdit::noConsole $mode
}

# Log a warning to stderr when running interactively, don't bother when
# started as a GUI; if an interactive session thinks it's running directly,
# set ::MetaEdit::noConsole to 0
#
# Parameters:
#   text - The message to write to stderr (actually, it's a list, and each
#          list entry is printed separately
#
proc logWarning {args} {
    if {!$::MetaEdit::noConsole && $::MetaEdit::logLevel >= 1} {
        foreach thing $args {
            puts stderr $thing
        }
        update
    }
}

# Log information to stdout  when running interactively, don't bother when
# started as a GUI; if an interactive session thinks it's running directly,
# set ::MetaEdit::noConsole to 0
#
# Parameters:
#   text - The message to write to stdout (actually, it's a list, and each
#          list entry is printed separately
#
proc logInfo {args} {
    if {!$::MetaEdit::noConsole && $::MetaEdit::logLevel >= 2} {
        foreach thing $args {
            puts stdout $thing
        }
        update
    }
}

# Log a debug message when running interactively, don't bother when
# started as a GUI; if an interactive session thinks it's running directly,
# set ::MetaEdit::noConsole to 0
#
# Parameters:
#   text - The message to write to stdout (actually, it's a list, and each
#          list entry is printed separately
#
proc logDebug {args} {
    if {!$::MetaEdit::noConsole && $::MetaEdit::logLevel >= 3} {
        foreach thing $args {
            puts stdout $thing
        }
        update
    }
}

# Create the color list for the editor widgets 
proc findColors {thrill} {
    set b1 [button .temp_button]
    set l1 [label .temp_label]

    set swbg [$l1 cget -background]
    set swfg [$l1 cget -foreground]
    set sbbg [$b1 cget -background]
    set sbfg [$b1 cget -foreground]

    destroy $l1
    destroy $b1
    set result [subst $thrill]
}

# Text Editor colors
array set browse_widgetColors [findColors {
    normal  {$swbg $swfg}
    ole     {$swbg $swfg}
    ule     {$swbg $swfg}
    raw     {yellow black}
    alt1    {red white}
    alt2    {black white}
    alt3    {green white}
    alt4    {wheat black}
    UnKnOwN {firebrick white}
    active  {"light cyan" gray10}
    inactive {$sbbg $swfg}
    settingsFrame {gray85 $swfg}
    changed {snow2 $sbbg}
    invalid {yellow $sbbg}
    animate {gray85 gray10}
}]

# Get the color lists for given widgets
proc widget_color {what which} {
    global browse_widgetColors
    if {[info exists browse_widgetColors($what)]} {
        set colorPair $browse_widgetColors($what)
    } else {
        set colorPair $browse_widgetColors(normal)
    }
    switch -- $which {
        foreground -
        fg {
            return [lindex $colorPair 1]
        }
        default {
            return [lindex $colorPair 0]
        }
    }
}

# Reset the application data to (close) to a pristine state so that
# it can be run multiple times (with possible code updates) in a single
# interactive session (wish/tkcon/tclsh)
proc browse_reset {} {
    global browse_settings browse_current browse_image
    global edit_paths

    if {[info exists browse_image]} {
        if {$browse_image ne ""} {
            image delete $browse_image
        }
    } else {
        set browse_image {}
    }

    if {[info exists browse_current]} {
        if {$browse_current ne "" && $browse_current ne "browse_default"} {
            if {[array exists $browse_current]} {
                upvar #0 $browse_current blockData
                if {[array exists $blockData(blockStyle)]} {
                    array unset $blockData(blockStyle)
                }
                if {[array exists $blockData(imgStyle)]} {
                    array unset $blockData(imgStyle)
                }
                array unset $browse_current
            }
        }
    }
    set browse_current {}
    # The global array 'browse_settings' contains various bits of data that
    # are useful to have available

    set baseFontSize [font actual TkTextFont -size]

    array set browse_settings [subst  {
        useAltInfoDir 0
        altInfoDir   ""
        imgDisplayRow   1
        imgDisplayCol   1
        textEditWidth   80
        fileEntryWidth  116
        blockTextLines  16
        blockStyleLines 4
        imageStyleLines 4
        appTextEditLines 10
        kwdListLines     9
        kwdListWidth    20
        viewCount       0
        showTooltips    0
        newFileSelected 0
        mediaViewX      500
        mediaViewY      600
        imageBGColor    white
        imageScaleMethod 0
        mediaName       ""
        autoLoadedKeywords 0
        boldButtonFont  [makeSimilarFont TkTextFont boldButtonFont \
			     -weight bold]
        buttonFont      TkTextFont
	entryFont       TkTextFont
        fileEntryFont   [makeSimilarFont TkTextFont fileEntryFont \
			     -family Courier]
        textEditFont    [makeSimilarFont TkTextFont textEditFont \
			     -size [expr $baseFontSize + 1]]
        textFixedFont   [makeSimilarFont textEditFont textFixedFont \
			     -family Courier]
    }]

    set browse_settings(cwd) [pwd]
    set browse_settings(busyMapped) 0
}

# Setup the empty context data template
array set browse_default {
    imgFile     {}
    infoFile    {}
    infoTitle   {}
    blockPrefix {}
    blockName   {}
    blockClass  {}
    blockStyle  {}
    imgStyle    {}
    textBlocks  {}
    ordered     {}
    unordered   {}
    keywords    {}
    unsupported {}
    globalData  browse_default
}

# better getter function to make it easy to get browser settings
proc b_get {item} {
    global browse_settings
    return $browse_settings($item)
}

# better setter function allows setting values in the browser
proc b_set {item value} {
    global browse_settings
    return [set browse_settings($item) $value]
}

# better getter function that returns the name of the value (that is, the
# array element reference) for a given item
proc b_get_var {item} {
    return browse_settings($item)
}

# getter function to make it easy to get widget variable values
proc m_get {item} {
    return $::MetaEdit::Store($item)
}

# setter function allows setting widget variable values
proc m_set {item value} {
    return [set ::MetaEdit::Store($item) $value]
}

# getter function that returns the name of the value (that is, the
# array element reference) for a given widget item
proc m_get_var {item} {
    return ::MetaEdit::Store($item)
}

# getter function to make it easy to get original media option values
proc o_get {item} {
    return $::MetaEdit::Backup($item)
}

# setter function allows easy setting of original media values and the
# editors working copy at the same time
proc o_set {item value} {
    return [m_set $item [set ::MetaEdit::Backup($item) $value]]
}


# Utility function to make it easy to 'remember' widget paths
proc edit_w {ctlName} {
    global edit_paths
    return $edit_paths($ctlName)
}

#####################################################################
# Beginning of GIF89a (and GIF87a) animation support procs          #
#####################################################################

namespace eval ::AnimGIF {
    variable available 1
}

# Procedure to consume a subblock from a GIF data stream. Only the length byte
# is actually looked at, the rest of the block is skipped using "seek".
# We don't care about the data in the sub-block, so it is not stored. We do
# care about its length, so that is returned to the caller.
#
# Parameters:
#   fd  The file descriptor for a stream open for reading and configured for
#       binary translation
#
# Returns:
#   The size of the sub-block
#
proc ::AnimGIF::SubBlock {fd} {
    binary scan [read $fd 1] c sbLen
    set cursor [tell $fd]
    set sbLen [expr $sbLen & 0xFF]
    if {$sbLen > 0} {
        seek $fd $sbLen current
    }
    return $sbLen
}

# 
# Procedure to consune a GIF 87a or GIF 89a image block from an open
# stream. The stream block is recorded at the end of a list as having
# occurred, but no information about the image block itself is preserved,
# since that will be handled by the TkImg GIF code for the photo image
# that will be created to display said block.
#
# Parameters:
#   fd      open read stream configured for binary translation
#   iList   the name of the list variable in the caller's scope
#   num     the block number to use when appending the image block's
#           presence in 'iList'
# Returns:
#   Nothing
#
# This procedure appends two items to the list referenced by 'iList',
# the block type ("image"), and a list that contains information about
# the list. The info list is made up of attribute/value pairs. Because
# no information about the image block itself is needed, this is just
# the block number '[list block $num]'.
#
proc ::AnimGIF::ImageBlock {fd iList num} {
    upvar 1 $iList itemList

    # read the remainder of the image block header; the first byte
    # was consumed by the caller
    binary scan [read $fd 9] ssssc lpos topos wid hgt flg
    set lctUsed [expr ($flg >> 7) & 1]
    set interlace [expr ($flg >> 6) & 1]
    set sorted  [expr ($flg >> 5) & 1]
    set lctSizeExp [expr ($flg & 7) + 1]
    set lctSize [expr 3 * (2**$lctSizeExp)]

    # Skip the local color table if there is one indicated
    if {$lctUsed} {
        set cursor [tell $fd]
        seek $fd $lctSize current
        set cursor [tell $fd]
    }
    # Read the LZW compression minimum code size byte
    binary scan [read $fd 1] c lzwMin

    # consume all of the GIF subblocks from the data stream
    while {[::AnimGIF::SubBlock $fd] > 0} {
    }

    # Record that we've processed an image block.  This will be used
    # to refine the animation frame list in post-processing
    lappend itemList image [list block $num]
}

# Procedure to consume GIF Extension blocks from within a GIF data stream.
# The first byte of the block header has been read already by the caller
# to identify it as an Extension Block in the first place.
#
# This procedure knows about all the Extension Block types defined in the
# GIF89a specification:
#   Plain Text (0x01)
#   Graphic Control (0xF9)
#   Comment (0xFE)
#   Application (0xFF)
# In each case, the remainder of the block header is read and any subblock
# data is consumed. Each Extension Block is recorded in a block description
# list by appending two elements to it of the form:
#     blockType attributeList
# where 'blockType' identifies the extended block type and 'attributeList'
# is a list of pairs of elements, the first identifying the attribute and
# the second giving its value. The attribute list can be accesed either
# directly using 'lindex' or by creating a temporary array with it as the
# source for an 'array set' command, with the attribute name as the array
# index and the value as the, um, value.
#
# Although the block headers are fully parsed, only minimal information
# is recorded about what's in them with the exception of the Graphic Control
# block. Much of the data from each Graphic Control block is recorded
# in the block description list for use when building the animation list
# later.
#
# Parameters:
#   fd      open read stream configured for binary translation
#   iList   the name of the list variable in the caller's scope
#   num     the block number to use when appending the image block's
#           presence in 'iList'
# Returns:
#   Nothing
#
proc ::AnimGIF::ExtensionBlock {fd iList num} {
    upvar 1 $iList itemList

    # The byte identifying the block type as "Extended" has already been
    # consumed by the caller; get the Extended Block Type code to identify
    # what to do with the rest.
    binary scan [read $fd 1] c type
    # the scan above ends up with a signed integer value, and we want
    # just the unsigned byte value, so mask off the rest of the bits
    set type [expr $type & 0x00FF]

    # Dispatch to the handler for the Extended Block under review
    # I was unable to get the numeric comparison to work they way I wanted,
    # so the 'format' in the 'switch' makes a string that matches fine,
    # though it's probably inefficient.
    switch -- [format 0x%02x $type] {
        0x01 {
            # plain text
            # This is not a comment block, it's text to be displayed as part
            # of the image within a defined (monospaced) grid.  I think I
            # saw this used early on, but I've not seen it used in many
            # years. See the GIF89a spec for details.
            #
            # This extended block does have an internal header (actually
            # the first subblock) that defines the location and size of
            # the grid; since I'm not doing anything with this block-type
            # other than consuming it and saying it exists, I am not
            # reading and decoding it.
            while {[::AnimGIF::SubBlock $fd] > 0} {
            }

            # Append the block type ("plaintext") and attributes to the
            # block description list.  The only attribute recorded is the
            # block number.
            lappend itemList plaintext [list block $num]
        }
        0xf9 {
            # graphic control extension block
            # This one has a 5 byte inner header, which is actually a subblock
            # but notdocumented as such in the GIF89a specification:
            #    +0x00-0x00: Header Length not including this field (always 4)
            #    +0x01-0x01: Packed binary flags and values (decoded below)
            #    +0x02-0x03: Delay time (little-endian 16 bit integer) in
            #                1/100 Second units
            #    +0x04-0x04: Index of transparent colormap entry, if any
            binary scan [read $fd 5] ccsc bsize flg delay trans

            # Decode the packed flag and data byte into its fields (msb=7):
            #     7-5: Reserved
            #     4-2: Disposal Method
            #     1-1: User Input Flag
            #     0-0: Transparent Color Flag
            #
            set dispose [expr ($flg >> 2) & 7]
            set userIn  [expr ($flg >> 1) & 1]
            set transC  [expr $flg & 1]

            # For the purposes of this exercise, we only really care about the
            # delay and the disposal; the GIF reader in the TkImg cares about
            # the transparent color and its flag, but we really don't need
            # them.  Nobody cares about user input that I'm aware of. Neat
            # idea, mind you, but of little utility here.
            #
            # Record the block type ("graphext") and the list of attributes:
            # block number, delay, disposition, and (for no real reason) the
            # transparent color flag (not the color index)
            # 
            lappend itemList graphext \
                [list block $num delay $delay dispose $dispose \
                    transparent $transC]

            # There is a single, zero-length subblock following the useful
            # information.
            while {[::AnimGIF::SubBlock $fd] > 0} {
            }
        }
        0xfe {
            # comment block
            # Just some supposedly human readable text with no meaning to the
            # decoder; I suspect that at least a few applications have taken
            # liberties with this particular extended block, but I'll keep my
            # mouth shut, since the GIF89a standard says one should never do
            # that.  It's just subblocks with text, ending with the obligatory
            # zero-length sub-block.

            # Consume all of the subblocks for this Comment Block
            while {[::AnimGIF::SubBlock $fd] > 0} {
            }

            # Record that we have a comment block, its only attribute is
            # its block number.
            lappend itemList comment [list block $num]
        }
        0xff {
            # Application extension
            # Application specific information
            # The first subblock contains the application identifier and
            # an authcode.  I assume that an application that uses this
            # will define their own structure in the subblocks that follow,
            # since the GIF89a specification doesn't really address this.
            # In any case, though we decode the header here, we don't
            # record anything other than the consumption of an
            # Application Extension Block.
            # Internal Header Data Subblock:
            #   00-00: Sub-block length beyond the length byte itself,
            #          always 11
            #   01-08: Application Identifier
            #   09-0B: Application Authentication Code
            binary scan [read $fd 12] ca8a3 bsize appId appAuth

            # Consume the subblocks ending in the mandatory zero-length one
            while {[::AnimGIF::SubBlock $fd] > 0} {
            }

            # Record the block in the block description list; all we record is
            # the block type ("application") and the block number (its only
            # attribute)
            lappend itemList application [list block $num]
        }
            
        default {
            # Unrecognized Extended Block Type
            # This should not occur, but if it does, this code assumes that
            # the form is the same as all the others, and can be consumed
            # without knowing anything about it.

            # Figure out where this block started (two bytes have been read
            # so far)
            set blockStart [expr [tell $fd] - 2]

            # Consume the subblocks ending in the mandatory zero-length one
            while {[::AnimGIF::SubBlock $fd] > 0} {
            }

            # This block is recorded as "unknown" with three attributes:
            # Block number ("block"), starting location ("start"), and
            # the beginning of the next block ("next").
            lappend itemList \
                unknown [list block $num start $blockStart next [tell $fd]]

            puts stderr \
                "Unrecognized GIF extension block id: [format %02x $type]"
        }
    } ; # end of switch
}

# proc to scan a named GIF89a or GIF87a file and identify all of its internal
# blocks, extracting the data required for animating a multi-frame GIF file
# in Tk with TkImg
#
# This procedure was written with a copy of the GIF89a specification in
# another window.  At the time of this writing, the GIF89a specification
# is available at "https://www.w3.org/Graphics/GIF/spec-gif89a.txt".
# I've taken a lot of shortcuts and I don't use the terminology in my
# comments that is used in the spec, so refer to the spec to understand
# what's really going on in GIF files.
#
# This procedure produces a list of internal blocks within the GIF file,
# not including the GIF Header, optional Global Color Table or the mandatory
# Logical Screen Descriptor, which all occur before the block structure
# really begins.
#
# The purpose of the list (referred to elsewhere as a "block description
# list) is to provide information on a frame-by-frame basis to code that
# animates multi-frame GIF files.  Many of these are optimized to have
# different delays between frames, and some have different disposal methods
# from frame to frame. Just grabbing the first Graphic Control Extension
# block from the stream does not always permit satisfactory results.
#
# Parameters:
#   fileName  Name of a GIF89a file to scan/decode.
#
# Returns:
#   A "Block Description List" that outlines the structure of the GIF87a
#   or GIF89a file that has been scanned.
#
proc ::AnimGIF::ScanFile {fileName} {
    # Open the file and configure the file stream for binary use
    set fd [open $fileName rb]
    fconfigure $fd -translation binary

    set blockList {}

    # A GIF8Xa file begins with a header that has the following fields
    #   00-02: Signature, always "GIF"
    #   03-05: Version, either "89a" or "87a"
    binary scan [read $fd 6] a3a3 sig ver

    # If the file doesn't begin with the right stuff, don't try to
    # process it further.
    if {$sig ne "GIF" || ($ver ne "89a" && $ver ne "87a")} {
        puts stderr "$file is not a GIF89a or GIF87a file"
        close $fd
        return {}
    }

    # The header is followed by the "Logical Screen Descriptor" with
    # the following fields:
    #   00-01: Logical Screen Width (little-endian unsigned 16 bit integer)
    #   02-03: Logical Screen Height (little-endian unsigned 16 bit integer)
    #   04-04: Packed byte with Flags and Settings (decoded below)
    #   05-05: Background Color Index (unsigned)
    #   06-06: Pixel Aspect Ratio (unsigned)
    binary scan [read $fd 7] ssccc wid hgt flg bk par

    # The packed byte at offset 0x04 into the Logical Screen Descriptor
    # has the following bit-fields in it (MSB=7):
    #   7-7: Global Color Table Flag (boolean)
    #   6-4: Color Resolution (bits/color plane minus 1, so a range of [1..8]
    #        inclusive)
    #   3-3: Sort Flag (boolean)
    #   2-0: Global Color Table Size (exponant minus 1, the size of the GCT,
    #        when present, is 3*2^(fieldValue+1))
    set gctUsed   [expr ($flg >> 7) & 1]
    set colorRes  [expr ($flg >> 4) & 7] 
    set colorSort [expr ($flg >> 3) & 1] 
    set gctSizeExp [expr $flg & 7]

    # calculate the GCT size (speculative)
    set gctSize [expr 3 * (2**($gctSizeExp + 1))]

    # For animation purposes, all we really care about is the height and
    # width, and maybe whether it's GIF89a or GIF87a.  The block description
    # list begins with this header information with the block type as "gif"
    # and the attribute list containing "version", "width" and "height",
    # plus a block number ("block") of 0, just to be consistent with the
    # other "records" in the list.
    lappend blockList gif [list block 0 width $wid height $hgt \
                               validated 0 \
                               version $ver file $fileName]

    # if the flags indicate that there is a Global Color Table (GCT),
    # consume it.  We don't look at it, as that's done by the TkImg
    # extensions GIF handling code.  All we care about is what the
    # animation code needs to make a flip-book out of images that are
    # loaded by lower level stuff.
    if {$gctUsed} {
        set cursor [tell $fd]
        seek $fd $gctSize current
        set cursor [tell $fd]
    }

    # From here on, the GIF8Xa file goes into a packet mode, where each
    # packet, or block, begins with a byte that identifies what sort of
    # packet it is.  The loop below decodes and consumes these packets
    # building up a list, in order, of information for each packet.
    set blockNum 0

    # Loop until we don't want to anymore
    while {true} {
        # Count the blocks in the file
        incr blockNum
        # keep track of where the block starts
        set cursor [tell $fd]

        # read the first byte of the block; this identifies the block type
        binary scan [read $fd 1] c blockType
        # The scan operation above produces a signed integer that has extended
        # bit 7 through the more significant bits; to dispatch, we want an
        # unsigned byte value, so those extra bits are masked off.
        set blockType [expr $blockType & 0x00FF]

        # I was having trouble with 'switch' treating 0x21 and 33 as a match,
        # so I use the format to force a string comparison. It may not be
        # efficient, but it works
        switch -- [format 0x%02x $blockType] {
            0x21 {
                # Extension Block
                # Decode these externally and come back with an updated
                # block description list
                ::AnimGIF::ExtensionBlock $fd blockList $blockNum
            }
            0x2c {
                # Image Description Block
                # These are the individual images within the GIF file.
                # They have structure, but we don't want to know much
                # about what they contain at this point.  Use an external
                # routine to consume (and ignore) the image and add
                # a brief block description to the list.
                if {[eof $fd]} {
                    puts stderr "Unexpected end of file at $blockNum"
                    lappend blockList end [list block $blockNum]

                    # mark it as valid
                    global TestBlockList
                    set TestBlockList $blockList

                    set status [lindex $blockList 1]
                    puts stdout "Status: $status"

                    set blockList \
                        [lreplace $blockList 1 1 \
                             [lreplace [lindex $blockList 1] 7 7 1]]

                    # And we are done.
                    break;
                }
                ::AnimGIF::ImageBlock $fd blockList $blockNum
            }
            0x3b {
                # GIF Trailer Block (end of GIF stream)
                # This has no data, it simply marks the end of the GIF
                # file data in an orderly fashion.  This is added to
                # the block description list as an "end" block, its
                # only attribute is the block number.
                lappend blockList end [list block $blockNum]

                # mark it as valid
                global TestBlockList
                set TestBlockList $blockList

                set status [lindex $blockList 1]
                puts stdout "Status: $status"

                set blockList \
                    [lreplace $blockList 1 1 \
                         [lreplace [lindex $blockList 1] 7 7 1]]

                # And we are done.
                break
            }
            default {
                # Unrecognized Block Identifier
                # This is probably a sign of either an error in the decoding
                # prior to this point or a corrupted GIF file.  Either way,
                # noting beyond this can be decoded.  Callers can detect this
                # condition by the absence of any "end" block descriptors in
                # the description list.
                puts stderr "Unknown block type: [format 0x%02x $blockType]"
                break
            }
        }
        # break
    }

    # close the GIF file
    close $fd

    # Give the caller the block description list
    return $blockList
}

proc ::AnimGIF::Analyze {fileName animListVar} {
    upvar 1 $animListVar frameList
    set blockList [::AnimGIF::ScanFile $fileName]

    set frameList {}

    if {![llength $blockList]} {
        return [list 0 0 0 0]
    }

    # we walk through the block description list, retaining the values
    # from the latest Graphics Control Extension block to be used with
    # the next Image Description block entry.
    set cnt 0
    set delay 0
    set transp 0
    set dispose 0
    set height 0
    set width 0
    set playTime 0

    # process the "records" in order pulling both the block type and the
    # attribute list for a record in each iteration
    foreach {type values} $blockList {
        # See what the record recorded
        if {$type eq "graphext"} {
            # It's a Graphic Control Extension record
            # Make a temporary array to make it easy to extract
            # attribute values
            array set attrs $values

            # extract what we care about
            set delay $attrs(delay)
            set transp $attrs(transparent)
            set dispose $attrs(dispose)

            # if the delay is 0, assume .1 seconds for now
            if {$delay == 0} {
                # delay is 100ms
                set delay 100
            } else {
                # delay is non-zero; the Graphic Control Extension block
                # uses 1/100's of a second, we want milliseconds, so we
                # multiply by 10
                set delay [expr $delay * 10]
            }
        } elseif {$type eq "image"} {
            # An image block was recorded
            # Add an entry to the animation frame list for later augmentation
            # with no image attached; the image will be added if needed later.
            lappend frameList [list $cnt $delay $dispose {}]
            incr playTime $delay
            incr cnt
        } elseif {$type eq "gif"} {
            # This tells us the size of the image. Though it's the first
            # record in the block description list, there's only one of them,
            # so it's last in the conditional.
            array set tempArray $values

            set width $tempArray(width)
            set height $tempArray(height)
            set valid $tempArray(validated)
            if {!$valid} {
                return [list 0 0 0 0 0]
            }
        }
        # we don't care about any of the other block record types;
        # they are ignored
    }

    # The animation frame list is already in the caller's context, so we just
    # need to return the image dimensions, the frame count, file validity and
    # ideal play time in milliseconds
    return [list $cnt $width $height $valid $playTime]
}

proc ::AnimGIF::TearDown {animListVar} {
    upvar 1 $animListVar frameList
    foreach frame $frameList {
        set img [lindex $frame end]
        if {$img != {}} {
            if {[catch {image delete $img} problem]} {
                logWarning "Unable to delete image $img, $problem"
            }
        }
    }
    set frameList {}
}

#####################################################################
# End of GIF89a (and GIF87a) animation support procs                #
#####################################################################

# set the ratio table for image scaling
proc set_ratios {matrix {limit 10}} {
    upvar 1 $matrix matrixList

    set matrixList {}

    for {set num 1} {$num < $limit} {incr num} {
        for {set den [expr $num + 1]} {$den < $limit} {incr den} {
            set dend [expr {int(floor((double($num)/double($den))*1000.0))}]
            set pos [lsearch -index 0 $matrixList $dend]
            if {$pos < 0} {
                lappend matrixList [list $dend $num $den]
            }
        }
    }
    set matrixList [lsort -integer -decreasing -index 0 $matrixList]
}

# Get the scaling info given a current and maximum allowed dimension
proc get_scales {scaleVar dim maxDim} {
    upvar 1 $scaleVar scaleList

    if {$dim <= $maxDim} {
        set result {1 1}
    } else {
        set ratio [expr {int(floor((double($maxDim)/double($dim))*1000.0))}]
        foreach g $scaleList {
            if {$ratio >= [lindex $g 0]} {
                set result [lreplace $g 0 0]
                break
            }
        }
    }
    return $result
}

# Fit an image into a rectangle of a given maximum width and height
proc browse_fit_image {img maxWidth maxHeight} {
    set wid [image width $img]
    set hgt [image height $img]

    logInfo "Image is $wid x $hgt, max is $maxWidth x $maxHeight"

    if {$wid <= $maxWidth && $hgt <= $maxHeight} {
        logInfo "No scalling needed"
        m_set mediaScale "1:1"
        return $img
    }

    if {![info exist ::MetaEdit::scaleLookup]} {
        set ::MetaEdit::scaleLookup {}
        set_ratios ::MetaEdit::scaleLookup 24
    }
    set ratiox [expr {int(floor((double($maxWidth)/double($wid))*1000.0))}]
    set ratioy [expr {int(floor((double($maxHeight)/double($hgt))*1000.0))}]

    logDebug "Ratios: X=$ratiox  Y=$ratioy"
    if {$ratiox < $ratioy} {
        set scaler [get_scales ::MetaEdit::scaleLookup $wid $maxWidth]
        logInfo "Selected X for scaling"
    } else {
        set scaler [get_scales ::MetaEdit::scaleLookup $hgt $maxHeight]
        logInfo "Selected Y for scaling"
    }

    set up [lindex $scaler 0]
    set down [lindex $scaler 1]
    logInfo "Scaling is $up / $down"
    m_set mediaScale "$down:$up"

    set finX [expr int(double($wid * $up) / double($down))]
    set finY [expr int(double($hgt * $up) / double($down))]

    logInfo "Final image size: ${finX}x${finY}"

    set finImage [image create photo -width $finX -height $finY]

    if {$up > 1} {
        set tempX [expr int(double($wid * $up + 3) / 4.0)]
        set tempY [expr int(double($hgt * $up + 3) / 4.0)]

        set stepOX [expr int(double($wid + 3) / 4.0)]
        set stepOY [expr int(double($hgt + 3) / 4.0)]
        set stepFX [expr int(double($finX + 3) / 4.0)]
        set stepFY [expr int(double($finY + 3) / 4.0)]

        set tempImage [image create photo -height $tempY -width $tempX]

        # set mx [toplevel .tempImg]
        # set mxImage [label $mx.image -image $finImage]
        # pack $mxImage

        set pixColO 0
        set pixRowO 0
        set remainOX $wid
        set remainOY $hgt

        set pixColF 0
        set pixRowF 0

        for {set $pixRowO 0} {$pixRowO < $hgt} {} {
            if {$stepOX > $remainOY} {
                set stepOY [expr $remainOY - 1]
            }

            set copyBotO [expr $pixRowO + $stepOY]
            set copyBotF [expr $pixRowF + $stepFY]

            if {$copyBotO >= $hgt} {
                set copyBotO [expr $hgt - 1]
                set copyBotF [expr $finY - 1]
            }
            for {} {$pixColO < $wid} {} {
                if {$stepOX > $remainOX} {
                    set stepOX [expr $remainOX - 1]
                }
                set copyRgtO [expr $pixColO + $stepOX]
                set copyRgtF [expr $pixColF + $stepFX]
                if {$copyRgtO >= $wid} {
                    set copyRgtO [expr $wid - 1]
                    set copyRgtF [expr $finX - 1]
                }

                logDebug \
                    "Copying from ($pixColO,$pixRowO)-($copyRgtO,$copyBotO) ($stepOX,$stepOY)"
                update
                $tempImage copy $img -from $pixColO $pixRowO $copyRgtO $copyBotO \
                    -zoom $up $up
                logDebug "Copying to ($pixColF,$pixRowF)-($copyRgtF,$copyBotF) ($stepFX,$stepFY)"
                update
                $finImage copy $tempImage -subsample $down $down \
                    -to $pixColF $pixRowF ; # $copyRgtF $copyBotF
                update
                $tempImage blank
                set pixColO [expr $pixColO + $stepOX]
                set pixColF [expr $pixColF + $stepFX]
            }
            set pixRowO [expr $pixRowO + $stepOY]
            set pixRowF [expr $pixRowF + $stepFY]
            set pixColO 0
            set pixColF 0
            logDebug "Row stepping to O:$pixRowO  F:$pixRowF"
            update
        }
        image delete $tempImage
        # after 15000 [list destroy $mx]
    } else {
        # integer downsampling; no upscale needed; simpler code
        # (also, can use integer aritmetic)
        logDebug "scaling down by $down to \[${finX}x${finY}\]"
        $finImage copy $img -subsample $down $down
    }
    image delete $img
    return $finImage
}

# Shrink an image to fit within a given set of bounds
proc browse_fit_image_simple {img maxWidth maxHeight} {
    set wid [image width $img]
    set hgt [image height $img]

    if {$wid <= $maxWidth && $hgt <= $maxHeight} {
        return $img
    }

    set sub 1
    while {($wid / $sub) > $maxWidth} {
        incr sub 1
    }
    while {($hgt / $sub) > $maxHeight} {
        incr sub 1
    }

    if {$sub > 1} {
        set wid [expr $wid / $sub]
        set hgt [expr $hgt / $sub]
        logDebug "scaling down by $sub to \[$wid x $hgt\]"
        set newImg [image create photo -height $hgt -width $wid]
        $newImg copy $img -subsample $sub $sub
        image delete $img
        set img $newImg
    }
    return $img
}

# Get a bit of stat info for a file
proc browse_get_file_stat {name item} {
    array set statArray {}
    file stat $name statArray
    if {[info exists statArray($item)]} {
        return $statArray($item)
    } else {
        return ""
    }
}

# Call the file open dialog to locate a new media file to load
proc browse_getMediaFile {parent} {
    global browse_fileTypes

    set filename [tk_getOpenFile -initialdir [b_get cwd] \
                      -title {Select a file} \
                      -filetypes $browse_fileTypes]
    if {$filename ne ""} {
        b_set cwd [file dirname $filename]
        b_set mediaFile [file tail $filename]
        b_set newFileSelected 1
        m_set fileSize [string trim [browse_get_file_stat $filename size]]
    }
    return $filename
}

##############################
# Block editor related procs
##############################

# Reset the alternate paragraph class to text tag list
proc reset_tags {} {
    global alt_class_assoc alt_classes_next
    array set alt_class_assoc {alt1 alt1 alt2 alt2 alt3 alt3 alt4 alt4}
    set alt_classes_next 1
}

# Assign a 'text' control tag to a user-specified alternative paragraph
# class in the info file
proc assign_tag {spec} {
    global alt_classes alt_classes_next alt_class_assoc
    for {set j 1} {$j < $alt_classes_next} {incr j 1} {
        set index "alt$j"
        if {$spec eq $alt_class_assoc($index)} {
            return $index
        }
    }
    if {$alt_classes_next < 5} {
        set result "alt${alt_classes_next}"
        incr alt_classes_next 1
        set alt_class_assoc($result) $spec
        return $result
    }
    logWarning "too many alt classes"
    return "alt4"
}

# Break down and store the image presentation options
proc decode_media_options {blockDataName optionText} {
    upvar 1 $blockDataName blockData

    foreach option [split $optionText "|"] {
        logDebug $option

        if {[regexp {^(.+?):(.*)$} $option matched item value]} {
            set item  [string trim $item]
            set value [string trim $value]

            logDebug "option=$item value=$value"

            switch -nocase -- $item {
                attrs -
                attributes {
                    o_set mediaAttributes $value
                }
                alt-text -
                alt {
                    o_set mediaAltText $value
                }
                width {
                    o_set mediaWidth $value
                }
                height {
                    o_set mediaHeight $value
                }
                link {
                    o_set mediaLink $value
                }
                title {
                    o_set mediaTitle $value
                }
                figure -
                fig {
                    if {[expr $value] && 1} {
                        set value 1
                    } else {
                        set value 0
                    }
                    o_set forceFigure $value
                }
                default {
                    # unrecognized option line
                    logWarning "Unrecognized media attribute: $item"
                }
            }
        }
    }
}

# Decode the in-memory data structure created by the info file reader
# procs and load the edit widgets in the metadata editor
proc load_edit_data {blockDataName} {
    global ol_icn ul_icn
    global alt_classes alt_classes_next alt_class_assoc
    global $blockDataName
    upvar #0 $blockDataName blockData

    reset_tags

    set bte [edit_w blockText]
    set bse [edit_w blockStyle]
    set ise [edit_w imgStyle]
    set apd [edit_w appText]

    set btitle [edit_w blockTitle]
    set bclass [edit_w blockClass]
    $bte configure -undo false
    $bse configure -undo false
    $ise configure -undo false
    $apd configure -undo false

    o_set blockTitle $blockData(infoTitle)
    o_set blockClass $blockData(blockClass)

    $bse configure -state normal
    $bse delete 1.0 end
    upvar #0 $blockData(blockStyle) blockStyle
    foreach {s v} [array get blockStyle] {
        $bse insert end "${s}: ${v};\n"
    }
    $bse edit modified false
    $bse edit reset
    $bse configure -undo true

    $ise configure -state normal
    $ise delete 1.0 end
    upvar #0 $blockData(imgStyle) imgStyle

    if {[array size imgStyle] > 0} {
        foreach {s v} [array get imgStyle] {
            $ise insert end "${s}: ${v};\n"
        }
    }
    $ise edit modified false
    $ise edit reset
    $ise configure -undo true

    $bte configure -state normal
    $bte delete 1.0 end
    set lineCounter 0

    foreach textBlock $blockData(textBlocks) {
        set line [lindex $textBlock 0]
        set type [lindex $textBlock 1]
#        logDebug "$type:$textBlock"
        incr lineCounter 1
        switch -exact -- $type {
            @ {
                # normal text
                $bte insert end "$line\n"
            }
            raw -
            ! {
                # Raw HTML
                $bte insert end "$line\n"
                $bte tag add raw $lineCounter.0 $lineCounter.end
            }
            UnKnOwN -
            () {
                # Unrecognized line; displayed with a special tag
                $bte insert end "$line\n"
                $bte tag add UnKnOwN $lineCounter.0 $lineCounter.end
            }
            + {
                # ordered list - taken out of another place
                foreach item $blockData(ordered) {
                    $bte insert end "\t"
                    $bte image create end -image $ol_icn
                    $bte insert end "\t$item\n"
                    $bte tag add ole $lineCounter.0 $lineCounter.end
                    incr lineCounter 1
                }
                incr lineCounter -1
            }
            . {
                # undordered list - taken out of another place
                foreach item $blockData(unordered) {
                    $bte insert end "\t"
                    $bte image create end -image $ul_icn
                    $bte insert end "\t$item\n"
                    $bte tag add ole $lineCounter.0 $lineCounter.end
                    incr lineCounter 1
                }
                incr lineCounter -1
            }
            default {
                # alternative <p> class
                set mtag [assign_tag $type]
                $bte insert end "$line\n"
                $bte tag add $mtag $lineCounter.0 $lineCounter.end
            }
        }
    }
    $bte edit modified false
    $bte edit reset
    $bte configure -undo true

    edit_load_keywords blockData
    edit_load_app_data blockData
    b_set newFileSelected 0
}

# Get the height for the media view area
proc get_media_area_height { } {
    set win [edit_w imageFrame]
    set treeHeight [winfo height [edit_w treeWindow]]
    set overhead [expr [grid rowconfigure $win 1 -minsize] + $treeHeight + \
                      2 * [winfo height [edit_w mediaBannerFrame]]]
    set imgHeight [expr [winfo height [edit_w editFrame]] - $overhead]
    return $imgHeight
}

# Fix the geometry of the editing controls on resize
proc edit_fix_geometry {args} {
    set targetWidth [winfo width [edit_w altKeyHelpFrame]]
    set editWidth   [winfo width [edit_w blockText]]
    set sYwidth     [winfo width [edit_w blockTextY]]
    set charWidth [font measure [b_get textEditFont] "0"]
    set diff [expr ($targetWidth - $editWidth - $sYwidth ) / $charWidth]
    set new [expr [[edit_w blockText] cget -width] + $diff]
    [edit_w blockText] configure -width $new
}

# End of Playback client callback
proc movie_end {} {
    puts stderr "Movie says it ended"
    if {[info exists ::edit_paths(movieViewerFrame)]} {
        destroy [edit_w movieViewerFrame]
        catch {unset ::edit_paths(movieViewerFrame)}
    } else {
        puts stderr "window doesn't exist anymore"
        puts stderr [info level]
    }
}

# Playback Started client callback
proc movie_started {args} {
    puts stderr "started"
    puts stderr "$args"
    movie_do_osd
    movie_do_pause
    ::Vplyr::VideoSetLooping 0
}

# Reconfig client callback
proc movie_reconfig {args} {
    puts stderr "reconfig $args"
    foreach {thing value} $args {
        switch -- $thing {
            -height {
                o_set mediaHeight $value
            }
            -width {
                o_set mediaWidth $value
            }
            -default {
                puts stderr "Unrecognized: $thing $value"
            }
        }
    }
}

# Pause client callback
proc movie_pause {paused} {
    puts stderr "pause"
    if {$paused} {
        [edit_w moviePause] configure -text "Play"
    } else {
        [edit_w moviePause] configure -text "Pause"
    }        
}

# Mute client callback
proc movie_mute {muted} {
    if {$muted} {
        [edit_w movieMute] configure -text "Unmute"
    } else {
        [edit_w movieMute] configure -text "Mute"
    }        
    puts stderr "mute"
}

# Movie controls

# Pause control commmand for button
proc movie_do_pause {} {
    ::Vplyr::PauseVideo
}

# Mute control command for button
proc movie_do_mute {} {
    ::Vplyr::MuteVideo
}

# OSD control command for button
proc movie_do_osd {} {
    ::Vplyr::OnScreenDisplay
}

# Set up the video player
proc movie_show {parent filename width height} {
    set mf [frame $parent.movieFrame -background gray20]
    set vf [frame $mf.video]
    set cf [frame $mf.controls -background gray20]
    
    o_set mediaWidth $width
    o_set mediaHeight $height
    set length [::Vplyr::GetVideoInfo $filename LENGTH {}]
    o_set mediaTime $length

    set pause [button $cf.pauseVideo -text "Pause" -command ::movie_do_pause \
                   -background pink]
    set osd [button $cf.osd -text "OSD" -command ::Vplyr::OnScreenDisplay]
    set mute [button $cf.muteAudio -text "Mute" -command ::movie_do_mute \
                  -background wheat]

    grid $pause -row 1 -column 1 -sticky nsw
    grid $osd -row 1 -column 5 -sticky ns
    grid $mute -row 1 -column 7 -sticky nse
    grid columnconfig $cf 0 -minsize 8 -weight 0
    grid columnconfig $cf 1 -minsize 40 -weight 0
    grid columnconfig $cf 2 -minsize 20 -weight 1
    grid columnconfig $cf 6 -minsize 20 -weight 1
    grid columnconfig $cf 7 -minsize 40 -weight 0
    grid columnconfig $cf 8 -minsize 8 -weight 0
    grid $vf -row 1 -column 1 -sticky news
    grid $cf -row 3 -column 1 -sticky news
    grid rowconfig $mf 2 -minsize 8
    grid rowconfig $mf 4 -minsize 8
    if {$width == {}} {
        set width 640
    }
    if {$height == {}} {
        set height 480
    }
    set vid [::Vplyr::vidframe $vf.player $filename \
                 -width $width -height $height \
                 -takefocus 1]

    ::Vplyr::SetVideoDoneCallback ::movie_end
    ::Vplyr::SetVideoPauseCallback ::movie_pause
    ::Vplyr::SetVideoMuteCallback ::movie_mute
    ::Vplyr::SetVideoStartedCallback ::movie_started
    ::Vplyr::SetVideoReconfigCallback ::movie_reconfig

    grid $vid -row 0 -column 0 -sticky new
    grid $mf -row 0 -column 0 -sticky new

    set ::edit_paths(moviePause) $pause
    set ::edit_paths(movieMute) $mute
    set ::edit_paths(movieViewerFrame) $mf
    set ::edit_paths(movieViewer) $vid

    #movie_do_pause
    #::Vplyr::VideoSetLooping 0

}

proc browse_fileSelected {w filename} {
    global browse_image browse_current
    global animControlBitmaps

    # Animation rundown
    if {[llength [m_get animFrameList]]} {
        if {[m_get animIsRunning]} {
            # stop the animation
            m_set animIsRunning 0
            catch {after cancel [m_get animAfterName]}
            m_set animAfterName {}
        }
        # Get rid of the stuff related to it
        ::AnimGIF::TearDown [m_get_var animFrameList]
    }

    m_set mediaTime ""
    m_set pauseControl ""
    m_set nextControl ""
    [edit_w nextControl] configure -background [widget_color inactive bg] \
        -image $animControlBitmaps(blank,im)
    [edit_w pauseControl] configure -background [widget_color inactive bg] \
        -image $animControlBitmaps(blank,im)
    hideFrameDisplay
    m_set isAnimation 0
    # end of animation rundown

    m_set currentMediaFile $filename

    set newData [setupImgInfo $filename]
    upvar #0 $newData blockData

    wm title $w [concat Loading \"[file tail [m_get currentInfoFile]]\"]
    if {[m_get panelsUndocked]} {
        wm title [edit_w editWindow] [wm title [edit_w mainWindow]]
        wm title [edit_w imageWindow] [file tail [m_get currentMediaFile]]
        wm title [edit_w treeWindow] {Media Selector}
    }
    if {[array exists $browse_current]} {
        array unset $browse_current
    }
    set browse_current $newData
    load_edit_data $newData

    logDebug [file extension $filename] $filename


    switch -nocase -- [file extension $filename] {
        .jpg -
        .jpeg -
        .jfif -
        .png {
            set supportedFile 1
            m_set mediaType "Image"
            logDebug "File $filename is supported"
        }

        .gif {
            logDebug "File $filename is supported"
            set supportedFile 1
            m_set mediaType "Still Image"
            set gifStatus \
                [::AnimGIF::Analyze $filename [m_get_var animFrameList]]
            set frameCount [lindex $gifStatus 0]
            set frameWidth [lindex $gifStatus 1]
            set frameHeight [lindex $gifStatus 2]
            set gifGood [lindex $gifStatus 3]
            set playTime [lindex $gifStatus 4]

            if {$gifGood && $frameCount > 1} {
                m_set mediaType "Animation"
                m_set nextControl "Next >"
                m_set pauseControl "Play"

                m_set isAnimation 1
                m_set animFrameNumber -1
                m_set animFrameCount $frameCount
                m_set animFrameWidth $frameWidth
                m_set animFrameHeight $frameHeight
                m_set animCycleTime $playTime
                m_set mediaTime [format %0.2f [expr double($playTime) / 1000.0]]
                showFrameDisplay

                [edit_w nextControl] configure \
                    -background [widget_color animate bg] \
                    -image $animControlBitmaps(next,im)
                [edit_w pauseControl] configure \
                    -background [widget_color animate bg] \
                    -image $animControlBitmaps(play,im)
            }
        }
        .avi -
        .mp4 -
        .mpg -
        .mpeg -
        .webm -
        .flv -
        .wmv -
        .mov -
        .ogv {
            set supportedFile 1
            m_set mediaType "Movie"
            logDebug "File $filename is supported"
        }

        .ogg {
            set supportedFile 0
            m_set mediaType Video
            logDebug "File $filename is not yet supported"
        }
        default {
            logDebug "File $filename is not supported"
            m_set mediaType Unknown
            m_set mediaSize "N/A"
            set supportedFile 0
        }
    }

    if {$supportedFile && ([m_get mediaType] == "Movie")} {
        browse_busy 1
        set blockData(imageX) [::Vplyr::GetVideoInfo $filename VIDEO_WIDTH]
        set blockData(imageY) [::Vplyr::GetVideoInfo $filename VIDEO_HEIGHT]
        m_set mediaSize \
            [string cat $blockData(imageX) " x " $blockData(imageY)]

        catch {image delete $browse_image}
        set browse_image {}
        b_set mediaName [file tail $filename]
        update

        movie_show [edit_w imageLabel] "$filename" \
            $blockData(imageX) $blockData(imageY)
        browse_busy 0
    } elseif {$supportedFile} {
        # Put up a "I'm busy, please wait" notice over the old image
        browse_busy 1

        catch {image delete $browse_image}
        set browse_image {}

        b_set mediaName [file tail $filename]
        update
        set new_image [image create photo -file $filename]
        update

        set blockData(imageX) [image width $new_image]
        set blockData(imageY) [image height $new_image]
        m_set mediaSize \
            [string cat $blockData(imageX) " x " $blockData(imageY)]

        if {[b_get imageScaleMethod]} {
            set new_image [browse_fit_image_simple $new_image \
                                      [winfo width [edit_w imageLabel]] \
                                      [winfo height [edit_w imageLabel]]]
#                               [b_get mediaViewX] [b_get mediaViewY]]
        } else {
            set new_image [browse_fit_image $new_image \
                               [winfo width [edit_w imageLabel]] \
                               [winfo height [edit_w imageLabel]]]
#                               [b_get mediaViewX] [b_get mediaViewY]]
        }
        set browse_image $new_image

        [edit_w imageLabel] configure -image $new_image

        # Remove the "busy" message
        browse_busy 0
    } else {
        browse_busy 1 "Media\nNot\nSupported"
        catch {image delete $browse_image}
        set browse_image [image create photo noImage -width 64 -height 64]
        [edit_w imageLabel] configure -image $browse_image
    }
    if {[m_get infoFileDisposition]} {
        set disp "File"
    } else {
        set disp "New file"
    }
    update_info_file_status [edit_w infoFileName]
    # wm title $w [concat $disp \"[file tail [m_get currentInfoFile]]\"]

    update
}

# Perform the 'open' action for the 'browse' button
proc browse_open {w} {
    if {[info exists ::edit_paths(movieViewerFrame)]} {
        ::movie_end
    }

    set filename [browse_getMediaFile $w]

    if {$filename eq ""} {
        # User cancelled out of the open dialog; no file selected
        logDebug "No new file selected; don't do anything"
        return;
    }
    logDebug "User selected $filename"

    if {[file exists $filename]} {
        # synchronize the directory tree selection with the user's chosen
        # media file to be opened
        dirTree_syncWithSelection $filename
    }
    # Do common media file display
    browse_fileSelected $w $filename
}

proc update_info_file_status {win args} {
    set infoFile [m_get currentInfoFile]
    if {[file isfile $infoFile]} {
        m_set infoFileDisposition 1
        set disp "File"
    } else {
        m_set infoFileDisposition 0
        set disp "New file"
    }
    wm title [edit_w mainWindow] \
        [concat $disp \"[file tail [m_get currentInfoFile]]\"]
    if {[m_get panelsUndocked]} {
        wm title [edit_w editWindow] [wm title [edit_w mainWindow]]
        wm title [edit_w imageWindow] [file tail [m_get currentMediaFile]]
        wm title [edit_w treeWindow] {Media Selector}
    }
}

proc update_info_path_status {win args} {
    set infoPath [b_get altInfoDir]
    if {[file isdirectory $infoPath]} {
        $win configure -background [widget_color normal bg]
    } else {
        $win configure -background [widget_color invalid bg]
    }
}

# Show busy label
proc browse_busy {show args} {
    global busy_font_list

    if {$show} {
        # Put up a "I'm busy, please wait" notice over the old image

        logDebug "Going busy for a while"
        set tmp1 [m_get busyFontIndex]
        if {$tmp1 < 0} {
            expr srand([clock seconds])
        }
        set idx $tmp1
        set numF [llength $busy_font_list]

        while {$idx == $tmp1} {
            set idx [expr round(rand() * $numF) % $numF]
        }
        set busyFont [lindex $busy_font_list $idx]
        m_set busyFontIndex $idx

        if {[llength $args]} {
            set mesg [lindex $args 0]
        } else {
            set mesg "Please\nbe\npatient..."
        }

        [edit_w busyLabel] configure -font $busyFont -text $mesg

        grid [edit_w busyLabel] -row [b_get imgDisplayRow] \
            -sticky news -column [b_get imgDisplayCol]

        b_set busyMapped 1
        update
    } else {
        # Remove the "busy" message
        grid forget [edit_w busyLabel]
        b_set busyMapped 1
        logDebug "Done being busy"
    }
}

# Action command proc for the 'close' button on the browser
proc browse_close {w} {
    if {$w eq "."} {
        destroy .
    } else {
        global browse_image ol_icn ul_icn
        if {$browse_image != {}} {
            image delete $browse_image
            logWarning "Warning: browse_image was not set"
        }
        set browse_image {}
        if {$ol_icn != {}} {
            image delete $ol_icn
            set ol_icn {}
        }
        if {$ul_icn != {}} {
            image delete $ul_icn
            set ul_icn {}
        }
        destroy $w
        logDebug "User closed main window $w"
        if {$w eq "."} {
            destroy .
        }
    }
    exit 0
}

# Service routine that does much of the work for saving the
# editor data in response to the "save" button
proc do_save_info {{filename ""}} {
    global browse_current
    global $browse_current
    upvar #0 $browse_current blockInfo
    array set newStyle {}
    array set newImg {}
    set newText {}

    edit_getStyle [edit_w blockStyle] newStyle
    edit_getStyle [edit_w imgStyle] newImg
    edit_getText [edit_w blockText] newText
    edit_update_info $browse_current newText newStyle newImg
    if {[writeInfoFile blockInfo $filename]} {
        set blockInfo(modified) 0
        m_set infoFileDisposition 1

        # copy updated info to backup
        foreach item [array names ::MetaEdit::Backup] {
            o_set $item [m_get $item]
            set item_w [edit_w $item]
            if {[lindex [bindtags $item_w] 1] eq "Checkbutton"} {
                $item_w configure -selectcolor ""
            } else {
                catch {$item_w configure -background [widget_color normal bg]}
            }
        }
        # media options in sync for now
        m_set mediaOptionsModified 0

        # reset the modified and undo status of the text widgets
        foreach widget {blockText blockStyle imgStyle} {
            set te [edit_w $widget]
            $te edit modified false
            $te edit reset
        }

        # return to the title without "modified"
        wm title [edit_w mainWindow] \
            [concat File [file tail [m_get currentInfoFile]]]

        if {[m_get panelsUndocked]} {
            wm title [edit_w editWindow] [wm title [edit_w mainWindow]]
            wm title [edit_w imageWindow] [file tail [m_get currentMediaFile]]
            wm title [edit_w treeWindow] {Media Selector}
        }
    }
}

# Save button command proc
proc browse_save {w} {
    global browse_current
    upvar #0 $browse_current blockData
    if {[array exists blockData] && \
            [info exists blockData(modified)] && \
            $blockData(modified)} {
        do_save_info
    }
}

# Save As button command proc
proc browse_save_as {w} {
    global browse_current
    upvar #0 $browse_current blockData
    if {[array exists blockData]} {
        set infoName [browse_infoFileName $blockData(imgFile)]
        set filename [tk_getSaveFile -initialdir [file dirname $infoName] \
                          -initialfile [file tail $infoName] \
                          -parent [edit_w mainWindow] \
                          -title "Save As..."]
        if {$filename ne ""} {
            do_save_info $filename
        }
    }
}

# compare two lists
proc check_kwd_list {list1 list2} {
    if {[llength $list1] == [llength $list2]} {
        foreach left $list1 right $list2 {
            if {$left ne $right} {
                return 1
            }
        }
        return 0
    }
    return 1
}

# Try to check the 'modified' status of the editor
proc check_modified_data {args} {
    global browse_current
    global $browse_current
    upvar #0 $browse_current blockData

    set btext  [[edit_w blockText] edit modified]
    set bstyle [[edit_w blockStyle] edit modified]
    set istyle [[edit_w imgStyle] edit modified]
    set atext  [[edit_w appText] edit modified]

    set btitle [string equal $blockData(infoTitle) [m_get blockTitle]]
    set bclass [string equal $blockData(blockClass) [m_get blockClass]]
    set keywd  [check_kwd_list $blockData(keywords) [m_get keywordList]]

    if {$btext || $bstyle || $istyle || $atext || \
            !$btitle || !$bclass || $keywd || [m_get mediaOptionsModified]} {
        set blockData(modified) 1
        [edit_w saveButton] configure -state normal
        [edit_w fileMenu] entryconfigure "Save Info File" -state normal
        return 1
    } else {
        [edit_w saveButton] configure -state disabled
        [edit_w fileMenu] entryconfigure "Save Info File" -state disabled
        set blockData(modified) 0
    }
    return 0
}

# Track what has changed in the media options
proc check_edit_field {item win args} {
    if {![string equal [o_get $item] [m_get $item]]} {
        m_set mediaOptionsModified 1
        if {[catch {$win configure -selectcolor [widget_color changed bg]}]} {
            catch {$win configure -background [widget_color changed bg]}
        }
        update_modified_status $win
    }
}

# Try to manage the 'modified' status of the editor
proc update_modified_status {win args} {
    global browse_current
    upvar #0 $browse_current blockData

    if {[m_get infoFileDisposition]} {
        set disp "File"
    } else {
        set disp "New file"
    }

    set w [edit_w mainWindow]
    if {$blockData(imgFile) != {}} {
        set banner "$disp \"[file tail [m_get currentInfoFile]]\""
    } else {
        set banner [list $win $args]
    }

    if {[check_modified_data]} {
        set banner [string cat $banner " -- Modified"]
    }
    wm title $w $banner
    if {[m_get panelsUndocked]} {
        wm title [edit_w editWindow] [wm title [edit_w mainWindow]]
    }
}

# make a text widget and an associated scrollbar
proc create_scrolltext {tpath sypath width height} {
    set t [text $tpath -setgrid true -wrap word -width $width \
               -height $height -undo true -state disabled \
               -yscrollcommand "$sypath set" \
               -font [b_get textEditFont]]
    set sy [scrollbar $sypath -orient vert -command "$tpath yview"]
    return [list $t $sy]
}
    
# set up the text tags for the block text edit widget
proc setup_text_tags {btTxt} {
    $btTxt tag configure raw -font [b_get textFixedFont] -background yellow \
        -background [widget_color raw bg] \
        -foreground [widget_color raw fg] \
        -spacing3 3

    # Special tag for unknown line types
    $btTxt tag configure UnKnOwN -font [b_get textFixedFont] \
        -background [widget_color UnKnOwN bg] \
        -foreground [widget_color UnKnOwN fg] \
        -spacing3 3

    $btTxt tag configure alt1 \
        -background [widget_color alt1 bg] \
        -foreground [widget_color alt1 fg] \
        -spacing3 3
    $btTxt tag configure alt2 \
        -background [widget_color alt2 bg] \
        -foreground [widget_color alt2 fg] \
        -spacing3 3

    $btTxt tag configure alt3 \
        -background [widget_color alt3 bg] \
        -foreground [widget_color alt3 fg] \
        -spacing3 3

    $btTxt tag configure alt4 \
        -background [widget_color alt4 bg] \
        -foreground [widget_color alt4 fg] \
        -spacing3 3

    $btTxt tag configure ole -font [b_get textEditFont] \
        -tabs ".5c center 1c left" \
        -lmargin1 0 -lmargin2 1c \
        -spacing3 3

    $btTxt tag configure ule -font [b_get textEditFont] \
        -tabs ".5c center 1c left" \
        -lmargin1 0 -lmargin2 1c \
        -spacing3 3
}

# Change/Apply a tag to an entire line in a 'text' control
proc edit_apply_tag {te newTag action args} {
    logDebug "apply_tag $te $newTag $action $args"
    set newLab ${newTag}L
    set priorTag [m_get activeTag]
    set priorLab ${priorTag}L
    if {[llength $args]} {
        set refocus [lindex $args 0]
    } else {
        set refocus 0
    }

    switch -- $action {
        toggle {
            if {$newTag eq $priorTag} {
                [edit_w $newLab] configure \
                    -background [widget_color inactive bg] \
                    -foreground [widget_color inactive fg]
                set newTag normal
                set newLab normalL
                m_set tagMode 0
            } else {
                [edit_w $priorLab] configure \
                    -background [widget_color inactive bg] \
                    -foreground [widget_color inactive fg]
                m_set tagMode 1
            }
            [edit_w $newLab] configure \
                -background [widget_color active bg] \
                -foreground [widget_color active fg]
            m_set activeTag $newTag
        }
        latched {
            if {$newTag ne $priorTag} {
                [edit_w $priorLab] configure \
                    -background [widget_color inactive bg] \
                    -foreground [widget_color inactive fg]
            }
            [edit_w $newLab] configure \
                -background [widget_color active bg] \
                -foreground [widget_color active fg]
            m_set activeTag $newTag
            if {$newTag ne "normal"} {
                m_set tagMode 1
            } else {
                m_set tagMode 0
            }
        }
        oneshot {
        }

        default {
        }
    }

    if {[winfo exists $te]} {
        set lineDump [$te dump -tag "insert linestart" "insert lineend"]
        foreach {key value index} $lineDump {
            regexp {^([0-9]+)\.([0-9]+)$} $index dummy lnum cpos
            switch -- $key {
                tagon {
                    if {$cpos eq "0"} {
                        $te tag remove $value $lnum.0 $lnum.end
                        logDebug "Removed tag $value from $index"
                        if {$value eq "ole" || $value eq "ule"} {
                            $te delete $index $lnum.3
                        }
                    }
                }
                default {
                }
            } ; # end of switch
        } ; # end of foreach
        if {$newTag ne "normal"} {
            $te mark set lineBegin "insert linestart"
            $te mark set lineEnd "insert lineend"
            if {$newTag eq "ole"} {
                global ol_icn
                $te insert lineBegin "\t"
                $te image create lineBegin -image $ol_icn
                $te insert lineBegin "\t"
            }
            if {$newTag eq "ule"} {
                global ul_icn
                $te insert lineBegin "\t"
                $te image create lineBegin -image $ul_icn
                $te insert lineBegin "\t"
            }
            $te tag add $newTag "insert linestart" "insert lineend"
            $te mark unset lineBegin
            $te mark unset lineEnd
            logDebug "Applied tag $newTag"
        }
    }

    $te mark set current insert

    return -code continue
}

# Event command proc bound to key presses in the 'blockText' 'text'
# widget
proc edit_fix_tag {te k a args} {
    if {[winfo exists $te] && $a ne ""} {
        set lineTags [$te tag names {insert linestart}]
        if {[llength $lineTags]} {
            set theTag [lindex $lineTags 0]
            $te tag add $theTag {insert linestart} {insert lineend}
        }
    }
    return -code continue
}

# Deal with <return> in the block text editor
proc edit_newline {bte args} {
    logDebug "<return> in $bte with tagMode [m_get tagMode]"

    if {[m_get tagMode]} {
        set newLineLen [$bte count -chars insert {insert lineend}]
        if {$newLineLen == 0} {
            set priorTag [$bte tag names {insert linestart}]
            logDebug "Prior line tags: $priorTag"
            $bte insert insert "\n"
            if {[llength $priorTag]} {
                set priorTag [lindex $priorTag 0]
                if {$priorTag eq "ole"} {
                    global ol_icn
                    $bte insert insert \t
                    $bte image create insert -image $ol_icn
                    $bte insert insert "\t"
                    logDebug "Ordered List"
                } elseif {$priorTag eq "ule"} {
                    global ul_icn
                    $bte insert {insert linestart} "\t"
                    $bte image create {insert linestart} -image $ul_icn
                    $bte insert {insert linestart} "\t"
                    logDebug "Unordered List"
                }
                $bte tag add $priorTag {insert linestart} {insert lineend}
                logDebug "New line set to tag $priorTag"
                return -code break
            } else {
                logDebug "Prior line has no tags \"($priorTag)\""
            }
        } else {
            logDebug "The new line is not empty ($newLineLen)"
        }
    }
    return -code continue
}

# command proc for the keyword copy-from-selection button
proc kw_copy_selection {fromWin toWin args} {
    set selList [$fromWin curselection]
    foreach item $selList {
        set text [$fromWin get $item]
        $toWin insert end $text
        $fromWin selection clear $item
        update
    }
}

# command proc for the delete buttons on the keyword lists
proc kw_delete_selection {fromWin args} {

    # get the selection list from the widget
    set selList [$fromWin curselection]

    # clear the selections from the widget
    $fromWin selection clear 0 end

    # delete the items
    foreach item $selList {
        $fromWin delete $item
    }
}

# command proc to add a keyword from the entry widget to the
# current media keyword listbox
proc kw_add_new {entryWin toWin args} {
    set newText [string trim [m_get newKeyword]]
#    if {![$toWin exists $newText]} {
        $toWin insert end $newText
#    }
    m_set newKeyword ""
}

# Handle select all and clear selection events on the keyword lists
proc kw_list_select {listWin action args} {
    if {$action} {
        $listWin selection set 0 end
    } else {
        $listWin selection clear 0 end
    }
}

# load "built-in" keyword list from a file
proc kw_load_file {listW args} {
    upvar #0 [m_get_var keywordDB] keywordDB

    if {[llength $args] > 1} {
        set escape [lindex $args 0]
        set kwdFile [lindex $args 1]
        b_set autoLoadedKeywords 1
    } else {
        set kwdFile [tk_getOpenFile -initialdir [b_get cwd] \
                         -filetypes {
                             {{Supported Files} {.kwd .txt .lst}}
                             {{Keyword File}   {.kwd}}
                             {{Text File}      {.txt}}
                             {{List File}      {.lst}}
                             {{All Files}      {*}}
                         } \
                         -parent [edit_w mainWindow] \
                         -title "Read Keyword List From..."]
    }

    if {$kwdFile eq ""} {
        return
    }

    if {![catch {set fd [open $kwdFile r]} err]} {
        if {[file extension $kwdFile] eq ".kwd"} {
            gets $fd keywordDB
        } else {
            while {[gets $fd line] >= 0} {
                foreach word [split $line ","] {
                    if {[lsearch -nocase $keywordDB $word] < 0} {
                        $listW insert end [string trim $word]
                        update
                    }
                }
            }
        }
        close $fd
        set keywordDB [lsort -nocase -unique $keywordDB]
    } else {
        global errorText
        if {![info exists errorText]} {
            set errorText "<none>"
        }

        tk_messageBox -default ok -type ok -detail $errorText \
            -icon error -message $err -title "Keyword file load failed" \
            -parent .
    }
}

proc kw_save_file {listW args} {
    set saveFile [tk_getSaveFile -initialdir [b_get cwd] \
                      -defaultextension ".kwd" \
                      -typevariable ::MetaEdit::kwdSaveType \
                      -filetypes {
                          {{Keyword File}   {.kwd}}
                          {{Text File}      {.txt}}
                          {{List File}      {.lst}}
                          {{All Files}      {*}}} \
                      -parent [edit_w mainWindow] \
                      -title "Save keyword list as..."]

    if {$saveFile eq ""} {
        return
    }

    set ofd [open $saveFile w]
    set ext [file extension $saveFile]

    if {$ext eq ".kwd"} {
        puts $ofd [m_get keywordDB]
    } elseif {$ext eq ".lst"} {
        foreach word [m_get keywordDB] {
            puts $ofd $word
        }
    } else {
        set line ""
        set sep  ""
        set osep ", "
        foreach word [m_get keywordDB] {
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

# Apply tooltips to various widgets in the edit box
proc setup_tooltips {args} {
    global editTTip

    foreach widget [array names editTTip] {
        tooltip [edit_w $widget] $editTTip($widget)
    }
    view_tooltips
}

# Scrollbar management for the listbox widget
proc scroll_set {sbar geomCmd offset size} {
    if {$offset != 0.0 || $size != 1.0} {
        eval $geomCmd
    }
    $sbar set $offset $size
}

# Show the debug console (tkcon)
proc show_console {btn args} {
    global tcl_version
    # Magic tkcon stuff
    namespace eval ::tkcon {}

    if {${::MetaEdit::debugConsole} < 0} {
        $btn configure -foreground gray20 -text "Loading TkCon"
        update
        set ::tkcon::OPT(exec) ""
        # source [file join [file dirname [info nameofexecutable]] tkcon.tcl]
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

        set ::MetaEdit::debugConsole 0
        # enable output to the 'console'
        setLogMode 0
        setLogLevel 3
    }

    set menu [edit_w utilMenu]
       
    if {!${::MetaEdit::debugConsole}} {
        $btn configure -foreground gray20 -text "Hide TkCon"
        tkcon show
        set ::MetaEdit::debugConsole 1
        $menu entryconfigure "*Console" -label "Hide Debug Console"
    } else {
        $btn configure -foreground gray50 -text "Show TkCon"
        tkcon hide
        set ::MetaEdit::debugConsole 0
        $menu entryconfigure "*Console" -label "Show Debug Console"
    }
}

# Create the data edit frame and the widgets that live in it. This will
# be gridded to the main window frame by "browse_show_main". 'parent'
# is the frame that is the parent of the edit frame.
#
# +----------------------------------------------------+
# |                                                    |
# | Title ___________________________________________  |
# | Class ___________________________________________  |
# | Style                                              |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# | Img Style                                          |
# | _________________________________________________  |
# | _________________________________________________  |
# |                                                    |
# | Alt1 _______ Alt2 ______ Alt3 ______ Alt4 _______  |
# | Text                                               |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# | _________________________________________________  |
# |                                                    |
# +----------------------------------------------------+

proc makeDummy {frm} {
    set mtb1 [button $frm.dummy1 -text "col 1"]
    set mtb3 [button $frm.dummy3 -text "col 3"]
    set mtb5 [button $frm.dummy5 -text "col 5"]
    set mtb7 [button $frm.dummy7 -text "col 7"]
    set mtb9 [button $frm.dummy9 -text "col 9"]
    set mtb11 [button $frm.dummy11 -text "col 11"]
    set mtb13 [button $frm.dummy13 -text "col 13"]
    set mtb15 [button $frm.dummy15 -text "col 15"]

    grid $mtb1 -row 11 -column 1 -sticky news
    grid $mtb3 -row 11 -column 3 -sticky news
    grid $mtb5 -row 11 -column 5 -sticky news
    grid $mtb7 -row 11 -column 7 -sticky news
    grid $mtb9 -row 11 -column 9 -sticky news
    grid $mtb11 -row 11 -column 11 -sticky news
    grid $mtb13 -row 11 -column 13 -sticky news
    grid $mtb15 -row 11 -column 15 -sticky news
}

# Entry event handler for editor controls
# %W = win
proc enter_entry_action {win args} {
    $win selection range 0 end
    $win icursor end
    $win xview end
}

# Leave event handler for the editor controls
proc exit_entry_action {win args} {
    $win selection clear
}

# Return key action handler for the editor controls
proc return_entry_action {win args} {
    focus [edit_w mainWindow]
}

# keyboard handler for searching keywords
# %W = win
# %K = sym
# %A = key
proc keyword_letter_search {win sym key args} {
    if {$key ne "" && [string is wordchar $key]} {
        set wordListName [$win cget -listvariable]
        # global $wordListName
        upvar #0 $wordListName wordList
        set actIndex [$win index active]
        set endIndex [llength $wordList]
        incr actIndex
        set newIndex [lsearch -ascii -glob -start $actIndex $wordList "$key*"]
        if {$newIndex < 0} {
            set newIndex [lsearch -ascii -glob $wordList "$key*"]
        }
        if {$newIndex >= 0} {
            $win see $newIndex
            $win activate $newIndex
            $win selection clear 0 end
            $win selection set $newIndex $newIndex
        }
    }
}

# Create a frame that contains the metadata editor widgets
# as sketched out above.
proc browse_build_edit {parent} {
    global edit_paths
    global alt_class_assoc

    # create frame
    set frm [labelframe $parent.edit -width 300 -text {Image Metadata Editor}]

    set topFrm [frame $frm.topFrame]
    set edit_paths(editTopFrame) $topFrm
    set entryFont [b_get entryFont]

    # block title entry
    set ttlLab [label $topFrm.blkTitleL -text "Block Title"]
    set ttl [entry $topFrm.blkTitle -textvariable [m_get_var blockTitle] \
                 -font $entryFont -width 50]
    set edit_paths(blockTitleL) $ttlLab
    set edit_paths(blockTitle)  $ttl

    # block class entry
    set bcl [entry $topFrm.blkClass -textvariable [m_get_var blockClass] \
                 -font $entryFont -width 20]
    set bcL [label $topFrm.blkClassL -text "Block Class"]
    set edit_paths(blockClass)  $bcl
    set edit_paths(blockClassL) $bcL

    # place-holder...
    set mediaCaptionL [label $topFrm.mediaCapL -text "Caption:"]
    set mediaCaption [entry $topFrm.medaCap -width 80 \
                          -font $entryFont \
			  -textvariable [m_get_var mediaCaption]]

    set edit_paths(mediaCaption) $mediaCaption

    grid $ttlLab -row 1 -column 1 -sticky nes
    grid $ttl -row 1 -column 2 -sticky news
    grid $bcL -row 1 -column 4 -sticky nse
    grid $bcl -row 1 -column 5 -sticky nswe
    grid rowconfigure $topFrm 2 -minsize 6
    grid $mediaCaptionL -row 3 -column 1 -sticky nse
    grid $mediaCaption -row 3 -column 2 -columnspan 4 -sticky nswe
    grid columnconfigure $topFrm 1 -weight 0
    grid columnconfigure $topFrm 4 -weight 0

    set textWidth [b_get textEditWidth]

    # Create a notebook frame for the upper section
    set nbX [ttk::notebook $frm.noteb]
    ttk::notebook::enableTraversal $nbX

    # Create a tab with the media information
    set mediaTab [ttk::frame $nbX.media]
    set edit_paths(mediaTab) $mediaTab

    set miFrame [ttk::labelframe $mediaTab.mediaInfoFrame \
                     -text "Media File Information"]
    set edit_paths(mediaInfoFrame) $miFrame

    set mediaNameL [label $miFrame.mediaNameL -text "File Name:"]
    set mediaName  [entry $miFrame.mediaName \
			-font $entryFont \
                        -takefocus 0 \
                        -state readonly \
                        -width 80 \
                        -justify left \
                        -textvariable [b_get_var mediaFile]]
    set edit_paths(mediaName) $mediaName

    set actSizeL [label $miFrame.actualSizeL -text "Dimensions:"]
    set actSize  [entry $miFrame.actualSize  \
		      -font $entryFont \
                      -takefocus 0 \
                      -state readonly \
                      -width 11 \
                      -textvariable [m_get_var mediaSize]]
    set edit_paths(mediaSize) $actSize

    set fileSizeL [label $miFrame.fileSizeL -text "File Size:"]
    set fileSize  [entry $miFrame.fileSize \
		       -font $entryFont \
                       -takefocus 0 \
                       -state readonly \
                       -width 8 \
                       -textvariable [m_get_var fileSize]]
    set edit_paths(fileSize) $fileSize

    set filler9L [label $miFrame.filler9L -text "Scaled:"]

    set filler11 [entry $miFrame.filler11 \
		      -font $entryFont \
                      -takefocus 0 \
                      -state readonly \
                      -width 5 \
                      -justify center \
                      -textvariable [m_get_var mediaScale]]

    set mediaTypeL [label $miFrame.mediaTypeL -text "Media Type:"]
    set mediaType [entry $miFrame.mediaType \
		       -font $entryFont \
                       -takefocus 0 \
                       -width 10 \
                       -state readonly \
                       -textvariable [m_get_var mediaType]]
    set edit_paths(mediaType) $mediaType

    set mediaTime [entry $miFrame.mediaPlayTime \
		       -font $entryFont \
                       -width 5 \
                       -takefocus 0 \
                       -state readonly \
                       -textvariable [m_get_var mediaTime]]
    set edit_paths(mediaTime) $mediaTime

    grid rowconfigure $miFrame 0 -minsize 5
    grid rowconfigure $miFrame 2 -minsize 5
    grid rowconfigure $miFrame 4 -minsize 5
    grid columnconfigure $miFrame 0 -minsize 5 -weight 0
    grid columnconfigure $miFrame 1 -weight 0
    grid columnconfigure $miFrame 2 -minsize 5 -weight 0
    grid columnconfigure $miFrame 4 -minsize 10 -weight 0
    grid columnconfigure $miFrame 5 -weight 0
    grid columnconfigure $miFrame 6 -minsize 5 -weight 0
    grid columnconfigure $miFrame 8 -minsize 5 -weight 0
    grid columnconfigure $miFrame 9 -weight 0
    grid columnconfigure $miFrame 10 -minsize 5 -weight 0
    grid columnconfigure $miFrame 12 -minsize 10 -weight 0
    grid columnconfigure $miFrame 13 -weight 0
    grid columnconfigure $miFrame 14 -minsize 5 -weight 0
    grid columnconfigure $miFrame 16 -minsize 5 -weight 0
    grid columnconfigure $miFrame 17 -weight 0
    grid columnconfigure $miFrame 18 -minsize 5 -weight 0

    grid $mediaNameL -row 1 -column 1 -sticky sen
    grid $mediaName  -row 1 -column 3 -sticky nwes -columnspan 15
    grid $actSizeL   -row 3 -column 1 -sticky sen
    grid $actSize    -row 3 -column 3 -sticky nws
    grid $fileSizeL  -row 3 -column 5 -sticky sen
    grid $fileSize   -row 3 -column 7 -sticky nws
    grid $filler9L   -row 3 -column 9 -sticky sen
    grid $filler11   -row 3 -column 11 -sticky news
    grid $mediaTypeL -row 3 -column 13 -sticky sen
    grid $mediaType  -row 3 -column 15 -sticky news
    grid $mediaTime  -row 3 -column 17 -sticky news

    set optFrame [ttk::labelframe $mediaTab.mediaOptFrame \
                      -text "Media Element Options"]
    set edit_paths(mediaOptions) $optFrame
#    makeDummy $optFrame
    set mediaAttrL [label $optFrame.attrL -text "Attributes:"]
    set mediaAttr  [entry $optFrame.attr \
                        -width 40 \
                        -textvariable [m_get_var mediaAttributes]]
    set edit_paths(mediaAttributes) $mediaAttr

    set mediaWidthL [label $optFrame.mediaWidthL -text "Width:"]
    set mediaWidth  [entry $optFrame.mediaWidth -width 8 \
                         -textvariable [m_get_var mediaWidth]]
    set edit_paths(mediaWidth) $mediaWidth

    set mediaHeightL [label $optFrame.mediaHeightL -text "Height:"]
    set mediaHeight  [entry $optFrame.mediaHeight -width 8 \
                         -textvariable [m_get_var mediaHeight]]
    set edit_paths(mediaHeight) $mediaHeight

    set mediaTitleL [label $optFrame.mediaTitle -text "Title Text:"]
    set mediaTitle  [entry $optFrame.title -width 40 \
                         -textvariable [m_get_var mediaTitle]]
    set edit_paths(mediaTitle) $mediaTitle

    set mediaAltL [label $optFrame.altTextL -text "Alt Text:"]
    set mediaAlt  [entry $optFrame.altText -width 32 \
                       -textvariable [m_get_var mediaAltText]]
    set edit_paths(mediaAltText) $mediaAlt

    set mediaLinkL [label $optFrame.mediaLinkL -text "Link URL:"]
    set mediaLink  [entry $optFrame.mediaLink -width 80 \
                         -textvariable [m_get_var mediaLink]]
    set edit_paths(mediaLink) $mediaLink

    set forceFig [checkbutton $optFrame.forceFigure \
                      -text "Force Figure Element" \
                      -variable [m_get_var forceFigure]]
    set edit_paths(forceFigure) $forceFig

#    set tempFrame6 [frame $optFrame.tempFrame -background orange]
#    grid $tempFrame6 -row 11 -column 6 -sticky news

    grid $mediaAttrL -row 1 -column 1 -sticky nse
    grid $mediaAttr  -row 1 -column 3 -sticky news -columnspan 5
    grid $mediaWidthL -row 1 -column 9 -sticky nse
    grid $mediaWidth  -row 1 -column 11 -sticky news
    grid $mediaHeightL -row 1 -column 13 -sticky nse
    grid $mediaHeight -row 1 -column 15 -sticky news
    grid $mediaTitleL -row 3 -column 1 -sticky nse
    grid $mediaTitle  -row 3 -column 3 -sticky news -columnspan 5
    grid $mediaAltL -row 3 -column 9 -sticky nse
    grid $mediaAlt  -row 3 -column 11 -sticky news -columnspan 5
    grid $mediaLinkL -row 5 -column 1 -sticky sne
    grid $mediaLink -row 5 -column 3 -sticky wsne -columnspan 13
    grid $forceFig -row 7 -column 13 -columnspan 5 -sticky swn

    grid columnconfigure $optFrame 0 -minsize 5 -weight 0
    grid columnconfigure $optFrame 1 -weight 0
    grid columnconfigure $optFrame 2 -minsize 5 -weight 0
    grid columnconfigure $optFrame 4 -minsize 10 -weight 0
    grid columnconfigure $optFrame 5 -weight 0
    grid columnconfigure $optFrame 6 -minsize 5 -weight 0
    grid columnconfigure $optFrame 8 -minsize 10 -weight 0
    grid columnconfigure $optFrame 9 -weight 0
    grid columnconfigure $optFrame 10 -minsize 5 -weight 0
    grid columnconfigure $optFrame 12 -minsize 10 -weight 0
    grid columnconfigure $optFrame 13 -weight 0
    grid columnconfigure $optFrame 14 -minsize 5 -weight 0
    grid columnconfigure $optFrame 16 -minsize 5 -weight 0
    grid rowconfigure $optFrame 0 -minsize 5
    grid rowconfigure $optFrame 2 -minsize 5
    grid rowconfigure $optFrame 4 -minsize 5
    grid rowconfigure $optFrame 6 -minsize 5

    grid $miFrame -row 1 -column 1 -sticky news
    grid rowconfigure $mediaTab 2 -minsize 2
    grid $optFrame -row 3 -column 1 -sticky news

    # Create a tab with the block and image styles
    set styleTab [ttk::frame $nbX.styles]
    
    set bsfrm [ttk::labelframe $styleTab.bstyleF -text {HTML Division Style}]
    set tmp [create_scrolltext $bsfrm.txt $bsfrm.scrollY \
                 $textWidth [b_get blockStyleLines]]
    set bsTxt [lindex $tmp 0]
    set bsScl [lindex $tmp 1]
    pack $bsTxt -side left -fill both
    pack $bsScl -side right -fill y

    set isfrm [ttk::labelframe $styleTab.istyleF \
                   -text {Media Element Style}]
    set tmp [create_scrolltext $isfrm.txt $isfrm.scrollY \
                 $textWidth [b_get imageStyleLines]]
    set isTxt [lindex $tmp 0]
    set isScl [lindex $tmp 1]
    pack $isTxt -side left -fill both
    pack $isScl -side right -fill y

    grid rowconfigure $styleTab 0 -minsize 6
    grid $bsfrm -row 1 -column 1 -sticky news
    grid rowconfigure $styleTab 2 -minsize 6
    grid $isfrm -row 3 -column 1 -sticky news

    # Create a tab for the editor preference settings
    set prefsTab [ttk::frame $nbX.prefsTab]
    set altClassFrm [ttk::labelframe $prefsTab.altClassEdit \
                         -text "Alternate HTML Paragraph Classes"]

    grid columnconfigure $altClassFrm 0 -minsize 4 -weight 0
    grid columnconfigure $altClassFrm 2 -minsize 4 -weight 0
    grid columnconfigure $altClassFrm 4 -minsize 4 -weight 0
    grid rowconfigure $altClassFrm 0 -minsize 4
    grid rowconfigure $altClassFrm 8 -minsize 4

    for {set tmp 1} {$tmp <= 4} {incr tmp} {
        set ctrlName "alt${tmp}"
        set ctrlLab [ttk::label "${altClassFrm}.${ctrlName}L" \
                         -text "HTML Class for ALT+${tmp}"]
        grid $ctrlLab -row [expr {$tmp * 2 - 1}] -column 1 -sticky news
        set ctrl [entry ${altClassFrm}.${ctrlName} \
                      -textvariable alt_class_assoc($ctrlName) \
                      -width 20]
        grid $ctrl -row [expr {$tmp * 2 - 1}] -column 3 -sticky news
        set edit_paths(${ctrlName}EditLabel) $ctrlLab
        set edit_paths(${ctrlName}Edit) $ctrl
    }
    grid $altClassFrm -row 1 -column 1 -sticky nw -columnspan 3 -rowspan 4

    grid columnconfigure $prefsTab 0 -minsize 4 -weight 0
    grid columnconfigure $prefsTab 2 -minsize 4 -weight 0
    grid columnconfigure $prefsTab 4 -minsize 4 -weight 0
    grid columnconfigure $prefsTab 6 -minsize 4 -weight 0
    grid columnconfigure $prefsTab 8 -minsize 4 -weight 0

    # dummy button, just to get the geometry right.
    set dmyButton [ttk::button $prefsTab.dummy -text "Nothing"]
    grid $dmyButton -row 4 -column 7 -sticky news
    set edit_paths(prefsTabDummyButton) $dmyButton
    set edit_paths(prefsTab) $prefsTab
    set edit_paths(altClassEditFrame) $altClassFrm


    # Create a tab with the other application text data editor in it
    set appTextTab [ttk::frame $nbX.appText]

    set atfrm [ttk::labelframe $appTextTab.appTextF -text {Application Data}]
    set tmp [create_scrolltext $atfrm.txt $atfrm.scrollY \
                 $textWidth [b_get appTextEditLines]]
    set atTxt [lindex $tmp 0]
    set atScl [lindex $tmp 1]
    pack $atTxt -side left -fill both
    pack $atScl -side right -fill y
    grid $atfrm -row 1 -column 1 -sticky news

    # Create a tab with the keyword editor in it
    set keywordTab [ttk::frame $nbX.keywordTab]

    set kwfrm [ttk::labelframe $keywordTab.keywordF -text {Keywords}]
    set kwLst [listbox $kwfrm.kwList -height [b_get kwdListLines] \
                   -listvariable [m_get_var keywordList] \
                   -exportselection 0 \
                   -selectmode extended -width [b_get kwdListWidth] \
                   -xscrollcommand [list scroll_set $kwfrm.scrollX \
                                        [list grid $kwfrm.scrollX -row 6 \
                                             -column 5 -sticky we]] \
                   -yscrollcommand [list scroll_set $kwfrm.scrollY \
                                        [list grid $kwfrm.scrollY -row 1 \
                                             -column 6 -sticky ns -rowspan 5]]]
    set kwSclX [scrollbar $kwfrm.scrollX -orient horizontal \
                    -command [list $kwLst xview]]
    set kwSclY [scrollbar $kwfrm.scrollY -orient vertical \
                    -command [list $kwLst yview]]

    m_set keywordDB $::MetaEdit::builtinKeywords

    set kpLst [listbox $kwfrm.kselList -height [b_get kwdListLines] \
                   -listvariable [m_get_var keywordDB] \
                   -selectmode extended -width [b_get kwdListWidth] \
                   -exportselection 0 \
                   -xscrollcommand [list scroll_set $kwfrm.pscrollX \
                                        [list grid $kwfrm.pscrollX -row 6 \
                                             -column 0 -sticky we]] \
                   -yscrollcommand [list scroll_set $kwfrm.pscrollY \
                                        [list grid $kwfrm.pscrollY -row 1 \
                                             -column 1 -sticky ns -rowspan 5]]]
    set kpSclX [scrollbar $kwfrm.pscrollX -orient horizontal \
                    -command [list $kpLst xview]]
    set kpSclY [scrollbar $kwfrm.pscrollY -orient vertical \
                    -command [list $kpLst yview]]


    set cpyBut [ttk::button $kwfrm.copyRight -image rightArrow \
                    -width 8 \
                    -command [list kw_copy_selection $kpLst $kwLst]]
    set cpyLft [ttk::button $kwfrm.copyLeft -image leftArrow \
                    -width 8 \
                    -command [list kw_copy_selection $kwLst $kpLst]]
    set delBut [ttk::button $kwfrm.delSel -image deleteEntry \
                    -command [list kw_delete_selection $kwLst]]
    set delLft [ttk::button $kwfrm.delKeep -image deleteEntry \
                    -command [list kw_delete_selection $kpLst]]
    set newWord [entry $kwfrm.kwEntry \
                     -textvariable [m_get_var newKeyword] \
                     -width [b_get kwdListWidth]]
    set addBut [ttk::button $kwfrm.addNew -image leftArrow \
                    -width 8 \
                    -command [list kw_add_new $newWord $kwLst]]
#    set loadBut [ttk::button $kwfrm.loadList -text "Load" \
#                     -command [list kw_load_file $kpLst]]
#    set saveBut [ttk::button $kwfrm.saveList -text "Save" \
#                     -command [list kw_save_file $kpLst]]

#    grid $kpLst -row 0 -column 0 -sticky news -rowspan 6
#    grid $kwLst -row 0 -column 5 -sticky news -rowspan 6
#    set kpLab [label $kwfrm.pL -text "Known Keywords"]
#    set kwLab [label $kwfrm.kL -text "File Keywords"]

    set kpLab [ttk::menubutton $kwfrm.pL -text "Built-In" -direction above]
    set kpMenu [menu $kpLab.selectMenu -tearoff 0]
    $kpMenu add command -label "Select All" \
        -command [list kw_list_select $kpLst 1]
    $kpMenu add command -label "Clear Selection" \
        -command [list kw_list_select $kpLst 0]
    $kpMenu add separator
    $kpMenu add command -label "Load from File..." \
        -command [list kw_load_file $kpLst]
    $kpMenu add command -label "Save to File..." \
        -command [list kw_save_file $kpLst]
    $kpLab configure -menu $kpMenu

    set kwLab [ttk::menubutton $kwfrm.kL -text "Current" -direction above]
    set kwMenu [menu $kwLab.selectMenu -tearoff 0]
    $kwMenu add command -label "Select All" \
        -command [list kw_list_select $kwLst 1]
    $kwMenu add command -label "Clear Selection" \
        -command [list kw_list_select $kwLst 0]
    $kwLab configure -menu $kwMenu

    grid $kpLab -row 0 -column 0 -sticky sew
    grid $kpLst -row 1 -column 0 -sticky news -rowspan 5
    grid $kpSclY -row 1 -column 1 -sticky news -rowspan 5
    grid $kwLab -row 0 -column 5 -sticky sew
    grid $kwLst -row 1 -column 5 -sticky news -rowspan 5
    grid $kwSclY -row 1 -column 6 -sticky news -rowspan 5
    grid $cpyLft -row 1 -column 3 -sticky ew
    grid $cpyBut -row 2 -column 3 -sticky ew
    grid $delLft -row 5 -column 3 -sticky w
    grid $delBut -row 5 -column 8 -sticky w
    grid $addBut  -row 1 -column 8 -sticky ew
    grid $newWord -row 1 -column 10 -sticky ew
#    grid $loadBut -row 4 -column 10 -sticky ew
#    grid $saveBut -row 5 -column 10 -sticky ew
#    grid rowconfigure $kwfrm 0 -weight 1
    grid columnconfigure $kwfrm 0 -weight 2
    grid columnconfigure $kwfrm 1 -minsize 17
    grid columnconfigure $kwfrm 2 -minsize 10
    grid columnconfigure $kwfrm 3 -weight 1 -minsize 60
    grid columnconfigure $kwfrm 4 -minsize 10
    grid columnconfigure $kwfrm 5 -weight 2
    grid columnconfigure $kwfrm 6 -minsize 17
    grid columnconfigure $kwfrm 7 -minsize 10
    grid columnconfigure $kwfrm 8 -weight 1 -minsize 60
    grid columnconfigure $kwfrm 9 -minsize 10
    grid columnconfigure $kwfrm 10 -weight 2
    grid columnconfigure $kwfrm 11 -minsize 10
    grid $kwfrm -row 1 -column 1 -sticky news

    # put the tabs into the notebook in the order we want them to appear
    $nbX add $mediaTab -text "Media" -underline 0
    $nbX add $keywordTab -text "Keywords" -underline 0
    $nbX add $styleTab -text "CSS" -underline 0
    $nbX add $appTextTab -text "App Data" -underline 0
    $nbX add $prefsTab -text "Preferences" -underline 0 -sticky e

    # Lower part of the display (ledgend and such)
    set acFrm [labelframe $frm.altClassF -text "ALT+key Combinations"]
    set edit_paths(altKeyHelpFrame) $acFrm
    set pos 0

    set lblFont [makeSimilarFont TkTextFont lblFont -family courier]
    foreach {lbl title wid chord} {
        normal Normal   10  "ALT+n"
        ole    OL       10  "ALT+o"
        ule    UL       10  "ALT+u"
        raw    Raw      10  "ALT+r"
        alt1   Alt1     10  "ALT+1"
        alt2   Alt2     10  "ALT+2"
        alt3   Alt3     10  "ALT+3"
        alt4   Alt4     10  "ALT+4"
    } {
        set alt_class_assoc($lbl) $title
        set ent [entry $acFrm.${lbl} -width $wid -relief raised \
		     -font $lblFont \
                     -takefocus 0 \
                     -justify center -state disabled \
                     -textvariable alt_class_assoc($lbl)]
        set edit_paths($lbl) $ent
        set lab [label "$acFrm.${lbl}L" -text $chord -justify center \
                     -font $lblFont -relief sunken]
        set edit_paths(${lbl}L) $lab

        $ent configure \
            -background [widget_color $lbl bg] \
            -readonlybackground [widget_color $lbl bg] \
            -disabledbackground [widget_color $lbl bg] \
            -foreground [widget_color $lbl fg] \
            -disabledforeground [widget_color $lbl fg]

        grid $lab -row 0 -column [expr {$pos * 2 + 1}] -sticky news
        grid $ent -row 1 -column [expr {$pos * 2 + 1}] -sticky news
        grid columnconfig $acFrm [expr {$pos * 2}] -minsize 5 -weight 0
        incr pos
    }
    grid columnconfig $acFrm 8 -minsize 20
    set pos [expr {$pos * 2 + 2}]
    grid columnconfig $acFrm $pos -minsize 8 -weight 0
    incr pos

    set btfrm [labelframe $frm.bTextF -text {Block Content Text}]
    set tmp [create_scrolltext $btfrm.txt $btfrm.scrollY \
                 $textWidth [b_get blockTextLines]]
    set btTxt [lindex $tmp 0]
    set btScl [lindex $tmp 1]
    $btTxt configure -blockcursor 1 -insertunfocussed hollow
    grid $btTxt -row 0 -column 0 -sticky news
    grid $btScl -row 0 -column 1 -sticky news

    # Main editing frame
    grid rowconfigure $frm 0 -minsize 6
    grid $topFrm -row 1 -column 1 -columnspan 3 -rowspan 3 -sticky news
    grid rowconfigure $frm 2 -minsize 6
    grid rowconfigure $frm 4 -minsize 8

    grid $nbX -row 5 -column 1 -columnspan 2 -sticky news -rowspan 3

    grid rowconfigure $frm 8 -minsize 12
    grid $acFrm -row 9 -column 1 -columnspan 2 -sticky news
    grid rowconfigure $frm 10 -minsize 12
    grid $btfrm -row 11 -column 1 -columnspan 2 -sticky news
    grid rowconfigure $frm 12 -minsize 6

    grid columnconfigure $frm 0 -minsize 5 -weight 0
    grid columnconfigure $frm 1 -weight 0
    grid columnconfigure $frm 2 -weight 1
    grid columnconfigure $frm 3 -minsize 5 -weight 0


    set edit_paths(notebook)    $nbX
    set edit_paths(styleTab)    $styleTab
    set edit_paths(keywordTab)  $keywordTab
    set edit_paths(appTextTab)  $appTextTab
    set edit_paths(blockStyle)  $bsTxt
    set edit_paths(blockStyleY) $bsScl
    set edit_paths(imgStyle)    $isTxt
    set edit_paths(imgStyleY)   $isScl
    set edit_paths(blockText)   $btTxt
    set edit_paths(blockTextY)  $btScl
    set edit_paths(appText)     $atTxt
    set edit_paths(appTextY)    $atScl
    set edit_paths(keywordList) $kwLst
    set edit_paths(keywordLY)   $kwSclY
    set edit_paths(keywordLX)   $kwSclX
    set edit_paths(imgStyleFrm) $isfrm
    set edit_paths(txtStyleFrm) $bsfrm
    set edit_paths(appTextFrm)  $atfrm
    set edit_paths(kwFrm)       $kwfrm
    set edit_paths(addNewKeyword) $addBut
    set edit_paths(copyKeyword) $cpyBut
    set edit_paths(keepKeyword) $cpyLft
    set edit_paths(unkeepKeyword) $delLft
    set edit_paths(deleteKeyword) $delBut
    set edit_paths(knownKeywordList) $kpLst
    set edit_paths(newKeywordEntry) $newWord
    set edit_paths(editFrame) $frm

    return $frm
}

proc hideFrameDisplay {args} {
    place forget [edit_w animFrameDisplay]
}

proc showFrameDisplay {args} {
    set frameDisp [edit_w animFrameDisplay]
    set frameCount [m_get animFrameCount]
    set currFrame  [expr [m_get animFrameNumber] + 1]
    if {$currFrame == 0} {
        set currFrame 1
    }
    $frameDisp configure -text "$currFrame/$frameCount"
    place $frameDisp -relx 0.85 -rely 0.0
}

# Handle button presses on the "next" and "pause" image labels
proc animation_control {win args} {
    global animControlBitmaps

    set frameDisp [edit_w animFrameDisplay]

    if {[m_get isAnimation]} {
        if {$win eq [edit_w pauseControl]} {
            if {[m_get animIsRunning]} {
                m_set animIsRunning 0
                m_set pauseControl Resume
                [edit_w pauseControl] configure \
                    -background [widget_color animate bg] \
                    -image $animControlBitmaps(resume,im)
                [edit_w nextControl] configure \
                    -image $animControlBitmaps(next,im) \
                    -background [widget_color animate bg]
                after 600 showFrameDisplay
                logDebug "Pause"
                update
            } else {
                m_set animIsRunning 1
                m_set pauseControl Pause
                [edit_w pauseControl] configure \
                    -background [widget_color animate bg] \
                    -image $animControlBitmaps(pause,im)
                [edit_w nextControl] configure \
                    -image $animControlBitmaps(nextDisabled,im) \
                    -background [widget_color animate bg]
                hideFrameDisplay
                logDebug "Resume"
                update
                next_frame 1
            }
        } elseif {![m_get animIsRunning]} {
            logDebug "Next Frame"
            next_frame 0
        }
    }
}

proc next_frame {mode} {
    set frameListVar [m_get_var animFrameList]
    upvar 0 $frameListVar frameList

    set frameNum [expr ([m_get animFrameNumber]+1) % [m_get animFrameCount]]
    set file [m_get currentMediaFile]
    set view [edit_w imageLabel]

    set img [lindex $frameList $frameNum 3]
    if {$img == {}} {
        set fmt "gif -index $frameNum"
        set elapsed \
            [time {set c [catch {image create photo -file $file -format $fmt} img]}]
        logDebug "Loading frame $frameNum from $file" $elapsed
        if {$c} {
            logWarning "Unable to load frame $frameNum from $file: $img"
            return
        }
        if {[b_get imageScaleMethod]} {
            set img [browse_fit_image_simple $img \
                         [winfo width [edit_w imageLabel]] \
                         [winfo height [edit_w imageLabel]]]
        } else {
            set img [browse_fit_image $img \
                         [winfo width [edit_w imageLabel]] \
                         [winfo height [edit_w imageLabel]]]
        }
        set newFrame [lreplace [lindex $frameList $frameNum] 3 3 $img]
        set frameList [lreplace $frameList $frameNum $frameNum $newFrame]
    }

    m_set animFrameNumber $frameNum

    [$view cget -image] copy $img
    set disp [edit_w animFrameDisplay]
    if {$mode && [m_get animIsRunning]} {
        # hideFrameDisplay
        set delay [lindex $frameList $frameNum 1]
        m_set animFrameDelay $delay
        m_set animAfterName [after $delay [list next_frame $mode]]
    } elseif {!$mode} {
        showFrameDisplay
    }
}

# Set up the event bindings for the browser/editor
proc setup_bindings {} {
    bind [edit_w pauseControl] <ButtonPress-1> {animation_control %W}
    bind [edit_w nextControl] <ButtonPress-1> {animation_control %W}
    bind [edit_w blockStyle] <<Modified>> {update_modified_status %W}
    bind [edit_w imgStyle]   <<Modified>> {update_modified_status %W}
    bind [edit_w blockText]  <<Modified>> {update_modified_status %W}
    bind [edit_w infoDirEntry] <FocusOut> {update_info_path_status %W}
    bind [edit_w infoDirEntry] <Key-Return> \
        {update_info_file_status %W; return_entry_action %W}
    bind [edit_w infoFileName] <FocusOut> {update_info_file_status %W}
    bind [edit_w infoFileName] <Key-Return> \
        {update_info_file_status %W; return_entry_action %W}

    foreach item [array names ::MetaEdit::Backup] {
        set item_w [edit_w $item]
        if {[lindex [bindtags $item_w] 1] eq "Entry"} {
            bindtags $item_w [concat [bindtags $item_w] MediaOptEnt]
        }
        bind $item_w <Leave> [list check_edit_field $item %W]
    }
    bind MediaOptEnt <Key-Return> {focus [tk_focusNext %W]}

    set item_w [edit_w knownKeywordList]
    bindtags $item_w [concat [bindtags $item_w] KeywordList]
    set item_w [edit_w keywordList]
    bindtags $item_w [concat [bindtags $item_w] KeywordList]
    bind KeywordList <Key> {keyword_letter_search %W %K %A}

    bind Entry <FocusIn> {enter_entry_action %W}
    bind Entry <FocusOut> {exit_entry_action %W}

    bind [edit_w blockTitle] <FocusOut> {check_edit_field blockTitle %W}
    bind [edit_w blockClass] <FocusOut> {check_edit_field blockClass %W}

    bind [edit_w mediaCaption] <FocusOut> {check_edit_field mediaCaption %W}
    bind [edit_w mediaAttributes] <FocusOut> \
        {check_edit_field mediaAttributes %W}
    bind [edit_w mediaHeight] <FocusOut> {check_edit_field mediaHeight %W}
    bind [edit_w mediaWidth] <FocusOut> {check_edit_field mediaWidth %W}
    bind [edit_w mediaTitle] <FocusOut> {check_edit_field mediaTitle %W}
    bind [edit_w mediaAltText] <FocusOut> {check_edit_field mediaAltText %W}
    bind [edit_w mediaLink] <FocusOut> {check_edit_field mediaLink %W}
    bind [edit_w forceFigure] <ButtonRelease-1> \
        {check_edit_field forceFigure %W}
    bind [edit_w forceFigure] <FocusOut> {check_edit_field forceFigure %W}

    set bte [edit_w blockText]
    bind $bte <KeyRelease> [list edit_fix_tag %W %K %A]
    bind $bte <Alt-n> [list edit_apply_tag %W normal oneshot]
    bind $bte <Alt-o> [list edit_apply_tag %W ole oneshot]
    bind $bte <Alt-u> [list edit_apply_tag %W ule oneshot]
    bind $bte <Alt-r> [list edit_apply_tag %W raw oneshot]
    bind $bte <Alt-v> [list edit_apply_tag %W UnKnOwN oneshot]
    bind $bte <Alt-Key-1> [list edit_apply_tag %W alt1 oneshot]
    bind $bte <Alt-Key-2> [list edit_apply_tag %W alt2 oneshot]
    bind $bte <Alt-Key-3> [list edit_apply_tag %W alt3 oneshot]
    bind $bte <Alt-Key-4> [list edit_apply_tag %W alt4 oneshot]
    bind $bte <Key-Return> [list edit_newline %W]

    foreach {ent act} {
        normal  latched
        ole     toggle
        ule     toggle
        alt1    toggle
        alt2    toggle
        alt3    toggle
        alt4    toggle
        raw     toggle
    } {
        bind [edit_w $ent] <ButtonPress-1> \
            [list edit_apply_tag $bte $ent $act 1]
        bind [edit_w $ent] <ButtonPress-2> \
            [list edit_apply_tag $bte normal latched 1]
    }
    bind [edit_w editWindow] <Destroy> [list destroy [edit_w mainWindow]]
    bind [edit_w imageWindow] <Destroy> [list destroy [edit_w mainWindow]]
}

# Command proc for the info dir button
# Allow the user to set the "Info File Dir" using the built-in directory
# choosing dialog native to the platform on which this is running
proc do_set_info_dir {w args} {
    if {[b_get altInfoDir] eq ""} {
        b_set altInfoDir [b_get cwd]
    }
    set newDir [tk_chooseDirectory \
                    -initialdir [b_get altInfoDir] \
                    -title {Select alternative info file directory} \
                    -parent $w]
    if {$newDir ne ""} {
        b_set altInfoDir $newDir
    }
}

# Load the data from the info files into the controls
# the parameters are not used
proc edit_load_app_data {args} {
    # copy the data into the text control
    global browse_current
    global $browse_current
    upvar #0 $browse_current blockData

    logDebug "browse_current is $browse_current"
    if {[array exists $browse_current]} {
        logDebug "$browse_current exists"

        set apTxt [edit_w appText]
        $apTxt configure -state normal
        $apTxt configure -undo false
        $apTxt delete 1.0 end

        if {![info exists blockData(unsupported)]} {
            set blockData(unsupported) {}
            logDebug "blockData(unsupported) was not set"
        } else {
            foreach line $blockData(unsupported) {
                $apTxt insert end "$line\n"
                logDebug $line
            }
        }
        $apTxt edit modified false
        $apTxt edit reset
        $apTxt configure -undo true
    }
}

# TODO

# Copy the data from the media edit controls back into the global blob of
# data for the current media file (name of the blob is in the global
# variable "browse_current") so that it can be written out to a file
# ('args' is not used)
proc edit_unload_app_data {args} {
    # copy the data out of the text control
    global browse_current
    global $browse_current
    upvar #0 $browse_current blockData

    if {[array exists $browse_current]} {
        set apTxt [edit_w appText]

        # set blockData(unsupported) {}

        foreach {key value index} [$apTxt dump -text 1.0 end] {
            regexp {^([0-9]+)\.([0-9]+)$} $index dummy lnum cpos
            switch -exact -- $key {
                tagon -
                tagoff -
                image -
                mark {
                }
                text {
                    foreach {line eol} [split $value \n] {
                        if {$line ne ""} {
                            logDebug "$lnum.$cpos $line"
                            lappend blockData(unsupported) $line
                        } else {
                            logDebug "empty line at $index"
                        }
                    }
                }
                default {
                    logWarning "key $key unsupported at $index"
                }
            } ; # end of switch
        } ; # end of foreach
        if {![info exists blockData(unsupported)]} {
            set blockData(unsupported) {}
        }
        logDebug "Dump of app data list:"
        logDebug $blockData(unsupported)
    }
}

# Load the keywords
proc edit_load_keywords {blockName} {
    global browse_current
    upvar #0 $browse_current blockData

    if {[info exists blockData(keywords)]} {
        m_set keywordList [lsort -ascii -unique $blockData(keywords)]
    } else {
        m_set keywordList {}
        set blockData(keywords) {}
    }
    logDebug $blockData(keywords)
    logDebug [m_get keywordList]
    set blockData(keywords) [m_get keywordList]
}

# Update the keywords
proc edit_unload_keywords {blockName} {
    global browse_current
    upvar #0 $browse_current blockData

    set blockData(keywords) [lsort -ascii -unique [m_get keywordList]]
    logInfo "edit_unload_keywords" \
        "blockData(keywords): $blockData(keywords)" \
        "temp list: [m_get keywordList]"

    m_set keywordList $blockData(keywords)
}

# Control view of tooltips
proc view_tooltips {args} {
    if {[b_get showTooltips]} {
        ::tooltip::tooltip enable
    } else {
        ::tooltip::tooltip disable
    }
}

# Command proc for the use info dir checkbox
proc browse_toggle_info {args} {
    if {[b_get useAltInfoDir]} {
        [edit_w infoDirButton] configure -state normal
        [edit_w infoDirEntry] configure -state normal
        if {[b_get altInfoDir] eq ""} {
            b_set altInfoDir [b_get cwd]
        }
    } else {
        [edit_w infoDirButton] configure -state disabled
        [edit_w infoDirEntry] configure -state readonly
    }
}

# Create the frame that contains the browser settings
proc browse_build_settings {parent} {
    global edit_paths

    set bgColor [widget_color settingsFrame bg]
    set fgColor [widget_color settingsFrame fg]

    set ef [labelframe $parent.browserSettings -text Settings \
                -background $bgColor]
    set fileBut [button $ef.fileButton -text "Media File" \
                     -state normal \
                     -font [b_get boldButtonFont] \
                     -command [list browse_open [edit_w mainWindow]]]
    set useAltInfoDir [checkbutton $ef.useAltInfoDir \
                           -font [b_get buttonFont] \
                           -variable [b_get_var useAltInfoDir] \
                           -text {Use separate info directory} \
                           -background $bgColor \
                           -command browse_toggle_info]
    set fileEntry [entry $ef.mediaFileEntry -width [b_get fileEntryWidth] \
                       -state readonly \
                       -textvariable [m_get_var currentMediaFile] \
                       -font [b_get fileEntryFont]]

    set infoDirBut [button $ef.infoDirButton -text "Info File Dir" \
                        -state disabled \
                        -font [b_get boldButtonFont] \
                        -command [list do_set_info_dir [edit_w mainWindow]]]
    set infoDir [entry $ef.infoDirEntry -width [b_get fileEntryWidth] \
                     -state readonly \
                     -textvariable [b_get_var altInfoDir] \
                     -font [b_get fileEntryFont]]

    set infoFileB [button $ef.infoFileButton -text "INFO File" \
                       -state disabled \
                       -font [b_get buttonFont]]
    set infoFile [entry $ef.infoFileEntry -width [b_get fileEntryWidth] \
                      -takefocus 0 \
                      -textvariable [m_get_var currentInfoFile] \
                      -font [b_get fileEntryFont]]

    set saveButton [button $ef.saveInfo -text Save -state disabled \
                        -width 12 \
                        -command [list browse_save [edit_w editWindow]]]

    set tkConBut $ef.consoleButton
    set tkConBut [button $ef.consoleButton -foreground gray80 \
                      -text "Start TkCon" \
                      -background $bgColor \
                      -command [list show_console $tkConBut] \
                      -relief flat]
    set edit_paths(consoleButton) $tkConBut

    set edit_paths(saveButton) $saveButton
    set edit_paths(settingsFrame) $ef
    set edit_paths(infoDirButton) $infoDirBut
    set edit_paths(infoDirEntry) $infoDir
    set edit_paths(useAltInfoDir) $useAltInfoDir
    set edit_paths(openMediaButton) $fileBut
    set edit_paths(openMediaEntry) $fileEntry
    set edit_paths(infoFileButton) $infoFileB
    set edit_paths(infoFileName)  $infoFile

    grid $fileBut    -row 1 -column 1 -sticky news
    grid $fileEntry  -row 1 -column 3 -sticky news
    grid $infoDirBut -row 3 -column 1 -sticky news
    grid $infoDir    -row 3 -column 3 -sticky news
    grid $useAltInfoDir -row 3 -column 5 -sticky nws -columnspan 3
    grid $infoFileB  -row 5 -column 1 -sticky news
    grid $infoFile   -row 5 -column 3 -sticky news
    grid $saveButton -row 5 -column 5 -sticky nws
    grid [edit_w consoleButton] -row 5 -column 7 -sticky news

    grid columnconfigure $ef 0 -minsize 5 -weight 0
    grid columnconfigure $ef 1 -weight 0
    grid columnconfigure $ef 2 -minsize 5 -weight 0
    grid columnconfigure $ef 4 -minsize 5 -weight 0
    grid columnconfigure $ef 5 -weight 1
    grid columnconfigure $ef 6 -minsize 5 -weight 0
    grid columnconfigure $ef 7 -weight 0
    grid columnconfigure $ef 8 -minsize 5
    grid rowconfigure $ef 0 -minsize 1
    grid rowconfigure $ef 2 -minsize 4
    grid rowconfigure $ef 4 -minsize 4
    grid rowconfigure $ef 6 -minsize 5

    set edit_paths(settingsFrame) $ef

    return $ef
}

proc dirTree_populateTree {tree item} {
    set path [$tree set $item fullpath]
    set itemType [$tree set $item type]
    if {[catch {set itemDate [file mtime $path]}]} {
        set itemDate 0
    }

    if {$itemType eq "Directory"} {
        if {[$tree set $item mtime] eq $itemDate} {
            return
        }
        $tree set $item mtime $itemDate
        puts stderr "directory $path has been updated"
    } elseif {$itemType ne "directory"} {
        return
    }

    puts stderr "Expanding $path"

    # remove the dummy child or old children
    $tree delete [$tree children $item]

    # reset the child file/directory counters
    set childFiles 0
    set childDirs 0
    # get the names of all of the files in this directory
    foreach f [lsort -dictionary [glob -nocomplain -dir $path *]] {
        set f [file normalize $f]
        set type [file type $f]
        if {[catch {set mtime [file mtime $f]}]} {
            set mtime 0
        }
        set id [$tree insert $item end -text [file tail $f] \
                    -values [list $f $type]]
        if {$type eq "directory"} {
            incr childDirs
            # Make it so that this node is openable by putting something
            # harmless in it
            $tree insert $id 0 -text dummy
            $tree item $id -text [file tail $f]/
            $tree set $id mtime $mtime
            $tree set $id size {-}
        } elseif {$type eq "file"} {
            # It's a "regular" file of some sort
            incr childFiles
            set size [file size $f]
            # format the file size
            if {$size > 1024*1024*1024} {
                set size [format "%.1f GB" [expr {$size/1024/1024/1024.}]]
            } elseif {$size >= 1024*1024} {
                set size [format "%.1f MB" [expr {$size/1024/1024.}]]
            } elseif {$size >= 1024} {
                set size [format "%.1f KB" [expr {$size/1024.}]]
            } else {
                append size " bytes"
            }
            $tree set $id size $size
            $tree set $id mtime $mtime
            set mType [fileTypeText $f]
            if {$mType ne {}} {
                $tree tag add sf $id
                $tree set $id media $mType
            }

        }
    }

    # stop from re-running on this node
    $tree set $item type Directory
    $tree set $item size "\[$childDirs d, $childFiles f\]"
}


proc dirTree_nodeSelected {tree item} {
    set itemType [$tree set $item type]
    # ignore directories, they're handled by the <<TreeviewOpen>> event
    if {$itemType eq "directory" || $itemType eq "Directory"} {
        return
    }

    set fullName [$tree set $item fullpath]
    puts stderr "dirTree_nodeSelected $tree $item ($fullName)"
}

proc dirTree_rightSelected {tree item} {
    set itemType [$tree set $item type]
    # ignore directories, they're handled by the <<TreeviewOpen>> event
    if {$itemType eq "directory" || $itemType eq "Directory"} {
        return
    }

    set fullName [$tree set $item fullpath]
    puts stderr "dirTree_rightSelected $tree $item ($fullName)"

    b_set cwd [file dirname $fullName]
    b_set mediaFile [file tail $fullName]
    b_set newFileSelected 1
    m_set fileSize [string trim [browse_get_file_stat $fullName size]]

    if {[info exists ::edit_paths(movieViewerFrame)]} {
        ::movie_end
    }

    browse_fileSelected [edit_w mainWindow] $fullName
}


proc dirTree_populateRoots {tree} {
    foreach vol [lsort -dictionary [file volumes]] {
        dirTree_populateTree $tree [$tree insert {} end -text $vol \
                                        -values [list $vol directory]]
    }
}

proc browse_build_dirTree {parent} {
    ttk::style configure Treeview \
        -font TkTextFont \
        -rowheight [expr {[font metrics TkTextFont -linespace] + 2}]

    set scrollX [ttk::scrollbar $parent.scrollX -orient horizontal \
                     -command "$parent.dirTree xview"]
    set scrollY [ttk::scrollbar $parent.scrollY -orient vertical \
                     -command "$parent.dirTree yview"]
    set dirTree [ttk::treeview $parent.dirTree \
                     -columns {fullpath type media size mtime} \
                     -displaycolumns {media size} \
                     -yscroll "$scrollY set" \
                     -xscroll "$scrollX set"]
    $dirTree heading \#0 -text "File System" 
    $dirTree heading size -text "Size"
    $dirTree heading media -text "FT"
    $dirTree column \#0 -stretch 1
    $dirTree column size -width 80 -anchor e -stretch 0
    $dirTree column media -width 80 -stretch 0
    # Temporary - some versions of Tk have the tag text configure broken, but still do -image
    $dirTree tag configure sf -background wheat -image $::ul_icn

    dirTree_populateRoots $dirTree

    bind $dirTree <<TreeviewOpen>> {dirTree_populateTree %W [%W focus]}
    bind $dirTree <<TreeviewSelect>> {dirTree_nodeSelected %W [%W focus]}
    bind $dirTree <Double-Button-1> {dirTree_rightSelected %W [%W focus]}

    grid $dirTree -row 1 -column 1 -sticky nsew
    grid $scrollY -row 1 -column 2 -sticky nsew
    grid $scrollX -row 2 -column 1 -sticky news
    grid columnconfigure $parent 1 -weight 1
    grid rowconfigure $parent 1 -weight 1

    return $dirTree
}

# recursive part of tree search used by proc "dirTree_syncWithSelection"
proc dirTree_followPath {tree parent parts depth sofar} {
   incr depth
   if {$depth eq [llength $parts]} {
      puts stdout "Got as far as $sofar at depth $depth"
      $tree see $parent
      return
   }
   ::dirTree_populateTree $tree $parent
   set newPart [lindex $parts $depth]
   set sofar [file join $sofar $newPart]
   if {[file isdirectory $sofar]} {
      set newPart "$newPart/"
   }
   foreach node [$tree children $parent] {
      puts stdout "Comparing $newPart with [$tree item $node -text]"
      if {$newPart eq [$tree item $node -text]} {
         $tree selection set $node
         puts stdout "recursing with $sofar at depth $depth"
	 dirTree_followPath $tree $node $parts $depth $sofar
         return
      }
   }
   puts stderr "didn't find anything"
}

# Select the node for a given filename (full path)
proc dirTree_syncWithSelection {filename} {
    set tree [edit_w dirTree]
    set depth 0
    set parts [file split $filename]
    foreach vol [$tree children {}] {
        set path [lindex $parts $depth]
        if {$path eq [$tree item $vol -text]} {
            $tree selection set $vol
            dirTree_followPath $tree $vol $parts $depth $path
            return
        }
    }
    puts stderr "didn't find $filename"
}

# Build and display the browser/editor window
proc browse_show_main {parent} {
    global browse_image edit_paths browse_current browse_default
    global ol_icn ul_icn del_icn ra_icn la_icn
    global edit_paths

    if {$parent eq "."} {
        # Use the Tk top window as the main window
        set w $parent
    } else {
        # Create a new toplevel window for this run
        set w [toplevel $parent]
    }
    # make the path to the main window generally available
    set edit_paths(mainWindow) $w

    # create the images used for ordered and unordered list entries
    if {$ol_icn == {}} {
        global ol_bitmap_fg
        set ol_icn [image create bitmap orderedList -data $ol_bitmap_fg]
    }
    if {$ul_icn == {}} {
        global ul_bitmap_fg
        set ul_icn [image create bitmap unorderedList -data $ul_bitmap_fg]
    }
    if {$del_icn == {}} {
        global del_bitmap_fg
        set del_icn [image create bitmap deleteEntry -data $del_bitmap_fg \
                         -foreground firebrick]
    }

    global animControlBitmaps
    # same bitmap for NEXT and (next)
    set animControlBitmaps(nextDisabled,bm) $animControlBitmaps(next,bm)
    foreach {icon color} {
        blank black
        next green
        nextDisabled gray70
        pause red
        play blue
        resume green} {
        catch {image delete $icon}
        set animControlBitmaps($icon,im) \
            [image create bitmap $icon -foreground $color \
                 -data $animControlBitmaps($icon,bm)]
    }

#    global del_pressed_icn
#    if {$del_pressed_icn == {}} {
#        global del_bitmap_fg
#        set del_icn_down [image create bitmap deleteEntryDown \
#                              -data $del_bitmap_fg \
#                              -foreground orange]
#    }
#    global del_active_icn
#    if {$del_pressed_icn == {}} {
#        global del_bitmap_fg
#        set del_active_icn [image create bitmap deleteEntryActive \
#                                -data $del_bitmap_fg \
#                                -foreground pink]
#    }
#    ttk::style element create Button.button image \
#        [list deleteEntry pressed deleteEntryDown active deleteEntryActive] \
#        -border {2 4} -sticky we

    if {$ra_icn == {}} {
        global ra_bitmap_fg
        set ra_icn [image create bitmap rightArrow -data $ra_bitmap_fg \
                        -foreground "light sea green"]
    }
    if {$la_icn == {}} {
        global la_bitmap_fg
        set la_icn [image create bitmap leftArrow -data $la_bitmap_fg \
                        -foreground "sea green"]
    }

    # Use a special (empty) data set initially
    set browse_current browse_default

    # Create the main frame for the browser window into which the other
    # elements will be put.
    set wf [frame $w.imageView]
    # start with an empty image
    # doesn't need to be large
    set browse_image [image create photo -height 64 -width 64]

    set imageWin [toplevel $wf.imageWin]
    wm title $imageWin Meta-Edit
    wm forget $imageWin
    set edit_paths(imageWindow) $imageWin

    set treeWin [toplevel $wf.treeWin]
    wm title $treeWin Meta-Edit
    wm forget $treeWin
    set edit_paths(treeWindow) $treeWin

    set editWin [toplevel $wf.editWin]
    wm title $editWin Meta-Edit
    wm forget $editWin
    set edit_paths(editWindow) $editWin

    set setWin [toplevel $wf.settingsWin]
    wm forget $setWin
    set edit_paths(settingsWindow) $setWin

    # Create the frame with the editing controls in it
    set editFrm [browse_build_edit $editWin]

    # The image is (for now) displayed in a label
    set imgFrame [labelframe $imageWin.imagePanel \
                      -text "Media Preview" \
                      -labelanchor n \
                      -width [b_get mediaViewX] \
                      -height [expr [winfo height [edit_w editFrame]] - 100]]

    set dirTreeFrame [labelframe $treeWin.dirTreeFrame \
                          -text "Directory Tree" \
                          -labelanchor n \
                          -width [b_get mediaViewX]]

    # The banner frame is across the top of the view window/frame;
    # having a frame for it makes it easier to place things on it without
    # worrying about changing "columnspan" for the main image.
    #
    set imgBanner [frame $imgFrame.banner]
    set imgPause [label $imgBanner.pauseAnim -width 6 -justify center]
    set imgNameL [label $imgBanner.imageName \
                      -textvariable [b_get_var mediaName] \
                      -font [b_get fileEntryFont] -justify center]
    set imgNext  [label $imgBanner.next -width 6 -justify center]

    # the animFrameDisplay label is only displayed during paused animations
    set animFrameL [label $imgBanner.animFrameDisplay -background white \
                        -justify center -width 7]
    grid $imgNameL -row 0 -column 1 -sticky news
    grid $imgPause -row 0 -column 0 -sticky news
    grid $imgNext  -row 0 -column 2 -sticky news
    grid columnconfig $imgBanner 1 -weight 1
    grid columnconfig $imgBanner 0 -minsize 24
    grid columnconfig $imgBanner 2 -minsize 24

    set imgLabel [label $imgFrame.image -image $browse_image]

    set dirTree [browse_build_dirTree $dirTreeFrame]

    set edit_paths(imageFrame) $imgFrame
    set edit_paths(imageLabel) $imgLabel
    set edit_paths(mediaNameBanner) $imgNameL
    set edit_paths(pauseControl) $imgPause
    set edit_paths(nextControl) $imgNext
    set edit_paths(animFrameDisplay) $animFrameL
    set edit_paths(mediaBannerFrame) $imgBanner
    set edit_paths(dirTreeFrame) $dirTreeFrame
    set edit_paths(dirTree) $dirTree

    # set things up for the "busy" screen
    m_set busyFontIndex -1
    set busyFont {{Poor Richard} 30}
    
    set busyLabel [label $imageWin.noImage -text "Please\nbe\npatient..." \
                       -font $busyFont \
                       -background snow]
    set edit_paths(busyLabel) $busyLabel

    # Create the frame with the browse settings in it
    set setFrm [browse_build_settings $setWin]

    grid $imgBanner -row 0 -column 0 -sticky news
    grid $imgLabel -row 2 -column 0 -sticky news
    grid rowconfigure $imgFrame 0 -weight 0
    grid rowconfigure $imgFrame 1 -minsize 5 -weight 0
    grid columnconfigure $imgFrame 0 -minsize [b_get mediaViewX] -weight 0

    grid $imgFrame -row 1 -column 1 -sticky news
    grid columnconfigure $imageWin 1 -weight 1

    grid $dirTreeFrame -row 1 -column 1 -sticky news
    grid columnconfigure $treeWin 1 -weight 1
    grid rowconfigure $treeWin 1 -minsize 40

    grid $editFrm  -row 1 -column 1 -sticky news
    grid columnconfigure $editWin 1 -weight 1
    grid $setFrm   -row 1 -column 1 -sticky news
    grid columnconfigure $setWin 1 -weight 1

    grid $setWin   -row 1 -column 0 -sticky news -columnspan 3
    grid $imageWin -row 3 -column 0 -sticky news
    grid $treeWin  -row 5 -column 0 -sticky news
    grid $editWin  -row 3 -column 2 -sticky news -rowspan 3

    #grid rowconfigure $wf 0 -minsize 6 -weight 0 ;# (not needed)
    grid rowconfigure $wf 2 -minsize 3 -weight 0
    grid rowconfigure $wf 4 -minsize 4 -weight 0

    grid columnconfigure $wf 0 -weight 1
    grid columnconfigure $wf 1 -minsize 3 -weight 0
    grid columnconfigure $wf 2 -weight 0

    grid $wf -row 1 -column 1 -sticky news

    grid columnconfigure $w 0 -minsize 5 -weight 0
    grid columnconfigure $w 1 -weight 1
    grid columnconfigure $w 2 -minsize 5 -weight 0
    grid rowconfigure $w 0 -minsize 2 -weight 0
    grid rowconfigure $w 1 -weight 1
    grid rowconfigure $w 2 -minsize 5 -weight 0

    update
    m_set area_height_1 [get_media_area_height]
    grid rowconfigure $imgFrame 2 -minsize [get_media_area_height] -weight 0

    $w configure -background gray86
    $wf configure -background gray90
    $setWin configure -background [widget_color settingsFrame bg]

    # grid rowconfigure $w 1 -minsize 400

    # The buttons and main window aren't in the editing frame, but are
    # referenced elsewhere anyway.  Make 'edit_w' work for them.
#    set edit_paths(openButton) $openButton
#    set edit_paths(saveButton) $saveButton
#    set edit_paths(closeButton) $closeButton

    # set up some menus
    set mainMenu [menu [edit_w mainWindow].mainMenu -tearoff 0]
    set edit_paths(mainMenu) $mainMenu

    set fileMenu [menu $mainMenu.fileMenu -tearoff 0]
    set edit_paths(fileMenu) $fileMenu
    $mainMenu add cascade -label "File" -menu $fileMenu -underline 0
    $fileMenu add command -label "Open Media..." \
        -command [list browse_open [edit_w mainWindow]]
    $fileMenu add command -label "Set Alternate INFO Directory..." \
        -command [list do_set_info_dir [edit_w mainWindow]]
    $fileMenu add separator
    $fileMenu add command -label "Save Info File" \
        -command [list browse_save [edit_w mainWindow]]
    $fileMenu add command -label "Save Info File As..." \
        -command [list browse_save_as [edit_w mainWindow]]
    $fileMenu add separator
    $fileMenu add command -label "Load Keyword List..." \
        -command [list kw_load_file [edit_w knownKeywordList]]
    $fileMenu add command -label "Save to File..." \
        -command [list kw_save_file [edit_w knownKeywordList]]
    $fileMenu add separator
    $fileMenu add command -label "Exit" \
        -command [list browse_close $w]
    set visualMenu [menu $mainMenu.visualMenu -tearoff 0]
    set edit_paths(visualMenu) $visualMenu
    $mainMenu add cascade -label "Visual" -menu $visualMenu -underline 0
    $visualMenu add command -label "Select image background color..." \
        -command [list choose_background_color $imgLabel]
    $visualMenu add separator
    $visualMenu add check -label "Simple Image Scaler" \
        -background snow \
        -variable [b_get_var imageScaleMethod]

    set utilMenu [menu $mainMenu.utilMenu -tearoff 0]
    set edit_paths(utilMenu) $utilMenu
    $mainMenu add cascade -label "Utilities" -menu $utilMenu -underline 0

    if {[tk windowingsystem] eq "win32"} {
        $utilMenu add command -label "Browse Selected Media Path" \
            -command [list launch_browser [edit_w mainWindow] media] \
            -underline 16
        $utilMenu add command -label "Browse Info File Path" \
            -command [list launch_browser [edit_w mainWindow] info] \
            -underline 8
        $utilMenu add separator
    }
    $utilMenu add command -label "Load Debug Console" -underline 5 \
        -command [list show_console [edit_w consoleButton]]

    set optMenu [menu $mainMenu.optionsMenu -tearoff 0]
    set edit_paths(optionMenu) $optMenu
    $mainMenu add cascade -label "Options" -menu $optMenu -underline 0
    $optMenu add check -label "Tooltips" -variable [b_get_var showTooltips] \
        -command view_tooltips

    set windowMenu [menu $mainMenu.windowMenu -tearoff 0]
    set edit_paths(windowMenu) $windowMenu
    $mainMenu add cascade -label "Windows" -menu $windowMenu -underline 0
    $windowMenu add command -label "Undock Panels" \
        -command undock_panels
    $windowMenu add command -label "Dock Panels" \
        -command dock_panels \
        -state disabled

    set helpMenu [menu $mainMenu.helpMenu -tearoff 0]
    set editPaths(helpMenu) $helpMenu
    $mainMenu add cascade -label "Help" -menu $helpMenu -underline 0
    $helpMenu add command -label "About..." -command display_about

    $w configure -menu $mainMenu

    set editMainMenu [menu $editWin.mainMenu -tearoff 0]
    set edit_paths(editMainMenu) $editMainMenu
    set editFileMenu [menu $editMainMenu.file -tearoff 0]
    set edit_paths(editFileMenu) $editFileMenu
    set editWindowMenu [menu $editMainMenu.window -tearoff 0]
    set edit_paths(editWindowMenu) $editWindowMenu
    set editHelpMenu [menu $editMainMenu.help -tearoff 0]
    set edit_paths(editHelpMenu) $editFileMenu

    $editMainMenu add cascade -label "File" -menu $editFileMenu -underline 0
    $editFileMenu add command -label "Open Media..." \
        -command [list browse_open [edit_w mainWindow]]
    $editFileMenu add command -label "Set Alternate INFO Directory..." \
        -command [list do_set_info_dir [edit_w mainWindow]]
    $editFileMenu add separator
    $editFileMenu add command -label "Save Info File" \
        -command [list browse_save [edit_w mainWindow]]
    $editFileMenu add command -label "Save Info File As..." \
        -command [list browse_save_as [edit_w mainWindow]]
    $editFileMenu add separator
    $editFileMenu add command -label "Load Keyword List..." \
        -command [list kw_load_file [edit_w knownKeywordList]]
    $editFileMenu add command -label "Save to File..." \
        -command [list kw_save_file [edit_w knownKeywordList]]
    $editFileMenu add separator
    $editFileMenu add command -label "Exit" \
        -command [list browse_close $w]

    $editMainMenu add cascade -label "Windows" \
        -menu $editWindowMenu -underline 0
    $editWindowMenu add command -label "Dock Panels" \
        -command dock_panels

    $editMainMenu add cascade -label "Help" -menu $editHelpMenu -underline 0
    $editHelpMenu add command -label "About..." -command display_about

    set imageMainMenu [menu $imageWin.mainMenu -tearoff 0]
    set edit_paths(imageMainMenu) $imageMainMenu
    set imageFileMenu [menu $imageMainMenu.file -tearoff 0]
    set edit_paths(imageFileMenu) $imageFileMenu
    set imageWindowMenu [menu $imageMainMenu.window -tearoff 0]
    set edit_paths(imageWindowMenu) $imageWindowMenu
    set imageHelpMenu [menu $imageMainMenu.help -tearoff 0]
    set edit_paths(imageHelpMenu) $imageFileMenu

    $imageMainMenu add cascade -label "File" -menu $imageFileMenu -underline 0
    $imageFileMenu add command -label "Open Media..." \
        -command [list browse_open [edit_w mainWindow]]
    $imageFileMenu add command -label "Set Alternate INFO Directory..." \
        -command [list do_set_info_dir [edit_w mainWindow]]
    $imageFileMenu add separator
    $imageFileMenu add command -label "Save Info File" \
        -command [list browse_save [edit_w mainWindow]]
    $imageFileMenu add command -label "Save Info File As..." \
        -command [list browse_save_as [edit_w mainWindow]]
    $imageFileMenu add separator
    $imageFileMenu add command -label "Load Keyword List..." \
        -command [list kw_load_file [edit_w knownKeywordList]]
    $imageFileMenu add command -label "Save to File..." \
        -command [list kw_save_file [edit_w knownKeywordList]]
    $imageFileMenu add separator
    $imageFileMenu add command -label "Exit" \
        -command [list browse_close $w]

    set imageVisualMenu [menu $imageMainMenu.imageVisualMenu -tearoff 0]
    set edit_paths(imageVisualMenu) $imageVisualMenu
    $imageMainMenu add cascade -label "Visual" \
        -menu $imageVisualMenu -underline 0
    $imageVisualMenu add command -label "Select image background color..." \
        -command [list choose_background_color $imgLabel]
    $imageVisualMenu add separator
    $imageVisualMenu add check -label "Simple Image Scaler" \
        -background snow \
        -variable [b_get_var imageScaleMethod]

    $imageMainMenu add cascade -label "Windows" \
        -menu $imageWindowMenu -underline 0
    $imageWindowMenu add command -label "Dock Panels" \
        -command dock_panels

    $imageMainMenu add cascade -label "Help" -menu $imageHelpMenu -underline 0
    $imageHelpMenu add command -label "About..." -command display_about

    # adjust the size of the image view area
    update
    grid rowconfigure $imgFrame 2 -minsize [get_media_area_height] -weight 0
    # clean up the geometry in the edit box...
    edit_fix_geometry

    # and finally...
    setup_tooltips
    setup_bindings
    setup_text_tags [edit_w blockText]
    autoload_opt_files
}

proc autoload_opt_files {args} {
    global argv0
    set autoload_path [file dirname $argv0]
    set autoload_keywords [file join $autoload_path meta-edit-keywords.kwd]
    if {[file exists $autoload_keywords]} {
        kw_load_file [edit_w knownKeywordList] autoload $autoload_keywords
    }
}

proc display_about {args} {
    set w [toplevel .aboutMe]
    wm title $w "About..."
    set lbl [label $w.about -justify center \
                 -text "Meta-Edit\nDaniel Glasser
\"Anything not worth doing is worth doing well\""]
    set btn [button $w.dismiss -text "Sure, if you say so..." \
                 -font {helvetica 10 italic} \
                 -command [list destroy $w]]
    grid $lbl -row 1 -column 1 -sticky news
    grid $btn -row 2 -column 1 -sticky news
    tkwait window $w
}

proc launch_browser {w pathSelect} {
    switch -- $pathSelect {
        media {
            set browserPath [file dirname [m_get currentMediaFile]]
        }
        info {
            set browserPath [b_get altInfoDir]
        }
        default {
            set browserPath ""
        }
    }

    if {$browserPath ne "" && [file isdirectory $browserPath]} {
        logInfo "exec explorer.exe [file nativename $browserPath] &"
        if {[catch {exec explorer.exe [file nativename $browserPath] &} pid]} {
            global errorInfo
            logWarning "Unable to launch the file browser" $pid $errorInfo
        } else {
            logInfo "PID $pid"
        }
    } else {
        logWarning "No path for $pathSelect"
    }
}

proc choose_background_color {win args} {
    set color [tk_chooseColor -initialcolor [b_get imageBGColor] \
                   -title "Pick a color, any color"]
    if {$color ne ""} {
        b_set imageBGColor $color
        $win configure -background $color
    }
}

# Fix the line types read from the blockText 'text' control
# to match more closely what is expected by the info file
# routines
proc edit_fix_lineType {lineVarName} {
    global alt_class_assoc
    upvar 1 $lineVarName linePair
    set ltype [lindex $linePair 1]
    switch -exact -- $ltype {
        ole {
            set linePair [lreplace $linePair 1 1 +]
            set linePair [lreplace $linePair 0 0 \
                              [string trim [lindex $linePair 0]]]
        }
        ule {
            set linePair [lreplace $linePair 1 1 .]
            set linePair [lreplace $linePair 0 0 \
                              [string trim [lindex $linePair 0]]]
        }
        UnKnOwN {
            set linePair [lreplace $linePair 1 1 ()]
        }
        raw {
            set linePair [lreplace $linePair 1 1 !]
        }
        @ {
            # these lines need no changes
        }
        alt1 -
        alt2 -
        alt3 -
        alt4 {
            set linePair [lreplace $linePair 1 1 $alt_class_assoc($ltype)]
            set linePair [lreplace $linePair 0 0 \
                              [string trim [lindex $linePair 0]]]
        }
        {} {
            set linePair [lreplace $linePair 1 1 @]
            set linePair [lreplace $linePair 0 0 \
                              [string trim [lindex $linePair 0]]]
        }

        default {
            logWarning "decoding error: ltype is '$ltype'"
        }
    } ; # end of switch
}

# Read the style data from one of the style related 'text' controls
# and store them in a named array
proc edit_getStyle {win destVarName} {
    upvar 1 $destVarName styleList
    array set styleList {}
    foreach {key value index} [$win dump -text 1.0 end] {
        regexp {^([0-9]+)\.([0-9]+)$} $index dummy lnum cpos
        if {[regexp {^([^\:]+)\:\ ([^\;]*)\;$} $value dummy style setting]} {
            set styleList($style) $setting
        }
    }
}

# Fetch the text and tag information from the blockText 'text' widget
# and convert it into a form almost the same as what is read from the
# info text files, which is built as a list in the named destination
# variable.  The resulting list made up of entries that are, in effect
#    [list $line $type]
# where 'line' is the line text, 'type' indicates the type of the line,
# such as '@' for normal paragraph, '!' for verbatim block, '+' for ordered
# list items, '.' for unordered list items, and names of alternate paragraph
# classes to be applied to 'line' text.
# Further post-processing is required to pull the ordered and unordered lists
# together.
proc edit_getText {win destVarName} {
    set lineType {@}
    set lineNum 0
    upvar 1 $destVarName lineList
    set lineList {}
    set lineText [list {} ""]
    set eol 0
    set cnt 0

    foreach {key value index} [$win dump -text -tag 1.0 end] {
        regexp {^([0-9]+)\.([0-9]+)$} $index dummy lnum cpos
        switch -exact -- $key {
            tagon {
                if {$cpos eq "0"} {
                    set lineType $value
                    set lineNum $lnum
                }
            }
            tagoff {
                if {$value eq $lineType} {
                    set lineType {@}
                }
            }
            mark {
                # ignoring mark
            }
            text {
                if {[string range $value end end] eq "\n"} {
                    regexp {^(.*)\n$} $value dummy value
                    set eol 1
                } else {
                    set eol 0
                }
                if {$cpos eq "0"} {
                    if {$lnum > 0} {
                        if {!$cnt && $lineText == [list {} ""]} {
                            logDebug "Discarding first empty line"
                        } else {
                            edit_fix_lineType lineText
                            lappend lineList $lineText
                        }
                    }
                    incr cnt 1
                    set lineText [list $value $lineType]
                } else {
                    set lineText [lreplace $lineText 0 0 \
                                      [string cat [lindex $lineText 0] \
                                           $value]]
                }
            }
            image {
                # ignoring embedded images, which are list related
            }
            default {
                logWarning "key $key unsupported at $index"
            }
        } ; # end of switch
    } ; # end of foreach
    lappend lineList $lineText
    return $lineList
}

# This proc massages the information collected from the edit controls
# in the metadata browser and uses it to replace the data read from the
# info file (or generated because there was no info file) in the in-memory
# data structure.  This includes gathering up the ordered and unordered
# list items and marking where each list appears in the text stream.
#
# Once this proc completes, the info-file writer proc must be called to
# write the updated metadata to the text file.  That's not done by this
# proc, it is expected that the caller will deal with that.
#
# Parameters:
#
#  infoBlock is the name of the global array that is the primary in-memory
#    data structure created by the info file reader and written from by the
#    info file writer procs
#  textList is the name of the variable in the caller that contains the
#    list of updated text blocks, along with the ordered and unordered
#    list items collected from the blockText 'text' widget
#  blockStyleArr is the name of the array variable in the caller that
#    contains the information from the 'blockStyle' text widget
#  imgStyleArr is the name of the array variable in the caller that
#    contains the information from the 'imgStyle' text widget
#
proc edit_update_info {infoBlock textList blockStyleArr imgStyleArr} {
    upvar 1 $textList newTextBlocks
    upvar 1 $blockStyleArr newBlockStyles
    upvar 1 $imgStyleArr newImgStyles
    upvar #0 $infoBlock blockData
    set olStarted 0
    set ulStarted 0

    # copy the 'entry' box data back from the widgets for the
    # title text and the extra class list
    set blockData(infoTitle) [m_get blockTitle]
    set blockData(blockClass) [m_get blockClass]

    # Rather than nesting arrays, the block data from the reader
    # simply contains the names of the global arrays that were
    # created for the blockStyle and imgStyle information
    # These get brought into the local scope via 'upvar' and then
    # the contents are replaced with that provided by the caller
    upvar #0 $blockData(blockStyle) blockStyle
    array set blockStyle [array get newBlockStyles]
    upvar #0 $blockData(imgStyle) imgStyle
    array set imgStyle [array get newImgStyles]

    # reset the data lists in the in-memory data structure
    # in preparation for them to be loaded with the new information
    set blockData(ordered) {}
    set blockData(unordered) {}
    set blockData(textBlocks) {}

    # trim the excess empty line added at end by the parsing of the
    # data from the 'text' control
    if {[lindex $newTextBlocks end] == {{} @}} {
        set newTextBlocks [lrange $newTextBlocks 0 end-1]
    }

    # Process each line of data in the list, collecting the ordered and
    # unordered lists, marking where each appears, etc.
    foreach chunk $newTextBlocks {
        set line [lindex $chunk 0]
        set type [lindex $chunk 1]
        if {$line eq ""} {
            set line "&nbsp;"
        }
        switch -exact -- $type {
            + {
                if {!$olStarted} {
                    set olStarted 1
                    lappend blockData(textBlocks) [list {<ol> here} +]
                }
                lappend blockData(ordered) $line
            }
            . {
                if {!$ulStarted} {
                    set ulStarted 1
                    lappend blockData(textBlocks) [list {<ul> here} .]
                }
                lappend blockData(unordered) $line
            }
            default {
                lappend blockData(textBlocks) $chunk
            }
        } ; #end of switch
    } ; # end of foreach

    # get updated keyword data
    edit_unload_keywords blockData

    # get updated data from the widget
    edit_unload_app_data blockData
}

########################################################################
# Copy of 'generate.tcl'
########################################################################
# This is the regular expression for info lines
# usage: regexp $infoPat(line) $line matchVar typeVar tailVar
set infoPat(line) {^([.,<>\[\]{}`'\"\|\\\-+%^~=&#@/!*\?\$\:\;])(.*)$}

# This is the regular expression for classy paragraphs
# usage: regexp $infoPat(class) $tailVar matchVar classVar tailVar
set infoPat(class) {^([^\ ]+)(?:\ )(.*)$}
# This is the regular expression for style entries
# usage: regexp $infoPat(style) $tailVar matchVar classVar tailVar
set infoPat(style) $infoPat(class)
# This is the plain-text to HTML entity mapping table
# usage: string map $infoPat(entity) $remain
set infoPat(entity) {... &helip;}

# Form a name for the global block data var for a given block name
proc blockVarName {blockName} {
    set bname "$blockName-block"
    return $bname
}
    
proc blockDestroy {blockName} {
    set bvname [blockVarName $blockName]
    upvar #0 $bvname blockData
    upvar #0 "$bvname-bs" blockStyle
    upvar #0 "$bvname-is" imgStyle
    if {[array exists blockData]} {
        array unset blockData
    }
    if {[array exists blockStyle]} {
        array unset blockStyle
    }
    if {[array exists imgStyle]} {
        array unset imgStyle
    }
}

proc blockCreate {blockName} {
    set bvname [blockVarName $blockName]
    set bsname "$bvname-bs"
    set biname "$bvname-is"

    upvar #0 $bvname blockData
    upvar #0 $bsname blockStyle
    upvar #0 $biname imgStyle

    blockDestroy $blockName
    array set blockData [list blockName $blockName]
    array set blockStyle {}
    array set imgStyle {}

    set blockData(textBlocks) {}
    set blockData(ordered) {}
    set blockData(unordered) {}
    set blockData(blockClass) {}
    set blockData(blockStyle) $bsname
    set blockData(imgStyle) $biname
    return $bvname
}

proc storeUnsupportedLine {bvname rawLine} {
    upvar 1 $bvname blockData
    lappend blockData(unsupported) $rawLine
}

proc saveUnsupportedLines {bvname outFile} {
    global $bvname
    upvar 1 $bvname blockData

    logDebug "saveUnsupportedLines $bvname $outFile"
    if {[llength $blockData(unsupported)]} {
        puts $outFile "# Data for other applications"
        foreach line $blockData(unsupported) {
            logDebug $line
            puts $outFile $line
        }
    }
}

# Add a keyword
proc addKeyword {blockName keyword} {
    global $blockName
    upvar 1 $blockName blockData

    logDebug "addKeyword $blockName $keyword"
    if {![info exists blockData(keywords)]} {
        set blockData(keywords) [list $keyword]
        logDebug "Added keyword $keyword (first one)"
    } elseif {[lsearch -nocase $blockData(keywords) $keyword] < 0} {
        lappend blockData(keywords) $keyword
        logDebug "Added keyword $keyword"
    }
}


proc saveKeywords {blockName info} {
    global $blockName
    upvar 1 $blockName blockData

    logInfo "Saving keywords"

    if {[info exists blockData(keywords)]} {
        logInfo "Keyword array exists"
        if {[llength $blockData(keywords)]} {
            logInfo "Keyword array isn't empty"
            set accum ""
            set sep ""
            foreach word $blockData(keywords) {
                logInfo "Keyword: $word"
                if {[string length $accum] + [string length $word] > 74} {
                    puts $info "*$accum"
                    set accum ""
                    set sep ""
                }
                set accum [string cat $accum $sep $word]
                set sep ", "
            }
            if {[string length $accum] > 0} {
                puts $info "*$accum"
            }
        }
    }
}

proc addBlockText {bvname blockType blockText} {
    upvar 1 $bvname blockData

#    if {$blockType eq "@"} {
#        set blockType {}
#    }

    lappend blockData(textBlocks) [list $blockText $blockType]
    return [llength $blockData(textBlocks)]
}

proc addListItem {bvname listType itemText} {
    upvar 1 $bvname blockData
    set result -1
    switch -exact -- $listType {
        + {
            if {![llength $blockData(ordered)]} {
                # set the position of the ordered list
                addBlockText blockData $listType {<ol> here}
            }
            lappend blockData(ordered) $itemText
            set result [llength $blockData(ordered)]
        }
        . {
            if {![llength $blockData(unordered)]} {
                # set the position of the unordered list
                addBlockText blockData $listType {<ul> here}
            }
            lappend blockData(unordered) $itemText
            set result [llength $blockData(unordered)]
        }
        default {
            logWarning "addListItem: unknown list type '$listType'"
        }
    }
    return $result
}

proc addBlockStyle {bvname styleName styleText} {
    upvar 1 $bvname blockData
    set styleArray $blockData(blockStyle)
    upvar #0 $styleArray blockStyle
    set blockStyle($styleName) $styleText
}

proc addBlockImgStyle {bvname styleName styleText} {
    upvar 1 $bvname blockData
    set styleArray $blockData(blockStyle)
    upvar #0 $blockData(imgStyle) imgStyle
    set imgStyle($styleName) $styleText
}

# Derive the info file name
proc browse_infoFileName {imgFileName} {
    if {[b_get useAltInfoDir]} {
        if {[b_get altInfoDir] eq {}} {
            b_set altInfoDir [file dirname $imgFileName]
        }
        set fName [string cat [file root [file tail $imgFileName]] .txt]
        set infoFileName \
            [string cat [file join [b_get altInfoDir] $fName]]
    } else {
        set infoFileName "[file rootname $imgFileName].txt"
    }
    return $infoFileName
}

# Get meta-data from info file, or make some up if the info file is missing
proc loadInfoFile {blockDataName} {
    global infoPat
    upvar 1 $blockDataName blockData
    set blockName   $blockData(blockName)
    set imgFileName $blockData(imgFile)
    set blockPrefix $blockData(blockPrefix)

    # set infoFileName "[file rootname $imgFileName].txt"
    set infoFileName [browse_infoFileName $imgFileName]
    set blockData(infoFile) $infoFileName
    set blockData(infoTitle) $blockPrefix

    # make the info file name easier to get to
    m_set currentInfoFile $infoFileName

    logDebug "Clearing optional attributes for media elements"
    m_set mediaOptionsModified 0
    o_set mediaAltText    ""
    o_set mediaAttributes ""
    o_set mediaWidth      ""
    o_set mediaHeight     ""
    o_set mediaTitle      ""
    o_set forceFigure     0

    if {[file exists $infoFileName]} {
        set line {}
        set info [open $infoFileName r]

        # it's an existing file
        m_set infoFileDisposition 1

        while {[set cnt [gets $info line]] >= 0} {
            if {$cnt} {
                if {![regexp $infoPat(line) $line matched bgn remain]} {
                    set bgn "()" ; # not a valid prefix
                    set remain $line
                }
            } else {
                # just go on to the next line
                continue
            }                

            # Note that we always must treat the input data as strings,
            # not lists. This prevents problems when Tcl converts a string
            # that is not a well formed Tcl list to a list; even strings
            # that are well formed lists get messed up if there are
            # quoted sections or various braces within them.
            switch -exact -- $bgn {
                + -
                . {
                    # Add list item (orered or unordered)
                    addListItem blockData $bgn $remain
                }
                @ {
                    # Add paragraph (no class specified)
                    # clean up the text to make it more HTML friendly
                    set remain [string map $infoPat(entity) $remain]
                    addBlockText blockData $bgn $remain
                }
                % {
                    # Add paragraph (explicit class specified)
                    set r [regexp $infoPat(class) $remain matched class remain]
                    if {!$r} {
                        logWarning "erroneous % line; winging it"
                        set class alt4
                    }
                    # clean up the text to make it more HTML friendly
                    set remain [string map $infoPat(entity) $remain]
                    addBlockText blockData $class $remain
                }
                = {
                    # Override "title"
                    set blockData(infoTitle) $remain
                }
                ~ {
                    # Add to CSS style for this item
                    regexp $infoPat(class) $remain matched attr remain
                    addBlockStyle blockData $attr $remain
                }
                / {
                    # Add to CSS style to the <img> for this item
                    regexp $infoPat(class) $remain matched attr remain
                    addBlockImgStyle blockData $attr $remain
                }
                ^ {
                    # Add additional class to <div> for the item
                    lappend blockData(blockClass) $remain
                }
                # -
                <> {
                    # discard comments
                }

                ! {
                    # Add a raw line of HTML (not in a <p>)
                    # or a comment
                    addBlockText blockData $bgn $remain
                }

                () {
                    # unrecognized line type
                    # Make it special
                    addBlockText blockData $bgn $remain
                }
                * {
                    # keyword list
                    foreach word [split $remain ,] {
                        addKeyword blockData [string trim $word]
                    }
                }
                & {
                    # media attributes
                    set sel [string range $remain 0 0]
                    set remain [string range $remain 1 end]

                    if {$sel eq "0"} {
                        decode_media_options blockData $remain
                    } elseif {$sel eq "1"} {
                        o_set mediaCaption [string trim $remain]
                    }
                }

                default {
                    # unsupported (but recognized) line type
                    # This is lines of data intended for other tools; it
                    # is stored in the order it is found in the info file
                    # and written back at the end of the file.
                    storeUnsupportedLine blockData $line
                }
            } ; # end switch
        } ; # end while
        # info file existed and has been read
        close $info
    } else {
        # info file does not yet exist
        set blockData(infoTitle) \
            "Description of $blockPrefix as shown in $imgFileName"
        addBlockText blockData @ $blockData(infoTitle)
        # it's a new file
        m_set infoFileDisposition 1
    }
}

proc writeInfoFile {bvname {filename ""}} {
    upvar 1 $bvname blockData

    set baseFile [file tail $blockData(imgFile)]
    if {$filename eq ""} {
        set filename $blockData(infoFile)
    }
    if {[file exists $filename]} {
        set bakFile "[file rootname $filename].bak"
        logInfo "Renaming info file $filename to $bakFile"
        if {[catch {file rename -force $filename $bakFile} res]} {
            logWarning "Unable to rename $filename to $bakFile: $res"
        }
    }
    if {[catch {open $filename "w"} info]} {
        logWarning "Cannot open $filename for write: $info"
        return 0
    }
        
    puts $info "# Info file for $blockData(imgFile)"
    puts $info "# generated on [clock format [clock seconds]]"

    # save the keyword list at the top of the file
    saveKeywords blockData $info
        
    if {[llength $blockData(blockClass)]} {
        puts $info "# Additional classes for <div> for $baseFile"
        foreach extraClass $blockData(blockClass) {
            puts $info "^$extraClass"
        }
    }

    if {[string length $blockData(infoTitle)]} {
        puts $info "=$blockData(infoTitle)"
    }

    set sarray $blockData(blockStyle)
    upvar #0 $sarray blockStyle
    if {[array exists blockStyle] && [array size blockStyle]} {
        puts $info "# CSS styles for <div> for $baseFile"
        foreach {style value} [array get blockStyle] {
            puts $info "~$style $value"
        }
    }

    # dump media attributes that have been defined
    foreach {thing ident} {
        mediaAttributes attributes
        mediaAltText    alt-text
        mediaWidth      width
        mediaHeight     height
        mediaTitle      title
        mediaLink       link
        forceFigure     figure
    } {
        set temp [m_get $thing]
        if {$temp ne ""} {
            puts $info "&0 $ident: $temp"
        }
    }

    set temp [m_get mediaCaption]
    if {$temp ne ""} {
        puts $info "&1 $temp"
    }

    set sarray $blockData(imgStyle)
    upvar #0 $sarray imgStyle
    if {[array exists imgStyle] && [array size imgStyle]} {
        puts $info "# CSS styles for <img> in <div> for $baseFile"
        foreach {style value} [array get imgStyle] {
            puts $info "/$style $value"
        }
    }

    # dump the text blocks; the lists are inserted where they start
    foreach block $blockData(textBlocks) {
        set tail [lindex $block 0]
        set type [lindex $block 1]

        if {$type eq {}} {
            set $type @
        }
        switch -exact -- $type {
            + {
                puts $info "# ordered list"
                foreach tail $blockData(ordered) {
                    puts $info "+$tail"
                }
            }
            . {
                puts $info "# unordered list"
                foreach tail $blockData(unordered) {
                    puts $info ".$tail"
                }
            }
            # -
            ! -
            @ {
                puts $info "$type$tail"
            }
            UnKnOwN -
            () {
                puts $info $tail
            }
                
            default {
                puts $info "%$type $tail"
            }
        } ; # end of switch
    } ; # end of the textBlock dump

    # Save any other-app data
    saveUnsupportedLines blockData $info

    close $info
    return 1
}

proc setupImgInfo {imgFilePath} {
    set baseName [file tail $imgFilePath]
    set suffix [file extension $baseName]
    set blockPrefix [string map [list $suffix {} {-} { }] $baseName]
    set blockName "d-[string map {{ } {-}} $blockPrefix]"

    # now for creating the data...
    set imgBlock [blockCreate $blockName]
    upvar #0 $imgBlock blockData

    set blockData(globalData)  $imgBlock
    set blockData(imgFile)     $imgFilePath
    set blockData(baseName)    $baseName
    set blockData(imgSuffix)   $suffix
    set blockData(blockPrefix) $blockPrefix

    # Load the existing info file data
    loadInfoFile blockData

    return $imgBlock
}

# Make a new font that is based on an existing one
proc makeSimilarFont {orig new args} {
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

proc undock_panels {args} {
    if {![m_get panelsUndocked]} {
        set editWin [edit_w editWindow]
        set mediaWin [edit_w imageWindow]
        set treeWin [edit_w treeWindow]
        set title [wm title [edit_w mainWindow]]
        grid forget $editWin
        wm manage $editWin
        $editWin configure -menu [edit_w editMainMenu]
        grid forget $mediaWin
        wm manage $mediaWin
        $mediaWin configure -menu [edit_w imageMainMenu]
        grid forget $treeWin
        wm manage $treeWin
        wm title $editWin $title
        wm title $mediaWin [file tail [m_get currentMediaFile]]
        wm title $treeWin {Media Selector}

        m_set panelsUndocked 1
        set winMenu [edit_w windowMenu]
        $winMenu entryconfigure "Undock*" -state disabled
        $winMenu entryconfigure "Dock*" -state normal
    }
}

proc dock_panels {args} {
    if {[m_get panelsUndocked]} {
        set editWin [edit_w editWindow]
        set mediaWin [edit_w imageWindow]
        set treeWin [edit_w treeWindow]
        wm forget $mediaWin
        wm forget $editWin
        wm forget $treeWin
        grid $mediaWin -row 3 -column 0 -sticky news
        grid $editWin  -row 3 -column 2 -sticky news -rowspan 3
        grid $treeWin -row 5 -column 0 -sticky news
        m_set panelsUndocked 0
        set winMenu [edit_w windowMenu]
        $winMenu entryconfigure "Undock*" -state normal
        $winMenu entryconfigure "Dock*" -state disabled
    }
}
    
namespace eval ::MetaEdit {
    variable builtinKeywords {
        easy hard medium
    }
}

# "tooltip" help messages

set editTTip(blockTitle) \
    "String to be used in headings and captions for this block"
set editTTip(blockTitleL) $editTTip(blockTitle)
set editTTip(blockClass) \
    {Space separated list of extra CSS class names
to be inserted in class list for <div>}
set editTTip(blockClassL) $editTTip(blockClass)
set editTTip(blockStyle) {Additional style entries for the <div>}
set editTTip(imgStyle) {Additional style entries for the <img> (or <figure>)}
set editTTip(blockText)  {Text content of block for the current image}
#set editTTip(openButton) {Select an image file}
set editTTip(saveButton) {Save data to current "info" file}
#set editTTip(saveAsButton) {Write the current edit data to a chosen file}
#set editTTip(closeButton) {Exit the application}
set editTTip(imageLabel) {The image corresponding to the data}
set editTTip(busyLabel)  {This operation can be slow,\nplease wait...}
set editTTip(useAltInfoDir) {When selected, the info files are read
    and written from a specific directory}
set editTTip(infoDirButton) {Set the alternate info file directory}
set editTTip(infoDirEntry) {Enter the alternate info file directory path}
set editTTip(addNewKeyword) \
    {Copy the keyword entry on the right\ninto the active keyword list}
set editTTip(copyKeyword) \
    {Copy keyword(s) selected\nfrom the list on the left\ninto the active keyword list}
set editTTip(keepKeyword) \
    {Copy selected keyword from active list to\nthe available list (on the left)}
set editTTip(unkeepKeyword) \
    {Remove selected keyword(s) from the left side keyword list}
set editTTip(deleteKeyword) \
    {Remove the selected keyword\nfrom the active keyword list}
set editTTip(knownKeywordList) {A list of known keywords to select from}
set editTTip(newKeywordEntry) {Entry for new keywords}
set editTTip(keywordList) {List of active keywords}
#set editTTip(showTooltips) "Enable tooltips"

# For the entries in the Alt-key section
set editTTip(normal) "Normal text\nLeft-click to select\nKB: ALT+n"
set commonSel "\nLeft-Click to select\nMiddle-Click to clear\nKB: ALT+"
set editTTip(ole) "Ordered list entry text${commonSel}o"
set editTTip(ule) "Unordered list entry text${commonSel}u"
set editTTip(raw) "Raw text line${commonSel}r"
set editTTip(alt1) "Alternate HTML class name 1${commonSel}1"
set editTTip(alt2) "Alternate HTML class name 2${commonSel}2"
set editTTip(alt3) "Alternate HTML class name 3${commonSel}3"
set editTTip(alt4) "Alternate HTML class name 4${commonSel}4"
unset commonSel


# A list of fonts to try for the "busy" message
set busy_font_list {
    {{Poor Richard} 40}
    {{Courier Code} 30}
    {{David Libre} 30}
    {Helvetica 30 bold}
    {{Lucida Calligraphy} 30}
    {{Monotype Corsiva} 30}
    {{Lucida Handwriting} 30}
    {{OCR A Extended} 30}
    {{Old English Text MT} 30}
    {Onyx 35}
    {Garamond 30}}

# Ordered list bullet bitmap definition
set ol_bitmap_fg {
    #define ol_width 11
    #define ol_height 9
    static char ol_bits[] = {
        0x00, 0x00,
        0xfc, 0x01,
        0xfc, 0x01,
        0x8c, 0x01,
        0x8c, 0x01,
        0x8c, 0x01,
        0xfc, 0x01,
        0xfc, 0x01,
        0x00, 0x00
    }
}

# Unordered list bullet bitmap definition
set ul_bitmap_fg {
    #define ul_width 11
    #define ul_height 9
    static char ul_bits[] = {
        0x00,0x00,
        0x00,0x00,
        0x70,0x00,
        0xf8,0x00,
        0xf8,0x00,
        0xf8,0x00,
        0x70,0x00,
        0x00,0x00,
        0x00,0x00
    }
}

set la_bitmap_fg {
    #define bullet_width 24
    #define bullet_height 16
    static char bullet_bits = {
        0x00, 0x00, 0x00,
        0x00, 0x02, 0x00,
        0x00, 0x03, 0x00,
        0x80, 0x03, 0x00,
        0xc0, 0x03, 0x00,
        0xe0, 0xff, 0x0f,
        0xf0, 0xff, 0x0f,
        0xf8, 0xff, 0x0f,
        0xf0, 0xff, 0x0f,
        0xe0, 0xff, 0x0f,
        0xc0, 0x03, 0x00,
        0x80, 0x03, 0x00,
        0x00, 0x03, 0x00,
        0x00, 0x02, 0x00,
        0x00, 0x00, 0x00,
        0x00, 0x00, 0x00
    }
}

set ra_bitmap_fg {
    #define bullet_width 24
    #define bullet_height 16
    static char bullet_bits = {
        0x00, 0x00, 0x00,
        0x00, 0x40, 0x00,
        0x00, 0xc0, 0x00,
        0x00, 0xc0, 0x01,
        0x00, 0xc0, 0x03,
        0xf0, 0xff, 0x07,
        0xf0, 0xff, 0x0f,
        0xf0, 0xff, 0x1f,
        0xf0, 0xff, 0x0f,
        0xf0, 0xff, 0x07,
        0x00, 0xc0, 0x03,
        0x00, 0xc0, 0x01,
        0x00, 0xc0, 0x00,
        0x00, 0x40, 0x00,
        0x00, 0x00, 0x00,
        0x00, 0x00, 0x00
    }
}

set del_bitmap_fg {
#define remove_width 16
#define remove_height 16
static char remove_bits = {
    0xf0, 0x07,   0xf0, 0x07,
    0xf0, 0x07,   0xf0, 0x07,
    0xf0, 0x07,   0xf0, 0x07,
    0xf0, 0x07,   0xf0, 0x07,
    0xff, 0x7f,   0xfe, 0x3f,
    0xfc, 0x1f,   0xf8, 0x0f,
    0xf0, 0x07,   0xe0, 0x03,
    0xc0, 0x01,   0x80, 0x00}
}

set animControlBitmaps(pause,bm) {
    #define pause_width 24
    #define pause_height 9
    static char pause_bits = {
        0x00, 0xc6, 0x00, 0x00, 0xc6, 0x00, 0x00, 0xc6, 0x00,
        0x00, 0xc6, 0x00, 0x00, 0xc6, 0x00, 0x00, 0xc6, 0x00,
        0x00, 0xc6, 0x00, 0x00, 0xc6, 0x00, 0x00, 0xc6, 0x00
    }
}
set animControlBitmaps(play,bm) {
    #define play_width 24
    #define play_height 9
    static char play_bits = {
        0x00, 0x03, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x3f, 0x00,
        0x00, 0xff, 0x00, 0x00, 0xff, 0x01, 0x00, 0xff, 0x00,
        0x00, 0x3f, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x03, 0x00
    }
}
set animControlBitmaps(resume,bm) {
    #define start_width 24
    #define start_height 9
    static char start_bits = {
        0x00, 0x03, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x3f, 0x00,
        0x00, 0xf3, 0x00, 0x00, 0xe3, 0x01, 0x00, 0xf3, 0x00,
        0x00, 0x3f, 0x00, 0x00, 0x0f, 0x00, 0x00, 0x03, 0x00
    }
}
set animControlBitmaps(next,bm) {
    #define next_width 24
    #define next_height 9
    static char next_bits = {
        0xc0, 0x0c, 0x00, 0xc0, 0x3c, 0x00, 0xc0, 0xf0, 0x00,
        0xc0, 0xc0, 0x03, 0xc0, 0x80, 0x07, 0xc0, 0xc0, 0x03,
        0xc0, 0xf0, 0x00, 0xc0, 0x3c, 0x00, 0xc0, 0x0c, 0x00
    }
}
set animControlBitmaps(blank,bm) {
    #define blank_width 24
    #define blank_height 9
    static char blank_bits = {
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    }
}

# Some information in place of real documentation:
#
# For each selected image file, the script looks for a file with the same
# root name and the extension ".txt". If this file exists, it is read into
# a global data array for the image/media file.
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
# Any line in the file that does not begin with one of the above characters
# is ignored (actually, it's reported, but not used otherwise).
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

# Immediate stuff to do before staring the application
# (more initialization)

if {[info exists ol_icn] && $ol_icn ne ""} {
    image delete $ol_icn
}
if {[info exists ul_icn] && $ul_icn ne ""} {
    image delete $ul_icn
}
if {[info exists la_icn] && $la_icn ne ""} {
    image delete $la_icn
}
if {[info exists ra_icn] && $ra_icn ne ""} {
    image delete $ra_icn
}
if {[info exists del_icn] && $del_icn ne ""} {
    image delete $del_icn
}

set ol_icn {}
set ul_icn {}
set la_icn {}
set ra_icn {}
set del_icn {}

# set up the media file type support
initBrowseSupport

if {![info exists browse_image]} {
    browse_reset
} elseif {![info exists browse_settings(cwd)]} {
    b_set cwd [pwd]
}

puts stderr "Got to the check for interactive"

# Run this from the shell or a window
# but not from a tclsh/wish/tkcon session
if {[file tail $argv0] eq "meta-edit-ext.tcl"} {
    puts stderr "Got into the non-interactive code"
    setLogMode 1

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

    if {[file exists .meta-edit.rc]} {
	source .meta-edit.rc
    }
    puts stderr "About to show the main window"

    browse_show_main .

    if {[info proc metaEditCustom] ne ""} {
        metaEditCustom
    }
}

puts stderr "Got to end of the script"

# Local Variables:
# mode: tcl
# End:
