#
# ttaskfile for iatclsh 
#

# gcc settings
set INC_PATH /usr/include/tcl8.5
set LIB_PATH /usr/lib

set src {iatclsh.tcl app_if.tcl PrefsDlg.tcl}

task build {
    $linuxKill build
    $tar build
}

task clean {file delete -force build}

# linux kill config
set linuxKill [project gcc]
$linuxKill src -add lib/linux_kill.c
$linuxKill build -buildDir build/libkill -incPath $INC_PATH \
        -libPath $LIB_PATH -lib tclstub8.5 -name libkill.so 

# tar archive config
set tar [project tar]
$tar src -srcDir ./tcl -add $src -srcDir ./build/libkill -add libkill.so
$tar build -buildDir build/tar -name iatclsh.tar.gz

