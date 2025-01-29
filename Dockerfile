FROM n8nio/n8n

COPY nodes/** /home/node/.n8n/custom/

EXPOSE 5678/tcp
