FROM nginx:1.28.0-alpine@sha256:30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284

COPY web-deployment/nginx.conf /etc/nginx/nginx.conf
COPY web-deployment/nginx-site.conf.template /opt/web-app/nginx-site.conf.template
COPY web-deployment/docker-entrypoint.sh /usr/local/bin/web-app-entrypoint
COPY build/web/ /usr/share/nginx/html/

RUN chmod 0555 /usr/local/bin/web-app-entrypoint \
    && chmod 0444 /etc/nginx/nginx.conf /opt/web-app/nginx-site.conf.template \
    && find /usr/share/nginx/html -type d -exec chmod 0555 {} + \
    && find /usr/share/nginx/html -type f -exec chmod 0444 {} +

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O - http://127.0.0.1:8080/healthz | grep -qx healthy

ENTRYPOINT ["/usr/local/bin/web-app-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
