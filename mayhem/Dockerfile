# syntax=docker/dockerfile:1.7
#
# Commit image for ctypes.sh (a bash loadable builtin plugin). The fuzz targets are bash scripts
# run by a bash built from pinned source with AFL instrumentation + ASan/UBSan, which loads the
# equally instrumented ctypes.so plugin (mayhem/build.sh).
FROM ghcr.io/savantenvs/base:20261023

ARG COMMIT
ARG REPO_URL
ARG SOURCE_DATE_EPOCH
ARG SANITIZER_FLAGS
ARG COVERAGE_FLAGS=
ARG MAYHEM_JOBS=

# libffi / libelf / libdw: the plugin's runtime deps (struct+sizeof need libelf+libdw).
USER root
RUN [ -n "$SOURCE_DATE_EPOCH" ] && repro-sources-list.sh || true ; \
    apt-get update && apt-get install -yq --no-install-recommends \
        libffi-dev libelf-dev libdw-dev zlib1g-dev bison \
 && rm -rf /var/lib/apt/lists/*

# GNU bash source, the host interpreter the plugin is loaded into. It is the fuzzed executable
# (AFL forkserver + sanitizer runtime), so build.sh builds it with the fuzz flags from this
# pinned source, out of tree under /mayhem (SPEC §6.2 item 19).
ARG BASH_VER=5.2
ARG BASH_SHA256=a139c166df7ff4471c5e0733051642ee5556c1cc8a4a78f145583c5c81ab32fb
RUN d=/opt/toolchains/deps/bash-${BASH_VER} && mkdir -p "$d/src" \
 && curl -fsSL -o /tmp/bash.tgz https://ftp.gnu.org/gnu/bash/bash-${BASH_VER}.tar.gz \
 && echo "${BASH_SHA256}  /tmp/bash.tgz" | sha256sum -c - \
 && tar -xzf /tmp/bash.tgz --strip-components=1 -C "$d/src" \
 && rm -f /tmp/bash.tgz && chmod -R a+rX,go-w "$d"

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

RUN if [ -x /opt/mayhem/ccache/prefill ]; then /opt/mayhem/ccache/prefill bash mayhem/build.sh; \
    else bash mayhem/build.sh; fi

RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
