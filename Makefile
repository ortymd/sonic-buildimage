###############################################################################
## Wrapper for starting make inside sonic-slave container
#
#  Supported parameters:
#
#  * PLATFORM: Specific platform we wish to build images for.
#  * BUILD_NUMBER: Desired version-number to pass to the building-system.
#  * ENABLE_DHCP_GRAPH_SERVICE: Enables get-graph service to fetch minigraph files
#    through http.
#  * SHUTDOWN_BGP_ON_START: Sets admin-down state for all bgp peerings after restart.
#  * ENABLE_PFCWD_ON_START: Enable PFC Watchdog (PFCWD) on server-facing ports
#  * by default for TOR switch.
#  * SONIC_ENABLE_SYNCD_RPC: Enables rpc-based syncd builds.
#  * USERNAME: Desired username -- default at rules/config
#  * PASSWORD: Desired password -- default at rules/config
#  * KEEP_SLAVE_ON: Keeps slave container up after building-process concludes.
#  * SOURCE_FOLDER: host path to be mount as /var/$(USER)/src, only effective when KEEP_SLAVE_ON=yes
#  * SONIC_BUILD_JOB: Specifying number of concurrent build job(s) to run
#
###############################################################################

SHELL = /bin/bash

USER := $(shell id -un)
PWD := $(shell pwd)

# Remove lock file in case previous run was forcefully stopped
$(shell rm -f .screen)

MAKEFLAGS += -B

SLAVE_BASE_TAG = $(shell sha1sum sonic-slave/Dockerfile | awk '{print substr($$1,0,11);}')
SLAVE_TAG = $(shell cat sonic-slave/Dockerfile.user sonic-slave/Dockerfile | sha1sum | awk '{print substr($$1,0,11);}')
SLAVE_BASE_IMAGE = sonic-slave-base
SLAVE_IMAGE = sonic-slave-$(USER)

DOCKER_RUN := docker run --rm=true --privileged \
    -v $(PWD):/sonic \
    -w /sonic \
    -e "http_proxy=$(http_proxy)" \
    -e "https_proxy=$(https_proxy)" \
    -i$(if $(TERM),t,)

DOCKER_BASE_BUILD = docker build --no-cache \
		    -t $(SLAVE_BASE_IMAGE) \
		    --build-arg http_proxy=$(http_proxy) \
		    --build-arg https_proxy=$(https_proxy) \
		    sonic-slave && \
		    docker tag $(SLAVE_BASE_IMAGE):latest $(SLAVE_BASE_IMAGE):$(SLAVE_BASE_TAG)

DOCKER_BUILD = docker build --no-cache \
	       --build-arg user=$(USER) \
	       --build-arg uid=$(shell id -u) \
	       --build-arg guid=$(shell id -g) \
	       --build-arg hostname=$(shell echo $$HOSTNAME) \
	       -t $(SLAVE_IMAGE) \
	       -f sonic-slave/Dockerfile.user \
	       sonic-slave && \
	       docker tag $(SLAVE_IMAGE):latest $(SLAVE_IMAGE):$(SLAVE_TAG)

SONIC_BUILD_INSTRUCTION :=  make \
                           -f slave.mk \
                           PLATFORM=$(PLATFORM) \
                           BUILD_NUMBER=$(BUILD_NUMBER) \
                           ENABLE_DHCP_GRAPH_SERVICE=$(ENABLE_DHCP_GRAPH_SERVICE) \
                           SHUTDOWN_BGP_ON_START=$(SHUTDOWN_BGP_ON_START) \
                           SONIC_ENABLE_PFCWD_ON_START=$(ENABLE_PFCWD_ON_START) \
                           ENABLE_SYNCD_RPC=$(ENABLE_SYNCD_RPC) \
                           PASSWORD=$(PASSWORD) \
                           USERNAME=$(USERNAME) \
                           SONIC_BUILD_JOBS=$(SONIC_BUILD_JOBS) \
                           HTTP_PROXY=$(http_proxy) \
                           HTTPS_PROXY=$(https_proxy) \
                           SONIC_ENABLE_SYSTEM_TELEMETRY=$(ENABLE_SYSTEM_TELEMETRY)

.PHONY: sonic-slave-build sonic-slave-bash init reset

.DEFAULT_GOAL :=  all

%::
	@docker inspect --type image $(SLAVE_BASE_IMAGE):$(SLAVE_BASE_TAG) &> /dev/null || \
	    { echo Image $(SLAVE_BASE_IMAGE):$(SLAVE_BASE_TAG) not found. Building... ; \
	    $(DOCKER_BASE_BUILD) ; }
	@docker inspect --type image $(SLAVE_IMAGE):$(SLAVE_TAG) &> /dev/null || \
	    { echo Image $(SLAVE_IMAGE):$(SLAVE_TAG) not found. Building... ; \
	    $(DOCKER_BUILD) ; }
ifeq "$(KEEP_SLAVE_ON)" "yes"
    ifdef SOURCE_FOLDER
		@$(DOCKER_RUN) -v $(SOURCE_FOLDER):/var/$(USER)/src $(SLAVE_IMAGE):$(SLAVE_TAG) bash -c "$(SONIC_BUILD_INSTRUCTION) $@; /bin/bash"
    else
		@$(DOCKER_RUN) $(SLAVE_IMAGE):$(SLAVE_TAG) bash -c "$(SONIC_BUILD_INSTRUCTION) $@; /bin/bash"
    endif
else
	@$(DOCKER_RUN) $(SLAVE_IMAGE):$(SLAVE_TAG) $(SONIC_BUILD_INSTRUCTION) $@
endif

sonic-slave-build :
	$(DOCKER_BASE_BUILD)
	$(DOCKER_BUILD)

sonic-slave-bash :
	@docker inspect --type image $(SLAVE_BASE_IMAGE):$(SLAVE_BASE_TAG) &> /dev/null || \
	    { echo Image $(SLAVE_BASE_IMAGE):$(SLAVE_BASE_TAG) not found. Building... ; \
	    $(DOCKER_BASE_BUILD) ; }
	@docker inspect --type image $(SLAVE_IMAGE):$(SLAVE_TAG) &> /dev/null || \
	    { echo Image $(SLAVE_IMAGE):$(SLAVE_TAG) not found. Building... ; \
	    $(DOCKER_BUILD) ; }
	@$(DOCKER_RUN) -t $(SLAVE_IMAGE):$(SLAVE_TAG) bash

showtag:
	@echo $(SLAVE_IMAGE):$(SLAVE_TAG)
	@echo $(SLAVE_BASE_IMAGE):$(SLAVE_BASE_TAG)

init :
	@git submodule update --init --recursive
	@git submodule foreach --recursive '[ -f .git ] && echo "gitdir: $$(realpath --relative-to=. $$(cut -d" " -f2 .git))" > .git'

reset :
	@echo && echo -n "Warning! All local changes will be lost. Proceed? [y/N]: "
	@read ans && \
	 if [ $$ans == y ]; then \
	     git clean -xfdf; \
	     git reset --hard; \
	     git submodule foreach --recursive git clean -xfdf; \
	     git submodule foreach --recursive git reset --hard; \
	     git submodule update --init --recursive;\
	 else \
	     echo "Reset aborted"; \
	 fi
