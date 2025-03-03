FROM ubuntu:latest as transferase-test-data-builder
WORKDIR /data
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    git
RUN git clone https://github.com/andrewdavidsmith/transferase-test-data-small.git $(pwd)

# Put it into an image that can build and run transferase
FROM andrewdavidsmith/transferase-build:latest
COPY --from=transferase-test-data-builder /data/ /data/
