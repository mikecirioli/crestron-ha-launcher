FROM python:3.12-slim
RUN pip install --no-cache-dir Pillow
COPY server.py /app/server.py
WORKDIR /app
EXPOSE 8099
CMD ["python3", "server.py"]
