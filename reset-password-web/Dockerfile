# Use the official Nginx image from Docker Hub
FROM nginx:alpine

# Remove default Nginx welcome page
RUN rm /usr/share/nginx/html/*

# Copy the static website content (HTML, CSS, JS with hardcoded keys, logo)
COPY . /usr/share/nginx/html

# Expose port 80
EXPOSE 80

# Command to run Nginx
CMD ["nginx", "-g", "daemon off;"]