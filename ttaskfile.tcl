#
# ttaskfile for iatclsh 
#

# for tclkit 
config runtimeDir ~/tclkit
config linuxRuntime tclkit-8.5.9-linux-ix86
config winRuntime tclkit-8.5.9-win32.upx.exe

# for tar/zip archives
set archiveSrc {iatclsh.tcl app_if.tcl PrefsDlg.tcl}

task build {runTask tclkit; runTask archive}
task tclkit {
    tclkit build -exe all -runtime $runtimeDir/$linuxRuntime
    tclkit build -exe wrap -runtime $runtimeDir/$winRuntime
}
task archive {
    tarArchive build 
    zipArchive build
}
task clean {rmdir build}

# starpacks
project add tclkit -type tclkit
tclkit src -srcDir tcl -add *.tcl 
tclkit build -buildDir build/starpack -prepare wrapper.tcl -name iatclsh

# tar archive 
project add tarArchive -type tar
tarArchive src -srcDir tcl -add $archiveSrc 
tarArchive build -buildDir build/tar -name iatclsh.tar.gz

# zip archive 
project add zipArchive -type zip
zipArchive src -srcDir tcl -add $archiveSrc 
zipArchive build -buildDir build/zip -name iatclsh.zip

