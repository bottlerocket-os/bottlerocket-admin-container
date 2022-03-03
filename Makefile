# IMAGE_NAME is the full name of the container image being built.
IMAGE_NAME ?= $(notdir $(shell pwd -P))$(IMAGE_ARCH_SUFFIX):$(IMAGE_VERSION)$(addprefix -,$(SHORT_SHA))
# IMAGE_VERSION is the semver version that's tagged on the image.
IMAGE_VERSION = $(shell cat VERSION)
# SHORT_SHA is the revision that the container image was built with.
SHORT_SHA ?= $(shell git describe --abbrev=8 --always --dirty='-dev' --exclude '*' || echo "unknown")
# IMAGE_ARCH_SUFFIX is the runtime architecture designator for the container
# image, it is appended to the IMAGE_NAME unless the name is specified.
IMAGE_ARCH_SUFFIX ?= $(addprefix -,$(ARCH))
# DESTDIR is where the release artifacts will be written.
DESTDIR ?= .
# DISTFILE is the path to the dist target's output file - the container image
# tarball.
DISTFILE ?= $(subst /,,$(DESTDIR))/$(subst /,_,$(IMAGE_NAME)).tar.gz

UNAME_ARCH = $(shell uname -m)
ARCH ?= $(lastword $(subst :, ,$(filter $(UNAME_ARCH):%,x86_64:amd64 aarch64:arm64)))

.PHONY: all build check check-static-bash

# Run all build tasks for this container image.
all: build check

# Create a distribution container image tarball for release.
dist: all
	@mkdir -p $(dir $(DISTFILE))
	docker save $(IMAGE_NAME) | gzip > $(DISTFILE)

# Build the container image.
build: export DOCKER_BUILDKIT = 1
build:
	docker build $(DOCKER_BUILD_FLAGS) \
		--tag $(IMAGE_NAME) \
		--build-arg IMAGE_VERSION="$(IMAGE_VERSION)" \
		-f Dockerfile . >&2

# Run checks against the container image.
check: check-static-bash

# Check that bash can be run without dependency on shared libraries.
check-static-bash:
	docker run $(DOCKER_RUN_FLAGS) \
		--rm \
		--entrypoint /opt/bin/bash \
		--mount type=volume,target=/usr/lib,volume-nocopy \
		--mount type=volume,target=/usr/lib64,volume-nocopy \
		$(IMAGE_NAME) \
		-c '/usr/bin/bash -c "echo \$$0 must not run" 2>/dev/null && exit 1 || exit 0'

clean:
	rm -f $(DISTFILE)
