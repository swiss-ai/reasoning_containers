FROM nvcr.io/nvidia/pytorch:25.01-py3

RUN apt-get update && apt-get install python3-pip python3-venv -y
RUN pip install --upgrade pip setuptools

RUN pip install \
    datasets \
    transformers \
    accelerate \
    wandb \
    dacite \
    pyyaml \
    numpy \
    packaging \
    safetensors \
    tqdm \
    sentencepiece \
    tensorboard \
    pandas \
    jupyter \
    deepspeed \
    seaborn

RUN mkdir -p /workspace