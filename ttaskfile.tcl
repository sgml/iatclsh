#
# ttaskfile for iatclsh 
#

# config variables for linux kill gcc
config INC_PATH /usr/include/tcl8.5
config LIB_PATH /usr/lib

set src {iatclsh.tcl app_if.tcl PrefsDlg.tcl}

task build {
    linuxKillLib build
    tarArchive build
    zipArchive build
}

task clean {file delete -force build}

# linux kill shared library
project add linuxKillLib -type gcc
linuxKillLib src -add lib/linux_kill.c
linuxKillLib build -buildDir build/libkill -incPath $INC_PATH \
        -libPath $LIB_PATH -lib tclstub8.5 -name libkill.so 

# tar archive 
project add tarArchive -type tar
tarArchive src -srcDir ./tcl -add $src -srcDir ./build/libkill -add libkill.so
tarArchive build -buildDir build/tar -name iatclsh.tar.gz

# zip archive 
project add zipArchive -type zip
zipArchive src -srcDir ./tcl -add $src 
zipArchive build -buildDir build/zip -name iatclsh.zip

