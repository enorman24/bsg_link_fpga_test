PROJ_NAME := bsg_link_vivado
BUILD_DIR  := build
LOG_DIR    := $(BUILD_DIR)/logs
JOBS       := 30
VIVADO     := vivado -mode batch

export BSG_LINK_JOBS := $(JOBS)

.PHONY: create-project recreate-project synth impl verify

$(LOG_DIR):
	mkdir -p $@

create-project: | $(LOG_DIR)
	$(VIVADO) -source scripts/create_project.tcl \
	  -journal $(LOG_DIR)/create_project.jou \
	  -log     $(LOG_DIR)/create_project.log

recreate-project: | $(LOG_DIR)
	BSG_LINK_FORCE_RECREATE=1 $(VIVADO) -source scripts/create_project.tcl \
	  -journal $(LOG_DIR)/create_project.jou \
	  -log     $(LOG_DIR)/create_project.log

synth: | $(LOG_DIR)
	$(VIVADO) -source scripts/run_synth.tcl \
	  -journal $(LOG_DIR)/run_synth.jou \
	  -log     $(LOG_DIR)/run_synth.log

impl: | $(LOG_DIR)
	$(VIVADO) -source scripts/run_impl.tcl \
	  -journal $(LOG_DIR)/run_impl.jou \
	  -log     $(LOG_DIR)/run_impl.log

verify: | $(LOG_DIR)
	$(VIVADO) -source scripts/verify_project.tcl \
	  -journal $(LOG_DIR)/verify_project.jou \
	  -log     $(LOG_DIR)/verify_project.log
