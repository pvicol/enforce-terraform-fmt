FROM python:3.13-alpine

RUN apk update --no-cache && apk add --no-cache git

# Set working directory
WORKDIR /app

# Copy requirements file
COPY requirements.txt .

# Install Python dependencies
RUN pip install --no-cache-dir -r requirements.txt

COPY enforce_tf_fmt.py .

# Code file to execute when the docker container starts up (`entrypoint.sh`)
CMD ["python", "/app/enforce_tf_fmt.py"]
