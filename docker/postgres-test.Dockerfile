# PostgreSQL with pgvector extension for CI/CD testing
FROM public.ecr.aws/docker/library/postgres:16-alpine

# Install build dependencies and pgvector
RUN apk add --no-cache --virtual .build-deps \
    git \
    build-base \
    clang15 \
    llvm15-dev && \
    cd /tmp && \
    git clone --branch v0.7.4 https://github.com/pgvector/pgvector.git && \
    cd pgvector && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/pgvector && \
    apk del .build-deps

# Keep llvm runtime for JIT compilation support
RUN apk add --no-cache llvm15
