FROM alpine:3.7 AS build
MAINTAINER Robb Wagoner <robb.wagoner@gmail.com>
LABEL app=vividcortex

ARG VC_API_TOKEN
ARG VC_ENABLE_RDS_OFFHOST=1

# verify VC_API_TOKEN set (required for installing the agent)
# openssl for https
# download, install
# remove sensitive data from the image

RUN test -n "${VC_API_TOKEN}" && apk update && apk add --no-cache openssl ca-certificates curl && \
    curl -O https://download.vividcortex.com/install && \
    sh install --token=${VC_API_TOKEN} --batch --init=None --static --proxy=dyn --skip-certs --off-host && \
    sed -i -e '/api-token/d' /etc/vividcortex/global.conf

RUN test -n "${VC_ENABLE_RDS_OFFHOST}" && \
    printf '{\n  "force-offhost-digests": "true",\n  "force-offhost-samples": "true"\n}\n' >/etc/vividcortex/vc-mysql-metrics.conf || true

# Use segmentio/chamber for reading settings from AWS SSM Parameter Store
RUN curl -L -s -o /usr/local/bin/chamber https://github.com/segmentio/chamber/releases/download/v2.0.0/chamber-v2.0.0-linux-amd64 && \
    sha256sum /usr/local/bin/chamber | grep bdff59df90a135ea485f9ce5bcfed2b3b1cc9129840f08ef9f0ab5309511b224 && \
    chmod 755 /usr/local/bin/chamber


FROM alpine:3.7
RUN apk update && apk add --no-cache ca-certificates

COPY --from=build /usr/local/bin/vc-agent-007 /usr/local/bin/vc-agent-007
COPY --from=build /etc/vividcortex /etc/vividcortex
COPY --from=build /var/log/vividcortex /var/log/vividcortex
COPY --from=build /usr/local/bin/chamber /usr/local/bin/chamber
COPY vividcortex.sh /usr/local/bin/vividcortex

# for overriding at runtime
ENV chamber_service prod-vividcortex
# segmentio/chamber defaults to `parameter_store_key`, but we can override, eg. `-e CHAMBER_KMS_KEY_ALIAS=aws/ssm`
ENV CHAMBER_KMS_KEY_ALIAS parameter_store_key

WORKDIR /
ENTRYPOINT ["/usr/local/bin/vividcortex","-foreground","-forbid-restarts","-log-type=stderr","-drv-mysql-query-capture=poll"]
ENTRYPOINT ["/usr/local/bin/vividcortex","-foreground","-forbid-restarts","-log-type=file","-drv-mysql-query-capture=poll"]
