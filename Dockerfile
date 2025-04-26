FROM alpine:3.18

ARG SQUID_VERSION=5.9-r0
ARG SQUID_PROXY_PORT=3128
ARG SQUID_PROXY_SSLBUMP_PORT=4128

# Set environment variables for certificate CA generation
ENV CERT_CN=squid.local \
    CERT_ORG=squid \
    CERT_OU=squid \
    CERT_COUNTRY=US \
    SQUID_PROXY_PORT=3128 \
    SQUID_PROXY_SSLBUMP_PORT=4128

# Install Squid, OpenSSL, and other required packages
RUN apk add --no-cache \
    squid=${SQUID_VERSION} \
    openssl \
    gettext \
    ca-certificates && \
    update-ca-certificates && \
    rm -rf /etc/squid/squid.conf

# Add configuration files to the container
ADD conf/squid.sample.conf /templates/squid.sample.conf
ADD conf/openssl.extra.cnf /etc/ssl
ADD conf/denylist.acl /etc/squid/denylist.acl
ADD conf/allowlist.acl /etc/squid/allowlist.acl

# Add entrypoint script and set permissions
ADD scripts/entrypoint.sh /entrypoint
RUN chmod u+x /entrypoint && \
    mkdir -p /etc/squid-cert /var/cache/squid/ /var/log/squid/ && \
    chown -R squid:squid /etc/squid-cert /var/cache/squid/ /var/log/squid/ && \
    cat /etc/ssl/openssl.extra.cnf >> /etc/ssl/openssl.cnf

# Expose ports for HTTP and SSL-Bump proxy
EXPOSE 3128
EXPOSE 4128

# Define a health check to ensure Squid is running
HEALTHCHECK CMD netstat -an | grep ${SQUID_PROXY_PORT} > /dev/null; if [ 0 != $? ]; then exit 1; fi;

# Set the entrypoint and default command for the container
ENTRYPOINT ["/entrypoint"]
CMD ["squid", "-NYCd", "1", "-f", "/etc/squid/squid.conf"]
