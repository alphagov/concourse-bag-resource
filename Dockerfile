ARG REGISTRY_IMAGE_RESOURCE=concourse/registry-image-resource:1.9.0
ARG GIT_RESOURCE=concourse/git-resource:1.16.0
FROM $REGISTRY_IMAGE_RESOURCE as registry-image-resource
FROM $GIT_RESOURCE as base-resource
FROM base-resource as build-resource
USER root

RUN apt update && apt install -y --no-install-recommends build-essential
COPY ./assets/forcedumpable.c /opt/resource/
WORKDIR /opt/resource
RUN gcc ./forcedumpable.c -o ./forcedumpable.so -shared -ldl

FROM base-resource as final-resource
USER root

RUN apt update && apt install -y --no-install-recommends proot

RUN mkdir /subresources
COPY --from=registry-image-resource / /subresources/registry-image

RUN mkdir -p /bag/lib && mkdir -p /bag/bin
COPY --from=build-resource --chmod=0644 /opt/resource/forcedumpable.so /bag/lib/
COPY --chmod=0755 ./assets/sleep-after /bag/bin/

RUN mv /opt/resource /opt/git-resource && mkdir /opt/resource
COPY --chmod=0644 ./assets/common.sh /opt/resource/
COPY --chmod=0755 ./assets/in /opt/resource/
COPY --chmod=0755 ./assets/out /opt/resource/
COPY --chmod=0755 ./assets/check /opt/resource/
COPY ./assets/disallowed-subresource-source-keys /opt/resource/disallowed-subresource-source-keys
