FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    COMB_DATA_DIR=/data

RUN useradd --system --uid 10001 --home /data comb \
 && mkdir -p /data && chown comb /data

WORKDIR /srv
COPY pyproject.toml ./
COPY comb_server ./comb_server
RUN pip install --no-cache-dir .

USER comb
VOLUME ["/data"]
EXPOSE 8080
CMD ["python", "-m", "comb_server", "serve", "--host", "0.0.0.0", "--port", "8080"]
