FROM ubuntu:bionic

RUN apt-get update \
  && apt-get install -y \
  bind9 \
  bind9utils \
  bind9-doc

# Enable IPv4
RUN sed -i 's/OPTIONS=.*/OPTIONS="-4 -u bind"/' /etc/default/bind9

# Copy configuration files
COPY conf/named.conf.options /etc/bind/
COPY conf/named.conf.local /etc/bind/
COPY zones/* /etc/bind/zones/

# Run eternal loop
CMD ["/bin/bash", "-c", "while :; do sleep 10; done"]