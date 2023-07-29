
PROJECT_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
#PROJECT_DIR := $(CURDIR)
USER := $(shell id -u):$(shell id -g)
IMAGE := klakegg/hugo:ext-ubuntu
DOCKER_COMMAND := docker run --user $(USER) --rm -it -v $(PROJECT_DIR):/src

.DEFAULT_GOAL := hugo
# For explanations see https://stackoverflow.com/a/6273809/4267183
hugo: # runs hugo commands in the container
	@$(DOCKER_COMMAND) $(IMAGE) $(filter-out $@,$(MAKECMDGOALS))

server:
	@$(DOCKER_COMMAND) -p 1313:1313 $(IMAGE) server -D


# This is necessary to pass the positional parameters to the target.
# It prevents Make from trying to find a rule for the arguments as targets.
%:
	@:
