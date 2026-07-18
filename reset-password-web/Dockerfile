FROM nginx:1.28.0-alpine@sha256:30f1c0d78e0ad60901648be663a710bdadf19e4c10ac6782c235200619158284

COPY nginx.conf /etc/nginx/nginx.conf
COPY nginx-site.conf.template /opt/reset-password/nginx-site.conf.template
COPY docker-entrypoint.sh /usr/local/bin/reset-password-entrypoint
COPY index.html style.css script.js logo.png /usr/share/nginx/html/
COPY email-templates/recovery.html /usr/share/nginx/html/email-templates/recovery.html

RUN chmod 0555 /usr/local/bin/reset-password-entrypoint \
    && chmod 0444 /etc/nginx/nginx.conf \
        /opt/reset-password/nginx-site.conf.template \
        /usr/share/nginx/html/index.html \
        /usr/share/nginx/html/style.css \
        /usr/share/nginx/html/script.js \
        /usr/share/nginx/html/logo.png \
        /usr/share/nginx/html/email-templates/recovery.html

USER nginx

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O - http://127.0.0.1:8080/healthz | grep -qx healthy

ENTRYPOINT ["/usr/local/bin/reset-password-entrypoint"]
CMD ["nginx", "-g", "daemon off;"]
