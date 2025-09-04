# scripts/build.tcl
project_open fpga/project.qpf
execute_flow -compile
project_close
