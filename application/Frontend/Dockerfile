FROM nginx:alpine

# Install envsubst for environment variable substitution
RUN apk add --no-cache gettext

# Copy all frontend static files (including index.html.template)
COPY . /usr/share/nginx/html

# Rename index.html to index.html.template for envsubst substitution
RUN mv /usr/share/nginx/html/index.html /usr/share/nginx/html/index.html.template

# Copy the nginx config template for envsubst substitution
COPY default.conf.template /etc/nginx/templates/default.conf.template

# Substitute environment variables in index.html and nginx config at container start, then start nginx
CMD ["/bin/sh", "-c", "\
    envsubst '$BACKEND_URL' < /usr/share/nginx/html/index.html.template > /usr/share/nginx/html/index.html && \
    envsubst '$BACKEND_URL' < /etc/nginx/templates/default.conf.template > /etc/nginx/conf.d/default.conf && \
    exec nginx -g 'daemon off;' \
"]
