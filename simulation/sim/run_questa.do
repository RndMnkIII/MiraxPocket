## ===========================================================================
##  run_questa.do  -  QuestaSim / ModelSim batch script for MiraxCore
##  Usage:   vsim -c -do run_questa.do
##  (interactive: launch Questa, then `do run_questa.do`)
##
##  Override plusargs by editing VSIM_ARGS below, e.g.:
##    set VSIM_ARGS "+FRAMES=300 +STRIDE=6 +DIR=frames +DSW2=0x04"
## ===========================================================================

set RTL ../rtl
set VSIM_ARGS "+FRAMES=0 +STRIDE=1 +DIR=frames"

# fresh work library
if {[file exists work]} { vdel -all }
vlib work

# --- vendored tv80 (MIT) : Verilog ----------------------------------------
vlog -quiet $RTL/cpu/tv80/tv80_core.v $RTL/cpu/tv80/tv80_alu.v \
            $RTL/cpu/tv80/tv80_mcode.v $RTL/cpu/tv80/tv80_reg.v

# --- vendored jt49 (GPL-3) : Verilog --------------------------------------
vlog -quiet $RTL/psg/jt49/jt49_cen.v $RTL/psg/jt49/jt49_div.v \
            $RTL/psg/jt49/jt49_eg.v  $RTL/psg/jt49/jt49_exp.v \
            $RTL/psg/jt49/jt49_noise.v $RTL/psg/jt49/jt49.v $RTL/psg/jt49/jt49_bus.v

# --- core + adapter : SystemVerilog ---------------------------------------
vlog -quiet -sv $RTL/cpu/tv80_adapter.sv \
     $RTL/mirax_decrypt.sv $RTL/ttl_ls259.sv $RTL/dpram.sv $RTL/mirax_clocks.sv \
     $RTL/mirax_sprite_engine.sv $RTL/mirax_video.sv $RTL/mirax_sound.sv \
     $RTL/mirax_main.sv $RTL/mirax_top.sv

# --- testbench ------------------------------------------------------------
vlog -quiet -sv tb_questa.sv

# make sure the output dir + ROMs exist
if {![file exists frames]} { file mkdir frames }
if {![file exists rom/prog.hex]} {
    puts "WARNING: rom/*.hex not found. Run:  python3 rom_build.py <romdir> rom"
}

# --- run ------------------------------------------------------------------
eval vsim -c -voptargs=+acc work.tb_questa $VSIM_ARGS
run -all
quit -f
