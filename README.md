# Multi-node serving of Llama 3.1 405B on Lambda Labs 1cc

Serving Llama 3.1 405B model without quantization can be done with 16xH100 GPUs using vLLM’s pipeline parallelism on Lambda 1cc. This guide is based on vLLM's awesome [Llama 3.1 Support tutorial](https://blog.vllm.ai/2024/07/23/llama31.html).

It requires running a Ray cluster on 1cc. You'll choose one of the nodes as the head node and the rest as worker nodes.

First, ensure you have ssh access to all of the nodes you want to use for serving.
For example:
```bash
ssh -i ~/.ssh/<your_key> -F ~/.ssh/config.d/cluster-config node00
ssh -i ~/.ssh/<your_key> -F ~/.ssh/config.d/cluster-config node01
```
All of the nodes should have access to a shared storage that we will use to store the model weights as well as the cluster setup script.


## Setup environment on each node

Setup some environment variables on each node:
- `HEAD_IP` is the IP address of the node that you choose as head node for the ray cluster
- `SHARED_DIR` is the path to the shared storage across nodes
- `HF_HOME` is the path for Hugging Face storage
- `HF_TOKEN` is the Hugging Face API token with access to the model to be downloaded
```bash
export HEAD_IP=... # eg: 172.26.135.124
export SHARED_DIR=/home/ubuntu/shared
export HF_HOME=${SHARED_DIR}/.cache/huggingface
export MODEL_REPO=meta-llama/Meta-Llama-3.1-405B-Instruct
export HF_TOKEN=... # eg : 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
```

Download HF model to local storage, shared across cluster nodes.  
This assumes you have created a Hugging Face token with access to the model.
```bash
mkdir -p ${HF_HOME}
huggingface-cli login --token ${HF_TOKEN}
huggingface-cli download ${MODEL_REPO}
```

Download cluster setup scripts to local storage shared across nodes
```bash
curl -o ${SHARED_DIR}/run_cluster.sh https://raw.githubusercontent.com/vllm-project/vllm/main/examples/run_cluster.sh
```

## Run cluster

The `run_cluster.sh` script should be ran on each node with the appropriate arguments. The script will start the Ray cluster on the head node and connect the worker nodes to it. The terminal sessions need to remain open for the duration of the serving.

Run on the head node:
```bash
/bin/bash ${SHARED_DIR}/run_cluster.sh \
    vllm/vllm-openai \
    ${HEAD_IP} \
    --head \
    ${HF_HOME} \
    --privileged -e NCCL_IB_HCA=mlx5
```

Run on each worker node:
```bash
/bin/bash ${SHARED_DIR}/run_cluster.sh \
    vllm/vllm-openai \
    ${HEAD_IP} \
    --worker \
    ${HF_HOME} \
    --privileged -e NCCL_IB_HCA=mlx5
```

## Serve model

On any node use `docker exec -it node /bin/bash` to enter container.

Then, check the cluster status with:
```bash
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

Then, serve the model from any node as if all the GPUs in the Ray cluster were accessible from that node:
```bash
export MODEL_PATH_IN_CONTAINER="" # e.g.: 'root/.cache/huggingface/hub/models--meta-llama--Meta-Llama-3.1-405B-Instruct/snapshots/7129260dd854a80eb10ace5f61c20324b472b31c'

vllm serve ${MODEL_PATH_IN_CONTAINER} \
    --tensor-parallel-size 8 \
    --pipeline-parallel-size 4
```
Common practice is to set:
* `tensor-parallel-size` to the number of GPUs in each node
* `pipeline-parallel-size` to the number of nodes

Success:
```
INFO 07-23 09:20:47 metrics.py:295] Avg prompt throughput: 0.0 tokens/s, Avg generation throughput: 0.0 tokens/s, Running: 0 reqs, Swapped: 0 reqs, Pending: 0 reqs, GPU KV cache usage: 0.0%, CPU KV cache usage: 0.0%.
```

## Test serving

From the model serving node, run a test inference script to check if the model is serving correctly.
```bash
curl -o ${SHARED_DIR}/inference_test.py 'https://raw.githubusercontent.com/vllm-project/vllm/main/examples/openai_chat_completion_client.py'
python3 ${SHARED_DIR}/inference_test.py
```

Success:
```
Chat completion results:
ChatCompletion(id='cmpl-0b7b5ebafc464dc29bcc825c60953993', choices=[Choice(finish_reason='stop', index=0, logprobs=None, message=ChatCompletionMessage(content='The 2020 World Series was played at Globe Life Field in Arlington, Texas. Due to the COVID-19 pandemic, the series was played at a neutral site, and Globe Life Field was chosen as the host stadium.', role='assistant', function_call=None, tool_calls=[]), stop_reason=None)], created=1721746113, model='/root/.cache/huggingface/hub/Meta-Llama-3.1-405B-Instruct', object='chat.completion', service_tier=None, system_fingerprint=None, usage=CompletionUsage(completion_tokens=46, prompt_tokens=59, total_tokens=105))
```
