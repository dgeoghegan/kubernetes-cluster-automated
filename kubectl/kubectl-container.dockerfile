FROM alpine:3.20

# Install dependencies
RUN apk add --no-cache curl bash ca-certificates gettext

# Argument allows injecting exact kubectl version (e.g., 1.34.2)
ARG KUBECTL_VERSION

# Download kubectl from official release
RUN test -n "$KUBECTL_VERSION" && \
    curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    curl -LO "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \
    echo "$(cat kubectl.sha256)  kubectl" | sha256sum -c - && \
    install -m 0755 kubectl /usr/local/bin/kubectl && \
    rm -f kubectl

# Verify installation
RUN kubectl version --client=true && \
    envsubst --version

ENTRYPOINT ["/usr/local/bin/kubectl"]
CMD ["help"]
