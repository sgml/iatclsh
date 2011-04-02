#
# PrefsDlg.tcl
#
# Preferences dialog
#

namespace eval iatclsh::PrefsDlg {    

    variable okButtonPressed  
    variable scrollLines 
    variable historySize 
    variable showScrollbar
    variable showCombobox
    variable changeDir

    proc showPrefsDlg {prefs} {
        variable okButtonPressed 
        variable scrollLines
        variable historySize
        variable showScrollbar
        variable showCombobox
        variable changeDir
        set okButtonPressed 0
        set scrollLines [dict get $prefs scrollLines]
        set historySize [dict get $prefs historySize]
        set showScrollbar [dict get $prefs showScrollbar]
        set showCombobox [dict get $prefs showCombobox]
        set changeDir [dict get $prefs changeDir]

        buildPrefsDlg 
        tkwait window .prefsDlg

        if {!$okButtonPressed} {
            return 
        }
        dict set prefs scrollLines $scrollLines
        dict set prefs historySize $historySize
        dict set prefs showScrollbar $showScrollbar
        dict set prefs showCombobox $showCombobox
        dict set prefs changeDir $changeDir
        return $prefs
    }

    proc buildPrefsDlg {} {
        set pkg iatclsh::PrefsDlg
        toplevel .prefsDlg 
        wm withdraw .prefsDlg
        wm title .prefsDlg "Preferences"
        wm resizable .prefsDlg 0 0
        wm protocol .prefsDlg WM_DELETE_WINDOW ${pkg}::cancelButtonEvent
        wm transient .prefsDlg .

        set prefsFrame .prefsDlg.prefsFrame
        set buttonsFrame .prefsDlg.buttonsFrame
        set scrollLabel $prefsFrame.scrollLabel
        set scrollEntry $prefsFrame.scrollEntry
        set historyLabel $prefsFrame.historyLabel
        set historyEntry $prefsFrame.historyEntry
        set showScrollbarCheckbutton $prefsFrame.showScrollbarCheckbutton
        set showComboboxCheckbutton $prefsFrame.showComboboxCheckbutton
        set changeDirCheckbutton $prefsFrame.changeDirCheckbutton
        set okButton $buttonsFrame.okButton
        set cancelButton $buttonsFrame.cancelButton

        ttk::frame $prefsFrame
        ttk::frame $buttonsFrame
        ttk::label $scrollLabel -text "Scroll lines:"
        ttk::entry $scrollEntry -width 5 \
                -textvariable ${pkg}::scrollLines
        ttk::label $historyLabel -text "Command history:"
        ttk::entry $historyEntry -width 4 \
                -textvariable ${pkg}::historySize
        ttk::checkbutton $showScrollbarCheckbutton \
                -text "Show scrollbar" \
                -variable ${pkg}::showScrollbar 
        ttk::checkbutton $showComboboxCheckbutton \
                -text "Show command combobox" \
                -variable ${pkg}::showCombobox 
        ttk::checkbutton $changeDirCheckbutton \
                -text "User script change directory" \
                -variable ${pkg}::changeDir 
        ttk::button $okButton -text "Ok" -command ${pkg}::okButtonEvent
        ttk::button $cancelButton -text "Cancel" \
                -command ${pkg}::cancelButtonEvent

        grid $prefsFrame -padx 10 -pady {10 0} 
        grid $buttonsFrame -padx 10 -pady 10
        grid $scrollLabel -padx {0 2} -sticky e
        grid $scrollEntry -row 0 -column 1 -sticky w
        grid $historyLabel -padx {0 2} -pady {5 0} -sticky e 
        grid $historyEntry -row 1 -column 1 -pady {5 0} -sticky w
        grid x $showScrollbarCheckbutton -pady {4 0} -sticky w
        grid x $showComboboxCheckbutton -pady {2 0} -sticky w
        grid x $changeDirCheckbutton -pady {2 0} -sticky w
        grid $okButton $cancelButton -padx 5 

        wm deiconify .prefsDlg
        tkwait visibility .prefsDlg
        grab set .prefsDlg
    }

    proc okButtonEvent {} {
        variable okButtonPressed
        set okButtonPressed 1
        destroy .prefsDlg
    }

    proc cancelButtonEvent {} {
        destroy .prefsDlg
    }
}

