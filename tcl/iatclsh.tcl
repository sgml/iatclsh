#!/usr/bin/tclsh8.5

#
# iatclsh.tcl
#
package require Tk
source [file dirname [file normalize [info script]]]/PrefsDlg.tcl

namespace eval iatclsh {    
    variable exports [list \
            slaveInterpVarChange \
            cmd stop start \
            isStatusBarHidden showStatusBar hideStatusBar \
            setStatusLeft setStatusRight getBusyString \
            addAction addCBAction addRBAction addSeparator] 
            
    # bgScript and userScript are for holding the background and user script
    # filenames
    variable bgScript ""
    variable userScript ""

    # recent user and background scripts 
    variable recentUserScripts [list]
    variable recentBgScripts [list]

    # fd is the file descriptor for the pipe to the tclsh 
    variable fd ""

    # appIf is the path to the app_if.tcl script
    variable appIf [file dirname [file normalize [info script]]]/app_if.tcl

    # for log and command history: cmdHistory is a list where the interactive
    # commands are stored; historyIndex is an index into cmdHistory; 
    # currentEditCmd is a store for an interactive command currently being
    # typed
    variable cmdHistory [list]
    variable historyIndex 0
    variable currentEditCmd ""

    # for running interactive/background commands: cmdLine is the variable 
    # associated with the command line entry widget; bgRxBuf is a buffer for 
    # holding the result of running a background command; bgCmdComplete 
    # indicates that a background command has run and completed; inBgCmd
    # indicates background command is executing.
    variable cmdLine ""
    variable bgRxBuf ""    
    variable bgCmdComplete 0
    variable inBgCmd 0

    # for backgound script: retartAppIfScheduled indicates that app interface
    # is scheduled for reload; reloadBgScriptScheduled indicates that
    # the background script has been scheduled for reload; bgScriptOk indicates 
    # that a background script has been loaded ok; bgInterp is the interpreter 
    # used for running background scripts
    variable restartAppIfScheduled 0 
    variable reloadBgScriptScheduled 0
    variable bgScriptOk 1 
    variable bgInterp ""
    
    # for run command: running indicates that the run command is running or 
    # scheduled to run; inRunCycle indicates that the run command is part way
    # through executing; stopRun indicates that the run procedure should stop
    variable running 0
    variable inRunCycle 0
    variable stopRun 0

    # for user interface relating to background script: subMenuCount holds 
    # count of menus added to Actions menu; traces maps Action menu variables
    # to procedures to run when they change; statusHidden controls whether 
    # the status bar is hidden
    variable subMenuCount 0
    variable traces [dict create]
    variable statusHidden 1
    
    # for busy string: busyCount keeps track of the current position in the
    # busy string sequence; busyTime records the time of the last sequence 
    # update
    variable busyCount 0
    variable busyTime [clock milliseconds]
    
    # user preferences
    variable prefs [dict create scrollLines 5000 historySize 100 \
            showScrollbar 0 showCombobox 0 changeDir 1]

    # parse command line arguments. Returns "" if command line parsed 
    # successfully, otherwise returns an error message string
    proc parseCmdLineArgs {} {
        global argc argv 
        variable userScript  
        set i 0
        while {$i < $argc} {
            set t [lindex $argv $i]
            if {[regexp {^-} $t]} {
                if {$t == "-bg"} {
                    incr i
                    if {$i >= $argc} {
                        return "command line parameter error"

                    }
                    set f [file normalize [lindex $argv $i]]
                    if {[file exists $f] && [file isfile $f]} {
                        setBgScript $f
                    } else {
                        return "background script filename error"
                    }
                    incr i
                } else {
                    return "command line parameter error"
                }
            } else {
                if {$userScript == ""} {
                    set f [file normalize $t]
                    if {[file exists $f] && [file isfile $f]} {
                        setUserScript $f
                    } else {
                        return "user script filename error"
                    }
                } else {
                    return "command line parameter error"
                }
                incr i
            }
        }
        return
    }

    # set user script and add to recent user scripts
    proc setUserScript {s} {
        variable userScript
        set userScript $s
        appendRecentUserScripts $s
    }

    # append filename to recent user scripts, with a maximum length of four
    proc appendRecentUserScripts {filename} {
        variable recentUserScripts
        set index [lsearch -exact $recentUserScripts $filename]
        if {$index == -1} {
            lappend recentUserScripts $filename
        } else {
            set recentUserScripts [lreplace $recentUserScripts $index $index]
            lappend recentUserScripts $filename
        }
        if {[llength $recentUserScripts] > 4} {
            set recentUserScripts [lrange $recentUserScripts end-3 end]
        }
    }

    # set background script and add to recent background scripts
    proc setBgScript {s} {
        variable bgScript
        set bgScript $s
        appendRecentBgScripts $s
    }

    # append filename to recent background scripts, with a maximum length of 
    # four
    proc appendRecentBgScripts {filename} {
        variable recentBgScripts
        set index [lsearch -exact $recentBgScripts $filename]
        if {$index == -1} {
            lappend recentBgScripts $filename
        } else {
            set recentBgScripts [lreplace $recentBgScripts $index $index]
            lappend recentBgScripts $filename
        }
        if {[llength $recentBgScripts] > 4} {
            set recentBgScripts [lrange $recentBgScripts end-3 end]
        }
    }

    # open pipe to app interface and source any user file 
    proc startAppIf {} {
        variable fd 
        variable userScript
        variable appIf
        variable prefs
        set exe [info nameofexecutable]
        set fd [open "|$exe $appIf" r+]
        chan configure $fd -blocking 0
        chan event $fd readable ::iatclsh::readPipe
        if {$userScript != ""} {
            if {[dict get $prefs changeDir]} {
                puts -nonewline $fd "cd [file dirname $userScript]; "
                puts $fd "source [file tail $userScript]"
            } else {
                puts $fd "source $userScript"
            }
            flush $fd
        } 
    }
   
    # event handler for reading pipe
    proc readPipe {} {
        variable fd
        variable inBgCmd
        variable bgCmdComplete
        variable bgRxBuf
        set r [read $fd]
        if {[eof $fd]} {
            closeApp
        }
        while {$r != ""} {
            if {$inBgCmd} {
                set i [string first "\x03" $r]
                if {$i == -1} {
                    append bgRxBuf $r
                    break
                } else {
                    append bgRxBuf [string range $r 0 $i-1]
                    set bgCmdComplete 1
                    set inBgCmd 0
                    set r [string range $r $i+1 end]
                }
            } else {
                set i [string first "\x02" $r]
                if {$i == -1} {
                    processRxMsg $r 
                    update idletasks
                    break
                } else {
                    if {$i > 0} {
                        processRxMsg [string range $r 0 $i-1] 
                        update idletasks
                        set r [string range $r $i+1 end]
                    } else {
                        set r [string range $r 1 end]
                    }
                    set inBgCmd 1
                }
            }
        }
    }
   
    # process received interactive messages
    proc processRxMsg {str} {
        while {$str != ""} {
            set i [string first "\x11" $str]
            set j [string first "\x04" $str]
            if {$i != -1 && (($i < $j) || ($j == -1))} {
                clearLog
                set str [string range $str $i+1 end]
            } elseif {$j != -1} {
                appendLog [string range $str 0 $j-1] response
                appendLog "% " command
                set str [string range $str $j+1 end]
            } else {
                appendLog $str response
                break
            }
        }
    }

    # append string str to text widget log, with supplied tag 
    proc appendLog {str tag} {
        .log configure -state normal
        .log insert end $str $tag
        trimLog
        .log configure -state disabled
        .log see end
    }
    
    # trim log to a maximum of lines set in user preferences
    proc trimLog {} {
        variable prefs
        set max [dict get $prefs scrollLines]
        set lines [.log count -lines 0.0 end]
        set deleteTo [expr {$lines - $max + 1}]
        if {$deleteTo > 0} {
            .log delete 1.0 $deleteTo.0    
        }
    }
    
    # remove all lines from log
    proc clearLog {} {
        .log configure -state normal
        .log delete 1.0 end
        .log configure -state disabled
    }
    
    # post interactive command 
    proc postIaCmd {} {
        variable cmdLine
        variable cmdHistory 
        variable historyIndex 
        variable prefs         
        variable fd 
        set cmd [string trim $cmdLine]
        set cmdLine ""
        if {$cmd != ""} {
            appendLog "$cmd\n" command
            if {$cmd != [lindex $cmdHistory end]} {
                lappend cmdHistory $cmd
                if {[llength $cmdHistory] > [dict get $prefs historySize]} {
                    set cmdHistory [lreplace $cmdHistory 0 0]
                }
                updateComboBox
            }
            set historyIndex [llength $cmdHistory]
        } else {
            appendLog "\n" command
        }
        puts $fd "$cmd"
        flush $fd
    }
   
    # sets command line entry widget, based on current historyIndex and dir.
    # dir may be up or down.
    proc setCmdLine {dir} {
        variable cmdHistory
        variable historyIndex
        variable cmdLine
        variable currentEditCmd
        if {$dir == "up"} {
            if {$historyIndex > 0} {
                if {$historyIndex == [llength $cmdHistory]} {
                    set currentEditCmd $cmdLine   
                }
                incr historyIndex -1
                set cmdLine [lindex $cmdHistory $historyIndex]
                .cmdEntry icursor end
            }
        } elseif {$historyIndex < [llength $cmdHistory]} {
            incr historyIndex
            if {$historyIndex == [llength $cmdHistory]} {
                set cmdLine $currentEditCmd
            } else {
                set cmdLine [lindex $cmdHistory $historyIndex]
            }
            .cmdEntry icursor end                             
        }
    }
    
    # called when app is closing, either due to exit command or window close
    # button pressed
    proc closeApp {} {
        variable fd
        closeAppIf
        saveHistory
        executeClosing 
        exit 0
    }

    proc closeAppIf {} {
        global tcl_platform
        variable fd
        set fdPid [pid $fd]
        close $fd
        after 100
        if {$tcl_platform(os) == "Linux"} {
            iatclsh::kill $fdPid
        }
    }
    
    # load command history from ~/.iatclsh file
    proc loadHistory {} {
        variable cmdHistory
        variable recentUserScripts
        variable recentBgScripts
        variable historyIndex
        variable prefs
        set f [open "~/.iatclsh" r]
        while {1} {
            gets $f s
            if {[eof $f]} {
                break
            }
            if {[string first "cmd:" $s] == 0} {
                lappend cmdHistory [string range $s 5 end]
            }
            if {[string first "rus:" $s] == 0} {
                set rus [string range $s 5 end]
                if {[lsearch -exact $recentUserScripts $rus] == -1} {
                    lappend recentUserScripts $rus
                }
            }
            if {[string first "rbg:" $s] == 0} {
                set rbg [string range $s 5 end]
                if {[lsearch -exact $recentBgScripts $rbg] == -1} {
                    lappend recentBgScripts $rbg
                }
            }
            if {[string first "pref:" $s] == 0} {
                set l [string range $s 6 end]
                set key [lindex $l 0]
                set value [lindex $l 1]
                dict set prefs $key $value
            }
        }
        set historyIndex [llength $cmdHistory]
        close $f
    }

    # save command history to ~./iatclsh file
    proc saveHistory {} {
        variable cmdHistory
        variable recentUserScripts
        variable recentBgScripts
        variable prefs
        if {[lindex $cmdHistory end] == "exit"} {
            set cmdHistory [lreplace $cmdHistory end end]   
        }
        set f [open "~/.iatclsh" w]
        foreach cmd $cmdHistory {
            puts $f "cmd: $cmd"   
        }
        foreach s $recentUserScripts {
            puts $f "rus: $s"   
        }
        foreach s $recentBgScripts {
            puts $f "rbg: $s"   
        }
        foreach k [dict keys $prefs] {
            puts $f "pref: [list $k [dict get $prefs $k]]"
        }
        close $f
    }

    # sends command and returns all response from background command
    proc cmd {args} {
        variable bgRxBuf 
        variable fd
        set bgRxBuf ""
        puts $fd "\x02$args"; flush $fd
        vwait ::iatclsh::bgCmdComplete
        regexp {(.*?)(\n)?$} $bgRxBuf match line
        return $line
    }

    proc isStatusBarHidden {} {
        variable statusHidden
        return $statusHidden
    }

    proc showStatusBar {} {
        variable statusHidden
        if {$statusHidden} {
            set statusHidden 0
            grid .status
        }
    }
    
    proc hideStatusBar {} {
        variable statusHidden
        if {!$statusHidden} {
            set statusHidden 1
            grid remove .status
        }
    }

    # set status bar left label
    proc setStatusLeft {str} {
        variable statusLeft
        if {[isStatusBarHidden]} {
            showStatusBar 
        }
        set statusLeft $str    
    }
    
    # set status bar right label
    proc setStatusRight {str} {
        variable statusRight
        if {[isStatusBarHidden]} {
            showStatusBar 
        }
        set statusRight $str
    }

    # diaplay menu bar for actions menu
    proc displayMenuBar {} {
        .mbar add cascade -label Actions -menu .mbar.actions -underline 0
        . configure -menu .mbar
    }

    # add command to action menu
    proc addAction {label command} {
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        .mbar.actions add command -label $label \
                -command "$::iatclsh::bgInterp eval $command"
    }
    
    # add check box actions to action menu
    proc addCBAction {label var args} {
        variable bgInterp
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        global shadow_$var
        set shadow_$var [$bgInterp eval set ::$var] 
        .mbar.actions add checkbutton -label $label -variable shadow_$var
        set command [getActionParam "-command" {*}$args]
        addVariableTraces $var $command
    }

    # add radio button actions to action menu
    proc addRBAction {labels var args} {
        variable bgInterp
        if {[. cget -menu] == ""} {
            displayMenuBar
        }
        set m .mbar.actions
        set subMenuLabel [getActionParam "-submenu" {*}$args]
        if {$subMenuLabel != ""} {
            set tail [getSubMenuTail]
            $m add cascade -label $subMenuLabel -menu $m.$tail
            menu $m.$tail
            set m $m.$tail
        } 
        global shadow_$var
        set shadow_$var [$bgInterp eval set ::$var] 
        foreach label $labels {
            $m add radiobutton -label $label -variable shadow_$var
        }
        set command [getActionParam "-command" {*}$args]
        addVariableTraces $var $command
    }

    # add separator to actions menu
    proc addSeparator {} {
        .mbar.actions add separator
    }

    # get unique tail for submenu
    proc getSubMenuTail {} {
        variable subMenuCount
        incr subMenuCount
        return $subMenuCount
    }

    # parse variable args supplied to action commands for a specific parameter
    proc getActionParam {param args} {
        for {set i 0} {$i < [llength $args]} {incr i} {
            if {[lindex $args $i] == $param} {
                incr i
                return [lindex $args $i]
            }
        }
        return "" 
    }

    # add traces to an action variable, both slave and shadow
    proc addVariableTraces {var command} {
        global shadow_$var
        variable bgInterp
        variable traces
        dict set traces shadow_$var $command
        trace add variable shadow_$var write iatclsh::variableTrace
        $bgInterp eval trace add variable ::$var write slaveInterpVarChange
    }

    # for managing slave variables and calling check-box and radio-button 
    # action commands
    proc variableTrace {name element op} {
        variable traces
        variable bgInterp
        set command [dict get $traces $name]
        set slaveName [string range $name 7 end]
        set val [eval set ::$name]
        $bgInterp eval set $slaveName $val
        if {$command != ""} {
            $bgInterp eval $command
        }
    }

    # called when a variable is changed in the slave interpreter that is also
    # used in the Actions menu
    proc slaveInterpVarChange {name element op} {
        variable bgInterp
        global shadow_$name
        set shadow_$name [$bgInterp eval set ::$name] 
    }

    # stop executing run procedure
    proc stop {} {
        variable stopRun
        set stopRun 1
    }
    
    # start executing run procedure 
    proc start {} {
        variable stopRun
        variable running
        if {!$running} {
            set stopRun 0
            executeRun
        } 
    }

    # returns next phase in a sequence of strings. If period is supplied, next
    # phase is provided only if time difference since last successful call 
    # exceeds period
    proc getBusyString {{period ""}} {
        variable busyCount
        variable busyTime
        if {$period == "" || [clock milliseconds] - $busyTime > $period} {
            incr busyCount
            if {$busyCount == 4} {
                set busyCount 0
            }
            set busyTime [clock milliseconds]
        }
        switch $busyCount {
            0 {return "|"}
            1 {return "/"}
            2 {return "-"}
            3 {return "\\"}
        }
    }

    # gui
    proc buildGui {} {

        # components
        text .log -background black -yscrollcommand ".sb set"
        ttk::scrollbar .sb -command ".log yview"
        ttk::entry .cmdEntry -textvariable iatclsh::cmdLine
        ttk::combobox .cmdCombobox -textvariable iatclsh::cmdLine
        ttk::frame .status
        ttk::label .status.left -justify left -textvariable iatclsh::statusLeft
        ttk::label .status.right -justify right \
                -textvariable iatclsh::statusRight
        option add *Menu.tearOff 0
        menu .mbar
        menu .mbar.actions
        menu .puMenu
        menu .puMenu.recentUserScriptsMenu
        menu .puMenu.recentBgScriptsMenu

        # pop up menu
        .puMenu add command -label "Load User Script..." \
                -command iatclsh::loadUserScriptUIEvent
        .puMenu add command -label "Load Background Script..." \
                -command iatclsh::loadBgScriptUIEvent
        .puMenu add separator
        .puMenu add cascade -label "Recent User Scripts" \
                -menu .puMenu.recentUserScriptsMenu
        .puMenu add cascade -label "Recent Background Scripts" \
                -menu .puMenu.recentBgScriptsMenu
        .puMenu add separator
        .puMenu add command -label "Reset tclsh" \
                -command iatclsh::resetTclshUIEvent
        .puMenu add command -label "Unload Background Script" \
                -command iatclsh::unloadBgScriptUIEvent
        .puMenu add separator
        .puMenu add command -label "Clear" -command {
            ::iatclsh::clearLog
            ::iatclsh::appendLog "% " command
        }            
        .puMenu add separator
        .puMenu add command -label "Preferences..." \
                -command {iatclsh::PrefsDlg::showPrefsDlg $iatclsh::prefs}

        # configure log
        .log configure -state disabled 
        .log tag configure command -foreground green
        .log tag configure response -foreground lightgrey

        # bindings
        bind .cmdEntry <Return> {::iatclsh::postIaCmd}
        bind .cmdEntry <Up> {::iatclsh::setCmdLine up}
        bind .cmdEntry <Down> {::iatclsh::setCmdLine dn}
        bind .log <ButtonPress-3> {tk_popup .puMenu %X %Y}
        bind .cmdCombobox <Return> {::iatclsh::postIaCmd}

        # layout 
        grid .log -row 0 -column 0 -sticky nsew
        grid .sb -row 0 -column 1 -sticky ns
        grid .cmdEntry -row 1 -column 0 -columnspan 2 -sticky ew 
        grid .cmdCombobox -row 2 -column 0 -columnspan 2 -sticky ew 
        grid .status -row 3 -column 0 -columnspan 2 -pady {5 0} -sticky ew
        grid columnconfigure . 0 -weight 1
        grid rowconfigure . 0 -weight 1
        grid .status.left -row 0 -column 0 -sticky nw  
        grid .status.right -row 0 -column 1 -sticky ne
        grid columnconfigure .status 0 -weight 1                       
        grid remove .status
        grid remove .sb
        wm protocol . WM_DELETE_WINDOW ::iatclsh::closeApp 
        wm title . "iatclsh"
        grid remove .cmdCombobox
        focus .cmdEntry
    }
 
    # update gui state based on state of program
    proc updateGuiState {} {
        variable userScript
        variable bgScript
        variable restartAppIfScheduled 
        variable reloadBgScriptScheduled 

        # load user script popup menu state
        if {$restartAppIfScheduled} {
            .puMenu entryconfigure "Load User Script..." -state disabled
        } else {
            .puMenu entryconfigure "Load User Script..." -state normal
        }

        # load background script popup menu state
        if {$reloadBgScriptScheduled} {
            .puMenu entryconfigure "Load Background Script..." -state disabled
        } else {
            .puMenu entryconfigure "Load Background Script..." -state normal
        }

        # unload background script popup menu state
        if {$bgScript == ""} {
            .puMenu entryconfigure "Unload Background Script" -state disabled
        } else {
            .puMenu entryconfigure "Unload Background Script" -state normal
        }

        # recent user scripts menu state
        if {[.puMenu.recentUserScriptsMenu index end] == "none"} {
            .puMenu entryconfigure "Recent User Scripts" -state disabled
        } else {
            .puMenu entryconfigure "Recent User Scripts" -state normal
        }

        # recent background scripts menu state
        if {[.puMenu.recentBgScriptsMenu index end] == "none"} {
            .puMenu entryconfigure "Recent Background Scripts" -state disabled
        } else {
            .puMenu entryconfigure "Recent Background Scripts" -state normal
        }

        # menu bar state
        if {$reloadBgScriptScheduled} {
            if {[. cget -menu] == ".mbar"} {
                .mbar entryconfigure "Actions" -state disabled
            }
        } else {
            if {[. cget -menu] == ".mbar"} {
                .mbar entryconfigure "Actions" -state normal
            }
        }

        # set main window title bar 
        if {$userScript == ""} {
            wm title . "iatclsh"
        } else {
            wm title . "iatclsh - [file tail $userScript]"    
        }
    }

    # update combobox from history 
    proc updateComboBox {} {
        variable cmdHistory 
        variable prefs          
        set max [dict get $prefs historySize]
        set i [expr {[llength $cmdHistory] - $max - 1}]
        set cmds [lrange $cmdHistory $i end]
        set revCmds ""
        for {set i [expr {[llength $cmds] - 1}]} {$i >= 0} {incr i -1} {
            lappend revCmds [lindex $cmds $i]
        }
        .cmdCombobox configure -values $revCmds
    }

    # update entries for recent user scripts menu
    proc updateRecentUserScriptsMenu {} {
        variable recentUserScripts
        .puMenu.recentUserScriptsMenu delete 0 end
        foreach s $recentUserScripts {
            .puMenu.recentUserScriptsMenu insert 0 command \
                    -label [file tail $s] \
                    -command [list ::iatclsh::recentUserScriptUIEvent $s]
        }
    }

    # update entries for recent background scripts menu
    proc updateRecentBgScriptsMenu {} {
        variable recentBgScripts
        .puMenu.recentBgScriptsMenu delete 0 end
        foreach s $recentBgScripts {
            .puMenu.recentBgScriptsMenu insert 0 command \
                    -label [file tail $s] \
                    -command [list ::iatclsh::recentBgScriptUIEvent $s]
        }
    }

    # callback for preferences dialog ok button
    proc prefsOkAction {updatedPrefs} {
        variable cmdHistory
        variable historyIndex
        variable prefs 
        set prefs $updatedPrefs
        
        # scroll lines
        set l [dict get $prefs scrollLines]
        if {$l < 200} {
            set l 200 
            dict set prefs scrollLines 200
        }
        .log configure -state normal
        trimLog
        .log configure -state disabled
        .log see end

        # command history size
        set s [dict get $prefs historySize]
        if {$s < 5} {
            set s 5 
            dict set prefs historySize 5
        }
        if {[llength $cmdHistory] > $s} {
            incr s -1
            set cmdHistory [lrange $cmdHistory end-$s end]
            set historyIndex [llength $cmdHistory]
        }

        # show scrollbar
        if {[dict get $prefs showScrollbar]} {
            grid .sb
        } else {
            grid remove .sb
        }

        # show combobox
        if {[dict get $prefs showCombobox]} {
            grid remove .cmdEntry
            grid .cmdCombobox
            focus .cmdCombobox
        } else {
            grid remove .cmdCombobox
            grid .cmdEntry
            focus .cmdEntry
        }
    }

    # present a file open dialog and load user script if one is chosen
    proc loadUserScriptUIEvent {} {
        set f [tk_getOpenFile -filetypes {{Tcl .tcl} {All *}}]
        if {$f == ""} {
            return
        }
        setUserScript [file normalize $f]
        updateRecentUserScriptsMenu
        restartAppIfRequest
    }

    # present a file open dialog and load background script if one is chosen
    proc loadBgScriptUIEvent {} {
        set f [tk_getOpenFile -filetypes {{Tcl .tcl} {All *}}]
        if {$f == ""} {
            return
        }
        setBgScript [file normalize $f]
        updateRecentBgScriptsMenu
        loadBgScriptRequest
    }

    # recent user script file selected from recent user files menu
    proc recentUserScriptUIEvent {filename} {
        setUserScript $filename
        updateRecentUserScriptsMenu
        restartAppIfRequest
    }

    # recent background script file selected from recent background files menu
    proc recentBgScriptUIEvent {filename} {
        setBgScript $filename
        updateRecentBgScriptsMenu
        loadBgScriptRequest
    }

    # load user script, either immediately if a background command isn't
    # running, otherwise schedule reload for when background command completes
    proc restartAppIfRequest {} {
        variable restartAppIfScheduled 
        variable inRunCycle
        if {$inRunCycle == 0} {
            restartAppIf
        } else {
            set restartAppIfScheduled 1
        }
        updateGuiState
    }

    # load background script, either immediately if a background command
    # isn't running, otherwise schedule reload for when background command 
    # completes
    proc loadBgScriptRequest {} {
        variable reloadBgScriptScheduled 1
        variable inRunCycle
        if {$inRunCycle == 0} {
            reloadBgScript
        } else {
            set reloadBgScriptScheduled 1
            updateGuiState
        }
    }

    # reset tclsh
    proc resetTclshUIEvent {} {
        variable fd
        variable restartAppIfScheduled 
        variable userScript
        variable bgRxBuf
        variable bgCmdComplete
        variable cmdLine
        closeAppIf
        set restartAppIfScheduled 0
        set userScript ""
        set bgRxBuf "\n"
        set bgCmdComplete 1
        set cmdLine ""
        startAppIf
    }

    # unload background script 
    proc unloadBgScriptUIEvent {} {
        variable bgScript 
        variable reloadBgScriptScheduled 
        variable running
        variable inRunCycle
        variable stopRun
        shutdownBgScriptUi
        set bgScript ""
        set reloadBgScriptScheduled 0
        set running 0
        set inRunCycle 0
        set stopRun 1
        updateGuiState 
    }

    # clear any pending interactive command and restart app i/f
    proc restartAppIf {} {
        variable fd
        variable restartAppIfScheduled 
        variable cmdLine
        closeAppIf
        set restartAppIfScheduled 0
        set cmdLine ""
        startAppIf 
    }
   
    # reload background script
    proc reloadBgScript {} {
        variable reloadBgScriptScheduled 
        variable bgScriptOk
        variable running
        variable stopRun
        set reloadBgScriptScheduled 0
        updateGuiState
        shutdownBgScriptUi
        set bgScriptOk [loadBgScript]
        if {$bgScriptOk} {
            set stopRun 0
            if {[executeInitialise]} {
                if {$running == 0} {
                    executeRun
                } 
            } else {
                set stopRun 1
            }
        } else {
            set stopRun 1
        }
    }

    # shutdown background script user interface, i.e. menubar and statusbar
    proc shutdownBgScriptUi {} {
        variable traces
        variable bgInterp
        if {$bgInterp == ""} {
            return
        }
        executeClosing
        setStatusRight ""
        setStatusLeft ""
        hideStatusBar
        . configure -menu ""
        destroy .mbar.actions
        destroy .mbar
        menu .mbar
        menu .mbar.actions
        . configure -menu 
        interp delete $bgInterp
        set bgInterp ""
        foreach var [dict keys $traces] {
            unset ::$var
        }
        set traces ""
    }

    # load background script. Returns 1 if successful, 0 otherwise.
    proc loadBgScript {} {
        variable exports
        variable bgInterp
        set bgInterp [interp create]
        foreach e $exports {
            $bgInterp alias $e ::iatclsh::$e
        }
        set script [format {
                cd [file dirname %s] 
                source [file tail %s]
                } $iatclsh::bgScript $iatclsh::bgScript]
        if {[catch {$bgInterp eval $script}]} {
            appendLog $::errorInfo response
            return 0
        }
        return 1 
    }

    # execute initialise command provided by background script. Returns 1 if 
    # initialise isn't provided, or if initialise is provided and successfully 
    # executes. Otherwise returns 0
    proc executeInitialise {} {
        variable bgInterp
        if {[$bgInterp eval {llength [info procs ::initialise]}] == 1} {
            if {[catch {$bgInterp eval ::initialise}]} {
                appendLog $::errorInfo response
                return 0
            } 
        }
        return 1
    }

    # execute closing command provided by background script. Returns 1 if 
    # closing isn't provided, or if closing is provided and successfully 
    # executes. Otherwise returns 0
    proc executeClosing {} {
        variable bgInterp
        if {$bgInterp != "" && [$bgInterp eval {llength \
                    [info procs ::closing]}] == 1} {
            if {[catch {$bgInterp eval ::closing}]} {
                appendLog $::errorInfo response
                return 0
            } 
        }
        return 1
    }

    # repeatedly execute run command provided by background script
    proc executeRun {} {
        variable stopRun 
        variable inRunCycle
        variable running
        variable restartAppIfScheduled
        variable reloadBgScriptScheduled
        variable bgInterp
        set running 1
        set inRunCycle 1
        if {$stopRun == 0 && \
                    [$bgInterp eval {llength [info procs ::run]}] == 1} {
            if {[catch {set rv [$bgInterp eval run]}]} {
                appendLog $::errorInfo response
                set running 0
            } elseif {[string is integer -strict $rv]} {
                after $rv iatclsh::executeRun
            } else {
                set running 0
            }
        } else {
            set running 0
        }
        set inRunCycle 0
        if {$restartAppIfScheduled} {
            restartAppIf
        }   
        if {$reloadBgScriptScheduled} {
            reloadBgScript
        }   
    }

    proc main {} {
        global tcl_platform
        variable prefs
        variable bgScript
        
        # load libkill
        if {$tcl_platform(os) == "Linux"} {
            set lib [file normalize [file dirname [info script]]]/libkill.so
            if {[catch {load $lib} errMsg]} {
                puts "error loading libkill"
                puts $errMsg
            }
        }

        catch iatclsh::loadHistory
        set parseRv [parseCmdLineArgs]

        buildGui

        # display error dialog and exit if command line param error
        if {$parseRv != ""} {
            tk_messageBox -type ok -icon error -title "Error" \
                    -message "Error parsing command line parameters:\n$parseRv"
            exit 1
        }

        # configure ui depending on user settings
        updateComboBox
        if {[dict get $prefs showScrollbar]} {
            grid .sb
        }
        if {[dict get $prefs showCombobox]} {
            grid remove .cmdEntry
            grid .cmdCombobox
            focus .cmdCombobox
        }
        
        # show gui before start up
        update 
        
        updateRecentUserScriptsMenu
        updateRecentBgScriptsMenu
        updateGuiState
        
        # open app interface and source any user file
        startAppIf 

        appendLog "% " command

        # load and run background script
        if {$bgScript != "" && [loadBgScript]} {
            if {[executeInitialise]} {
                executeRun
            }
        }
    }
    
    main
}

