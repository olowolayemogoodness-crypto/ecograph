# falkordblite ships manylinux_2_39 wheels (glibc 2.39 or newer), so the base must be Debian 13 (trixie), not bookworm.
FROM python:3.13-slim-trixie
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY eco ./eco
COPY web_app ./web_app
ENV PORT=8000 PYTHONUNBUFFERED=1
EXPOSE 8000
HEALTHCHECK CMD python -c "import urllib.request,os;urllib.request.urlopen('http://127.0.0.1:'+os.environ.get('PORT','8000')+'/api/health')"
CMD ["python", "-m", "eco.server"]
