#===============================================================================
# create_project.tcl
# Srotas - 5-Stage RISC-V Processor
#
# Creates a Vivado project with all RTL sources and both testbenches added,
# and sets tb_program (the one that loads mem/program.mem) as the
# simulation top. Run from the Vivado Tcl console:
#
#     cd path/to/Srotas
#     source vivado/create_project.tcl
#
# Or from a shell with Vivado on PATH:
#
#     vivado -mode batch -source vivado/create_project.tcl
#
# Change PART below to match your board (a few common ones are listed).
#===============================================================================

set proj_name "srotas"
set proj_dir  "./vivado_project"

# Default: Digilent Basys3 (xc7a35tcpg236-1). Other common choices:
#   Arty A7-35T   : xc7a35ticsg324-1L
#   Arty A7-100T  : xc7a100tcsg324-1L
#   Nexys A7-100T : xc7a100tcsg324-1
set part "xc7a35tcpg236-1"

set origin_dir [file normalize [file dirname [info script]]/..]

create_project $proj_name $proj_dir -part $part -force

# ---------------------------------------------------------------------------
# RTL sources (synthesizable design, default fileset)
# ---------------------------------------------------------------------------
set rtl_files [list \
    "$origin_dir/src/if_stage/pc_register.v" \
    "$origin_dir/src/if_stage/instruction_memory.v" \
    "$origin_dir/src/if_stage/if_id_register.v" \
    "$origin_dir/src/if_stage/if_stage_top.v" \
    "$origin_dir/src/id_stage/register_file.v" \
    "$origin_dir/src/id_stage/sign_extend.v" \
    "$origin_dir/src/id_stage/control_unit.v" \
    "$origin_dir/src/id_stage/id_ex_register.v" \
    "$origin_dir/src/id_stage/id_stage_top.v" \
    "$origin_dir/src/ex_stage/alu.v" \
    "$origin_dir/src/ex_stage/branch_unit.v" \
    "$origin_dir/src/ex_stage/muldiv_unit.v" \
    "$origin_dir/src/ex_stage/ex_mem_register.v" \
    "$origin_dir/src/ex_stage/ex_stage_top.v" \
    "$origin_dir/src/csr/csr_file.v" \
    "$origin_dir/src/mem_stage/data_memory.v" \
    "$origin_dir/src/mem_stage/mem_wb_register.v" \
    "$origin_dir/src/mem_stage/mem_stage_top.v" \
    "$origin_dir/src/wb_stage/wb_stage.v" \
    "$origin_dir/src/top_level/hazard_detection.v" \
    "$origin_dir/src/top_level/srotas_processor.v" \
]
add_files -norecurse -fileset [get_filesets sources_1] $rtl_files
set_property top srotas_processor [get_filesets sources_1]
set_property include_dirs "$origin_dir/src/common" [get_filesets sources_1]

# Note: rv32i_defines.vh / rv32i_encoder.vh are deliberately NOT added as
# fileset members here. They're pulled in by explicit `include directives
# already present in the .v sources; include_dirs (below) is all xvlog
# needs to resolve those. Adding rv32i_encoder.vh as a fileset member and
# marking it "global include" (an earlier version of this script did) makes
# Vivado prepend it outside any module in every file, which breaks its
# function definitions - functions require module scope.

# ---------------------------------------------------------------------------
# Simulation sources
# ---------------------------------------------------------------------------
set sim_files [list \
    "$origin_dir/src/testbenches/tb_program.v" \
    "$origin_dir/src/testbenches/tb_isa_directed.v" \
]
add_files -norecurse -fileset [get_filesets sim_1] $sim_files

# Memory init file. Vivado auto-exports any "Memory Initialization Files"
# fileset member into the xsim run directory (<project>.sim/sim_1/behav/xsim)
# by its bare filename before each simulation launch - confirmed by running
# this exact flow. That's why tb_program's IMEM_INIT_FILE parameter default
# is "program.mem" (no "mem/" prefix): it has to match where Vivado actually
# puts the file, not where it lives in the repo.
add_files -norecurse -fileset [get_filesets sim_1] "$origin_dir/mem/program.mem"
set_property file_type "Memory Initialization Files" \
    [get_files "$origin_dir/mem/program.mem"]

set_property top tb_program [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property include_dirs [list "$origin_dir/src/common" "$origin_dir/src/testbenches"] [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Project '$proj_name' created at $proj_dir"
puts "Open the Flow Navigator -> SIMULATION -> Run Simulation -> Run Behavioral Simulation"
puts "To run the full directed regression instead, set tb_isa_directed as the sim top:"
puts "  set_property top tb_isa_directed \[get_filesets sim_1\]"
