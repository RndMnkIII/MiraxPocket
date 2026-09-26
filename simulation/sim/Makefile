# ============================================================================
#  Makefile - Mirax core simulation (self-contained: tv80 + jt49 vendored)
# ============================================================================
IVERILOG ?= iverilog
VVP      ?= vvp
RTL := ../rtl
CORE := $(RTL)/mirax_decrypt.sv $(RTL)/ttl_ls259.sv $(RTL)/mirax_main.sv \
        $(RTL)/mirax_sound.sv $(RTL)/mirax_sprite_engine.sv $(RTL)/mirax_video.sv \
        $(RTL)/mirax_clocks.sv $(RTL)/dpram.sv $(RTL)/mirax_top.sv

# vendored external cores (no network needed)
CPU := $(RTL)/cpu/tv80_adapter.sv \
       $(RTL)/cpu/tv80/tv80_core.v $(RTL)/cpu/tv80/tv80_alu.v \
       $(RTL)/cpu/tv80/tv80_mcode.v $(RTL)/cpu/tv80/tv80_reg.v
PSG := $(RTL)/psg/jt49/jt49_bus.v $(RTL)/psg/jt49/jt49.v $(RTL)/psg/jt49/jt49_div.v \
       $(RTL)/psg/jt49/jt49_eg.v $(RTL)/psg/jt49/jt49_exp.v \
       $(RTL)/psg/jt49/jt49_noise.v $(RTL)/psg/jt49/jt49_cen.v

.PHONY: video elab top smoke roms png compare clean

## video : synthetic video-path TB (no CPU/ROMs) -> frame.ppm
video:
	$(IVERILOG) -g2012 -o tb_video.out -s tb_video_synth \
	    $(RTL)/mirax_video.sv $(RTL)/mirax_sprite_engine.sv tb_video_synth.sv
	$(VVP) tb_video.out

## elab : elaborate the whole core with the REAL vendored tv80+jt49
elab:
	$(IVERILOG) -g2012 -Wno-timescale -o /dev/null -s mirax_top $(CPU) $(CORE) $(PSG)

## top : build+run full system (tv80+jt49). Needs rom/*.hex (make roms).
top:
	$(IVERILOG) -g2012 -Wno-timescale -o tb_top.out -s tb_top \
	    tb_top.sv $(CPU) $(CORE) $(PSG)
	$(VVP) tb_top.out

## smoke : full-system build+run with zero ROMs (integration check)
smoke:
	python3 -c "import os;os.makedirs('rom',exist_ok=True);\
[open(f'rom/{n}.hex','w').write('00\n'*s) for n,s in \
[('prog',0xC000),('audio',0x2000),('proms',0x40)]];\
[open(f'rom/{t}_p{p}.hex','w').write('00\n'*s) for t,s in \
[('tiles',16384),('sprites',32768)] for p in range(3)]"
	$(MAKE) top

## roms : pack a romset:  make roms ROMDIR=/path/to/miraxa
roms:
	python3 rom_build.py $(ROMDIR) rom

## questa : continuous frame dump in QuestaSim/ModelSim (needs vsim on PATH).
##   make questa                     # run forever, every frame -> frames/*.ppm
##   make questa QARGS="+FRAMES=300 +STRIDE=6"
questa:
	@mkdir -p frames
	vsim -c -do "run_questa.do" $(QARGS)

## png : convert the latest frame*.ppm to PNG
png:
	python3 ppm2png.py

## compare : diff a core frame vs a MAME reference:
##   make compare CORE=frame_0.ppm REF=mame_stage1.png
compare:
	python3 frame_compare.py $(CORE) $(REF) --out cmp.png

clean:
	rm -f *.out *.ppm *.png rom/*.bin rom/*.hex
