FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV PORT=7860
EXPOSE 7860
CMD ["sh","-c","gunicorn -w 1 --threads 4 -t 120 -b 0.0.0.0:${PORT} app:app"]
