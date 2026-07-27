package require ::quartus::project
package require ::quartus::flow

set base_dir [pwd]

# Quartus stamps its own version into these on open, so snapshot them and restore
# byte-for-byte after, keeping one tree buildable by both 21.1 and 25.1
set guarded_files {
    projects/ap_core.qpf
    projects/ap_core.qsf
}
set snap_dir build_output/.proj_snapshot
file mkdir $snap_dir
foreach f $guarded_files {
    if {[file exists $f]} {
        file copy -force $f [file join $snap_dir [file tail $f]]
    }
}

# -force lets project_open overwrite a database written by the other Quartus
# version. The catch is what makes the restore below run on a failed flow too,
# which is the case the snapshot guard exists for
set build_status [catch {
    project_open -force -revision ap_core projects/ap_core.qpf
    set_global_assignment -name NUM_PARALLEL_PROCESSORS ALL
    execute_flow -compile
    project_close

    # project_open changes cwd to the project directory; restore it
    cd $base_dir

    # Custom STA report for detailed timing path analysis
    file mkdir build_output/reports
    post_message "Running custom STA report..."
    if {[catch {qexec "quartus_sta -t scripts/sta_custom_report.tcl"} result]} {
        post_message -type warning "Custom STA report failed: $result"
    } else {
        post_message "Custom STA completed successfully."
    }
} build_error]

# The catch may have aborted with cwd still inside the project dir
cd $base_dir

# Must run after the STA report, which reopens the project and re-stamps them
foreach f $guarded_files {
    set snap [file join $snap_dir [file tail $f]]
    if {[file exists $snap]} {
        file copy -force $snap $f
    }
}

# Propagate the failure now the files are restored, so quartus_sh -t exits non-zero
if {$build_status} {
    error $build_error
}
