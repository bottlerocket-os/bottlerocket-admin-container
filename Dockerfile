################################################################################
# Base image for all builds

FROM public.ecr.aws/amazonlinux/amazonlinux:2 as builder-base
RUN yum group install -y "Development Tools"
RUN useradd builder


################################################################################
# Statically linked, more recent version of bash

FROM builder-base as builder-static
RUN yum install -y glibc-static

ARG musl_version=1.2.3
ARG bash_version=5.1.16

WORKDIR /opt/build
COPY ./sdk-fetch ./

WORKDIR /opt/build
COPY ./hashes/musl ./hashes

RUN \
  ./sdk-fetch hashes && \
  tar -xf musl-${musl_version}.tar.gz && \
  rm musl-${musl_version}.tar.gz hashes

WORKDIR /opt/build/musl-${musl_version}
RUN ./configure --enable-static && make -j$(nproc) && make install

WORKDIR /opt/build
COPY ./hashes/bash ./hashes

RUN \
  ./sdk-fetch hashes && \
  tar -xf bash-${bash_version}.tar.gz && \
  rm bash-${bash_version}.tar.gz hashes

WORKDIR /opt/build/bash-${bash_version}
RUN CC=""/usr/local/musl/bin/musl-gcc CFLAGS="-Os -DHAVE_DLOPEN=0" \
    ./configure \
        --enable-static-link \
        --without-bash-malloc \
    || { cat config.log; exit 1; }
RUN make -j`nproc`
RUN cp bash /opt/bash
RUN mkdir -p /usr/share/licenses/bash && \
    cp -p COPYING /usr/share/licenses/bash


################################################################################
# Rebuild of Amazon Linux 2's systemd v219 with downstream patches

FROM builder-base AS builder-systemd
RUN yum install -y yum-utils rpm-build
RUN yum-builddep -y systemd

USER builder
WORKDIR /home/builder
RUN yumdownloader --source systemd
RUN rpm -Uv systemd-219-*.src.rpm

WORKDIR /home/builder/rpmbuild/SOURCES
COPY systemd-patches/*.patch ./

WORKDIR /home/builder/rpmbuild/SPECS
# Recreate the spec file from three parts: everything up until the last upstream
# patch, downstream patches, everything else.
RUN last_patch=$(awk '/^Patch[0-9]+/ { line = NR } END { print line }' systemd.spec); \
    head -n${last_patch} systemd.spec >systemd.mod.spec; \
    { \
        echo ;\
        echo '# Bottlerocket Patches'; \
        echo 'Patch9501: 9500-cgroup-util-extract-cgroup-hierarchy-base-path-into-.patch'; \
        echo 'Patch9502: 9501-cgroup-util-accept-cgroup-hierarchy-base-as-option.patch'; \
        echo ; \
    } >>systemd.mod.spec; \
    tail -n+$((last_patch + 1)) systemd.spec >>systemd.mod.spec; \
    mv systemd.mod.spec systemd.spec
RUN rpmbuild --bb systemd.spec


################################################################################
# Actual admin container image

FROM public.ecr.aws/amazonlinux/amazonlinux:2

ARG IMAGE_VERSION
# Make the container image version a mandatory build argument
RUN test -n "$IMAGE_VERSION"
LABEL "org.opencontainers.image.version"="$IMAGE_VERSION"

# Install the custom systemd build in the same transaction as all original
# packages to save space. For example, openssh-server pulls in systemd. This
# dependency is best satisfied by the downstream build. Reinstalling it later
# would result in also carrying around the original systemd in the final image
# where it would remain forever hidden and unused in a lower layer.
RUN --mount=type=bind,from=builder-systemd,source=/home/builder/rpmbuild/RPMS,target=/tmp/systemd-rpms \
    yum update -y \
    && yum install -y \
        /tmp/systemd-rpms/*/systemd-{219,libs}*.rpm \
        ec2-instance-connect \
        jq \
        openssh-server \
        openssl \
        procps-ng \
        shadow-utils \
        sudo \
        util-linux \
    && yum clean all

# Delete SELinux config file to prevent relabeling with contexts provided by the container's image
RUN rm -rf /etc/selinux/config

COPY --from=builder-static /opt/bash /opt/bin/
COPY --from=builder-static /usr/share/licenses/bash /usr/share/licenses/bash

RUN rm -f /etc/motd /etc/issue
COPY --chown=root:root motd /etc/

COPY --chown=root:root units /etc/systemd/user/

ARG CUSTOM_PS1='[\u@admin]\$ '
RUN echo "PS1='$CUSTOM_PS1'" > "/etc/profile.d/bottlerocket-ps1.sh" \
    && echo "PS1='$CUSTOM_PS1'" >> "/root/.bashrc" \
    && echo "cat /etc/motd" >> "/root/.bashrc"

COPY --chmod=755 start_admin.sh /usr/sbin/
COPY ./sshd_config /etc/ssh/
COPY --chmod=755 ./sheltie /usr/bin/

RUN groupadd -g 274 api

# Reduces issues related to logger and our implementation of systemd. This is
# necessary for scripts logging to logger, such as in EC2 Instance Connect.
RUN ln -sf /usr/bin/true /usr/bin/logger

CMD ["/usr/sbin/start_admin.sh"]
ENTRYPOINT ["/bin/bash", "-c"]
