
## Setup ray runtime on multi-node GPU cluster

[documentation reference](https://vllm--6529.org.readthedocs.build/en/6529/serving/distributed_serving.html#multi-node-inference-and-serving)

Install ray on each node
```bash
pip install ray
```

Pick node as head node, and run
```bash
ray start --head
# Local node IP: 172.26.135.124
```
will return message like `To add another node to this Ray cluster, run ray start --address='xxx.xxx.xxx.xxx:6379'`

On other nodes, run
```bash
ray start --address='xxx.xxx.xxx.xxx:6379'
# ray start --address='172.26.135.124:6379'
```

Sanity check

To make sure all nodes joined successfully, run from any node:
```bash
ray status
```

Check GPU-GPU communication

Create `test.py` on each node
```python
import torch
import torch.distributed as dist
dist.init_process_group(backend="nccl")
local_rank = dist.get_rank() % torch.cuda.device_count()
data = torch.FloatTensor([1,] * 128).to(f"cuda:{local_rank}")
dist.all_reduce(data, op=dist.ReduceOp.SUM)
torch.cuda.synchronize()
value = data.mean().item()
world_size = dist.get_world_size()
assert value == world_size, f"Expected {world_size}, got {value}"

gloo_group = dist.new_group(ranks=list(range(world_size)), backend="gloo")
cpu_data = torch.FloatTensor([1,] * 128)
dist.all_reduce(cpu_data, op=dist.ReduceOp.SUM, group=gloo_group)
value = cpu_data.mean().item()
assert value == world_size, f"Expected {world_size}, got {value}"

print("sanity check is successful!")
```

Run `test.py` on each node:
```
RANK=<0 for master and 1+ for workers>
MASTER_ADDR=172.26.135.124:1234
torchrun \
--nproc_per_node=8 \
--nnodes=4 \
--node_rank=$RANK \
--rdzv_backend=c10d \
--rdzv_endpoint=$MASTER_ADDR \
/home/ubuntu/ml-Illinois/eole/test.py
```

![alt text](image.png)
