# Headless Retro Toolbox: the Linux release bundle on a KasmVNC virtual display.
# Build context is this directory with retro_toolbox_linux_x64.tar.gz dropped in:
#   docker build --platform linux/amd64 -f server/Dockerfile -t retro-toolbox-server:dev server
FROM ubuntu:24.04

ARG KASMVNC_VERSION=1.5.2
ADD https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_ubuntu_noble_${KASMVNC_VERSION}_amd64.deb /tmp/kasmvnc.deb

# libarchive13 is named libarchive13t64 on noble.
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      /tmp/kasmvnc.deb libgtk-3-0t64 libgl1-mesa-dri libegl1 libgles2 libarchive13t64 \
      xdg-user-dirs zenity tini openssl matchbox-window-manager \
 && rm -rf /var/lib/apt/lists/* /tmp/kasmvnc.deb \
 && userdel -r ubuntu \
 && useradd -u 1000 -U -m -d /data -s /bin/bash retro

# ADD unpacks the local tarball. The bundled libarchive comes from the newer CI runner and needs a
# libxml2 noble lacks; removing it lets librar_native load noble's ABI-compatible libarchive13t64.
ADD retro_toolbox_linux_x64.tar.gz /opt/retro_toolbox/
RUN rm -f /opt/retro_toolbox/lib/libarchive.so.13
COPY kasmvnc.yaml /etc/kasmvnc/kasmvnc.yaml
COPY entrypoint.sh watchdog.sh /opt/server/

ENV RETRO_TOOLBOX_SERVER=1 RETRO_TOOLBOX_BUSY_FILE=/tmp/retro_toolbox.busy LANG=C.UTF-8
USER retro
WORKDIR /data
VOLUME /data
EXPOSE 8444
ENTRYPOINT ["tini", "--", "/opt/server/entrypoint.sh"]
