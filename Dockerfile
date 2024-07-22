# Use the base image
FROM vllm/vllm-openai:latest

# Install necessary packages
RUN apt-get update && apt-get install -y \
    libibverbs-dev \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /root/cwd

# Clear the entrypoint
ENTRYPOINT []