# Jenkins LTS plus the tools the pipeline needs: docker CLI (build/push images) and kubectl (deploy)
FROM jenkins/jenkins:lts-jdk21

USER root
COPY --from=docker:29-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker:29-cli /usr/local/libexec/docker/cli-plugins/docker-buildx /usr/local/libexec/docker/cli-plugins/docker-buildx
RUN curl -fsSLo /usr/local/bin/kubectl https://dl.k8s.io/release/v1.37.2/bin/linux/amd64/kubectl \
 && chmod +x /usr/local/bin/kubectl
USER jenkins
