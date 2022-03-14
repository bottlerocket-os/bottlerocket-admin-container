FROM public.ecr.aws/amazonlinux/amazonlinux:2 as builder
RUN yum group install -y "Development Tools"
RUN yum install -y glibc-static

ARG musl_version=1.2.2
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

FROM public.ecr.aws/amazonlinux/amazonlinux:2

ARG IMAGE_VERSION
# Make the container image version a mandatory build argument
RUN test -n "$IMAGE_VERSION"
LABEL "org.opencontainers.image.version"="$IMAGE_VERSION"

RUN yum update -y \
    && yum install -y openssh-server sudo util-linux procps-ng jq openssl ec2-instance-connect \
    && yum clean all

COPY --from=builder /opt/bash /opt/bin/
COPY --from=builder /usr/share/licenses/bash /usr/share/licenses/bash

RUN rm -f /etc/motd /etc/issue
COPY --chown=root:root motd /etc/

ARG CUSTOM_PS1='[\u@admin]\$ '
RUN echo "PS1='$CUSTOM_PS1'" > "/etc/profile.d/bottlerocket-ps1.sh" \
    && echo "PS1='$CUSTOM_PS1'" >> "/root/.bashrc" \
    && echo "cat /etc/motd" >> "/root/.bashrc"

COPY --chmod=755 start_admin_sshd.sh /usr/sbin/
COPY ./sshd_config /etc/ssh/
COPY --chmod=755 ./sheltie /usr/bin/

RUN groupadd -g 274 api

CMD ["/usr/sbin/start_admin_sshd.sh"]
ENTRYPOINT ["/bin/bash", "-c"]
