ARG DOCKER_ARCH
FROM $DOCKER_ARCH/amazonlinux:2 as builder
RUN yum group install -y "Development Tools"
RUN yum install -y glibc-static

ARG musl_version=1.2.2
ARG bash_version=5.0
ARG bash_patch_level=18

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
RUN for patch_level in $(seq ${bash_patch_level}); do \
        patch -p0 < /opt/build/bash${bash_version//.}-$(printf '%03d' $patch_level); \
    done
RUN CC=""/usr/local/musl/bin/musl-gcc CFLAGS="-Os -DHAVE_DLOPEN=0" \
    ./configure \
        --enable-static-link \
        --without-bash-malloc \
    || { cat config.log; exit 1; }
RUN make -j`nproc`
RUN cp bash /opt/bash

FROM $DOCKER_ARCH/amazonlinux:2

ARG IMAGE_VERSION
# Make the container image version a mandatory build argument
RUN test -n "$IMAGE_VERSION"
LABEL "org.opencontainers.image.version"="$IMAGE_VERSION"

RUN yum update -y \
    && yum install -y openssh-server sudo util-linux procps-ng jq \
    && yum clean all

COPY --from=builder /opt/bash /opt/bin/

RUN rm -f /etc/motd /etc/issue
ADD --chown=root:root motd /etc/

ADD --chown=root:root ec2-user.sudoers /etc/sudoers.d/ec2-user
ADD start_admin_sshd.sh /usr/sbin/
ADD ./sshd_config /etc/ssh/
ADD ./sheltie /usr/bin/

RUN chmod 440 /etc/sudoers.d/ec2-user
RUN chmod +x /usr/sbin/start_admin_sshd.sh
RUN chmod +x /usr/bin/sheltie
RUN groupadd -g 274 api
RUN useradd -m -G users,api ec2-user

CMD ["/usr/sbin/start_admin_sshd.sh"]
ENTRYPOINT ["/bin/bash", "-c"]
