# Multi-node serving of llama3.1 on Lambda Labs 1cc


Hop onto cluster:
```bash
ssh -i ~/.ssh/ml.pem -F ~/.ssh/config.d/config.ml-512 ml-512-node-061
ssh -i ~/.ssh/ml.pem -F ~/.ssh/config.d/config.ml-512 ml-512-node-062
ssh -i ~/.ssh/ml.pem -F ~/.ssh/config.d/config.ml-512 ml-512-node-063
ssh -i ~/.ssh/ml.pem -F ~/.ssh/config.d/config.ml-512 ml-512-node-064
```


## Setup environment on each node

Setup environment variables on each node:
- `HF_HOME`
- `HF_TOKEN`
- `HEAD_IP`
```bash
export HEAD_IP=172.26.135.124
export HF_HOME=/home/ubuntu/ml-1cc/eole/.cache/huggingface
export HF_TOKEN=<...>
```

Download HF model to local storage shared across nodes
```bash
mkdir -p /home/ubuntu/ml-1cc/eole/.cache/huggingface
huggingface-cli login --token ${HF_TOKEN}
huggingface-cli download meta-llama/llama-3-1
```
huggingface-cli download meta-llama/Meta-Llama-3-70B-Instruct


*Note: model local path for serving later is like `/home/ubuntu/ml-1cc/eole/.cache/huggingface/hub/models--meta-llama/llama-3-1/snapshots/607a30d783dfa663caf39e06633721c8d4cfcd7e`.*

Download cluster setup scripts  to local storage shared across nodes
```bash
mkdir -p /home/ubuntu/ml-1cc/eole/cwd/
curl -o /home/ubuntu/ml-1cc/eole/cwd/run_cluster.sh https://raw.githubusercontent.com/vllm-project/vllm/main/examples/run_cluster.sh
```

## Run cluster

The `run_cluster.sh` script should be ran on each node with the appropriate arguments. The script will start the Ray cluster on the head node and connect the worker nodes to it. The terminal sessions need to remain open for the duration of the serving.

On head node:
*Note: Ignoring infiniband argument for now*
```bash
cd /home/ubuntu/ml-1cc/eole/cwd
/bin/bash run_cluster.sh \
    vllm/vllm-openai \
    ${HEAD_IP} \
    --head \
    ${HF_HOME}
```

On worker nodes:
```bash
cd /home/ubuntu/ml-1cc/eole/cwd
/bin/bash run_cluster.sh \
    vllm/vllm-openai \
    ${HEAD_IP} \
    --worker \
    ${HF_HOME}
```

## Serve model

On any node use `docker exec -it node /bin/bash` to enter container. Then check the cluster status with:
```
ray status
```
*You should see the right number of nodes and GPUs. For example:*
```
======== Autoscaler status: 2024-07-23 09:19:52.787566 ========
Node status
---------------------------------------------------------------
Active:
 1 node_5d49b4192028cade9fcc36bf741baa374e6169db9d4aeeb264850668
 1 node_59308d679572cae0898f6db34114493561a510ae74f8d26e7e1bbba9
 1 node_4c0f7b67a5148571b04928b345c5d33b68bcd6d74596414422b81ded
 1 node_01021d1b6c25b1259b66865684ca5f03ae2735917bdda01a628aab67
Pending:
 (no pending nodes)
Recent failures:
 (no failures)

Resources
---------------------------------------------------------------
Usage:
 0.0/832.0 CPU
 32.0/32.0 GPU (32.0 used of 32.0 reserved in placement groups)
 0B/6.87TiB memory
 0B/38.91GiB object_store_memory

Demands:
 (no resource demands)
```

Then serve the model from any node as if all the GPUs were accessible from that node
```bash
# export MODEL_PATH_IN_CONTAINER='/root/.cache/huggingface/hub/models--meta-llama--Meta-Llama-3-70B-Instruct/snapshots/7129260dd854a80eb10ace5f61c20324b472b31c'
vllm serve ${MODEL_PATH_IN_CONTAINER} \
    --tensor-parallel-size 8 \
    --pipeline-parallel-size 4
```
common configuration:
* set `tensor-parallel-size` to the number of GPUs in each node
* set `pipeline-parallel-size` to the number of nodes

Success:
```
...
INFO 07-23 09:20:47 metrics.py:295] Avg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s, Running: 0 reqs, Swapped: 0 reqs, Pending: 0 reqs, GPU KV cache usage: 0.0%, CPU KV cache usage: 0.0%.
```

## Test serving

Download a test inference script from vllm to a local directory, then run from the model serving node:
```bash
TEST_SCRIPT_PATH='/home/ubuntu/ml-1cc/eole/cwd/inference_test.py'
TEST_SCRIPT_URL='https://raw.githubusercontent.com/vllm-project/vllm/main/examples/openai_chat_completion_client.py'
curl -o ${TEST_SCRIPT_PATH} ${TEST_SCRIPT_URL}
python3 /home/ubuntu/ml-1cc/eole/cwd/inference_test.py
```

Success:
```
Chat completion results:
ChatCompletion(id='cmpl-f5871c90353b44d8b2c1c7bf5ff4415d', choices=[Choice(finish_reason='stop', index=0, logprobs=None, message=ChatCompletionMessage(content='The 2020 World Series was played at Globe Life Field in Arlington, Texas. It was a neutral-site series, meaning that neither team had home-field advantage, due to the COVID-19 pandemic.', role='assistant', function_call=None, tool_calls=[]), stop_reason=None)], created=1721725755, model='/root/.cache/huggingface/hub/models--meta-llama--Meta-Llama-3-70B-Instruct/snapshots/7129260dd854a80eb10ace5f61c20324b472b31c', object='chat.completion', service_tier=None, system_fingerprint=None, usage=CompletionUsage(completion_tokens=42, prompt_tokens=59, total_tokens=101))
```