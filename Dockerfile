# ==== Base Debian slim ====
FROM debian:stable-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Zurich

# ==== Dépendances système ====
# - poppler-utils : pdftotext, pdftoppm (extraction texte + images)
# - tesseract-ocr (+ eng/fra/deu) : OCR multilingue
# - qpdf/ghostscript : utilitaires PDF (robustesse)
# - curl, xz-utils, ca-certificates : pour installer pdfcpu + node
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl xz-utils jq \
    poppler-utils \
    tesseract-ocr tesseract-ocr-eng tesseract-ocr-fra tesseract-ocr-deu \
    ghostscript qpdf \
 && rm -rf /var/lib/apt/lists/*

# ==== pdfcpu (split/merge) ====
# Version stable; ajustez si besoin
RUN curl -L https://github.com/pdfcpu/pdfcpu/releases/download/v0.6.0/pdfcpu_0.6.0_Linux_x86_64.tar.xz \
    -o /tmp/pdfcpu.tar.xz \
 && tar -xf /tmp/pdfcpu.tar.xz -C /usr/local/bin pdfcpu \
 && chmod +x /usr/local/bin/pdfcpu \
 && rm /tmp/pdfcpu.tar.xz

# ==== Node.js ====
# Render build avec Docker : on installe Node via Nodesource
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
 && apt-get update && apt-get install -y --no-install-recommends nodejs \
 && rm -rf /var/lib/apt/lists/*

# ==== App ====
WORKDIR /app

# Copie d'abord le manifest pour profiter du cache Docker
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Puis le code
COPY server.js ./

# Port imposé par Render via $PORT (ne PAS exposer une valeur fixe)
ENV NODE_ENV=production
# Vous pouvez aussi définir une limite taille upload via env si vous modifiez server.js

# ==== Démarrage ====
# IMPORTANT : votre server.js doit écouter process.env.PORT
# Exemple dans server.js :
#   const PORT = process.env.PORT || 8088;
#   app.listen(PORT, () => console.log(`PDF service on :${PORT}`));
CMD ["node", "server.js"]

