# Use the official Nginx image from Docker Hub
ARG SUPABASE_URL
ARG SUPABASE_ANON_KEY
FROM nginx:alpine

# Remove default Nginx welcome page
RUN rm /usr/share/nginx/html/*

# Copy the static website content (HTML, CSS, JS, logo) into the Nginx html directory
COPY . /usr/share/nginx/html

# Create a config file for environment variables using the build arguments
# This avoids putting keys directly into the JS file in the image layer
# Note the escaping of $ to prevent shell substitution within the Dockerfile itself
RUN echo "window.ENV = { SUPABASE_URL: '${SUPABASE_URL}', SUPABASE_ANON_KEY: '${SUPABASE_ANON_KEY}' };" > /usr/share/nginx/html/env-config.js

# Inject the config script into index.html right before the main script.js
# Using sed to insert the script tag before the line containing <script src="script.js">
RUN sed -i '/<script src="script.js">/i <script src="env-config.js"><\/script>' /usr/share/nginx/html/index.html

# Expose port 80 to the outside world
EXPOSE 80

# Command to run Nginx in the foreground when the container starts
CMD ["nginx", "-g", "daemon off;"]