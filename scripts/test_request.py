from openai import OpenAI
client = OpenAI(
    base_url="http://172.26.135.124:8000/v1",
    api_key="token-abc123",
)

completion = client.chat.completions.create(
  model="meta-llama/Meta-Llama-3-70B-Instruct",
  messages=[
    {"role": "user", "content": "Hello!"}
  ]
)

print(completion.choices[0].message)