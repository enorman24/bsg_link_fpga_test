BASEJUMP_STL_DIR ?= /data2/enorman/basejump_stl

export BASEJUMP_STL_DIR

VCS_FLAGS := -full64 -sverilog -timescale=1ps/1ps \
             +define+SIM \
             -f ./filelist \
             -top bsg_link_test_tb \
             -debug_access+all -kdb -lca +vpi \
             +define+FSDB +fsdb+struct=on \
             -assert svaext

compile:
	vcs $(VCS_FLAGS) -o simv

sim: compile
	./simv | tee sim.log

run: sim

verdi:
	verdi -ssf waveform.fsdb &

clean:
	rm -rf simv simv.daidir csrc DVEfiles *.key vc_hdrs.h sim.log ucli.key *.fsdb
