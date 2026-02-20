# PostgreSQL with pgvector extension for CI/CD testing
FROM public.ecr.aws/docker/library/postgres:16-alpine

# Install build dependencies and pgvector
# Need clang for LLVM bitcode compilation (PostgreSQL 16 has JIT enabled)
RUN apk add --no-cache --virtual .build-deps \
    git \
    build-base \
    postgresql-dev \
    clang19 \
    llvm19-dev && \
    ln -s /usr/bin/clang-19 /usr/bin/clang && \
    cd /tmp && \
    git clone --branch v0.7.4 https://github.com/pgvector/pgvector.git && \
    cd pgvector && \
    make PG_CONFIG=/usr/local/bin/pg_config && \
    make install PG_CONFIG=/usr/local/bin/pg_config && \
    cd / && \
    rm -rf /tmp/pgvector && \
    apk del .build-deps
