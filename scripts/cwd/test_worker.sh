docker run \
  --network host \
  --name node \
  --ipc host \
  --gpus all \
  --privileged \
  --uts=host \
  -e UCX_TLS=self,shm,tcp \
  -e NCCL_P2P_LEVEL=NVL \
  -e NCCL_NET_GDR_LEVEL=PIX \
  -e NCCL_IB_HCA='mlx5_1,mlx5_2,mlx5_3,mlx5_4,mlx5_5,mlx5_6,mlx5_7,mlx5_8' \
  -e NCCL_IB_PCI_RELAXED_ORDERING=1 \
  -v /home/ubuntu/ml-1cc/eole/.cache:/root/.cache/ \
  -v /home/ubuntu/ml-1cc/eole/cwd:/root/cwd \
  vllm/vllm-openai:latest /bin/bash -c "apt install -y libibverbs-dev && ray start --address=172.26.135.124:6379 --block"

cleanup() {
    docker stop node
    docker remove node
}
trap cleanup EXIT
