#!/bin/bash
apt-get update -y
apt-get install nginx -y
systemctl restart nginx
cat > index.html <<EOF
<h1>Hello, World</h1>
<body>${html_body}</body>
EOF
copy index.html /usr/share/nginx/html