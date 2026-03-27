################################################################################
# Base image for all builds

FROM public.ecr.aws/amazonlinux/amazonlinux:2023 AS builder-base
RUN dnf group install -y "Development Tools"
RUN useradd builder


################################################################################
# Statically linked, more recent version of bash

FROM builder-base AS builder-static
RUN dnf install -y glibc-static

ARG musl_version=1.2.5
ARG bash_version=5.2.37

WORKDIR /opt/build
COPY ./sdk-fetch ./

WORKDIR /opt/build
COPY ./hashes/musl ./hashes
COPY ./patches/musl ./patches

RUN \
  ./sdk-fetch hashes && \
  tar -xf musl-${musl_version}.tar.gz && \
  rm musl-${musl_version}.tar.gz hashes && \
  cd musl-${musl_version} && \
  git init . && \
  git apply --whitespace=nowarn ../patches/*.patch

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

# Build bash library first, then remove conflicting strtoimax object to avoid duplicate symbols with musl
RUN make lib/sh/libsh.a && \
    ar d lib/sh/libsh.a lib/sh/strtoimax.o && \
    ranlib lib/sh/libsh.a
RUN make -j`nproc`
RUN cp bash /opt/bash
RUN mkdir -p /usr/share/licenses/bash && \
    cp -p COPYING /usr/share/licenses/bash


################################################################################
# Actual admin container image

FROM public.ecr.aws/amazonlinux/amazonlinux:2023

ARG IMAGE_VERSION
# Make the container image version a mandatory build argument
RUN test -n "$IMAGE_VERSION"
LABEL "org.opencontainers.image.version"="$IMAGE_VERSION"

RUN dnf update -y \
    && dnf install -y \
        crypto-policies-scripts \
        ec2-instance-connect \
        jq \
        openssh-server \
        openssl \
        procps-ng \
        shadow-utils \
        sudo \
        util-linux \
    && dnf clean all

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
COPY --chmod=755 ./sheltie ./host-wrappers/* ./nvidia-bug-report.sh /usr/bin/

RUN groupadd -g 274 api

# Reduces issues related to logger and our implementation of systemd. This is
# necessary for scripts logging to logger, such as in EC2 Instance Connect.
RUN ln -sf /usr/bin/true /usr/bin/logger

CMD ["/usr/sbin/start_admin.sh"]
ENTRYPOINT ["/bin/bash", "-c"]
