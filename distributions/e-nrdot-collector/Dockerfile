FROM alpine:3.21 AS certs
RUN apk --update add ca-certificates

FROM scratch

ARG USER_UID=10001
ARG DIST_NAME="e-nrdot-collector"
USER ${USER_UID}

COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --chmod=755 ${DIST_NAME} /e-nrdot-collector
COPY config.yaml /etc/e-nrdot-collector/config.yaml
ENTRYPOINT ["/e-nrdot-collector"]
CMD ["--config", "/etc/e-nrdot-collector/config.yaml"]

# `4317` and `4318`: OTLP
EXPOSE 4317 4318
