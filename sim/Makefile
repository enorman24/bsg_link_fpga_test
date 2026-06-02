BASEJUMP_STL_DIR ?= /data2/enorman/basejump_stl
export BASEJUMP_STL_DIR

VIVADO_DATA   ?= /data/eda_tools/AMD/2025.1/data
BUILD_DIR     := ../build/bsg_link_vivado
IP_SIM_DIR    := $(BUILD_DIR)/bsg_link_vivado.gen/sources_1/ip/axi_crossbar/sim
IP_STATIC_DIR := $(BUILD_DIR)/bsg_link_vivado.ip_user_files/ipstatic
GLBL_V        := $(VIVADO_DATA)/verilog/src/glbl.v

XELAB_LIBS := -L xil_defaultlib \
              -L smartconnect_v1_0 \
              -L axi_infrastructure_v1_1_0 \
              -L axi_register_slice_v2_1_35 \
              -L axi_vip_v1_1_21 \
              -L proc_sys_reset_v5_0_17 \
              -L xlconstant_v1_1_10 \
              -L axi_switch_v1_0_0 \
              -L uvm -L xilinx_vip \
              -L unisims_ver -L unimacro_ver -L secureip -L xpm

DESIGN_FILES := \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_defines.sv \
  $(BASEJUMP_STL_DIR)/bsg_async/bsg_async_ptr_gray.sv \
  $(BASEJUMP_STL_DIR)/bsg_async/bsg_launch_sync_sync.sv \
  $(BASEJUMP_STL_DIR)/bsg_async/bsg_async_credit_counter.sv \
  $(BASEJUMP_STL_DIR)/bsg_async/bsg_async_fifo.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_array_reverse.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_circular_ptr.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_counter_clear_up.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_and.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_mux.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_gray_to_binary.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_binary_plus_one_to_gray.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_scan.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_dff_reset.sv \
  $(BASEJUMP_STL_DIR)/bsg_misc/bsg_dff_en.sv \
  $(BASEJUMP_STL_DIR)/bsg_mem/bsg_mem_1r1w_synth.sv \
  $(BASEJUMP_STL_DIR)/bsg_mem/bsg_mem_1r1w.sv \
  $(BASEJUMP_STL_DIR)/bsg_mem/bsg_mem_1r1w_sync_synth.sv \
  $(BASEJUMP_STL_DIR)/bsg_mem/bsg_mem_1r1w_sync.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_fifo_tracker.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_fifo_1r1w_small_unhardened.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_fifo_1r1w_small_hardened.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_fifo_1r1w_small.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_one_fifo.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_two_fifo.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_parallel_in_serial_out.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_serial_in_parallel_out_full.sv \
  $(BASEJUMP_STL_DIR)/bsg_dataflow/bsg_round_robin_1_to_n.sv \
  $(BASEJUMP_STL_DIR)/bsg_link/bsg_link_oddr_phy.sv \
  $(BASEJUMP_STL_DIR)/bsg_link/bsg_link_iddr_phy.sv \
  $(BASEJUMP_STL_DIR)/bsg_link/bsg_link_source_sync_upstream.sv \
  $(BASEJUMP_STL_DIR)/bsg_link/bsg_link_source_sync_downstream.sv \
  $(BASEJUMP_STL_DIR)/bsg_link/bsg_link_ddr_upstream.sv \
  $(BASEJUMP_STL_DIR)/bsg_link/bsg_link_ddr_downstream.sv \
  ../rtl/bsg_link_xbar_pkg.sv \
  ../rtl/bsg_link_axi_tx_fifo.sv \
  ../rtl/bsg_link_axi_rx_fifo.sv \
  ../rtl/bsg_link_axi_rx_status.sv \
  ../rtl/bsg_link_test_top.sv \
  ./bsg_link_test_tb.sv

xsim.ini:
	cp $(VIVADO_DATA)/xsim/xsim.ini .
	echo "xil_defaultlib=xsim.dir/xil_defaultlib" >> xsim.ini

compile: xsim.ini
	xvlog --sv --incr --relax \
	  -L uvm -L axi_vip_v1_1_21 -L smartconnect_v1_0 \
	  -L axi_switch_v1_0_0 -L xilinx_vip \
	  --include $(IP_STATIC_DIR)/hdl/verilog \
	  --include $(IP_STATIC_DIR)/hdl \
	  --include $(VIVADO_DATA)/xilinx_vip/include \
	  -work xil_defaultlib \
	  $(IP_SIM_DIR)/axi_crossbar.sv
	xvlog --incr --relax -work xil_defaultlib $(GLBL_V)
	xvlog --sv --incr --relax \
	  --define SIM \
	  --include $(BASEJUMP_STL_DIR)/bsg_misc \
	  -work xil_defaultlib \
	  $(DESIGN_FILES)

elaborate: xsim.ini
	xelab --incr --debug typical --relax --mt 8 \
	  $(XELAB_LIBS) \
	  --snapshot sim_snap \
	  xil_defaultlib.bsg_link_test_tb xil_defaultlib.glbl \
	  -log xelab.log

sim:
	xsim sim_snap -tclbatch xsim.tcl 2>&1 | tee sim.log

wave:
	vivado -source open_wave.tcl &

run: compile elaborate sim

clean:
	rm -rf xsim.ini xsim.ini.bak xsim.dir xelab.pb xelab.log \
	       xsim.jou xvlog.log xvlog.pb xsim.log sim_snap.wdb \
	       sim.log .Xil vivado.jou vivado.log
