FROM alpine:3.14.4

COPY init.sh /bin/
RUN chmod 755 /bin/init.sh

COPY run.sh /bin/
RUN chmod 755 /bin/run.sh

ENTRYPOINT ["/bin/init.sh", "/bin/run.sh"]
