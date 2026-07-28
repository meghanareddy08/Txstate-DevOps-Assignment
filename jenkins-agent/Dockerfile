FROM jenkins/inbound-agent:latest-jdk21

USER root

RUN apt-get update && \
    apt-get install -y \
      git \
      curl \
      jq \
      python3 \
      python3-pip \
      docker.io && \
    rm -rf /var/lib/apt/lists/*

USER jenkins
