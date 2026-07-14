FROM bitnami/openldap:latest

ENV LDAP_ADMIN_USERNAME="admin"
ENV LDAP_ADMIN_PASSWORD="test"
ENV LDAP_USERS="customuser"
ENV LDAP_PASSWORDS="custompassword"
ENV LDAP_ROOT="dc=foo,dc=example,dc=com"
ENV LDAP_ADMIN_DN="cn=admin,dc=foo,dc=example,dc=com"
ENV LDAP_LISTEN_ADDRESS="0.0.0.0"
ENV LDAP_ENABLE_TLS="no"
ENV LDAP_PORT_NUMBER="389"

USER root

COPY zammad.ldif /ldifs/

RUN chown -R 1001:1001 /ldifs
RUN chmod -R 755 /ldifs

USER 1001
